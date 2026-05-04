// Kiosk exit PIN modal (Slice 4).
//
// The kiosk is locked down — back gestures are blocked, and the
// only way out is the teacher entering the 4-digit PIN they set
// at survey creation. This modal:
//   * shows 4 dot-indicators at the top
//   * a 0-9 number pad with a delete key
//   * shakes + clears on a wrong PIN
//   * after 3 wrong attempts, locks for 30 seconds
//   * pops the modal with `true` on success, `false` on Cancel
//
// The modal verifies via `SurveyRepository.verifyPin` (constant-
// time SHA-256 compare) so an attacker can't probe digits.

import 'dart:async';
import 'dart:math' as math;

import 'package:basecamp/features/surveys/survey_models.dart';
import 'package:basecamp/features/surveys/survey_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KioskExitPinModal extends ConsumerStatefulWidget {
  const KioskExitPinModal({required this.survey, super.key});

  final SurveyConfig survey;

  /// Convenience launcher. Returns `true` if the teacher entered
  /// the correct PIN; `false` (or null) if they cancelled.
  static Future<bool> show(BuildContext context, SurveyConfig survey) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => KioskExitPinModal(survey: survey),
    );
    return result ?? false;
  }

  @override
  ConsumerState<KioskExitPinModal> createState() =>
      _KioskExitPinModalState();
}

class _KioskExitPinModalState extends ConsumerState<KioskExitPinModal>
    with SingleTickerProviderStateMixin {
  static const _maxAttempts = 3;
  static const _lockoutSeconds = 30;

  String _entered = '';
  int _wrongAttempts = 0;
  DateTime? _lockedUntil;
  Timer? _lockoutTicker;

  late final AnimationController _shakeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _lockoutTicker?.cancel();
    super.dispose();
  }

  bool get _isLocked {
    final until = _lockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _lockoutSecondsLeft {
    final until = _lockedUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inSeconds;
  }

  void _onDigit(String d) {
    if (_isLocked) return;
    if (_entered.length >= 4) return;
    setState(() => _entered += d);
    if (_entered.length == 4) {
      _verify();
    }
  }

  void _onDelete() {
    if (_isLocked) return;
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _verify() {
    final repo = ref.read(surveyRepositoryProvider);
    final ok = repo.verifyPin(widget.survey, _entered);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _wrongAttempts += 1;
      unawaited(_shakeCtrl.forward(from: 0));
      if (_wrongAttempts >= _maxAttempts) {
        _engageLockout();
      } else {
        // Clear the entry after a beat so the teacher sees the
        // dots fill before they shake out.
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          setState(() => _entered = '');
        });
      }
    }
  }

  void _engageLockout() {
    _lockedUntil = DateTime.now().add(
      const Duration(seconds: _lockoutSeconds),
    );
    setState(() => _entered = '');
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _lockoutTicker?.cancel();
        return;
      }
      if (!_isLocked) {
        _lockoutTicker?.cancel();
        _wrongAttempts = 0;
        setState(() => _lockedUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Teacher exit',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _isLocked
                    ? 'Too many tries. Wait ${_lockoutSecondsLeft}s.'
                    : 'Enter the 4-digit PIN to exit the kiosk.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _isLocked
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) {
                  // Damped sine: fast at the start, decays.
                  final t = _shakeCtrl.value;
                  final dx = (1 - t) * 12 * math.sin(t * math.pi * 6);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: _DotsIndicator(
                  count: 4,
                  filled: _entered.length,
                  theme: theme,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _NumberPad(
                onDigit: _onDigit,
                onDelete: _onDelete,
                disabled: _isLocked,
                theme: theme,
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({
    required this.count,
    required this.filled,
    required this.theme,
  });

  final int count;
  final int filled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? theme.colorScheme.primary : Colors.transparent,
            border: Border.all(
              color: isFilled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({
    required this.onDigit,
    required this.onDelete,
    required this.disabled,
    required this.theme,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool disabled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: row.map((c) {
                  if (c.isEmpty) return const Spacer();
                  if (c == '⌫') {
                    return Expanded(
                      child: _PadButton(
                        label: c,
                        onTap: disabled ? null : onDelete,
                        theme: theme,
                      ),
                    );
                  }
                  return Expanded(
                    child: _PadButton(
                      label: c,
                      onTap: disabled ? null : () => onDigit(c),
                      theme: theme,
                    ),
                  );
                }).toList(),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.label,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final VoidCallback? onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: onTap == null ? 0.2 : 0.6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: onTap == null
                      ? theme.colorScheme.outline
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
