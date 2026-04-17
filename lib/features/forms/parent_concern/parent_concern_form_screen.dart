import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/forms/parent_concern/parent_concern_share.dart';
import 'package:basecamp/features/forms/widgets/form_section_card.dart';
import 'package:basecamp/features/forms/widgets/inline_signature_pad.dart';
import 'package:basecamp/features/forms/widgets/kid_chip_picker.dart';
import 'package:basecamp/features/forms/widgets/specialist_chip_picker.dart';
import 'package:basecamp/features/forms/widgets/voice_dictation_field.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/specialists/specialists_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:basecamp/ui/step_wizard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Layout shape for [ParentConcernFormScreen]. Creation walks the
/// teacher through the seven sections one page at a time (matches
/// the rest of the app's "new thing → wizard" convention); editing
/// keeps every section visible at once so a quick tweak is a
/// tap-and-go instead of a seven-step tour.
enum ConcernFormPresentation { wizard, scroll }

/// Full-screen editor for a Parent Concern Note. Broken into seven
/// self-contained sections staff can fill in any order. Fields that
/// take narrative text expose a mic button for Deepgram dictation,
/// and the signatures section expands an inline signature pad when
/// the teacher taps "Sign now".
///
/// Pass [noteId] to edit an existing row; leave null to start fresh.
/// [presentation] defaults to [ConcernFormPresentation.scroll] —
/// creation sites explicitly pass `wizard` so the new-note flow
/// mirrors the new-activity / new-kid wizards.
class ParentConcernFormScreen extends ConsumerStatefulWidget {
  const ParentConcernFormScreen({
    this.noteId,
    this.presentation = ConcernFormPresentation.scroll,
    super.key,
  });

  final String? noteId;
  final ConcernFormPresentation presentation;

  @override
  ConsumerState<ParentConcernFormScreen> createState() =>
      _ParentConcernFormScreenState();
}

class _ParentConcernFormScreenState
    extends ConsumerState<ParentConcernFormScreen> {
  // Controllers for every text input. Booleans, dates, selected ids,
  // and signature paths live on [_input].
  final _childNamesExtra = TextEditingController();
  final _parentName = TextEditingController();
  final _staffReceivingExtra = TextEditingController();
  final _supervisorNotifiedExtra = TextEditingController();
  final _methodOther = TextEditingController();
  final _concernDescription = TextEditingController();
  final _immediateResponse = TextEditingController();
  final _followUpOther = TextEditingController();
  final _additionalNotes = TextEditingController();
  final _staffSignature = TextEditingController();
  final _supervisorSignature = TextEditingController();

  final _input = ParentConcernInput();

  /// Kids selected via the avatar picker. Combined with
  /// [_childNamesExtra] on save — picker names come first, extras are
  /// appended comma-separated.
  final List<String> _selectedKidIds = [];

  /// Specialist picker values — null when staff typed a name by hand
  /// instead of picking from the list.
  String? _selectedStaffId;
  String? _selectedSupervisorId;

  /// Last auto-filled value for the parent field. Tracked so we only
  /// overwrite the parent name when the teacher hasn't hand-edited it
  /// since our last write.
  String _lastAutoParentText = '';

  bool _loaded = false;
  bool _submitting = false;

  bool _showStaffSigPad = false;
  bool _showSupervisorSigPad = false;

  /// Whether anything in the form has been touched since load. A
  /// dozen controllers plus half a dozen chip selectors is too many
  /// to diff explicitly — we track it imperatively with listeners
  /// on the controllers (added in [initState] after load) and flip
  /// it on every non-text `setState` that mutates [_input] or the
  /// kid / specialist picker state.
  bool _dirty = false;

  List<TextEditingController> get _allControllers => [
        _childNamesExtra,
        _parentName,
        _staffReceivingExtra,
        _supervisorNotifiedExtra,
        _methodOther,
        _concernDescription,
        _immediateResponse,
        _followUpOther,
        _additionalNotes,
        _staffSignature,
        _supervisorSignature,
      ];

  bool get _isEdit => widget.noteId != null;

  void _attachDirtyListeners() {
    for (final c in _allControllers) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  /// Wraps a `setState` with a dirty-flag bump so every picker,
  /// chip, date, and signature interaction keeps Save in sync
  /// without touching each call site twice.
  void _mutate(VoidCallback fn) {
    setState(() {
      fn();
      _dirty = true;
    });
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    } else {
      _loaded = true;
      _input.concernDate = DateTime.now();
      // Brand-new note: every keystroke counts as "dirty" from the
      // get-go, so listeners can attach right away. `_dirty` stays
      // false until the user actually types, so Save is gated by
      // both interaction AND content existing.
      _attachDirtyListeners();
    }
  }

  Future<void> _loadExisting() async {
    final note = await ref
        .read(parentConcernRepositoryProvider)
        .getOne(widget.noteId!);
    if (!mounted || note == null) return;
    final fromRow = ParentConcernInput.fromRow(note);
    setState(() {
      _childNamesExtra.text = fromRow.childNames;
      _parentName.text = fromRow.parentName;
      _staffReceivingExtra.text = fromRow.staffReceiving;
      _supervisorNotifiedExtra.text = fromRow.supervisorNotified ?? '';
      _methodOther.text = fromRow.methodOther ?? '';
      _concernDescription.text = fromRow.concernDescription;
      _immediateResponse.text = fromRow.immediateResponse;
      _followUpOther.text = fromRow.followUpOther ?? '';
      _additionalNotes.text = fromRow.additionalNotes ?? '';
      _staffSignature.text = fromRow.staffSignature ?? '';
      _supervisorSignature.text = fromRow.supervisorSignature ?? '';

      _input
        ..concernDate = fromRow.concernDate
        ..methodInPerson = fromRow.methodInPerson
        ..methodPhone = fromRow.methodPhone
        ..methodEmail = fromRow.methodEmail
        ..followUpMonitor = fromRow.followUpMonitor
        ..followUpStaffCheckIns = fromRow.followUpStaffCheckIns
        ..followUpSupervisorReview = fromRow.followUpSupervisorReview
        ..followUpParentConversation = fromRow.followUpParentConversation
        ..followUpDate = fromRow.followUpDate
        ..staffSignaturePath = fromRow.staffSignaturePath
        ..staffSignatureDate = fromRow.staffSignatureDate
        ..supervisorSignaturePath = fromRow.supervisorSignaturePath
        ..supervisorSignatureDate = fromRow.supervisorSignatureDate;
      _loaded = true;
    });
    // Wire dirty-tracking listeners AFTER we seed the controllers —
    // otherwise the initial .text assignment above would fire and
    // mark the form dirty on mount.
    _attachDirtyListeners();
  }

  @override
  void dispose() {
    _childNamesExtra.dispose();
    _parentName.dispose();
    _staffReceivingExtra.dispose();
    _supervisorNotifiedExtra.dispose();
    _methodOther.dispose();
    _concernDescription.dispose();
    _immediateResponse.dispose();
    _followUpOther.dispose();
    _additionalNotes.dispose();
    _staffSignature.dispose();
    _supervisorSignature.dispose();
    super.dispose();
  }

  // ---- kid / parent sync ----

  /// Combine selected kid names (in picker order) with anything the
  /// teacher typed into the extras field, for the serialized column.
  String _composeChildNames() {
    final kidsState = ref.read(kidsProvider).asData?.value ?? const <Kid>[];
    final selectedNames = <String>[
      for (final id in _selectedKidIds)
        if (kidsState.any((k) => k.id == id))
          _nameOf(kidsState.firstWhere((k) => k.id == id))
        else
          '',
    ];
    final extras = _childNamesExtra.text.trim();
    final parts = [
      ...selectedNames.where((n) => n.isNotEmpty),
      if (extras.isNotEmpty) extras,
    ];
    return parts.join(', ');
  }

  String _composeStaff() {
    final specialists =
        ref.read(specialistsProvider).asData?.value ?? const [];
    final picked = _selectedStaffId == null
        ? null
        : specialists
            .where((s) => s.id == _selectedStaffId)
            .map((s) => s.name)
            .firstOrNull;
    final extra = _staffReceivingExtra.text.trim();
    if (picked != null && extra.isNotEmpty) return '$picked · $extra';
    return picked ?? extra;
  }

  String? _composeSupervisor() {
    final specialists =
        ref.read(specialistsProvider).asData?.value ?? const [];
    final picked = _selectedSupervisorId == null
        ? null
        : specialists
            .where((s) => s.id == _selectedSupervisorId)
            .map((s) => s.name)
            .firstOrNull;
    final extra = _supervisorNotifiedExtra.text.trim();
    if (picked != null && extra.isNotEmpty) return '$picked · $extra';
    final out = picked ?? extra;
    return out.isEmpty ? null : out;
  }

  String _nameOf(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    return '${kid.firstName} ${last[0]}.';
  }

  /// Pulls every selected kid's parent_name, dedupes, joins. If the
  /// teacher hasn't hand-edited the parent field (its current text
  /// matches what we last wrote), we overwrite; otherwise we leave
  /// their edit alone.
  void _autoFillParent(List<String> selectedIds) {
    final kidsState = ref.read(kidsProvider).asData?.value ?? const <Kid>[];
    final parents = <String>{};
    for (final id in selectedIds) {
      final kid = kidsState.where((k) => k.id == id).firstOrNull;
      final pn = kid?.parentName?.trim();
      if (pn != null && pn.isNotEmpty) parents.add(pn);
    }
    final next = parents.join(', ');
    final current = _parentName.text.trim();
    final manuallyEdited = current.isNotEmpty &&
        current != _lastAutoParentText;

    if (!manuallyEdited) {
      _parentName.text = next;
      _lastAutoParentText = next;
    }
  }

  // ---- save / delete ----

  void _syncControllersToInput() {
    _input
      ..childNames = _composeChildNames()
      ..parentName = _parentName.text.trim()
      ..staffReceiving = _composeStaff()
      ..supervisorNotified = _composeSupervisor()
      ..methodOther = _nullIfEmpty(_methodOther.text)
      ..concernDescription = _concernDescription.text.trim()
      ..immediateResponse = _immediateResponse.text.trim()
      ..followUpOther = _nullIfEmpty(_followUpOther.text)
      ..additionalNotes = _nullIfEmpty(_additionalNotes.text)
      ..staffSignature = _nullIfEmpty(_staffSignature.text)
      ..supervisorSignature = _nullIfEmpty(_supervisorSignature.text);
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    _syncControllersToInput();
    setState(() => _submitting = true);
    final repo = ref.read(parentConcernRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.noteId!, _input);
      } else {
        await repo.create(_input);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved'),
          duration: Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $e")),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Share / print the current note. If the form is dirty, save first
  /// so the exported document reflects what's on screen. Bails quietly
  /// if the note hasn't been saved at least once — there's nothing to
  /// share from an empty new-form draft yet.
  Future<void> _share() async {
    if (!_isEdit) return;
    _syncControllersToInput();
    await ref
        .read(parentConcernRepositoryProvider)
        .update(widget.noteId!, _input);
    final note = await ref
        .read(parentConcernRepositoryProvider)
        .getOne(widget.noteId!);
    if (!mounted || note == null) return;
    await showParentConcernShareSheet(context, note);
  }

  Future<void> _delete() async {
    if (!_isEdit) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete this note?',
      message: 'This cannot be undone.',
    );
    if (!confirmed) return;
    await ref.read(parentConcernRepositoryProvider).delete(widget.noteId!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.presentation == ConcernFormPresentation.wizard) {
      return _buildWizard();
    }
    return _buildScroll(theme);
  }

  // ---- wizard layout (create flow) ----

  Widget _buildWizard() {
    return StepWizardScaffold(
      title: _isEdit ? 'Edit concern note' : 'New concern note',
      finalActionLabel: _isEdit ? 'Save changes' : 'Save note',
      onFinalAction: _save,
      steps: [
        for (final section in _sections(context))
          WizardStep(
            headline: section.title,
            subtitle: section.subtitle,
            canSkip: true,
            content: section.content,
          ),
      ],
    );
  }

  // ---- scroll layout (edit flow) ----

  Widget _buildScroll(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit concern note' : 'New concern note'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Share / print',
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
            ),
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                for (final section in _sections(context)) ...[
                  FormSectionCard(
                    icon: section.icon,
                    title: section.title,
                    subtitle: section.subtitle,
                    child: section.content,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
          _buildStickyActionBar(theme),
        ],
      ),
    );
  }

  // ---- section list (shared between scroll + wizard) ----

  List<_ConcernSection> _sections(BuildContext context) {
    return [
      _ConcernSection(
        icon: Icons.info_outline,
        title: 'About this concern',
        subtitle: 'Who, when, and who received it',
        content: _aboutContent(context),
      ),
      _ConcernSection(
        icon: Icons.forum_outlined,
        title: 'Method of communication',
        subtitle: 'Select every channel that applied',
        content: _methodContent(),
      ),
      _ConcernSection(
        icon: Icons.flag_outlined,
        title: 'Concern reported',
        subtitle: "Brief description in the parent or guardian's words",
        content: VoiceDictationField(
          controller: _concernDescription,
          hint: 'Briefly describe the concern shared…',
        ),
      ),
      _ConcernSection(
        icon: Icons.reply_outlined,
        title: 'Immediate response / actions taken',
        subtitle: 'What you communicated and did at the time',
        content: VoiceDictationField(
          controller: _immediateResponse,
          hint: 'How it was handled in the moment…',
        ),
      ),
      _ConcernSection(
        icon: Icons.event_repeat_outlined,
        title: 'Follow-up plan',
        subtitle: 'Next steps, if any',
        content: _followUpContent(context),
      ),
      _ConcernSection(
        icon: Icons.note_outlined,
        title: 'Additional notes',
        subtitle: 'Anything else worth logging',
        content: VoiceDictationField(
          controller: _additionalNotes,
          hint: 'Context, background, related observations…',
        ),
      ),
      _ConcernSection(
        icon: Icons.draw_outlined,
        title: 'Signatures',
        subtitle: 'Type the signer\u2019s name, then draw your signature',
        content: _signaturesContent(context),
      ),
    ];
  }

  // ---- section content builders ----

  Widget _aboutContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Text('Child / children', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          KidChipPicker(
            selectedIds: _selectedKidIds,
            onChanged: (ids) {
              _mutate(() {
                _selectedKidIds
                  ..clear()
                  ..addAll(ids);
              });
              _autoFillParent(ids);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _childNamesExtra,
            hint: 'Add other names (comma-separated)',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _parentName,
            label: 'Parent or guardian',
            hint: _selectedKidIds.isEmpty
                ? 'Their name'
                : 'Auto-filled from kid record — edit if needed',
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Date of concern', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          FormDateField(
            value: _input.concernDate,
            onChanged: (d) => _mutate(() => _input.concernDate = d),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Staff receiving the concern',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          SpecialistChipPicker(
            selectedId: _selectedStaffId,
            onChanged: (id) => _mutate(() => _selectedStaffId = id),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _staffReceivingExtra,
            hint: 'Or type another name',
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Supervisor notified',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          SpecialistChipPicker(
            selectedId: _selectedSupervisorId,
            onChanged: (id) => _mutate(() => _selectedSupervisorId = id),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _supervisorNotifiedExtra,
            hint: 'Or type another name (optional)',
          ),
        ],
      );
  }

  Widget _methodContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilterChip(
              label: const Text('In person'),
              avatar: const Icon(Icons.people_outline, size: 18),
              selected: _input.methodInPerson,
              onSelected: (v) => _mutate(() => _input.methodInPerson = v),
            ),
            FilterChip(
              label: const Text('Phone'),
              avatar: const Icon(Icons.phone_outlined, size: 18),
              selected: _input.methodPhone,
              onSelected: (v) => _mutate(() => _input.methodPhone = v),
            ),
            FilterChip(
              label: const Text('Email'),
              avatar: const Icon(Icons.email_outlined, size: 18),
              selected: _input.methodEmail,
              onSelected: (v) => _mutate(() => _input.methodEmail = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _methodOther,
          label: 'Other (optional)',
          hint: 'e.g. Text message, after-care chat',
        ),
      ],
    );
  }

  // concernContent + responseContent + additionalNotesContent live
  // inline in the section list — they're each a single
  // VoiceDictationField so there's no helper to factor out.

  Widget _followUpContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilterChip(
              label: const Text('Monitor situation'),
              selected: _input.followUpMonitor,
              onSelected: (v) =>
                  _mutate(() => _input.followUpMonitor = v),
            ),
            FilterChip(
              label: const Text('Staff check-ins with child'),
              selected: _input.followUpStaffCheckIns,
              onSelected: (v) =>
                  _mutate(() => _input.followUpStaffCheckIns = v),
            ),
            FilterChip(
              label: const Text('Supervisor review'),
              selected: _input.followUpSupervisorReview,
              onSelected: (v) =>
                  _mutate(() => _input.followUpSupervisorReview = v),
            ),
            FilterChip(
              label: const Text('Parent follow-up conversation'),
              selected: _input.followUpParentConversation,
              onSelected: (v) =>
                  _mutate(() => _input.followUpParentConversation = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _followUpOther,
          label: 'Other (optional)',
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Follow-up date & time (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        FormDateField(
          value: _input.followUpDate,
          includeTime: true,
          onChanged: (d) => _mutate(() => _input.followUpDate = d),
        ),
      ],
    );
  }

  Widget _signaturesContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // Staff
          AppTextField(
            controller: _staffSignature,
            label: 'Staff signature',
            hint: 'Printed name',
          ),
          const SizedBox(height: AppSpacing.sm),
          _signatureRow(
            theme: theme,
            signedAt: _input.staffSignatureDate,
            signaturePath: _input.staffSignaturePath,
            expanded: _showStaffSigPad,
            onToggle: () => setState(
              () => _showStaffSigPad = !_showStaffSigPad,
            ),
            onClear: () => _mutate(() {
              _input.staffSignaturePath = null;
              _input.staffSignatureDate = null;
            }),
          ),
          if (_showStaffSigPad)
            InlineSignaturePad(
              onSigned: (path, at) {
                _mutate(() {
                  _input.staffSignaturePath = path;
                  _input.staffSignatureDate = at;
                  _showStaffSigPad = false;
                });
              },
              onCancel: () => setState(() => _showStaffSigPad = false),
            ),

          const Divider(height: AppSpacing.xxl),

          // Supervisor
          AppTextField(
            controller: _supervisorSignature,
            label: 'Supervisor signature',
            hint: 'Printed name',
          ),
          const SizedBox(height: AppSpacing.sm),
          _signatureRow(
            theme: theme,
            signedAt: _input.supervisorSignatureDate,
            signaturePath: _input.supervisorSignaturePath,
            expanded: _showSupervisorSigPad,
            onToggle: () => setState(
              () => _showSupervisorSigPad = !_showSupervisorSigPad,
            ),
            onClear: () => _mutate(() {
              _input.supervisorSignaturePath = null;
              _input.supervisorSignatureDate = null;
            }),
          ),
          if (_showSupervisorSigPad)
            InlineSignaturePad(
              onSigned: (path, at) {
                _mutate(() {
                  _input.supervisorSignaturePath = path;
                  _input.supervisorSignatureDate = at;
                  _showSupervisorSigPad = false;
                });
              },
              onCancel: () =>
                  setState(() => _showSupervisorSigPad = false),
            ),
      ],
    );
  }

  Widget _signatureRow({
    required ThemeData theme,
    required DateTime? signedAt,
    required String? signaturePath,
    required bool expanded,
    required VoidCallback onToggle,
    required VoidCallback onClear,
  }) {
    final signed = signedAt != null && signaturePath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                signed
                    ? 'Signed ${_formatDateTime(signedAt)}'
                    : 'Not signed yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.edit_calendar_outlined,
                size: 18,
              ),
              label: Text(
                expanded
                    ? 'Hide pad'
                    : (signed ? 'Re-sign' : 'Sign now'),
              ),
            ),
            if (signed)
              IconButton(
                tooltip: 'Clear signature',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
        if (signed) SignaturePreview(path: signaturePath),
      ],
    );
  }

  Widget _buildStickyActionBar(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting || (_isEdit && !_dirty)
                      ? null
                      : _save,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isEdit ? 'Save changes' : 'Save note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
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
    final hour12 =
        dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour < 12 ? 'a' : 'p';
    final minutes = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minutes$period';
  }
}

/// Metadata + widget for one section of the concern note form. Shared
/// between the scroll layout (wrapped in a [FormSectionCard]) and the
/// wizard layout (lifted into a [WizardStep]) — same content,
/// different chrome.
class _ConcernSection {
  const _ConcernSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget content;
}
