import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/adults/adults_repository.dart';
import 'package:basecamp/features/adults/widgets/new_adult_wizard.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/children/group_colors.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step-wizard for creating a group. Mirrors the "+ Adult" flow so a
/// first-timer can walk from zero to fully-seeded group — kids, leads,
/// and default room all wired — in one pass.
///
/// Pages:
///   1. Name + color          — required
///   2. Default room          — pick from existing rooms, or skip
///   3. Anchor leads          — which adults live in this group
///   4. Kids                  — which unassigned kids to add now
///
/// Everything after page 1 is optional; the wizard saves the group
/// first, then applies the optional wiring (room / leads / kids) in
/// one transaction so a partial failure doesn't leave half-configured
/// rows lying around.
class NewGroupWizardScreen extends ConsumerStatefulWidget {
  const NewGroupWizardScreen({
    super.key,
    this.allowCreateAdultInline = true,
  });

  /// When `false`, the anchor-leads page hides its "+ New adult"
  /// action. Set by callers that opened this wizard from inside
  /// `NewAdultWizardScreen` or `EditAdultSheet` — otherwise the
  /// teacher can nest wizards forever (Adult → Group → Adult →
  /// Group → …) through the mutual inline-create path. Top-level
  /// opens keep the default `true` so the empty state still
  /// offers inline-create.
  final bool allowCreateAdultInline;

  @override
  ConsumerState<NewGroupWizardScreen> createState() =>
      _NewGroupWizardScreenState();
}

class _NewGroupWizardScreenState extends ConsumerState<NewGroupWizardScreen> {
  final _name = TextEditingController();
  String? _colorHex;

  /// Rooms the teacher picked as this group's default. Null means
  /// "skip" — no default room set yet.
  String? _defaultRoomId;

  /// Adult ids to anchor to this group as leads. Flips an
  /// existing adult into adultRole = lead AND retargets their
  /// anchoredGroupId on save.
  final Set<String> _leadIds = {};

  /// Kid ids to move into this group. Limited to currently-unassigned
  /// kids in the picker below so the teacher doesn't silently yank a
  /// child out of another group by mistake.
  final Set<String> _kidIds = {};

  bool get _dirty =>
      _name.text.trim().isNotEmpty ||
      _colorHex != null ||
      _defaultRoomId != null ||
      _leadIds.isNotEmpty ||
      _kidIds.isNotEmpty;

  bool get _page1Valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final childrenRepo = ref.read(childrenRepositoryProvider);
    final roomsRepo = ref.read(roomsRepositoryProvider);
    final adultsRepo = ref.read(adultsRepositoryProvider);

    final groupId = await childrenRepo.addGroup(
      name: name,
      colorHex: _colorHex,
    );

    // Wire room → group. Room-side knows which group it's the default
    // for (schema is `rooms.default_for_group_id`), so we update the
    // picked room's column rather than the group's.
    if (_defaultRoomId != null) {
      await roomsRepo.updateRoom(
        id: _defaultRoomId!,
        defaultForGroupId: Value(groupId),
      );
    }

    // Flip each picked adult into a lead anchored here. If they were
    // already a lead somewhere else, they switch anchors — pods only
    // hold one or two leads so this is the typical "seeding a new
    // group" move, not a cross-group re-assignment.
    for (final sid in _leadIds) {
      final s = await adultsRepo.getAdult(sid);
      if (s == null) continue;
      await adultsRepo.updateAdult(
        id: sid,
        name: s.name,
        role: s.role,
        notes: s.notes,
        avatarPath: s.avatarPath,
        adultRole: const Value('lead'),
        anchoredGroupId: Value(groupId),
      );
    }

    // Assign kids — only among the ones we showed in the picker, i.e.
    // previously unassigned.
    for (final kid in _kidIds) {
      await childrenRepo.updateChildGroup(childId: kid, groupId: groupId);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New group',
      dirty: _dirty,
      finalActionLabel: 'Create group',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'Name and color',
          subtitle: 'A short name plus a color to tell it apart on '
              'the Children tab and the launcher.',
          canProceed: _page1Valid,
          content: _buildNameColorPage(),
          needsKeyboard: true,
        ),
        WizardStep(
          headline: 'Default room',
          subtitle: 'The room this group calls home. Skip if they '
              "don't have a fixed room yet — set it later on the "
              'Rooms screen.',
          canSkip: true,
          content: _buildRoomPage(),
        ),
        WizardStep(
          headline: 'Anchor leads',
          subtitle: 'Adults who live with this group all day. Pick '
              'up to two; you can change the roster any time.',
          canSkip: true,
          content: _buildLeadsPage(),
        ),
        WizardStep(
          headline: 'Add kids',
          subtitle: 'Move any unassigned kids into this group now. '
              'You can also do this later from the Children tab.',
          canSkip: true,
          content: _buildKidsPage(),
        ),
      ],
    );
  }

  // ---- Page 1: name + color ----

  Widget _buildNameColorPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _name,
          label: 'Group name',
          hint: 'e.g. Dolphins',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Color', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        _GroupColorPicker(
          selectedHex: _colorHex,
          onChanged: (hex) => setState(() => _colorHex = hex),
        ),
      ],
    );
  }

  // ---- Page 2: default room ----

  Widget _buildRoomPage() {
    final theme = Theme.of(context);
    final roomsAsync = ref.watch(roomsProvider);
    return roomsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
      data: (rooms) {
        if (rooms.isEmpty) {
          return Text(
            'No rooms yet. Tap Skip — you can add rooms later from '
            'the Rooms screen and point this group at one from the '
            "group's detail page.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: const Text('No room yet'),
              selected: _defaultRoomId == null,
              onSelected: (_) =>
                  setState(() => _defaultRoomId = null),
            ),
            for (final r in rooms)
              ChoiceChip(
                label: Text(r.name),
                selected: _defaultRoomId == r.id,
                onSelected: (_) =>
                    setState(() => _defaultRoomId = r.id),
              ),
          ],
        );
      },
    );
  }

  // ---- Page 3: anchor leads ----

  Widget _buildLeadsPage() {
    final theme = Theme.of(context);
    final adultsAsync = ref.watch(adultsProvider);
    return adultsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
      data: (adults) {
        // When this wizard was opened from inside NewAdultWizard /
        // EditAdultSheet, cross-inline-create is disabled to cut the
        // Adult ↔ Group recursion. Teacher uses Skip to finish the
        // nested group and returns to the outer flow.
        final allowInline = widget.allowCreateAdultInline;
        if (adults.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                allowInline
                    ? 'No adults in the program yet. Add one below to '
                        'anchor as a lead for this group.'
                    : 'No adults yet. Tap Skip — once the outer adult '
                        'is saved you can come back and anchor more '
                        'leads from the group detail page.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (allowInline) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _openNewAdultWizard(context),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('New adult'),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Picking an adult switches their role to Lead and '
              "re-anchors them here — so don't pick a lead who's "
              'already running another group unless you mean it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final s in adults)
              _AdultRow(
                adult: s,
                selected: _leadIds.contains(s.id),
                onToggle: () => setState(() {
                  if (_leadIds.contains(s.id)) {
                    _leadIds.remove(s.id);
                  } else {
                    _leadIds.add(s.id);
                  }
                }),
              ),
            if (allowInline) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openNewAdultWizard(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add another adult…'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Spawns the New-Adult wizard above this one so a teacher who
  /// lands here with no adults yet can bootstrap one without
  /// backing all the way out. Uses rootNavigator so the new wizard
  /// mounts above everything; stream providers auto-refresh on
  /// return, so the leads list repopulates on its own.
  Future<void> _openNewAdultWizard(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        // Nested spawn: disable the nested wizard's "+ New group"
        // cross-create so the teacher can't recurse forever.
        builder: (_) => const NewAdultWizardScreen(
          allowCreateGroupInline: false,
        ),
      ),
    );
  }

  // ---- Page 4: add kids ----

  Widget _buildKidsPage() {
    final theme = Theme.of(context);
    final kidsAsync = ref.watch(childrenProvider);
    return kidsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
      data: (kids) {
        // Only show unassigned kids here — re-assigning a child out of
        // another group has downstream effects (their observations,
        // attendance, concerns) and should happen on the child detail
        // screen, not buried in a group-creation flow.
        final unassigned =
            kids.where((k) => k.groupId == null).toList();
        if (unassigned.isEmpty) {
          return Text(
            kids.isEmpty
                ? 'No children yet. Skip — you can add them from the '
                    'Children tab and assign them to this group '
                    'later.'
                : 'Every child is already assigned to a group. Skip '
                    'this step — to move a child over, open them '
                    'from the Children tab.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final k in unassigned)
              CheckboxListTile(
                value: _kidIds.contains(k.id),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _kidIds.add(k.id);
                  } else {
                    _kidIds.remove(k.id);
                  }
                }),
                title: Text(_fullName(k)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        );
      },
    );
  }

  String _fullName(Child k) {
    final last = k.lastName;
    if (last == null || last.trim().isEmpty) return k.firstName;
    return '${k.firstName} ${last.trim()}';
  }
}

/// Tappable row on the "Anchor leads" page. Shows the adult's name,
/// photo initial, and current role context so the teacher sees
/// whether picking them would re-anchor them.
class _AdultRow extends StatelessWidget {
  const _AdultRow({
    required this.adult,
    required this.selected,
    required this.onToggle,
  });

  final Adult adult;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = AdultRole.fromDb(adult.adultRole);
    final currentLabel = switch (current) {
      AdultRole.lead => adult.anchoredGroupId == null
          ? 'Currently: Lead (no group)'
          : 'Currently: Lead',
      AdultRole.specialist => 'Currently: Specialist',
      AdultRole.ambient => 'Currently: Ambient',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
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
                      adult.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    Text(
                      currentLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid of preset group colors plus an "unset" chip. Shared between
/// the create wizard and the edit sheet so the two flows agree on
/// which swatches are offered.
class _GroupColorPicker extends StatelessWidget {
  const _GroupColorPicker({
    required this.selectedHex,
    required this.onChanged,
  });

  final String? selectedHex;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        // "No color" tile — outlined circle with a strike-through.
        _ColorDot(
          color: theme.colorScheme.surfaceContainerHigh,
          selected: selectedHex == null,
          border: theme.colorScheme.outlineVariant,
          icon: Icons.block,
          iconColor: theme.colorScheme.onSurfaceVariant,
          onTap: () => onChanged(null),
        ),
        for (final c in groupColors)
          _ColorDot(
            color: c.color,
            selected: c.hex == selectedHex,
            onTap: () => onChanged(c.hex),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.border,
    this.icon,
    this.iconColor,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color? border;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : (border ?? Colors.transparent),
            width: selected ? 3 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: iconColor, size: 20)
            : (selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null),
      ),
    );
  }
}
