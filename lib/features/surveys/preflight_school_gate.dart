// Pre-flight school gate — the first screen a kid sees before
// the survey questions begin. The teacher who configured the
// survey listed which schools their kids might come from; this
// gate makes the kid pick one (or fall through to free-text).
//
// Two stages:
//
//   Stage 1 — KIPP? Yes / No
//     Big two-button screen. KIPP is the canonical fast path
//     for BASECamp programs, so it gets dedicated buttons
//     instead of being one entry in a dropdown.
//
//   Stage 2 — Pick another school (only if "No" on stage 1)
//     Renders a list of the survey's configured schools (minus
//     KIPP, which already had its chance on stage 1). Each row
//     is a tap-to-select tile. A trailing "Other…" row reveals
//     a text field for one-off schools the teacher didn't
//     pre-configure.
//
// On submission, calls [onSchoolPicked] with the resolved
// string. The kiosk uses that to stamp `survey_sessions.school`
// before showing Q1.

import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';

class PreflightSchoolGate extends StatefulWidget {
  const PreflightSchoolGate({
    required this.config,
    required this.onSchoolPicked,
    super.key,
  });

  final SurveyConfig config;

  /// Fired exactly once when the kid finalises a school choice.
  /// The string is `'KIPP'` (Yes on stage 1), or whatever they
  /// picked / typed on stage 2.
  final ValueChanged<String> onSchoolPicked;

  @override
  State<PreflightSchoolGate> createState() => _PreflightSchoolGateState();
}

enum _Stage { kippAsk, otherPick, otherType }

class _PreflightSchoolGateState extends State<PreflightSchoolGate> {
  _Stage _stage = _Stage.kippAsk;
  final TextEditingController _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  /// Configured schools minus "KIPP" (case-insensitive). KIPP
  /// already had its dedicated stage-1 button; showing it again
  /// in the stage-2 list would be redundant.
  List<String> get _otherSchools => widget.config.schools
      .where((s) => s.trim().toLowerCase() != 'kipp')
      .toList();

  void _commitKipp() => widget.onSchoolPicked('KIPP');

  void _onNoKipp() {
    final others = _otherSchools;
    if (others.isEmpty) {
      // No pre-configured list → straight to free-text input.
      setState(() => _stage = _Stage.otherType);
    } else {
      setState(() => _stage = _Stage.otherPick);
    }
  }

  void _commitOtherTyped() {
    final raw = _otherCtrl.text.trim();
    if (raw.isEmpty) return;
    widget.onSchoolPicked(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // No AppBar — the kiosk wraps this screen and provides its
      // own triple-tap exit gesture on the parent. Keeping the
      // gate borderless avoids a "settings"-flavoured chrome on
      // a screen that should feel like a question.
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: switch (_stage) {
                _Stage.kippAsk => _KippAsk(
                    onYes: _commitKipp,
                    onNo: _onNoKipp,
                    theme: theme,
                  ),
                _Stage.otherPick => _OtherPick(
                    schools: _otherSchools,
                    onPick: widget.onSchoolPicked,
                    onOther: () =>
                        setState(() => _stage = _Stage.otherType),
                    onBack: () =>
                        setState(() => _stage = _Stage.kippAsk),
                    theme: theme,
                  ),
                _Stage.otherType => _OtherType(
                    controller: _otherCtrl,
                    onSubmit: _commitOtherTyped,
                    onBack: () => setState(
                      () => _otherSchools.isEmpty
                          ? _stage = _Stage.kippAsk
                          : _stage = _Stage.otherPick,
                    ),
                    theme: theme,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _KippAsk extends StatelessWidget {
  const _KippAsk({
    required this.onYes,
    required this.onNo,
    required this.theme,
  });

  final VoidCallback onYes;
  final VoidCallback onNo;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Are you from KIPP?',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        _BigButton(
          label: 'Yes!',
          color: theme.colorScheme.primary,
          onTap: onYes,
        ),
        const SizedBox(height: AppSpacing.md),
        _BigButton(
          label: 'No',
          color: theme.colorScheme.surfaceContainerHigh,
          textColor: theme.colorScheme.onSurface,
          onTap: onNo,
        ),
      ],
    );
  }
}

class _OtherPick extends StatelessWidget {
  const _OtherPick({
    required this.schools,
    required this.onPick,
    required this.onOther,
    required this.onBack,
    required this.theme,
  });

  final List<String> schools;
  final ValueChanged<String> onPick;
  final VoidCallback onOther;
  final VoidCallback onBack;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which school?',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final s in schools) ...[
          _SchoolTile(
            label: s,
            onTap: () => onPick(s),
            theme: theme,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _SchoolTile(
          label: 'Other…',
          onTap: onOther,
          theme: theme,
          subtle: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        TextButton(
          onPressed: onBack,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _OtherType extends StatelessWidget {
  const _OtherType({
    required this.controller,
    required this.onSubmit,
    required this.onBack,
    required this.theme,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What school are you from?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            hintText: 'Type your school name',
            border: OutlineInputBorder(),
          ),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onSubmit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            textStyle: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Continue'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: onBack,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.textColor,
  });

  final String label;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: textColor ?? theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SchoolTile extends StatelessWidget {
  const _SchoolTile({
    required this.label,
    required this.onTap,
    required this.theme,
    this.subtle = false,
  });

  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: subtle
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: subtle ? FontWeight.w500 : FontWeight.w600,
                    color: subtle
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
