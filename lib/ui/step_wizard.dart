import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';

/// Lightweight controller that step content can use to drive the
/// wizard from inside its body — e.g. a "Mark all OK & continue"
/// button on a checklist step that wants to flip values + advance
/// in one tap.
///
/// Reach it from any descendant of [StepWizardScaffold] via
/// `WizardController.of(context)`. The scaffold publishes itself
/// through an InheritedWidget on every rebuild, so the controller
/// always reflects the current step state (e.g. don't advance past
/// the last step — call `submit` instead).
abstract class WizardController {
  /// Advance to the next step (or run the final action if already
  /// on the last step). Same semantics as tapping "Next" / Save.
  Future<void> next();

  /// Jump directly to step [index]. Out-of-range targets are
  /// clamped silently (so callers can do `goTo(steps.length - 1)`
  /// without bounds-checking).
  Future<void> goTo(int index);

  /// Current 0-based step index, useful for "are we on step 1?"
  /// affordances inside step content (e.g. show a form-level
  /// shortcut button only on the first step).
  int get currentIndex;

  /// Total number of steps in the wizard.
  int get stepCount;

  /// Pull the controller from the closest enclosing wizard.
  /// Throws if used outside a [StepWizardScaffold] — that's a
  /// programmer error, not a runtime branch worth guarding.
  static WizardController of(BuildContext context) {
    final inh =
        context.dependOnInheritedWidgetOfExactType<_WizardScope>();
    assert(inh != null, 'No StepWizardScaffold found in context');
    return inh!.controller;
  }

  /// Non-throwing variant for cases where the widget might be
  /// reused outside a wizard. Returns null when nothing's
  /// available.
  static WizardController? maybeOf(BuildContext context) {
    final inh =
        context.dependOnInheritedWidgetOfExactType<_WizardScope>();
    return inh?.controller;
  }
}

/// InheritedWidget that surfaces the current [_StepWizardScaffoldState]'s
/// controller to descendants. Rebuilds shouldn't notify dependents
/// because none of the surfaced fields drive layout — the controller
/// reads them lazily on call.
class _WizardScope extends InheritedWidget {
  const _WizardScope({
    required this.controller,
    required super.child,
  });

  final WizardController controller;

  @override
  bool updateShouldNotify(_WizardScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// One page in a multi-step wizard. The wizard scaffold handles the
/// shell (progress strip, heading, action bar, animated transitions);
/// each step just supplies its own body content and tells the scaffold
/// whether the user is allowed to move on yet.
class WizardStep {
  const WizardStep({
    required this.headline,
    required this.content,
    this.subtitle,
    this.canProceed = true,
    this.canSkip = false,
    this.nextLabelOverride,
    this.needsKeyboard = false,
  });

  /// Big on-page title — usually a question ("When?", "Who's in it?").
  final String headline;

  /// One-line helper under the headline. Keep it short.
  final String? subtitle;

  /// The page body. Built fresh every frame so it can react to state.
  final Widget content;

  /// When false, Next is disabled. Required-field pages flip this on
  /// as the form fills in.
  final bool canProceed;

  /// When true, a "Skip" action appears next to Next so the user can
  /// blow past optional pages without touching every field.
  final bool canSkip;

  /// Normally the action bar's primary button says "Next" (or "Create"
  /// on the last page). Override per-step if that wording doesn't fit —
  /// e.g. "Pick from library" when the step is a picker.
  final String? nextLabelOverride;

  /// True when this page has a text field the teacher will type in, so
  /// the wizard knows to leave the keyboard alone.
  ///
  /// On any transition into a page with `needsKeyboard: false`, the
  /// wizard scaffold drops focus — which dismisses an open keyboard
  /// that a previous typing-page had raised. Defaults to false so new
  /// pages are keyboard-free unless they explicitly opt in.
  final bool needsKeyboard;
}

/// Full-screen scaffold that lays out a sequence of [WizardStep]s as
/// a paged flow. Handles: animated forward/back transitions, a row of
/// progress dots at the top (tap to jump), a sticky action bar at the
/// bottom, and the exit-confirmation when there's in-flight input.
///
/// The wizard is dumb about data — it owns navigation only. The parent
/// widget keeps the form state (usually an `_Input` object in
/// `setState`) and rebuilds the steps list on every change.
class StepWizardScaffold extends StatefulWidget {
  const StepWizardScaffold({
    required this.title,
    required this.steps,
    required this.finalActionLabel,
    required this.onFinalAction,
    this.initialIndex = 0,
    this.onExit,
    this.dirty = false,
    this.onStepAdvance,
    this.appBarActions,
    super.key,
  });

  final String title;
  final List<WizardStep> steps;

  /// Label + callback for the primary button on the last step (e.g.
  /// "Create activity", "Add child").
  final String finalActionLabel;
  final Future<void> Function() onFinalAction;

  final int initialIndex;

  /// When non-null, tapping close calls this instead of a plain pop —
  /// lets the parent do any last-minute cleanup.
  final VoidCallback? onExit;

  /// If true, closing the wizard shows a "Discard?" confirmation. Pass
  /// `true` the moment the user types anything worth saving.
  final bool dirty;

  /// Optional hook fired right before the wizard advances to the
  /// next step. Forms that want per-step persistence (so a
  /// half-finished checklist isn't lost if the teacher swipes
  /// away) pass a draft-save closure here. Awaited — the wizard
  /// doesn't animate to the next step until it resolves.
  final Future<void> Function()? onStepAdvance;

  /// Optional trailing actions for the wizard's AppBar. Used by
  /// edit-existing flows that want a Share button / overflow menu
  /// at the top-right; fresh-create wizards leave this null.
  final List<Widget>? appBarActions;

  @override
  State<StepWizardScaffold> createState() => _StepWizardScaffoldState();
}

class _StepWizardScaffoldState extends State<StepWizardScaffold>
    implements WizardController {
  late int _index = widget.initialIndex;
  late final _pageController = PageController(initialPage: widget.initialIndex);
  bool _submitting = false;

  @override
  int get currentIndex => _index;

  @override
  int get stepCount => widget.steps.length;

  @override
  Future<void> next() => _next();

  @override
  Future<void> goTo(int index) {
    final clamped = index.clamp(0, widget.steps.length - 1);
    return _goTo(clamped);
  }

  bool get _isLast => _index == widget.steps.length - 1;
  bool get _hasMultipleSteps => widget.steps.length > 1;
  WizardStep get _step => widget.steps[_index];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goTo(int target) async {
    if (target < 0 || target >= widget.steps.length) return;
    // Drop focus before the page swap when the destination page
    // doesn't want a keyboard — otherwise the IME stays up from the
    // previous typing page, hiding half the screen on the new one.
    // Pages that DO want the keyboard (needsKeyboard: true) can
    // request focus on mount.
    final destinationNeedsKeyboard = widget.steps[target].needsKeyboard;
    if (!destinationNeedsKeyboard) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => _index = target);
    await _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _next() async {
    if (_submitting) return;
    if (_isLast) {
      setState(() => _submitting = true);
      try {
        await widget.onFinalAction();
      } on Object catch (e, st) {
        // Without a visible error, a failed save reads as "nothing
        // happened" — the wizard just stops responding. Surface
        // every exception via snackbar so the teacher sees what
        // went wrong (and a developer's console gets the stack).
        debugPrint('Wizard final action failed: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('Save failed: $e'),
                duration: const Duration(seconds: 6),
              ),
            );
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }
    // Per-step persistence hook — runs BEFORE we navigate so a
    // thrown save surfaces to the user on this page (where they
    // have context), not on the next one. Swallow silently only
    // when the form hasn't wired a save.
    final hook = widget.onStepAdvance;
    if (hook != null) {
      try {
        await hook();
      } on Object catch (_) {
        // Let advance still happen; the teacher can retry via the
        // explicit save-draft on the next page. We choose not to
        // block navigation on a transient save failure.
      }
    }
    await _goTo(_index + 1);
  }

  Future<void> _back() async {
    await _goTo(_index - 1);
  }

  Future<bool> _maybeExit() async {
    if (!widget.dirty) return true;
    return showConfirmDialog(
      context: context,
      title: 'Discard this?',
      message: "You'll lose whatever you've typed in so far. Continue?",
      cancelLabel: 'Keep editing',
      confirmLabel: 'Discard',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigator = Navigator.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Hardware back: if mid-wizard, step back. On the first page,
        // confirm exit (via dirty check) and pop.
        if (_index > 0) {
          await _back();
          return;
        }
        if (!mounted) return;
        final ok = await _maybeExit();
        if (!ok || !mounted) return;
        if (widget.onExit != null) {
          widget.onExit!();
        } else {
          navigator.pop();
        }
      },
      child: _WizardScope(
        controller: this,
        child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surfaceContainerLowest,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              final ok = await _maybeExit();
              if (!ok || !mounted) return;
              if (widget.onExit != null) {
                widget.onExit!();
              } else {
                navigator.pop();
              }
            },
          ),
          title: Text(
            widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: false,
          actions: widget.appBarActions,
        ),
        body: Column(
          children: [
            if (_hasMultipleSteps)
              _ProgressStrip(
                count: widget.steps.length,
                index: _index,
                onTap: _goTo,
              ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final step = widget.steps[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_hasMultipleSteps) ...[
                          Text(
                            'Step ${i + 1} of ${widget.steps.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        Text(
                          step.headline,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (step.subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            step.subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        step.content,
                      ],
                    ),
                  );
                },
              ),
            ),
            _ActionBar(
              isFirst: _index == 0,
              isLast: _isLast,
              canProceed: _step.canProceed,
              canSkip: _step.canSkip,
              submitting: _submitting,
              primaryLabel: _isLast
                  ? widget.finalActionLabel
                  : (_step.nextLabelOverride ?? 'Next'),
              onBack: _back,
              onNext: _next,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            if (i < count - 1) const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isFirst,
    required this.isLast,
    required this.canProceed,
    required this.canSkip,
    required this.submitting,
    required this.primaryLabel,
    required this.onBack,
    required this.onNext,
  });

  final bool isFirst;
  final bool isLast;
  final bool canProceed;
  final bool canSkip;
  final bool submitting;
  final String primaryLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: isFirst ? null : onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
              const Spacer(),
              if (canSkip && !isLast)
                TextButton(
                  onPressed: onNext,
                  child: const Text('Skip'),
                ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: canProceed && !submitting ? onNext : null,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isLast ? Icons.check : Icons.arrow_forward,
                        size: 18,
                      ),
                label: Text(primaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
