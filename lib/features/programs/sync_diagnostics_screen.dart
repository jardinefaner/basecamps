import 'dart:convert';

import 'package:basecamp/config/env.dart';
import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `/more/programs/diagnostics` — surfaces every piece of state
/// that determines whether a cloud write will succeed. Built for
/// the persistent 42501 ("new row violates RLS for 'programs'")
/// case where the Dart client thinks it's signed in but the
/// server's `auth.uid()` doesn't match `created_by`.
///
/// Compares three sides:
///   * Local: `Supabase.instance.client.auth.currentUser` (cached).
///   * JWT: the `sub` claim decoded from the access token in the
///     Authorization header — what the SERVER actually sees.
///   * Server: `auth.getUser()` round-trip + `select auth.uid()`
///     RPC — the ground truth.
///
/// If those three diverge, RLS rejects writes. Copy-button each
/// value so you can paste back to me / file a Supabase support
/// ticket without retyping.
class SyncDiagnosticsScreen extends ConsumerStatefulWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  ConsumerState<SyncDiagnosticsScreen> createState() =>
      _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState
    extends ConsumerState<SyncDiagnosticsScreen> {
  bool _running = false;
  String? _refreshResult;
  String? _getUserResult;
  String? _authUidResult;
  String? _connectionResult;
  String? _insertResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  Future<void> _runChecks() async {
    setState(() {
      _running = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      // 1. Refresh — check whether the refresh token is still
      //    valid. If this throws, the session is dead.
      try {
        await auth.refreshSession();
        _refreshResult = '✓ refreshed OK';
      } on Object catch (e) {
        _refreshResult = '✗ refresh failed: $e';
      }
      // 2. getUser — server confirms the JWT and returns the
      //    user. If the local `currentUser.id` differs from this,
      //    the cached identity is stale.
      try {
        final res = await auth.getUser();
        _getUserResult =
            res.user?.id ?? '(server returned no user)';
      } on Object catch (e) {
        _getUserResult = '✗ getUser failed: $e';
      }
      // 3. public.whoami() RPC — what the RLS engine actually
      //    sees when evaluating CHECK clauses. This is the value
      //    `programs_insert` compares against `created_by`.
      //    The function lives in migration 0014.
      try {
        final raw = await Supabase.instance.client.rpc<dynamic>('whoami');
        final value = raw?.toString() ?? '';
        _authUidResult = value.isEmpty
            ? '(empty — no valid JWT received server-side)'
            : value;
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST202' ||
            e.code == '42883' ||
            e.message.contains('not find')) {
          _authUidResult =
              'whoami() not deployed — apply migration '
              '0014_whoami.sql in the Supabase SQL editor.';
        } else {
          _authUidResult = '✗ rpc failed: ${e.message} (${e.code})';
        }
      } on Object catch (e) {
        _authUidResult = '✗ rpc failed: $e';
      }
      // 4. Plain connection — `select id from programs limit 0`
      //    succeeds even when there are no rows; this proves
      //    the client→server pipe + apikey are valid.
      try {
        await Supabase.instance.client
            .from('programs')
            .select('id')
            .limit(0);
        _connectionResult = '✓ programs SELECT works';
      } on Object catch (e) {
        _connectionResult = '✗ SELECT failed: $e';
      }
    } on Object catch (e) {
      _error = 'Unexpected: $e';
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Manual smoke-test: try an actual INSERT into `programs` with
  /// `created_by = currentUser.id`. Captures the exact server
  /// error if any. The row is deleted right after on success so
  /// we don't pollute the user's program list with diagnostic
  /// programs.
  ///
  /// Useful when every other identity check passes (auth.uid()
  /// matches currentUser, JWT is valid, etc.) but the actual
  /// create flow keeps 42501-ing — proves whether the policy
  /// itself is the blocker vs something in the upsert path.
  Future<void> _runInsertProbe() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _insertResult = '✗ no current user');
      return;
    }
    final probeId = 'diagnostic-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _insertResult = 'running…');
    try {
      await Supabase.instance.client.from('programs').insert({
        'id': probeId,
        'name': '[diagnostic probe — safe to delete]',
        'created_by': user.id,
      });
      // Clean up. Best-effort — if the delete fails the row is
      // visible in the user's programs list with a clear name.
      try {
        await Supabase.instance.client
            .from('programs')
            .delete()
            .eq('id', probeId);
      } on Object {
        // Leave the row if cleanup fails; the user can drop it.
      }
      if (!mounted) return;
      setState(() => _insertResult =
          '✓ INSERT succeeded — RLS lets you create programs.');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _insertResult =
          '✗ INSERT failed: ${e.message} (code: ${e.code}, '
          'details: ${e.details}, hint: ${e.hint})');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _insertResult = '✗ INSERT failed: $e');
    }
  }

  String? get _jwtSub {
    final token = Supabase
        .instance.client.auth.currentSession?.accessToken;
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final padded = _padBase64(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
      return payload['sub'] as String?;
    } on Object {
      return null;
    }
  }

  String _padBase64(String raw) {
    final mod = raw.length % 4;
    return mod == 0 ? raw : raw + '=' * (4 - mod);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeId = ref.watch(activeProgramIdProvider);
    final session = Supabase.instance.client.auth.currentSession;
    final cachedUser =
        Supabase.instance.client.auth.currentUser?.id;
    final jwtSub = _jwtSub;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text('Sync diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-run checks',
            onPressed: _running ? null : _runChecks,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_running)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const _Section(title: 'Project'),
          const _DiagRow(label: 'Supabase URL', value: Env.supabaseUrl),
          _DiagRow(
            label: 'Anon key',
            value:
                '${Env.supabaseAnonKey.substring(0, _safeMin(Env.supabaseAnonKey, 12))}…',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Section(title: 'Identity'),
          _DiagRow(
            label: 'currentUser.id',
            value: cachedUser ?? '(null)',
            highlight: true,
          ),
          _DiagRow(
            label: 'JWT.sub',
            value: jwtSub ?? '(null)',
            highlight: true,
            warn: cachedUser != null && jwtSub != cachedUser,
          ),
          _DiagRow(
            label: 'getUser().id',
            value: _getUserResult ?? '…',
            highlight: true,
            warn: _getUserResult != null &&
                cachedUser != null &&
                _getUserResult != cachedUser,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Section(title: 'Server checks'),
          _DiagRow(
            label: 'Refresh',
            value: _refreshResult ?? '…',
            warn: (_refreshResult ?? '').startsWith('✗'),
          ),
          _DiagRow(
            label: 'auth.uid() RPC',
            value: _authUidResult ?? '…',
            warn: (_authUidResult ?? '').contains('failed'),
          ),
          _DiagRow(
            label: 'Connection',
            value: _connectionResult ?? '…',
            warn: (_connectionResult ?? '').startsWith('✗'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Section(title: 'INSERT probe'),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Tries an actual INSERT into programs with the same '
              'created_by we use during create-program. Reveals '
              'the exact PostgreSQL error if RLS is blocking. The '
              'probe row is auto-deleted on success.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _running ? null : _runInsertProbe,
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Try a real INSERT'),
            ),
          ),
          if (_insertResult != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DiagRow(
              label: 'Result',
              value: _insertResult!,
              warn: _insertResult!.startsWith('✗'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const _Section(title: 'App state'),
          _DiagRow(
            label: 'Active program',
            value: activeId ?? '(none)',
          ),
          _DiagRow(
            label: 'Session expires',
            value:
                session?.expiresAt?.toString() ?? '(no session)',
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (cachedUser != null && jwtSub != null && cachedUser != jwtSub)
            _Hint(
              text:
                  "JWT mismatch: the client thinks you're user $cachedUser "
                  'but the JWT in the Authorization header carries '
                  'sub=$jwtSub. RLS will reject writes. Sign out + '
                  'sign in to recover.',
              tone: theme.colorScheme.error,
            ),
        ],
      ),
    );
  }

  int _safeMin(String s, int n) => s.length < n ? s.length : n;
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool highlight;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warn
        ? theme.colorScheme.error
        : highlight
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
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
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_outlined, size: 16),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.tone});
  final String text;
  final Color tone;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: tone),
      ),
    );
  }
}
