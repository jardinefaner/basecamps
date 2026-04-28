import 'package:basecamp/features/programs/invite_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modal sheet for entering an invite code. Used by both
/// `WelcomeScreen` (zero-program user landing page) and the
/// programs screen ("Join another program" entry).
///
/// On success: redeems via the edge function, switches the
/// active program to the joined one (the bootstrap pulls + sub-
/// scribes), and pops itself with the `RedeemResult` so the
/// caller can show a "Joined Bug Week summer camp" toast.
class JoinWithCodeSheet extends ConsumerStatefulWidget {
  const JoinWithCodeSheet({super.key});

  @override
  ConsumerState<JoinWithCodeSheet> createState() =>
      _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends ConsumerState<JoinWithCodeSheet> {
  final _code = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets.bottom,
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
