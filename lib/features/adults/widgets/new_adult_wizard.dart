import 'package:basecamp/core/format/text.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/availability_editor.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/widgets/new_group_wizard.dart';
import 'package:basecamp/features/roles/roles_repository.dart';
import 'package:basecamp/features/roles/widgets/edit_role_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/avatar_picker.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Create-only step-wizard for a new adult. Editing an existing row
/// still uses the dense EditAdultSheet; this flow walks a
/// first-timer through every field one page at a time so nothing the
/// edit sheet exposes is hidden from creation.
///
/// Pages:
///   1. Who is this?          — photo + name
///   2. Job title              — free-form ("Art teacher")
///   3. Role on the schedule   — Lead / Adult / Ambient
///   4. Anchor group           — only when Lead; skipped otherwise
///   5. When do they work?     — per-day shift (Mon–Fri)
///   6. Break & lunch          — per-day break + lunch windows
///   7. Notes                  — freeform (optional)
class NewAdultWizardScreen extends ConsumerStatefulWidget {
  const NewAdultWizardScreen({
    super.key,
    this.allowCreateGroupInline = true,
  });

  /// When `false`, the anchor-group page hides its "+ New group"
  /// action. Set by callers that opened this wizard from inside
  /// `NewGroupWizardScreen` — otherwise the teacher can nest
  /// wizards forever (Group → Adult → Group → Adult → …) through
  /// the mutual inline-create path. Top-level opens keep the
  /// default `true` so the empty state still offers inline-create.
  final bool allowCreateGroupInline;

  @override
  ConsumerState<NewAdultWizardScreen> createState() =>
      _NewAdultWizardScreenState();
}

class _NewAdultWizardScreenState
    extends ConsumerState<NewAdultWizardScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  // v40: direct contact on the adult. Lives on page 1 with the name so
  // first-timers capture it in one pass — adding a dedicated page for
  // two optional fields would bloat the wizard.
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();

  /// Freshly-picked avatar. Carried as XFile so the upload works
  /// on every platform (web reads bytes via XFile; dart:io.File
  /// throws there).
  XFile? _avatarFile;

  AdultRole _adultRole = AdultRole.specialist;
  String? _anchoredGroupId;

  /// v39: picked role FK. When set, supersedes the [_role] text
  /// controller at submit time — same "picker wins" rule as the
  /// edit sheet.
  String? _roleId;

  /// Weekly shift sketch (per-day branch). Seeded with Mon–Fri 9–5
  /// so a "just tap Next" teacher gets a sensible default instead of
  /// an empty week. Used when [_uniformMode] is false.
  late final Map<int, AvailabilityBlock> _availability = {
    for (final b in defaultAvailability()) b.dayOfWeek: b,
  };

  /// Uniform-mode state. Defaults to ON because "same hours every
  /// day" is the common case and we don't want teachers tapping Mon,
  /// Tue, Wed, Thu, Fri to set 9-5 on each. When they need nuance
  /// they flip the switch off and get per-day editing.
  bool _uniformMode = true;
  AvailabilityBlock _uniformBlock = AvailabilityBlock(
    dayOfWeek: 1,
    start: const TimeOfDay(hour: 9, minute: 0),
    end: const TimeOfDay(hour: 17, minute: 0),
  );
  Set<int> _uniformDays = {1, 2, 3, 4, 5};

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _role.text.trim().isNotEmpty ||
      _roleId != null ||
      _phone.text.trim().isNotEmpty ||
      _email.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _avatarFile != null ||
      _adultRole != AdultRole.specialist ||
      _anchoredGroupId != null;

  bool get _page1Valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final typed = _role.text.trim();
    // Picker wins: if an FK is set, save only that and drop the
    // free-text to avoid double storage. Mirror of edit sheet.
    final role = _roleId != null || typed.isEmpty ? null : typed;
    final notes = _notes.text.trim();
    final repo = ref.read(adultsRepositoryProvider);
    // Anchor only applies to leads — don't persist a stale value if
    // the teacher picked Lead, set a group, then switched roles.
    final effectiveAnchor =
        _adultRole == AdultRole.lead ? _anchoredGroupId : null;
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final id = await repo.addAdult(
      name: _name.text.trim(),
      role: role,
      roleId: _roleId,
      notes: notes.isEmpty ? null : notes,
      avatarFile: _avatarFile,
      adultRole: _adultRole,
      anchoredGroupId: effectiveAnchor,
      phone: phone.isEmpty ? null : phone,
      email: email.isEmpty ? null : email,
    );
    // Uniform mode: expand the single block across selected days on
    // save. Per-day mode: just serialize the map as-is.
    final blocks = _uniformMode
        ? expandUniform(block: _uniformBlock, days: _uniformDays)
            .values
            .map((b) => b.toInput())
            .toList()
        : _availability.values.map((b) => b.toInput()).toList();
    await repo.replaceAvailability(
      adultId: id,
      blocks: blocks,
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
          needsKeyboard: true,
        ),
        WizardStep(
          headline: 'What do they do?',
          subtitle: 'Art teacher, head cook, director — whatever fits.',
          canSkip: true,
          content: _buildJobTitlePage(),
          needsKeyboard: true,
        ),
        WizardStep(
          headline: 'Role on the schedule',
          subtitle: 'How they show up on Today. You can change this later.',
          content: _buildRolePage(),
        ),
        // Anchor page only matters for Leads; the wizard still shows it
        // but lets adults/ambient skip through it with the default
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
          subtitle: 'Mon–Fri shift. Tap Add break / Add lunch on any '
              'day to set an optional window inside the shift.',
          canSkip: true,
          content: _buildAvailabilityPage(),
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
          needsKeyboard: true,
        ),
      ],
    );
  }

  // ---- page builders ----

  Widget _buildNamePage() {
    final initial = _name.text.initial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AvatarPicker(
            // Wizard is create-only — there's no existing
            // avatar_path / storage_path / etag to render. Picker
            // shows the pending pick (if any) or the fallback
            // initial.
            currentLocalPath: null,
            currentStoragePath: null,
            currentEtag: null,
            pendingFile: _avatarFile,
            fallbackInitial: initial,
            onChanged: (file) => setState(() => _avatarFile = file),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTextField(
          controller: _name,
          label: 'Name',
          hint: 'e.g. Sarah',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        // v40: phone + email sit right under the name so first-timers
        // capture them in one pass. Both optional — validation matches
        // parents (lenient, no strict format check).
        AppTextField(
          controller: _phone,
          label: 'Phone (optional)',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _email,
          label: 'Email (optional)',
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }

  Widget _buildJobTitlePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardRolePicker(
          selectedRoleId: _roleId,
          onPick: (id) => setState(() {
            _roleId = id;
            if (id != null) _role.clear();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _role,
          label: 'Or type a one-off title (optional)',
          hint: 'e.g. Floater · Visiting artist',
          onChanged: (v) => setState(() {
            // Typing clears the picker — legacy path wins.
            if (v.trim().isNotEmpty && _roleId != null) _roleId = null;
          }),
        ),
      ],
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
        // When this wizard was opened from inside NewGroupWizard,
        // cross-inline-create is disabled to cut the recursion.
        // Teacher uses Skip to finish the nested adult and returns.
        final allowInline = widget.allowCreateGroupInline;
        if (groups.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                allowInline
                    ? 'No groups in the program yet. Add one below '
                        'to anchor this lead.'
                    : 'No groups yet. Tap Skip — once the outer '
                        'group is saved, re-open the adult and '
                        'anchor them there.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (allowInline) ...[
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _openNewGroupWizard(context),
                    icon: const Icon(
                      Icons.group_add_outlined,
                      size: 18,
                    ),
                    label: const Text('New group'),
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
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
            ),
            if (allowInline) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openNewGroupWizard(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add another group…'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Spawns the New-Group wizard above this one so a teacher who
  /// marked this adult as a lead but has no groups yet can create
  /// one inline instead of dead-ending. Uses rootNavigator so the
  /// new wizard sits above everything; groupsProvider auto-refreshes
  /// on return.
  Future<void> _openNewGroupWizard(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        // Nested spawn: disable the nested wizard's "+ New adult"
        // cross-create so the teacher can't recurse forever.
        builder: (_) => const NewGroupWizardScreen(
          allowCreateAdultInline: false,
        ),
      ),
    );
  }

  Widget _buildAvailabilityPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Same hours every day'),
          subtitle: const Text(
            'Turn off for different hours on different days.',
          ),
          value: _uniformMode,
          onChanged: (v) => setState(() {
            if (v) {
              // Per-day → Uniform: use Monday's values as the seed
              // if any are set, otherwise keep the current uniform
              // defaults.
              final pd = _availability;
              if (pd.isNotEmpty) {
                final seed = pd.values.first;
                _uniformBlock = AvailabilityBlock(
                  dayOfWeek: 1,
                  start: seed.start,
                  end: seed.end,
                  breakStart: seed.breakStart,
                  breakEnd: seed.breakEnd,
                  lunchStart: seed.lunchStart,
                  lunchEnd: seed.lunchEnd,
                );
                _uniformDays = pd.keys.toSet();
              }
            } else {
              // Uniform → Per-day: expand the shared block across
              // the selected days so the teacher doesn't lose their
              // hours when switching.
              _availability
                ..clear()
                ..addAll(
                  expandUniform(
                    block: _uniformBlock,
                    days: _uniformDays,
                  ),
                );
            }
            _uniformMode = v;
          }),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_uniformMode)
          UniformAvailabilityEditor(
            block: _uniformBlock,
            days: _uniformDays,
            onToggleDay: (day, {required enabled}) {
              setState(() {
                if (enabled) {
                  _uniformDays.add(day);
                } else {
                  _uniformDays.remove(day);
                }
              });
            },
            onPickStart: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _uniformBlock.start,
              );
              if (picked == null || !mounted) return;
              setState(() {
                _uniformBlock = _uniformBlock.copyWith(start: picked);
              });
            },
            onPickEnd: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _uniformBlock.end,
              );
              if (picked == null || !mounted) return;
              setState(() {
                _uniformBlock = _uniformBlock.copyWith(end: picked);
              });
            },
            onPickBreak: () => _pickUniformWindow(
              seedStart: const TimeOfDay(hour: 10, minute: 30),
              seedDurationMinutes: 15,
              readStart: (b) => b.breakStart,
              readEnd: (b) => b.breakEnd,
              apply: (b, start, end) =>
                  b.copyWith(breakStart: start, breakEnd: end),
            ),
            onPickBreak2: () => _pickUniformWindow(
              seedStart: const TimeOfDay(hour: 14, minute: 30),
              seedDurationMinutes: 15,
              readStart: (b) => b.break2Start,
              readEnd: (b) => b.break2End,
              apply: (b, start, end) =>
                  b.copyWith(break2Start: start, break2End: end),
            ),
            onPickLunch: () => _pickUniformWindow(
              seedStart: const TimeOfDay(hour: 12, minute: 0),
              seedDurationMinutes: 60,
              readStart: (b) => b.lunchStart,
              readEnd: (b) => b.lunchEnd,
              apply: (b, start, end) =>
                  b.copyWith(lunchStart: start, lunchEnd: end),
            ),
            onClearBreak: () => setState(() {
              _uniformBlock = _uniformBlock.copyWith(clearBreak: true);
            }),
            onClearBreak2: () => setState(() {
              _uniformBlock = _uniformBlock.copyWith(clearBreak2: true);
            }),
            onClearLunch: () => setState(() {
              _uniformBlock = _uniformBlock.copyWith(clearLunch: true);
            }),
          )
        else
          _buildPerDayEditor(theme),
      ],
    );
  }

  Widget _buildPerDayEditor(ThemeData theme) {
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
      onPickBreak: (day) => _pickWindow(
        day,
        seedStart: const TimeOfDay(hour: 10, minute: 30),
        seedDurationMinutes: 15,
        readStart: (b) => b.breakStart,
        readEnd: (b) => b.breakEnd,
        apply: (b, start, end) =>
            b.copyWith(breakStart: start, breakEnd: end),
      ),
      onPickBreak2: (day) => _pickWindow(
        day,
        seedStart: const TimeOfDay(hour: 14, minute: 30),
        seedDurationMinutes: 15,
        readStart: (b) => b.break2Start,
        readEnd: (b) => b.break2End,
        apply: (b, start, end) =>
            b.copyWith(break2Start: start, break2End: end),
      ),
      onPickLunch: (day) => _pickWindow(
        day,
        seedStart: const TimeOfDay(hour: 12, minute: 0),
        seedDurationMinutes: 60,
        readStart: (b) => b.lunchStart,
        readEnd: (b) => b.lunchEnd,
        apply: (b, start, end) =>
            b.copyWith(lunchStart: start, lunchEnd: end),
      ),
      onClearBreak: (day) => setState(() {
        final existing = _availability[day];
        if (existing == null) return;
        _availability[day] = existing.copyWith(clearBreak: true);
      }),
      onClearBreak2: (day) => setState(() {
        final existing = _availability[day];
        if (existing == null) return;
        _availability[day] = existing.copyWith(clearBreak2: true);
      }),
      onClearLunch: (day) => setState(() {
        final existing = _availability[day];
        if (existing == null) return;
        _availability[day] = existing.copyWith(clearLunch: true);
      }),
    );
  }

  /// Uniform-mode twin of [_pickWindow]. Pops the same start→end
    /// picker pair, but writes the result back to the single shared
    /// [_uniformBlock] instead of a per-day row.
  Future<void> _pickUniformWindow({
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
    final existingStart = readStart(_uniformBlock);
    final existingEnd = readEnd(_uniformBlock);
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
      _uniformBlock = apply(_uniformBlock, start, end);
    });
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

/// Wizard-page twin of the edit sheet's role picker — chip grid for
/// `Adults.roleId` with an "+ New role" action chip. Kept separate
/// from the edit sheet's version because the wizard page has its
/// own surrounding layout + copy.
class _WizardRolePicker extends ConsumerWidget {
  const _WizardRolePicker({
    required this.selectedRoleId,
    required this.onPick,
  });

  final String? selectedRoleId;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rolesAsync = ref.watch(rolesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pick from the list', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Or tap "+ New role" to add one. Leave unpicked to type a '
          'one-off title below.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        rolesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (roles) {
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final r in roles)
                  ChoiceChip(
                    label: Text(r.name),
                    selected: selectedRoleId == r.id,
                    onSelected: (_) => onPick(
                      selectedRoleId == r.id ? null : r.id,
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New role'),
                  onPressed: () => _openNewRoleSheet(context),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openNewRoleSheet(BuildContext context) async {
    final id = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => const EditRoleSheet(),
    );
    if (id != null) onPick(id);
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
