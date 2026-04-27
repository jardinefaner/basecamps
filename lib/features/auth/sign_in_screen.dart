import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign-in landing page. Single primary action: continue with Google.
/// On tap, we kick the OAuth redirect; the browser leaves and comes
/// back with a session. The router's redirect rule swaps to /today
/// once [authStateProvider] reports a signed-in session.
///
/// No password fields, no email form, no signup vs login distinction —
/// teachers in this product already have a Google account; making
/// them invent another one is friction we don't need.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  /// True from the moment we kick off the OAuth call until we leave
  /// the page. Mostly cosmetic — on web the browser navigates away
  /// almost immediately, so the spinner flashes. Useful on slow
  /// connections and to guard against double-taps.
  bool _redirecting = false;
  String? _error;

  Future<void> _handleSignIn() async {
    if (_redirecting) return;
    setState(() {
      _redirecting = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // We don't unset _redirecting on success — the page is about to
      // unmount when the browser navigates to Google.
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _redirecting = false;
        _error = 'Sign-in failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Basecamp',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sign in to sync your program across devices.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: _redirecting ? null : _handleSignIn,
                  icon: _redirecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    _redirecting ? 'Redirecting…' : 'Continue with Google',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
