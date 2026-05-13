// Survey setup form (Slice 1) — the teacher-facing screen for
// configuring a new BASECamp Student Survey kiosk. Collects:
// site name, classroom, age band, 4-digit PIN, audio mode, voice.
// Saves a Survey row, then routes into the kiosk.
//
// Voice samples don't actually play in this slice — that ships in
// 2.5 alongside the bundled audio assets. The play buttons are
// wired but currently just show a "coming soon" snack.

import 'dart:async';

import 'package:basecamp/features/programs/programs_repository.dart';
import 'package:basecamp/features/surveys/canonical_questions.dart';
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
  bool _canonicalFaceColors = false;
  SurveyVoice _voice = SurveyVoice.asteria;
  SurveyStyle _style = SurveyStyle.marbleJar;

  /// Pre-configured school list for the pre-flight gate's
  /// dropdown. Seeded from `programSchoolsProvider` on first build,
  /// so a teacher who already set up schools on a previous survey
  /// (or on another device — schools live on the program now)
  /// doesn't have to retype them. Edits here are persisted back to
  /// the program on save so every future survey inherits the latest.
  final List<String> _schools = <String>[];
  bool _seededFromProgram = false;
  final TextEditingController _schoolDraftCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _siteCtrl.dispose();
    _classroomCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    _schoolDraftCtrl.dispose();
    super.dispose();
  }

  void _addSchool() {
    final raw = _schoolDraftCtrl.text.trim();
    if (raw.isEmpty) return;
    if (_schools.any((s) => s.toLowerCase() == raw.toLowerCase())) {
      // Already in the list — silently de-dupe.
      _schoolDraftCtrl.clear();
      return;
    }
    setState(() {
      _schools.add(raw);
      _schoolDraftCtrl.clear();
    });
  }

  void _removeSchool(String name) {
    setState(() {
      _schools.removeWhere((s) => s == name);
    });
  }

  Future<void> _onStart() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Persist the (possibly edited) schools list back to the
      // program so every future survey + every other device
      // inherits without retyping. Best-effort — failure to push
      // shouldn't block the survey create itself.
      final programId = ref.read(activeProgramIdProvider);
      if (programId != null) {
        await ref
            .read(programsRepositoryProvider)
            .setSchools(programId: programId, schools: _schools);
      }
      final repo = ref.read(surveyRepositoryProvider);
      final survey = await repo.create(
        siteName: _siteCtrl.text,
        classroom: _classroomCtrl.text,
        ageBand: _ageBand,
        pinDigits: _pinCtrl.text,
        audioMode: _audioMode,
        voice: _voice,
        style: _style,
        // Pick the right canonical question list for the cohort.
        // TK-G3 → 3-point; G4-G6 → 5-point + the SEL section.
        // Frozen onto the survey row's questionsJson at create
        // time, so any later edit to the canonical lists doesn't
        // disturb in-flight surveys.
        questions: canonicalQuestionsForBand(_ageBand),
        // The pre-flight gate dropdown is built from this list.
        // Empty → gate falls back to free-text. Order is preserved
        // so the most common school can sit at the top.
        schools: _schools,
        canonicalFaceColors: _canonicalFaceColors,
      );
      // Pre-warm the audio cache so the kiosk doesn't pause on the
      // first question while it fetches an MP3. Best-effort —
      // failures are silent (the kiosk falls back to running with
      // no audio for any phrase that didn't resolve).
      unawaited(
        ref.read(surveyAudioServiceProvider).prewarmForSurvey(survey),
      );
      if (!mounted) return;
      // Replace the setup route with the results screen so a
      // back-press lands the teacher at the survey list (not the
      // setup form they just filled in). The teacher tap "Start
      // kiosk" from the results screen when they're ready.
      context.pushReplacement('/surveys/${survey.id}');
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
    // Seed the schools list from the program once it's available.
    // Guarded by `_seededFromProgram` so a later edit by the
    // teacher isn't clobbered by a re-emit of the provider. The
    // mutation has to run AFTER build (post-frame) because
    // setState during build is a framework violation — without
    // that, the chip list would silently fail to render.
    final programSchools = ref.watch(programSchoolsProvider).asData?.value;
    if (!_seededFromProgram && programSchools != null) {
      _seededFromProgram = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _schools
            ..clear()
            ..addAll(
              programSchools.isEmpty ? const ['KIPP'] : programSchools,
            );
        });
      });
    }
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
              text: 'Schools',
              theme: theme,
              subtitle:
                  'Each kid picks from this list before starting. KIPP is '
                  'the default fast-path; add others as needed.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _SchoolListEditor(
              schools: _schools,
              draftCtrl: _schoolDraftCtrl,
              onAdd: _addSchool,
              onRemove: _removeSchool,
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
            const SizedBox(height: AppSpacing.lg),

            _SectionLabel(
              text: 'Style',
              theme: theme,
              subtitle:
                  'How the kid interacts with the survey. The questions + '
                  'recorded responses are identical between styles.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _StylePicker(
              value: _style,
              onChanged: (s) => setState(() => _style = s),
              theme: theme,
            ),
            // Display options only matter for the basket kiosk —
            // the marble jar uses fixed per-mood colors regardless.
            // Hidden when marble jar is selected to keep the form
            // tight; appears when the teacher picks basket.
            if (_style == SurveyStyle.basket) ...[
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel(
                text: 'Face colors',
                theme: theme,
                subtitle:
                    'The basket kiosk normally rotates a random color '
                    'palette per question so kids read the expression, '
                    'not the color. Switch on if your cohort needs the '
                    'canonical mapping (red sad → green happy).',
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                value: _canonicalFaceColors,
                onChanged: (v) =>
                    setState(() => _canonicalFaceColors = v),
                title: const Text(
                  'Canonical emotion colors (red→green)',
                ),
                subtitle: Text(
                  _canonicalFaceColors
                      ? 'Faces show red for sad, green for happy.'
                      : 'Faces rotate colors per question (anti-bias).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ],
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

/// Style picker — Marble Jar vs Basket. Two side-by-side cards
/// with a one-line description; tapped card gets a thick border
/// + tinted background. Both styles share the same questions and
/// answer-recording path; only the kid-facing UI differs.
class _StylePicker extends StatelessWidget {
  const _StylePicker({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  final SurveyStyle value;
  final ValueChanged<SurveyStyle> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in SurveyStyle.values) ...[
          Expanded(child: _StyleCard(
            style: s,
            selected: value == s,
            onTap: () => onChanged(s),
            theme: theme,
          )),
          if (s != SurveyStyle.values.last)
            const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final SurveyStyle style;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  IconData get _icon => switch (style) {
        SurveyStyle.marbleJar => Icons.sports_esports_outlined,
        SurveyStyle.basket => Icons.shopping_basket_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.4)
              : cs.surfaceContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _icon,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  style.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              style.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip-input for the survey's `schools` list. Each entry is a
/// removable chip; the row at the bottom adds a new entry on
/// Enter / submit. Saves into [SurveyConfig.schools] verbatim
/// (order preserved, exact spelling), which the kiosk's pre-
/// flight gate uses as the dropdown options.
class _SchoolListEditor extends StatelessWidget {
  const _SchoolListEditor({
    required this.schools,
    required this.draftCtrl,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> schools;
  final TextEditingController draftCtrl;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schools.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in schools)
                  InputChip(
                    label: Text(s),
                    onDeleted: () => onRemove(s),
                    deleteIconColor: theme.colorScheme.onSurfaceVariant,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: draftCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                decoration: const InputDecoration(
                  labelText: 'Add a school',
                  hintText: 'Cesar Chavez Elementary',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}
