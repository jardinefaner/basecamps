import 'package:basecamp/features/auth/auth_repository.dart';
import 'package:basecamp/features/programs/invite_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Modal sheet for entering an invite code. Used by both
/// `WelcomeScreen` (zero-program user landing page) and the
/// programs screen ("Join another program" entry).
///
/// On success: redeems via the edge function, switches the
/// active program to the joined one (the bootstrap pulls + sub-
/// scribes), and pops itself with the `RedeemResult` so the
/// caller can show a "Joined Bug Week summer camp" toast.
///
/// [initialCode] pre-fills the input — used by the deep-link
/// route `/redeem/:code` so a teacher tapping a shared link in
/// their email lands on this sheet with the code already in.
class JoinWithCodeSheet extends ConsumerStatefulWidget {
  const JoinWithCodeSheet({this.initialCode, super.key});

  final String? initialCode;

  @override
  ConsumerState<JoinWithCodeSheet> createState() =>
      _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends ConsumerState<JoinWithCodeSheet> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final raw = _code.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter a code.');
      return;
    }
    // Pre-flight: redeeming requires a signed-in session because
    // the edge function reads `auth.uid()` for the membership
    // insert. Calling it unauthenticated returned an opaque
    // 401 that surfaced as "Couldn't join — Exception". Catch
    // it here so a teacher who lands on `/redeem/:code` while
    // logged out gets a clear "sign in first" hint instead.
    if (ref.read(currentSessionProvider) == null) {
      setState(() => _error =
          'Sign in to your Basecamp account first, then try the '
          'code again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await redeemAndSwitch(ref: ref, code: raw);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on RedeemError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Couldn’t join — $e';
      });
    }
  }

  Future<void> _switchAccount() async {
    // Wrong-account guard. Some teachers tap an invite link from an
    // email opened in a browser already signed in to a personal
    // Google account; the redemption would bind the adult row to
    // that personal account instead of their work account. Surface
    // a "Not you?" affordance: sign out, close the sheet, and let
    // the router bounce them to /sign-in (which will preserve the
    // /redeem/:code deep link via the existing `next` param).
    final navigator = Navigator.of(context);
    final code = _code.text.trim();
    await ref.read(authRepositoryProvider).signOut();
    if (!mounted) return;
    // Capture the messenger AFTER the await + mounted check. Capturing
    // before the await is safe-by-contract but `signOut` triggers an
    // auth-state rebuild that may remount the scaffold tree, so the
    // pre-await messenger could be detached by the time we use it.
    // Also show the snackbar BEFORE navigating — `context.go` replaces
    // the GoRouter stack synchronously and would tear this scaffold
    // down before the snack ever appears.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Signed out. Sign in with the account your admin invited.',
        ),
      ),
    );
    // Re-enter the redeem route so the auth gate re-runs and the
    // user lands back here once signed in with the right account.
    // When there's a code, `go` replaces the stack on its own — pop+go
    // in the same frame races. Pop only the no-code (modal) case.
    if (code.isNotEmpty) {
      context.go('/redeem/$code');
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(currentSessionProvider);
    final signedInEmail = session?.user.email;
    // Canonical keyboard-aware modal pattern: outer padding =
    // viewInsets.bottom (so the modal lifts as the keyboard rises),
    // inner SingleChildScrollView so content can scroll when the
    // available area is smaller than its natural height (tablets
    // with their tall keyboards are the worst offender).
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Join with code',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enter the 8-character invite code an admin shared '
              'with you. Codes are case-insensitive.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (signedInEmail != null) ...[
              const SizedBox(height: AppSpacing.md),
              // Wrong-account guard. Redeeming binds memberships
              // (and any `adult_id` carried on the invite) to the
              // currently signed-in account. If the user opened the
              // invite link in a browser session for a personal
              // account, the bind will land on the wrong user and
              // the admin will need to reconcile. Surface the email
              // they're about to redeem under and offer a one-tap
              // switch.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Joining as',
                            style:
                                theme.textTheme.labelSmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            signedInEmail,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _switchAccount,
                      child: const Text('Not you?'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                // Force uppercase + strip whitespace as the user types
                // — the code alphabet is uppercase A-Z + 2-9 only.
                FilteringTextInputFormatter.allow(
                  RegExp('[A-Za-z0-9]'),
                ),
                _UppercaseFormatter(),
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(
                labelText: 'Invite code',
                hintText: 'e.g. K7P2H4QM',
              ),
              onSubmitted: (_) => _redeem(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _redeem,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Join'),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _UppercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
