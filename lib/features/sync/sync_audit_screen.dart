import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/programs/program_bootstrap.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/sync/sync_specs.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `/more/programs/audit` — surfaces every fact about the device's
/// sync state so a teacher can self-diagnose "Sync said success but
/// nothing showed up." That symptom is almost always one of:
///   1. The active program on this device doesn't match the program
///      where their other device wrote rows. Same account, two
///      programs in cloud, devices land on different ones.
///   2. Cloud RLS is hiding rows because the user's `program_members`
///      row is missing or has wrong role. Pull queries return zero
///      rows even though data exists in cloud.
///   3. Watermark drift / table-not-in-publication / etc.
///
/// The audit answers each in plain language: "you're in program X
/// (id ...) locally, but your account has memberships in programs A,
/// B, C in the cloud." Plus a per-table cloud-row-count vs local-
/// row-count for the active program — if cloud is 5 and local is 0,
/// the pull is broken; if both are 0 but another program has rows,
/// you're on the wrong program.
class SyncAuditScreen extends ConsumerStatefulWidget {
  const SyncAuditScreen({super.key});

  @override
  ConsumerState<SyncAuditScreen> createState() => _SyncAuditScreenState();
}

class _SyncAuditScreenState extends ConsumerState<SyncAuditScreen> {
  bool _busy = false;
  String? _error;
  _AuditResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      if (session == null) {
        setState(() => _error = 'Not signed in.');
        return;
      }
      final userId = session.user.id;
      final email = session.user.email ?? '';
      final activeId = ref.read(activeProgramIdProvider);

      // Cloud memberships — every program this auth.uid is in.
      // RLS allows the user to read their own membership rows.
      final memberRowsRaw = await supabase
          .from('program_members')
          .select('program_id, role, joined_at')
          .eq('user_id', userId);
      final memberRows =
          List<Map<String, dynamic>>.from(memberRowsRaw);

      // Names of those programs (RLS allows reading any program
      // the user is a member of).
      final programIds = [
        for (final m in memberRows) m['program_id'] as String,
      ];
      final programs = <String, _ProgramInfo>{};
      if (programIds.isNotEmpty) {
        final programRowsRaw = await supabase
            .from('programs')
            .select('id, name, created_by, created_at')
            .inFilter('id', programIds);
        for (final raw in List<Map<String, dynamic>>.from(programRowsRaw)) {
          final id = raw['id'] as String;
          programs[id] = _ProgramInfo(
            id: id,
            name: raw['name'] as String? ?? '(unnamed)',
          );
        }
      }
      final memberships = [
        for (final m in memberRows)
          _MembershipInfo(
            programId: m['program_id'] as String,
            programName:
                programs[m['program_id']]?.name ?? '(unknown)',
            role: m['role'] as String? ?? 'teacher',
          ),
      ]..sort((a, b) => a.programName.compareTo(b.programName));

      // Per-table cloud + local counts for the active program.
      // Cheap: HEAD-style count requests. Local is a SELECT count(*)
      // through a custom statement.
      final tables = <_TableCount>[];
      if (activeId != null) {
        for (final spec in kAllSpecs) {
          final cloudCount = await _cloudCount(supabase, spec.table, activeId);
          final localCount = await _localCount(spec.table, activeId);
          tables.add(_TableCount(
            table: spec.table,
            cloud: cloudCount,
            local: localCount,
          ));
        }
      }

      // Watermarks per table for the active program.
      final watermarkRows = activeId == null
          ? const <SyncWatermark>[]
          : await (ref.read(databaseProvider).select(
                  ref.read(databaseProvider).syncState,
                )..where((s) => s.programId.equals(activeId)))
              .get();
      final watermarks = {
        for (final w in watermarkRows) w.targetTable: w.lastPulledAt,
      };

      setState(() {
        _result = _AuditResult(
          userId: userId,
          email: email,
          activeProgramId: activeId,
          activeProgramName:
              activeId == null ? null : programs[activeId]?.name,
          memberships: memberships,
          tables: tables,
          watermarks: watermarks,
        );
      });
    } on Object catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _cloudCount(
    SupabaseClient supabase,
    String table,
    String programId,
  ) async {
    try {
      // count: exact returns the value in the response headers but
      // supabase-dart exposes it via .count on PostgrestResponse —
      // simplest portable approach is to select() with a head=true
      // and read .count.
      final res = await supabase
          .from(table)
          .select('id')
          .eq('program_id', programId)
          .count(CountOption.exact);
      return res.count;
    } on Object {
      return -1; // sentinel: count not available (RLS or 4xx)
    }
  }

  /// Force-refresh: re-runs the bootstrap (hydrate cloud programs
  /// into local Drift, decide an active program, push membership,
  /// pull tables, subscribe realtime). Heals devices stuck without
  /// an active program — the most common cause of an empty audit
  /// is bootstrap raced the network on cold launch and never
  /// retried.
  Future<void> _rerunBootstrap() async {
    setState(() => _busy = true);
    try {
      await ref.read(programAuthBootstrapProvider).rerunBootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bootstrap re-ran. Re-running audit…'),
          duration: Duration(seconds: 2),
        ),
      );
      await _run();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bootstrap failed: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap-to-activate on a non-active cloud membership row. Hydrates
  /// the cloud program into local Drift if it's missing, then
  /// switches the active program to it. This is the recovery path
  /// for "phone shows my membership but no row counts because no
  /// active program is set" — the user just taps the program they
  /// want and we wire up the rest.
  Future<void> _activate(String programId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(programAuthBootstrapProvider)
          .setActiveFromCloud(programId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active program switched. Re-running audit…'),
          duration: Duration(seconds: 2),
        ),
      );
      await _run();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _localCount(String table, String programId) async {
    try {
      final db = ref.read(databaseProvider);
      final res = await db.customSelect(
        'SELECT count(*) as c FROM "$table" WHERE program_id = ?',
        variables: [Variable<String>(programId)],
      ).getSingle();
      return res.read<int>('c');
    } on Object {
      return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text('Sync audit'),
        actions: [
          IconButton(
            tooltip: 'Re-run audit',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _run,
          ),
          IconButton(
            tooltip: 'Re-run bootstrap (re-hydrate cloud, re-pick active)',
            icon: const Icon(Icons.restart_alt),
            onPressed: _busy ? null : _rerunBootstrap,
          ),
        ],
      ),
      body: _busy && _result == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_error != null)
                  AppCard(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (_result != null) ..._buildSections(theme, _result!),
              ],
            ),
    );
  }

  List<Widget> _buildSections(ThemeData theme, _AuditResult r) {
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Identity', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            _kv(theme, 'Email', r.email.isEmpty ? '(no email)' : r.email),
            _kv(theme, 'User id', r.userId),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Active program', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            if (r.activeProgramId == null)
              Text(
                'No active program. The launcher / welcome screen '
                'will let you pick or create one.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              _kv(
                theme,
                'Name',
                r.activeProgramName ?? '(not in cloud!)',
                warn: r.activeProgramName == null,
              ),
              _kv(theme, 'Id', r.activeProgramId!),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cloud memberships (${r.memberships.length})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (r.memberships.isEmpty)
              Text(
                'You have no memberships in the cloud. Every push '
                'will 403 until the bootstrap re-pushes your '
                'program + membership row, or until you join a '
                'program with an invite code.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              for (final m in r.memberships)
                _MembershipTile(
                  membership: m,
                  isActive: m.programId == r.activeProgramId,
                  busy: _busy,
                  onActivate: () => _activate(m.programId),
                ),
            if (r.activeProgramId == null && r.memberships.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You have a cloud membership but no active program '
                'set on this device — tap the program above to '
                'activate it. (Most often happens when the bootstrap '
                'raced the network on cold launch.)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ] else if (r.memberships.length > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tap a program above to switch to it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (r.activeProgramId != null && r.tables.isNotEmpty)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Row counts for active program',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Cloud is the source of truth (RLS-filtered). Local '
                'is what this device has pulled. A persistent gap = '
                'pull is failing or RLS is denying.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ..._buildTableRows(theme, r),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildTableRows(ThemeData theme, _AuditResult r) {
    final rows = <Widget>[];
    for (final t in r.tables) {
      final cloudStr = t.cloud < 0 ? '?' : '${t.cloud}';
      final localStr = t.local < 0 ? '?' : '${t.local}';
      final mismatch = t.cloud > t.local;
      final color = mismatch
          ? theme.colorScheme.error
          : theme.colorScheme.onSurface;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: Text(t.table, style: theme.textTheme.bodyMedium),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'C $cloudStr',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  'L $localStr',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (r.watermarks[t.table] != null)
                Expanded(
                  child: Text(
                    'last pull: ${_relativeTime(r.watermarks[t.table]!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  Widget _kv(
    ThemeData theme,
    String label,
    String value, {
    bool warn = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: warn
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _AuditResult {
  const _AuditResult({
    required this.userId,
    required this.email,
    required this.activeProgramId,
    required this.activeProgramName,
    required this.memberships,
    required this.tables,
    required this.watermarks,
  });

  final String userId;
  final String email;
  final String? activeProgramId;
  final String? activeProgramName;
  final List<_MembershipInfo> memberships;
  final List<_TableCount> tables;
  final Map<String, DateTime> watermarks;
}

/// A row in the cloud-memberships section. Tappable when not the
/// active program — fires [onActivate] to hydrate the program into
/// local Drift and switch to it. Disabled while the audit is busy
/// (re-running, switching, etc.) so the user can't double-tap.
class _MembershipTile extends StatelessWidget {
  const _MembershipTile({
    required this.membership,
    required this.isActive,
    required this.busy,
    required this.onActivate,
  });

  final _MembershipInfo membership;
  final bool isActive;
  final bool busy;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: isActive || busy ? null : onActivate,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              isActive
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    membership.programName,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '${membership.role} · ${membership.programId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!isActive)
              Icon(
                Icons.touch_app_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _MembershipInfo {
  const _MembershipInfo({
    required this.programId,
    required this.programName,
    required this.role,
  });

  final String programId;
  final String programName;
  final String role;
}

class _ProgramInfo {
  const _ProgramInfo({required this.id, required this.name});

  final String id;
  final String name;
}

class _TableCount {
  const _TableCount({
    required this.table,
    required this.cloud,
    required this.local,
  });

  final String table;
  final int cloud;
  final int local;
}
