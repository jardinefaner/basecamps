import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/features/specialists/widgets/availability_editor.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-only step-wizard for a new adult. Editing an existing row
/// still uses the dense EditSpecialistSheet; this flow walks a
/// first-timer through every field one page at a time so nothing the
/// edit sheet exposes is hidden from creation.
///
/// Pages:
///   1. Who is this?          — photo + name
///   2. Job title              — free-form ("Art teacher")
///   3. Role on the schedule   — Lead / Specialist / Ambient
///   4. Anchor group           — only when Lead; skipped otherwise
///   5. When do they work?     — per-day shift (Mon–Fri)
///   6. Break & lunch          — per-day break + lunch windows
///   7. Notes                  — freeform (optional)
class NewSpecialistWizardScreen extends ConsumerStatefulWidget {
  const NewSpecialistWizardScreen({super.key});

  @override
  ConsumerState<NewSpecialistWizardScreen> createState() =>
      _NewSpecialistWizardScreenState();
}

class _NewSpecialistWizardScreenState
    extends ConsumerState<NewSpecialistWizardScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _notes = TextEditingController();
  String? _avatarPath;

  AdultRole _adultRole = AdultRole.specialist;
  String? _anchoredGroupId;

  /// Weekly shift sketch — seeded with Mon–Fri 9–5 so a "just tap
  /// Next" teacher gets a sensible default instead of an empty week.
  late final Map<int, AvailabilityBlock> _availability = {
    for (final b in defaultAvailability()) b.dayOfWeek: b,
  };

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _role.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _avatarPath != null ||
      _adultRole != AdultRole.specialist ||
      _anchoredGroupId != null;

  bool get _page1Valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role.text.trim();
    final notes = _notes.text.trim();
    final repo = ref.read(specialistsRepositoryProvider);
    // Anchor only applies to leads — don't persist a stale value if
    // the teacher picked Lead, set a group, then switched roles.
    final effectiveAnchor =
        _adultRole == AdultRole.lead ? _anchoredGroupId : null;
    final id = await repo.addSpecialist(
      name: _name.text.trim(),
      role: role.isEmpty ? null : role,
      notes: notes.isEmpty ? null : notes,
      avatarPath: _avatarPath,
      adultRole: _adultRole,
      anchoredGroupId: effectiveAnchor,
    );
    await repo.replaceAvailability(
      specialistId: id,
      blocks: _availability.values.map((b) => b.toInput()).toList(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New adult',
      dirty: _dirty,
      finalActionLabel: 'Add adult',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: "Who's this?",
          subtitle: 'Name and photo — you can change the photo later too.',
          canProceed: _page1Valid,
          content: _buildNamePage(),
        ),
        WizardStep(
          headline: 'What do they do?',
          subtitle: 'Art teacher, head cook, director — whatever fits.',
          canSkip: true,
          content: _buildJobTitlePage(),
        ),
        WizardStep(
          headline: 'Role on the schedule',
          subtitle: 'How they show up on Today. You can change this later.',
          content: _buildRolePage(),
        ),
        // Anchor page only matters for Leads; the wizard still shows it
        // but lets specialists/ambient skip through it with the default
        // "Skip" action.
        WizardStep(
          headline: 'Which group do they anchor?',
          subtitle: _adultRole == AdultRole.lead
              ? 'Leads stay with one group all day — pick which.'
              : 'Only leads anchor a group. You can skip this.',
          canProceed:
              _adultRole != AdultRole.lead || _anchoredGroupId != null,
          canSkip: _adultRole != AdultRole.lead,
          content: _buildAnchorPage(),
        ),
        WizardStep(
          headline: 'When do they work?',
          subtitle: 'Mon–Fri, toggle any day off, tweak the hours. '
              "You'll set breaks on the next page.",
          canSkip: true,
          content: _buildAvailabilityPage(withBreaks: false),
        ),
        WizardStep(
          headline: 'Break & lunch?',
          subtitle: 'Optional — tap "Add break" or "Add lunch" on any '
              'day to set a window inside the shift.',
          canSkip: true,
          content: _buildAvailabilityPage(withBreaks: true),
        ),
        WizardStep(
          headline: 'Anything worth noting?',
          subtitle: 'Internal notes for staff. Skip if nothing comes to mind.',
          canSkip: true,
          content: AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Certifications, availability quirks, etc.',
            maxLines: 4,
          ),
        ),
      ],
    );
  }

  // ---- page builders ----

  Widget _buildNamePage() {
    final initial = _name.text.trim().isNotEmpty
        ? _name.text.trim().characters.first.toUpperCase()
        : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AvatarPicker(
            currentPath: _avatarPath,
            fallbackInitial: initial,
            onChanged: (p) => setState(() => _avatarPath = p),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Sarah',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildJobTitlePage() {
    return AppTextField(
      controller: _role,
      label: 'Job title (optional)',
      hint: 'e.g. Art teacher · Director · Head cook',
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRolePage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in AdultRole.values) ...[
          _RoleOption(
            role: r,
            selected: _adultRole == r,
            onTap: () => setState(() {
              _adultRole = r;
              if (r != AdultRole.lead) _anchoredGroupId = null;
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          _adultRole == AdultRole.lead
              ? "Leads anchor a single group — you'll pick which on "
                  'the next step.'
              : _adultRole == AdultRole.specialist
                  ? 'Specialists rotate between activities on the '
                      'schedule.'
                  : "Ambient staff have a shift but aren't on the "
                      'activity grid — director, nurse, kitchen, etc.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAnchorPage() {
    final theme = Theme.of(context);
    if (_adultRole != AdultRole.lead) {
      return Text(
        'This page only applies to leads. Tap Skip to continue.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final groupsAsync = ref.watch(groupsProvider);
    return groupsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
      data: (groups) {
        if (groups.isEmpty) {
          return Text(
            'No groups yet — add some in the Children tab first, '
            'then come back to pick the anchor.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final g in groups)
              ChoiceChip(
                label: Text(g.name),
                selected: _anchoredGroupId == g.id,
                onSelected: (_) =>
                    setState(() => _anchoredGroupId = g.id),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAvailabilityPage({required bool withBreaks}) {
    return AvailabilityEditor(
      blocksByDay: _availability,
      onToggleDay: (day, {required enabled}) {
        setState(() {
          if (enabled) {
            _availability[day] = AvailabilityBlock(
              dayOfWeek: day,
              start: const TimeOfDay(hour: 9, minute: 0),
              end: const TimeOfDay(hour: 17, minute: 0),
            );
          } else {
            _availability.remove(day);
          }
        });
      },
      onPickStart: (day) async {
        final existing = _availability[day];
        if (existing == null) return;
        final picked = await showTimePicker(
          context: context,
          initialTime: existing.start,
        );
        if (picked == null || !mounted) return;
        setState(() {
          _availability[day] = existing.copyWith(start: picked);
        });
      },
      onPickEnd: (day) async {
        final existing = _availability[day];
        if (existing == null) return;
        final picked = await showTimePicker(
          context: context,
          initialTime: existing.end,
        );
        if (picked == null || !mounted) return;
        setState(() {
          _availability[day] = existing.copyWith(end: picked);
        });
      },
      // Break + lunch pickers only hooked up on the dedicated page —
      // keeps the shift page focused on shift hours.
      onPickBreak: withBreaks
          ? (day) => _pickWindow(
                day,
                seedStart: const TimeOfDay(hour: 10, minute: 30),
                seedDurationMinutes: 15,
                readStart: (b) => b.breakStart,
                readEnd: (b) => b.breakEnd,
                apply: (b, start, end) =>
                    b.copyWith(breakStart: start, breakEnd: end),
              )
          : null,
      onPickLunch: withBreaks
          ? (day) => _pickWindow(
                day,
                seedStart: const TimeOfDay(hour: 12, minute: 0),
                seedDurationMinutes: 60,
                readStart: (b) => b.lunchStart,
                readEnd: (b) => b.lunchEnd,
                apply: (b, start, end) =>
                    b.copyWith(lunchStart: start, lunchEnd: end),
              )
          : null,
      onClearBreak: withBreaks
          ? (day) => setState(() {
                final existing = _availability[day];
                if (existing == null) return;
                _availability[day] = existing.copyWith(clearBreak: true);
              })
          : null,
      onClearLunch: withBreaks
          ? (day) => setState(() {
                final existing = _availability[day];
                if (existing == null) return;
                _availability[day] = existing.copyWith(clearLunch: true);
              })
          : null,
    );
  }

  Future<void> _pickWindow(
    int day, {
    required TimeOfDay seedStart,
    required int seedDurationMinutes,
    required TimeOfDay? Function(AvailabilityBlock) readStart,
    required TimeOfDay? Function(AvailabilityBlock) readEnd,
    required AvailabilityBlock Function(
      AvailabilityBlock,
      TimeOfDay,
      TimeOfDay,
    ) apply,
  }) async {
    final existing = _availability[day];
    if (existing == null) return;
    final existingStart = readStart(existing);
    final existingEnd = readEnd(existing);
    final start = await showTimePicker(
      context: context,
      initialTime: existingStart ?? seedStart,
      helpText: 'Starts at',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: existingEnd ?? _addMinutes(start, seedDurationMinutes),
      helpText: 'Ends at',
    );
    if (end == null || !mounted) return;
    setState(() {
      _availability[day] = apply(existing, start, end);
    });
  }

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = t.hour * 60 + t.minute + minutes;
    final wrapped = ((total % (24 * 60)) + 24 * 60) % (24 * 60);
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
  }
}

/// Large tappable role tile on the role-selection wizard page. Same
/// information as the edit sheet's three-chip picker but laid out so
/// each option has its own one-line explanation — wizard page has the
/// space for it and first-timers want the descriptions.
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final AdultRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, desc) = switch (role) {
      AdultRole.lead => (
          'Lead',
          'Stays with one group all day. Most of the teachers in a '
              'typical classroom setup.',
        ),
      AdultRole.specialist => (
          'Specialist',
          'Rotates between activities (art, music, swim, etc.). '
              'Comes into a group for one block, moves to the next.',
        ),
      AdultRole.ambient => (
          'Ambient staff',
          'In the building but not on the activity grid — director, '
              'nurse, kitchen, front desk.',
        ),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.4 : 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Simple "selected" indicator — using an Icon instead of
            // Radio because Radio's API changed in recent Flutter and
            // the newer RadioGroup form is heavier than this card
            // layout needs.
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
