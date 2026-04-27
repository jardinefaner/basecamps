import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign-in landing page. Two flows depending on platform:
///
/// - **Web**: email magic-link form. Type email → "Send sign-in link"
///   → Supabase emails a one-click link → click it → signed in. No
///   passwords, no third-party OAuth, no hash-routing edge cases.
/// - **Native (iOS/Android)**: "Continue with Google" button.
///   Round-trips cleanly via the registered URL scheme deep link.
///
/// The two paths converge on the same [authStateProvider] and the
/// router redirects them both to /today once a session lands.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// True from the moment we kick off any sign-in network call until
  /// it resolves. Disables the button to prevent double-submit.
  bool _busy = false;

  /// Inline error for either flow — bad email, rate-limit, OAuth
  /// initiation failure, etc. Cleared on every fresh attempt.
  String? _error;

  /// Set once the magic-link email has been requested successfully.
  /// Switches the UI to the "check your inbox" state with a "use a
  /// different email" button to back out. The address is rendered
  /// into the notice copy.
  String? _magicLinkSentTo;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // On native, the OAuth round-trip leaves and reenters the app
      // via deep link; the screen's about to be torn down so don't
      // bother unsetting _busy.
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Sign-in failed: $e';
      });
    }
  }

  Future<void> _handleMagicLink() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithMagicLink(email: email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _magicLinkSentTo = email;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Couldn’t send the sign-in link: $e';
      });
    }
  }

  void _resetMagicLinkState() {
    setState(() {
      _magicLinkSentTo = null;
      _error = null;
    });
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
                if (kIsWeb)
                  _magicLinkSentTo == null
                      ? _MagicLinkForm(
                          formKey: _formKey,
                          controller: _emailCtrl,
                          busy: _busy,
                          onSubmit: _handleMagicLink,
                        )
                      : _MagicLinkSentNotice(
                          email: _magicLinkSentTo!,
                          onUseDifferentEmail: _resetMagicLinkState,
                        )
                else
                  _GoogleButton(busy: _busy, onPressed: _handleGoogle),
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

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: Text(busy ? 'Redirecting…' : 'Continue with Google'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      ),
    );
  }
}

class _MagicLinkForm extends StatelessWidget {
  const _MagicLinkForm({
    required this.formKey,
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: controller,
            enabled: !busy,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onFieldSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@school.org',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Enter your email.';
              if (!v.contains('@') || !v.contains('.')) {
                return 'That doesn’t look like an email.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.email_outlined),
            label: Text(busy ? 'Sending…' : 'Send sign-in link'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
          ),
        ],
      ),
    );
  }
}

class _MagicLinkSentNotice extends StatelessWidget {
  const _MagicLinkSentNotice({
    required this.email,
    required this.onUseDifferentEmail,
  });

  final String email;
  final VoidCallback onUseDifferentEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'We sent a sign-in link to '),
              TextSpan(
                text: email,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '. Click it to finish signing in.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        TextButton(
          onPressed: onUseDifferentEmail,
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
