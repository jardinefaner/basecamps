import 'package:basecamp/core/format/date.dart';
import 'package:basecamp/core/format/time.dart';
import 'package:basecamp/core/id.dart';
import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/activity_library/activity_library_repository.dart';
import 'package:basecamp/features/activity_library/library_usages_repository.dart';
import 'package:basecamp/features/activity_library/widgets/edit_library_item_sheet.dart';
import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/widgets/adult_chip_picker.dart';
import 'package:basecamp/features/rooms/widgets/room_picker.dart';
import 'package:basecamp/features/schedule/schedule_repository.dart';
import 'package:basecamp/features/schedule/week_days.dart';
import 'package:basecamp/features/schedule/widgets/library_picker_screen.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/step_wizard.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen wizard for creating a new weekly-recurring activity
/// (aka "template"). Splits the dense edit sheet into five light pages
/// so first-timers aren't faced with a wall of inputs. Editing an
/// existing activity still uses the dense edit sheet — this wizard is
/// creation-only.
///
/// Pages:
///   1. Activity — library pick OR typed name
///   2. When — day chips + start/end times
///   3. Groups  — who it's for (optional)
///   4. Who + where — adult + location (optional)
///   5. Range — optional date bounds
class NewActivityWizardScreen extends ConsumerStatefulWidget {
  const NewActivityWizardScreen({
    this.initialDays,
    this.initialAdultId,
    this.initialLibraryItem,
    super.key,
  });

  final Set<int>? initialDays;

  /// Pre-selects a adult on page 4. Used when opening the wizard
  /// from the adult detail screen so "+ Add activity" already
  /// knows who the activity is for.
  final String? initialAdultId;

  /// Pre-fills the wizard from a library card — used by the
  /// activity-library screen's "Schedule" action so teachers skip
  /// the extra step of opening the library picker from inside the
  /// wizard. Same behaviour as tapping "Pick from library" and
  /// choosing this item.
  final ActivityLibraryData? initialLibraryItem;

  @override
  ConsumerState<NewActivityWizardScreen> createState() =>
      _NewActivityWizardScreenState();
}

class _NewActivityWizardScreenState
    extends ConsumerState<NewActivityWizardScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  // "Describe (optional)" — teachers want to jot a short description
  // of the activity right at creation time, not only via the rich
  // library-card flow. Writes straight through to the existing
  // ScheduleTemplates.notes column (no schema change needed).
  final _notes = TextEditingController();
  // v40: per-activity reference link. Writes to the new
  // ScheduleTemplates.sourceUrl column — independent of any library-
  // card sourceUrl. Rendered tappably on the detail sheet when set.
  final _sourceUrl = TextEditingController();

  late final Set<int> _selectedDays =
      widget.initialDays?.toSet() ??
      <int>{clampToScheduleDay(DateTime.now().weekday)};
  // Default to the next full-hour slot — if it's 10:34 now, start at
  // 11:00; 11:00 + 1h = 12:00. Beats hardcoded 9–10 which was always
  // stale the moment someone opened the wizard mid-morning.
  late TimeOfDay _start = _nextHourSlot(DateTime.now());
  late TimeOfDay _end = _addOneHour(_start);

  final Set<String> _groupIds = <String>{};
  bool _allGroups = true;

  late String? _adultId = widget.initialAdultId;

  /// Tracked room for this activity. When null, the teacher is in
  /// "custom location" mode (free-form text in [_location]) and no
  /// room conflict detection applies. When set, [_location] is treated
  /// as a display fallback only.
  String? _roomId;

  // Both dates default to concrete values so teachers don't have to
  // guess what "blank" means. Start = today; end = start + 8 weeks
  // (typical program-term length). A teacher running an activity
  // every week for the semester gets a reasonable bound baked in;
  // anyone wanting longer just pushes the end date out. Clearing
  // the end date is opt-in "forever" behavior and shows a warning.
  late DateTime? _startDate = _today();
  late DateTime? _endDate = _today().add(const Duration(days: 7 * 8));

  /// When non-null, the wizard is populated from a library item.
  ActivityLibraryData? _fromLibrary;

  @override
  void initState() {
    super.initState();
    // Constructor-param seed: when Schedule-from-library opens the
    // wizard with a card in hand, mirror the "tap Pick from library"
    // flow so the user lands on page 1 already populated.
    final seed = widget.initialLibraryItem;
    if (seed != null) {
      _fromLibrary = seed;
      _title.text = seed.title;
      if (seed.location != null) _location.text = seed.location!;
      if (seed.adultId != null) _adultId = seed.adultId;
      final dur = seed.defaultDurationMin;
      if (dur != null) {
        final startDt = DateTime(2000, 1, 1, _start.hour, _start.minute);
        final endDt = startDt.add(Duration(minutes: dur));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _sourceUrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text.trim().isNotEmpty ||
      _location.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _sourceUrl.text.trim().isNotEmpty ||
      _groupIds.isNotEmpty ||
      _adultId != null ||
      _startDate != null ||
      _endDate != null ||
      _fromLibrary != null;

  // ---- page-level helpers ----

  bool get _page1Valid => _title.text.trim().isNotEmpty;

  bool get _page2Valid =>
      _selectedDays.isNotEmpty && _minutesFor(_start) < _minutesFor(_end);

  void _pickFromLibrary(ActivityLibraryData item) {
    setState(() {
      _fromLibrary = item;
      _title.text = item.title;
      if (item.location != null) _location.text = item.location!;
      if (item.adultId != null) _adultId = item.adultId;
      final dur = item.defaultDurationMin;
      if (dur != null) {
        final startDt = DateTime(2000, 1, 1, _start.hour, _start.minute);
        final endDt = startDt.add(Duration(minutes: dur));
        _end = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
      }
    });
  }

  Future<void> _openLibraryPicker() async {
    final picked = await Navigator.of(context).push<ActivityLibraryData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LibraryPickerScreen(),
      ),
    );
    if (picked != null && mounted) _pickFromLibrary(picked);
  }

  /// Opens the rich library-item editor as a bottom sheet. On save the
  /// sheet pops with the new item's id; we resolve it to a full row and
  /// delegate to [_pickFromLibrary] so the wizard behaves identically
  /// to the "Pick from library" flow — title / location / adult /
  /// duration / sourceLibraryItemId all pre-filled from the same path.
  Future<void> _openNewLibraryCard() async {
    final newId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const EditLibraryItemSheet(),
    );
    if (newId == null || !mounted) return;
    final repo = ref.read(activityLibraryRepositoryProvider);
    final card = await repo.getItem(newId);
    if (card == null || !mounted) return;
    _pickFromLibrary(card);
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked == null || !mounted) return;
    final startMinutes = picked.hour * 60 + picked.minute;
    final endMinutes = _end.hour * 60 + _end.minute;
    setState(() {
      _start = picked;
      if (endMinutes <= startMinutes) {
        // Keep a positive-duration by default when the user pushes the
        // start past the end — nudge the end to +60 minutes.
        final bumped = DateTime(
          2000,
          1,
          1,
          picked.hour,
          picked.minute,
        ).add(const Duration(hours: 1));
        _end = TimeOfDay(hour: bumped.hour, minute: bumped.minute);
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(context: context, initialTime: _end);
    if (picked != null && mounted) setState(() => _end = picked);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    final repo = ref.read(scheduleRepositoryProvider);
    // Only carry specific group ids when the teacher actually picked some.
    // The new allGroups flag preserves the distinction between "for
    // everyone" (toggle on) and "for nobody yet" (toggle off, no groups).
    final groupIds = _allGroups ? const <String>[] : _groupIds.toList();
    final location = _location.text.trim().isEmpty
        ? null
        : _location.text.trim();
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final sourceUrl = _sourceUrl.text.trim().isEmpty
        ? null
        : _sourceUrl.text.trim();
    // If the teacher didn't touch page 5, default to "this week only"
    // instead of weekly-forever. That matches what most one-off
    // activities actually are, and keeps the schedule from filling up
    // with perpetual rows people forget about.
    final bounds = _effectiveRange();
    // One fresh series id per wizard pass, so "delete every
    // occurrence" on any tapped day can later nuke every weekday row
    // this submit is about to create.
    final seriesId = _selectedDays.length > 1 ? newId() : null;
    final createdTemplateIds = <String>[];
    for (final day in _selectedDays) {
      final templateId = await repo.addTemplate(
        dayOfWeek: day,
        startTime: Hhmm.formatLongTimeOfDay(_start),
        endTime: Hhmm.formatLongTimeOfDay(_end),
        title: _title.text.trim(),
        groupIds: groupIds,
        allGroups: _allGroups,
        adultId: _adultId,
        location: location,
        notes: notes,
        startDate: bounds.start,
        endDate: bounds.end,
        seriesId: seriesId,
        // Link back to the library row when the wizard was seeded
        // from a library pick — lets the Today detail sheet show a
        // "view activity card" affordance with the rich content.
        sourceLibraryItemId: _fromLibrary?.id,
        // Tracked room when picked; null = custom location mode
        // (location string in _location still saved as display fallback).
        roomId: _roomId,
        // v40: per-activity reference link. Null when the teacher
        // left the field blank. Independent of the library-card
        // sourceUrl copied above.
        sourceUrl: sourceUrl,
      );
      createdTemplateIds.add(templateId);
    }
    // When the wizard was seeded from a library card, log a usage
    // row per created template so the library screen's
    // "recently used" sort and per-card last-used badges update
    // immediately. One row per day keeps the count honest — a
    // Mon/Wed/Fri create = three usages of that card today.
    final fromLibrary = _fromLibrary;
    if (fromLibrary != null && createdTemplateIds.isNotEmpty) {
      final usages = ref.read(libraryUsagesRepositoryProvider);
      final usedOn = bounds.start ?? DateTime.now();
      for (final tId in createdTemplateIds) {
        await usages.logUsage(
          libraryItemId: fromLibrary.id,
          templateId: tId,
          usedOn: usedOn,
        );
      }
    }
    if (!mounted) return;
    // Hand the start date back to the caller so the schedule editor
    // can jump its week view to where the activity actually lives.
    // Without this, activities scheduled for a future date range are
    // saved correctly but invisible on the current week — the teacher
    // thinks nothing happened.
    Navigator.of(context).pop<_CreatedActivity>(
      _CreatedActivity(
        title: _title.text.trim(),
        startDate: bounds.start,
        endDate: bounds.end,
        dayCount: _selectedDays.length,
      ),
    );
  }

  ({DateTime? start, DateTime? end}) _effectiveRange() {
    if (_startDate != null || _endDate != null) {
      return (start: _startDate, end: _endDate);
    }
    final (monday, friday) = _currentProgramWeek();
    return (start: monday, end: friday);
  }

  (DateTime monday, DateTime friday) _currentProgramWeek() {
    final now = DateTime.now();
    final todayOnly = now.dayOnly;
    final monday = todayOnly.subtract(Duration(days: todayOnly.weekday - 1));
    final friday = monday.add(const Duration(days: 4));
    return (monday, friday);
  }

  // Round [now] up to the next full hour slot — e.g. 10:34 → 11:00,
  // 10:00 → 11:00. Never returns a slot that's already past, so the
  // wizard's initial time never looks stale.
  static TimeOfDay _nextHourSlot(DateTime now) {
    final nextHour = now.hour + 1;
    // Wrap midnight: 23:xx → 00:00 next day (we only care about the
    // time-of-day, the rest of the app handles the date).
    return TimeOfDay(hour: nextHour % 24, minute: 0);
  }

  // Returns [t] + 1 hour, wrapping at midnight like [_nextHourSlot].
  static TimeOfDay _addOneHour(TimeOfDay t) {
    return TimeOfDay(hour: (t.hour + 1) % 24, minute: t.minute);
  }

  static DateTime _today() {
    final n = DateTime.now();
    return n.dayOnly;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return StepWizardScaffold(
      title: 'New activity',
      dirty: _dirty,
      finalActionLabel: _selectedDays.length > 1
          ? 'Create on ${_selectedDays.length} days'
          : 'Create activity',
      onFinalAction: _submit,
      steps: [
        WizardStep(
          headline: 'What are you scheduling?',
          subtitle: 'Pick from your library, or type a new one.',
          content: _buildActivityPage(),
          canProceed: _page1Valid,
        ),
        WizardStep(
          headline: 'When does it happen?',
          subtitle: 'Pick days of the week and a time window.',
          content: _buildWhenPage(),
          canProceed: _page2Valid,
        ),
        WizardStep(
          headline: "Who's in it?",
          subtitle: 'Leave as "All groups" if the activity is for everyone.',
          content: _buildGroupsPage(),
          canSkip: true,
        ),
        WizardStep(
          headline: "Who's running it, and where?",
          subtitle: 'Assign an adult and a location if it matters.',
          content: _buildAdultPage(),
          canSkip: true,
        ),
        WizardStep(
          headline: 'How long does this run?',
          subtitle:
              'Skip to keep it to this week only. Pick dates to run it '
              'longer — a camp block, a summer session, etc.',
          content: _buildRangePage(),
          canSkip: true,
        ),
      ],
    );
  }

  // ---- page 1: activity ----

  Widget _buildActivityPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_fromLibrary != null)
          _LibraryBanner(
            item: _fromLibrary!,
            onClear: () => setState(() {
              _fromLibrary = null;
              // Don't wipe fields — teacher may still want the text.
            }),
          )
        else ...[
          // Library picker is now a separate fullscreen screen — the
          // inline grid would overflow when the library has more than a
          // handful of cards. Tapping pushes a LibraryPickerScreen that
          // shares the search + age-band filter with the Activity
          // library screen. "New library card" sits next to it so
          // teachers who haven't built up a library yet can author a
          // rich card (with AI assist, summary, hook, key points, etc.)
          // inline — save pops back with the new id, and the wizard
          // treats it exactly like a picked card.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openLibraryPicker,
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: const Text('Pick from library'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openNewLibraryCard,
                  icon: const Icon(Icons.add),
                  label: const Text('New library card'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Divider(color: theme.colorScheme.outlineVariant),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: Text(
                  'OR',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: theme.colorScheme.outlineVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppTextField(
          controller: _title,
          label: _fromLibrary == null
              ? 'Or type an activity name'
              : 'Activity name',
          hint: 'e.g. Morning circle, Swim, Field trip',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        // "Describe" writes into the existing ScheduleTemplates.notes
        // column — no schema change.
        AppTextField(
          controller: _notes,
          label: 'Describe (optional)',
          hint: 'What is this activity? What will kids do?',
          keyboardType: TextInputType.multiline,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        // v40: reference link field. Single-line URL input; persists
        // to ScheduleTemplates.sourceUrl on save. Detail sheet
        // launches it via url_launcher when set.
        AppTextField(
          controller: _sourceUrl,
          label: 'Reference link (optional)',
          hint: 'https://…',
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  // ---- page 2: when ----

  Widget _buildWhenPage() {
    final theme = Theme.of(context);
    final duration = _minutesFor(_end) - _minutesFor(_start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Days', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var d = 1; d <= scheduleDayCount; d++)
              FilterChip(
                label: Text(scheduleDayShortLabels[d - 1]),
                selected: _selectedDays.contains(d),
                onSelected: (_) => setState(() {
                  if (!_selectedDays.add(d)) _selectedDays.remove(d);
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _TimeTile(
                label: 'Starts',
                time: _start,
                onTap: _pickStart,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _TimeTile(
                label: 'Ends',
                time: _end,
                onTap: _pickEnd,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _selectedDays.isEmpty
                      ? 'Pick at least one day'
                      : _buildWhenPreview(duration),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildWhenPreview(int durationMins) {
    final days = _selectedDays.toList()..sort();
    final dayStr = days.length == 1
        ? scheduleDayLabels[days.first - 1]
        : days.map((d) => scheduleDayShortLabels[d - 1]).join(' · ');
    final timeStr = '${_formatClock(_start)} – ${_formatClock(_end)}';
    if (durationMins <= 0) {
      return '$dayStr · $timeStr (end must be after start)';
    }
    final hours = durationMins ~/ 60;
    final mins = durationMins % 60;
    final lenStr = hours == 0
        ? '$mins min'
        : (mins == 0 ? '${hours}h' : '${hours}h ${mins}m');
    return '$dayStr · $timeStr · $lenStr';
  }

  // ---- page 3: groups ----

  Widget _buildGroupsPage() {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(groupsProvider);
    final noGroupsSelected = !_allGroups && _groupIds.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('All groups'),
          subtitle: const Text(
            'Everyone at the program is included',
          ),
          value: _allGroups,
          onChanged: (v) => setState(() {
            _allGroups = v;
            if (v) _groupIds.clear();
          }),
          contentPadding: EdgeInsets.zero,
        ),
        // Clarify the "staff prep" state — this used to be a silent
        // legal-but-weird configuration. Teachers wondering if they'd
        // mis-set the toggle saw no indication either way.
        if (noGroupsSelected) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'No groups selected — saves as staff-only prep. No '
                    "children are tracked, and it won't conflict with "
                    'other activities on the same day.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (!_allGroups)
          groupsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (groups) {
              if (groups.isEmpty) {
                return Text(
                  'No groups yet — add some from the Children tab, or stay on "All groups".',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final group in groups)
                    FilterChip(
                      label: Text(group.name),
                      selected: _groupIds.contains(group.id),
                      onSelected: (_) => setState(() {
                        if (!_groupIds.add(group.id)) {
                          _groupIds.remove(group.id);
                        }
                      }),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  // ---- page 4: adult + location ----

  Widget _buildAdultPage() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Who's leading?", style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        AdultChipPicker(
          selectedId: _adultId,
          onChanged: (id) => setState(() => _adultId = id),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Location', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        RoomPicker(
          selectedRoomId: _roomId,
          customLocationController: _location,
          onRoomSelected: (id) => setState(() => _roomId = id),
        ),
      ],
    );
  }

  // ---- page 5: date range ----

  Widget _buildRangePage() {
    final bounds = _effectiveRange();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'Starts',
                value: _startDate,
                onTap: _pickStartDate,
                onClear: _startDate == null
                    ? null
                    : () => setState(() => _startDate = null),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _DateTile(
                label: 'Ends',
                value: _endDate,
                onTap: _pickEndDate,
                onClear: _endDate == null
                    ? null
                    : () => setState(() => _endDate = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _RangePreview(
          startDate: bounds.start,
          endDate: bounds.end,
          days: _selectedDays,
          isDefault: _startDate == null && _endDate == null,
        ),
      ],
    );
  }

  // ---- utils ----

  int _minutesFor(TimeOfDay t) => t.hour * 60 + t.minute;

  String _formatClock(TimeOfDay t) {
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final period = t.hour < 12 ? 'a' : 'p';
    final mins = t.minute.toString().padLeft(2, '0');
    return '$hour12:$mins$period';
  }
}

// ---------- page 1 helpers ----------

class _LibraryBanner extends StatelessWidget {
  const _LibraryBanner({required this.item, required this.onClear});

  final ActivityLibraryData item;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bookmark_outlined,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From library',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  item.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Unlink',
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

// ---------- page 2 helpers ----------

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              time.format(context),
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- page 5 helpers ----------

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? 'Pick a date' : _formatDate(value!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: value == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

class _RangePreview extends StatelessWidget {
  const _RangePreview({
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.isDefault,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> days;

  /// True when the teacher skipped the range step entirely — the dates
  /// come from the "this week only" fallback rather than their pick.
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _countOccurrences();
    final bounds = _describeBounds();
    final label = isDefault ? 'This week only · $bounds' : bounds;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            isDefault
                ? Icons.calendar_today_outlined
                : Icons.event_repeat_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == null
                  ? label
                  : '$label · ${count == 1 ? "1 occurrence" : "$count occurrences"}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _describeBounds() {
    if (startDate != null && endDate != null) {
      return '${_formatDate(startDate!)} → ${_formatDate(endDate!)}';
    }
    if (startDate != null) return 'Starts ${_formatDate(startDate!)}';
    if (endDate != null) return 'Ends ${_formatDate(endDate!)}';
    return 'No dates set';
  }

  /// Count the actual dates in the range that match the selected days.
  /// Returns null when either bound is open-ended.
  int? _countOccurrences() {
    if (startDate == null || endDate == null || days.isEmpty) return null;
    final start = startDate!.dayOnly;
    final end = endDate!.dayOnly;
    if (end.isBefore(start)) return 0;
    var count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (days.contains(d.weekday)) count++;
    }
    return count;
  }
}

/// Result handed back from the wizard so the schedule editor can jump
/// its week view and show a confirmation. Public so other callers
/// (e.g. schedule_editor_screen) can pattern-match the pop result.
class CreatedActivity {
  const CreatedActivity({
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.dayCount,
  });

  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final int dayCount;
}

// Private alias so the class stays typed in _submit's return, while
// callers reference the public name.
typedef _CreatedActivity = CreatedActivity;

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
