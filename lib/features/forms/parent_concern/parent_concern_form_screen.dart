import 'package:basecamp/features/forms/parent_concern/parent_concern_repository.dart';
import 'package:basecamp/features/forms/widgets/form_section_card.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen editor for a Parent Concern Note. The form is broken
/// into seven cards so each section looks and feels self-contained —
/// staff can fill them in whatever order makes sense while the
/// conversation is fresh, save once, and come back to finish later.
///
/// Pass [noteId] to edit an existing row; leave null for a brand-new
/// note. Saving pops back to the list.
class ParentConcernFormScreen extends ConsumerStatefulWidget {
  const ParentConcernFormScreen({this.noteId, super.key});

  final String? noteId;

  @override
  ConsumerState<ParentConcernFormScreen> createState() =>
      _ParentConcernFormScreenState();
}

class _ParentConcernFormScreenState
    extends ConsumerState<ParentConcernFormScreen> {
  // Controllers for every text input. Booleans and dates live on [_input].
  final _childNames = TextEditingController();
  final _parentName = TextEditingController();
  final _staffReceiving = TextEditingController();
  final _supervisorNotified = TextEditingController();
  final _methodOther = TextEditingController();
  final _concernDescription = TextEditingController();
  final _immediateResponse = TextEditingController();
  final _followUpOther = TextEditingController();
  final _additionalNotes = TextEditingController();
  final _staffSignature = TextEditingController();
  final _supervisorSignature = TextEditingController();

  final _input = ParentConcernInput();
  bool _loaded = false;
  bool _submitting = false;

  bool get _isEdit => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    } else {
      _loaded = true;
      // Seed the "concern date" with today so the common case is one
      // tap fewer.
      _input.concernDate = DateTime.now();
    }
  }

  Future<void> _loadExisting() async {
    final note = await ref
        .read(parentConcernRepositoryProvider)
        .getOne(widget.noteId!);
    if (!mounted || note == null) return;
    final fromRow = ParentConcernInput.fromRow(note);
    setState(() {
      _childNames.text = fromRow.childNames;
      _parentName.text = fromRow.parentName;
      _staffReceiving.text = fromRow.staffReceiving;
      _supervisorNotified.text = fromRow.supervisorNotified ?? '';
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
        ..staffSignatureDate = fromRow.staffSignatureDate
        ..supervisorSignatureDate = fromRow.supervisorSignatureDate;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _childNames.dispose();
    _parentName.dispose();
    _staffReceiving.dispose();
    _supervisorNotified.dispose();
    _methodOther.dispose();
    _concernDescription.dispose();
    _immediateResponse.dispose();
    _followUpOther.dispose();
    _additionalNotes.dispose();
    _staffSignature.dispose();
    _supervisorSignature.dispose();
    super.dispose();
  }

  void _syncControllersToInput() {
    _input
      ..childNames = _childNames.text.trim()
      ..parentName = _parentName.text.trim()
      ..staffReceiving = _staffReceiving.text.trim()
      ..supervisorNotified = _nullIfEmpty(_supervisorNotified.text)
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

  Future<void> _delete() async {
    if (!_isEdit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(parentConcernRepositoryProvider).delete(widget.noteId!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Stamp in the current moment for a signature date. Keeps signing
  /// quick — teacher types their name, taps "Sign now", done.
  void _signNow({required bool staff}) {
    setState(() {
      if (staff) {
        _input.staffSignatureDate = DateTime.now();
      } else {
        _input.supervisorSignatureDate = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit concern note' : 'New concern note'),
        actions: [
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
                _buildAboutCard(),
                const SizedBox(height: AppSpacing.md),
                _buildMethodCard(),
                const SizedBox(height: AppSpacing.md),
                _buildConcernCard(),
                const SizedBox(height: AppSpacing.md),
                _buildResponseCard(),
                const SizedBox(height: AppSpacing.md),
                _buildFollowUpCard(),
                const SizedBox(height: AppSpacing.md),
                _buildAdditionalNotesCard(),
                const SizedBox(height: AppSpacing.md),
                _buildSignaturesCard(),
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
          _buildStickyActionBar(theme),
        ],
      ),
    );
  }

  // -------- cards --------

  Widget _buildAboutCard() {
    return FormSectionCard(
      icon: Icons.info_outline,
      title: 'About this concern',
      subtitle: 'Who, when, and who received it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _childNames,
            label: 'Child / children',
            hint: 'One or more kids involved',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _parentName,
            label: 'Parent or guardian',
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Date of concern',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          FormDateField(
            value: _input.concernDate,
            onChanged: (d) => setState(() => _input.concernDate = d),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _staffReceiving,
            label: 'Staff receiving the concern',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _supervisorNotified,
            label: 'Supervisor notified (optional)',
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard() {
    return FormSectionCard(
      icon: Icons.forum_outlined,
      title: 'Method of communication',
      subtitle: 'Select every channel that applied',
      child: Column(
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
                onSelected: (v) =>
                    setState(() => _input.methodInPerson = v),
              ),
              FilterChip(
                label: const Text('Phone'),
                avatar: const Icon(Icons.phone_outlined, size: 18),
                selected: _input.methodPhone,
                onSelected: (v) => setState(() => _input.methodPhone = v),
              ),
              FilterChip(
                label: const Text('Email'),
                avatar: const Icon(Icons.email_outlined, size: 18),
                selected: _input.methodEmail,
                onSelected: (v) => setState(() => _input.methodEmail = v),
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
      ),
    );
  }

  Widget _buildConcernCard() {
    return FormSectionCard(
      icon: Icons.flag_outlined,
      title: 'Concern reported',
      subtitle: "Brief description in the parent or guardian's words",
      child: AppTextField(
        controller: _concernDescription,
        hint: 'Briefly describe the concern shared…',
        maxLines: 6,
      ),
    );
  }

  Widget _buildResponseCard() {
    return FormSectionCard(
      icon: Icons.reply_outlined,
      title: 'Immediate response / actions taken',
      subtitle: 'What you communicated and did at the time',
      child: AppTextField(
        controller: _immediateResponse,
        hint: 'How it was handled in the moment…',
        maxLines: 6,
      ),
    );
  }

  Widget _buildFollowUpCard() {
    return FormSectionCard(
      icon: Icons.event_repeat_outlined,
      title: 'Follow-up plan',
      subtitle: 'Next steps, if any',
      child: Column(
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
                    setState(() => _input.followUpMonitor = v),
              ),
              FilterChip(
                label: const Text('Staff check-ins with child'),
                selected: _input.followUpStaffCheckIns,
                onSelected: (v) =>
                    setState(() => _input.followUpStaffCheckIns = v),
              ),
              FilterChip(
                label: const Text('Supervisor review'),
                selected: _input.followUpSupervisorReview,
                onSelected: (v) =>
                    setState(() => _input.followUpSupervisorReview = v),
              ),
              FilterChip(
                label: const Text('Parent follow-up conversation'),
                selected: _input.followUpParentConversation,
                onSelected: (v) =>
                    setState(() => _input.followUpParentConversation = v),
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
            'Follow-up date (optional)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          FormDateField(
            value: _input.followUpDate,
            onChanged: (d) => setState(() => _input.followUpDate = d),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalNotesCard() {
    return FormSectionCard(
      icon: Icons.note_outlined,
      title: 'Additional notes',
      subtitle: 'Anything else worth logging',
      child: AppTextField(
        controller: _additionalNotes,
        hint: 'Context, background, related observations…',
        maxLines: 4,
      ),
    );
  }

  Widget _buildSignaturesCard() {
    final theme = Theme.of(context);
    return FormSectionCard(
      icon: Icons.draw_outlined,
      title: 'Signatures',
      subtitle: "Type the signer's name, then tap Sign now",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _staffSignature,
            label: 'Staff signature',
            hint: 'Printed name',
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _input.staffSignatureDate == null
                      ? 'Not signed yet'
                      : 'Signed ${_formatDateTime(_input.staffSignatureDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _signNow(staff: true),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Sign now'),
              ),
              if (_input.staffSignatureDate != null)
                IconButton(
                  tooltip: 'Clear signature date',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      setState(() => _input.staffSignatureDate = null),
                ),
            ],
          ),
          const Divider(height: AppSpacing.xxl),
          AppTextField(
            controller: _supervisorSignature,
            label: 'Supervisor signature',
            hint: 'Printed name',
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _input.supervisorSignatureDate == null
                      ? 'Not signed yet'
                      : 'Signed ${_formatDateTime(_input.supervisorSignatureDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _signNow(staff: false),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Sign now'),
              ),
              if (_input.supervisorSignatureDate != null)
                IconButton(
                  tooltip: 'Clear signature date',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(
                    () => _input.supervisorSignatureDate = null,
                  ),
                ),
            ],
          ),
        ],
      ),
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
                  onPressed: _submitting ? null : _save,
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
