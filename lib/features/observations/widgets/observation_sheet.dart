import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/kids/kids_repository.dart';
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_button.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _TargetKind { kid, pod, activity }

class ObservationSheet extends ConsumerStatefulWidget {
  const ObservationSheet({super.key, this.initialKidId});

  final String? initialKidId;

  @override
  ConsumerState<ObservationSheet> createState() => _ObservationSheetState();
}

class _ObservationSheetState extends ConsumerState<ObservationSheet> {
  final _noteController = TextEditingController();
  final _activityController = TextEditingController();
  late _TargetKind _target =
      widget.initialKidId != null ? _TargetKind.kid : _TargetKind.kid;
  late String? _selectedKidId = widget.initialKidId;
  String? _selectedPodId;
  ObservationDomain _domain = ObservationDomain.social;
  ObservationSentiment _sentiment = ObservationSentiment.neutral;
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    _activityController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_noteController.text.trim().isEmpty) return false;
    return switch (_target) {
      _TargetKind.kid => _selectedKidId != null,
      _TargetKind.pod => _selectedPodId != null,
      _TargetKind.activity => _activityController.text.trim().isNotEmpty,
    };
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    await ref.read(observationsRepositoryProvider).addObservation(
          targetKind: _target.name,
          kidId: _target == _TargetKind.kid ? _selectedKidId : null,
          podId: _target == _TargetKind.pod ? _selectedPodId : null,
          activityLabel: _target == _TargetKind.activity
              ? _activityController.text.trim()
              : null,
          domain: _domain,
          sentiment: _sentiment,
          note: _noteController.text.trim(),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: AppSpacing.xl + insets,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New observation', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            Text('About', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<_TargetKind>(
              segments: const [
                ButtonSegment(value: _TargetKind.kid, label: Text('Kid')),
                ButtonSegment(value: _TargetKind.pod, label: Text('Pod')),
                ButtonSegment(
                    value: _TargetKind.activity, label: Text('Activity')),
              ],
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            _TargetPicker(
              target: _target,
              selectedKidId: _selectedKidId,
              selectedPodId: _selectedPodId,
              activityController: _activityController,
              onKidChanged: (id) => setState(() => _selectedKidId = id),
              onPodChanged: (id) => setState(() => _selectedPodId = id),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Domain', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final d in ObservationDomain.values)
                  ChoiceChip(
                    label: Text(d.label),
                    selected: _domain == d,
                    onSelected: (_) => setState(() => _domain = d),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Sentiment', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ObservationSentiment>(
              segments: const [
                ButtonSegment(
                    value: ObservationSentiment.positive,
                    label: Text('Positive'),
                    icon: Icon(Icons.sentiment_satisfied_outlined)),
                ButtonSegment(
                    value: ObservationSentiment.neutral,
                    label: Text('Neutral'),
                    icon: Icon(Icons.sentiment_neutral_outlined)),
                ButtonSegment(
                    value: ObservationSentiment.concern,
                    label: Text('Concern'),
                    icon: Icon(Icons.flag_outlined)),
              ],
              selected: {_sentiment},
              onSelectionChanged: (s) => setState(() => _sentiment = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _noteController,
              label: 'Note',
              hint: 'What did you observe?',
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton.primary(
              onPressed: _isValid ? _submit : null,
              label: 'Save observation',
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetPicker extends ConsumerWidget {
  const _TargetPicker({
    required this.target,
    required this.selectedKidId,
    required this.selectedPodId,
    required this.activityController,
    required this.onKidChanged,
    required this.onPodChanged,
  });

  final _TargetKind target;
  final String? selectedKidId;
  final String? selectedPodId;
  final TextEditingController activityController;
  final ValueChanged<String?> onKidChanged;
  final ValueChanged<String?> onPodChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (target) {
      case _TargetKind.kid:
        final kidsAsync = ref.watch(kidsProvider);
        return kidsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (kids) => DropdownButtonFormField<String>(
            initialValue: selectedKidId,
            decoration: const InputDecoration(hintText: 'Select a kid'),
            items: [
              for (final k in kids)
                DropdownMenuItem(
                  value: k.id,
                  child: Text(_kidName(k)),
                ),
            ],
            onChanged: onKidChanged,
          ),
        );
      case _TargetKind.pod:
        final podsAsync = ref.watch(podsProvider);
        return podsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Error: $err'),
          data: (pods) => DropdownButtonFormField<String>(
            initialValue: selectedPodId,
            decoration: const InputDecoration(hintText: 'Select a pod'),
            items: [
              for (final p in pods)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: onPodChanged,
          ),
        );
      case _TargetKind.activity:
        return TextField(
          controller: activityController,
          decoration: const InputDecoration(hintText: 'e.g. Morning circle'),
        );
    }
  }

  String _kidName(Kid kid) {
    final last = kid.lastName;
    if (last == null || last.isEmpty) return kid.firstName;
    final initial = last.isNotEmpty ? last[0] : '';
    return '${kid.firstName} $initial.';
  }
}
