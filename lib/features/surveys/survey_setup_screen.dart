// Survey setup form (Slice 1) — the teacher-facing screen for
// configuring a new BASECamp Student Survey kiosk. Collects:
// site name, classroom, age band, 4-digit PIN, audio mode, voice.
// Saves a Survey row, then routes into the kiosk.
//
// Voice samples don't actually play in this slice — that ships in
// 2.5 alongside the bundled audio assets. The play buttons are
// wired but currently just show a "coming soon" snack.

import 'dart:async';

import 'package:basecamp/features/surveys/survey_audio_service.dart';
import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SurveySetupScreen extends ConsumerStatefulWidget {
  const SurveySetupScreen({super.key});

  @override
  ConsumerState<SurveySetupScreen> createState() => _SurveySetupScreenState();
}

class _SurveySetupScreenState extends ConsumerState<SurveySetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _siteCtrl = TextEditingController();
  final _classroomCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();

  SurveyAgeBand _ageBand = SurveyAgeBand.tk;
  SurveyAudioMode _audioMode = SurveyAudioMode.full;
  SurveyVoice _voice = SurveyVoice.asteria;

  bool _saving = false;

  @override
  void dispose() {
    _siteCtrl.dispose();
    _classroomCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onStart() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(surveyRepositoryProvider);
      final survey = await repo.create(
        siteName: _siteCtrl.text,
        classroom: _classroomCtrl.text,
        ageBand: _ageBand,
        pinDigits: _pinCtrl.text,
        audioMode: _audioMode,
        voice: _voice,
      );
      if (!mounted) return;
      // Replace the setup route with the kiosk so a back-press
      // from the kiosk drops the teacher back at the survey list,
      // not the setup form they just filled in.
      context.pushReplacement(
        '/experiment/surveys/${survey.id}/play',
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save survey: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New Survey')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _SectionLabel(text: 'Where', theme: theme),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _siteCtrl,
              decoration: const InputDecoration(
                labelText: 'Site name',
                hintText: 'Sunrise Elementary',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _classroomCtrl,
              decoration: const InputDecoration(
                labelText: 'Classroom',
                hintText: 'Room 12 / Ms. Patel',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel(text: 'Age band', theme: theme),
            const SizedBox(height: AppSpacing.sm),
            _AgeBandPicker(
              value: _ageBand,
              onChanged: (b) => setState(() => _ageBand = b),
              theme: theme,
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel(
              text: 'Teacher PIN',
              theme: theme,
              subtitle:
                  '4 digits. Triple-tap the title in kiosk + this PIN to exit.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _pinCtrl,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length != 4) ? '4 digits' : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _pinConfirmCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Confirm',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.length != 4) return '4 digits';
                      if (v != _pinCtrl.text) return "Doesn't match";
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel(text: 'Audio prompts', theme: theme),
            const SizedBox(height: AppSpacing.sm),
            _AudioModePicker(
              value: _audioMode,
              onChanged: (m) => setState(() => _audioMode = m),
              theme: theme,
            ),
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel(
              text: 'Voice',
              theme: theme,
              subtitle:
                  'Pick a voice for the questions + nudges. Tap ▶ to preview.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _VoicePicker(
              value: _voice,
              onChanged: (v) => setState(() => _voice = v),
              theme: theme,
            ),
            const SizedBox(height: AppSpacing.xxl),

            FilledButton.icon(
              onPressed: _saving ? null : _onStart,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_saving ? 'Saving…' : 'Save & Start'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _saving ? null : () => context.pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.text,
    required this.theme,
    this.subtitle,
  });

  final String text;
  final ThemeData theme;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _AgeBandPicker extends StatelessWidget {
  const _AgeBandPicker({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final SurveyAgeBand value;
  final ValueChanged<SurveyAgeBand> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: SurveyAgeBand.values.map((b) {
        final selected = b == value;
        return ChoiceChip(
          label: Text(b.label),
          selected: selected,
          onSelected: (_) => onChanged(b),
        );
      }).toList(),
    );
  }
}

class _AudioModePicker extends StatelessWidget {
  const _AudioModePicker({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final SurveyAudioMode value;
  final ValueChanged<SurveyAudioMode> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: SurveyAudioMode.values.map((m) {
        return RadioListTile<SurveyAudioMode>(
          title: Text(m.label),
          value: m,
          // RadioListTile.groupValue/onChanged were deprecated in
          // a recent Flutter release in favor of RadioGroup. The
          // newer API isn't available across all our SDK targets
          // yet, so we use the legacy form here.
          // Same legacy-API caveat as the line above.
          // ignore: deprecated_member_use
          groupValue: value,
          // Legacy onChanged matches groupValue.
          // ignore: deprecated_member_use
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          dense: true,
          contentPadding: EdgeInsets.zero,
        );
      }).toList(),
    );
  }
}

class _VoicePicker extends ConsumerWidget {
  const _VoicePicker({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final SurveyVoice value;
  final ValueChanged<SurveyVoice> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final female = SurveyVoice.female;
    final male = SurveyVoice.male;
    return Column(
      children: [
        for (var i = 0; i < female.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: _VoiceTile(
                    voice: female[i],
                    selected: value == female[i],
                    onSelected: () => onChanged(female[i]),
                    theme: theme,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _VoiceTile(
                    voice: male[i],
                    selected: value == male[i],
                    onSelected: () => onChanged(male[i]),
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _VoiceTile extends ConsumerWidget {
  const _VoiceTile({
    required this.voice,
    required this.selected,
    required this.onSelected,
    required this.theme,
  });

  final SurveyVoice voice;
  final bool selected;
  final VoidCallback onSelected;
  final ThemeData theme;

  void _previewSample(BuildContext context, WidgetRef ref) {
    final audio = ref.read(surveyAudioServiceProvider);
    // Fire-and-forget: when assets aren't generated yet the
    // service silently no-ops (returns without playing).
    unawaited(audio.playSample(voice));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.4 : 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      voice.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      voice.tagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _previewSample(context, ref),
                icon: const Icon(Icons.play_circle_outline),
                visualDensity: VisualDensity.compact,
                tooltip: 'Preview',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
