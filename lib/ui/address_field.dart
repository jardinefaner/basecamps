import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Editable address field with a "Open in Google Maps" button that
/// launches the system Maps app + a "Paste" button that pulls from
/// the clipboard in one tap.
///
/// Used for trip / off-site event addresses. Deliberately NOT used
/// for in-building locations — those are tracked rooms (v28) and go
/// through the RoomPicker widget instead.
///
/// Return-trip UX: once the teacher copies an address in Maps and
/// returns to the app, this field notices the clipboard has changed
/// and (if it looks address-ish) surfaces a small "Paste this?"
/// banner right above the field. One tap to use, one tap to dismiss.
/// Saves the manual paste step most of the time.
class AddressField extends StatefulWidget {
  const AddressField({
    required this.controller,
    this.label = 'Address',
    this.hint = 'e.g. Monterey Bay Aquarium',
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField>
    with WidgetsBindingObserver {
  /// Clipboard text we saw right before opening Maps. Used to detect
  /// "the teacher copied something new" on resume — if the clipboard
  /// hasn't changed we don't pester them.
  String? _preLaunchClipboard;

  /// Suggested paste text (clipboard contents that look address-ish
  /// and aren't already in the field). Null → no banner.
  String? _pasteSuggestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;
    // Only check when we actually launched Maps from this field —
    // otherwise we'd pop a paste suggestion every time the app comes
    // back from any background trip.
    if (_preLaunchClipboard == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    _preLaunchClipboard = null;
    if (text == null || text.isEmpty) return;
    if (widget.controller.text.trim() == text) return;
    if (!_looksLikeAddress(text)) return;
    if (!mounted) return;
    setState(() => _pasteSuggestion = text);
  }

  /// Soft heuristic for "clipboard contents might be an address":
  /// long enough to be real, has at least two words, and either a
  /// comma (street + city pattern) or a digit (street numbers). Skips
  /// random short copies, URLs, single words, and so on — if it
  /// guesses wrong the teacher just dismisses the banner.
  bool _looksLikeAddress(String s) {
    if (s.length < 10 || s.length > 300) return false;
    final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words < 2) return false;
    final hasComma = s.contains(',');
    final hasDigit = s.contains(RegExp(r'\d'));
    return hasComma || hasDigit;
  }

  Future<void> _openMaps() async {
    // Grab the messenger before any awaits so we don't have to
    // revalidate `context` after the background trip.
    final messenger = ScaffoldMessenger.of(context);
    final query = widget.controller.text.trim();
    // Snapshot clipboard BEFORE launching so we can tell on resume
    // whether the teacher actually copied something new.
    final snapshot = await Clipboard.getData(Clipboard.kTextPlain);
    _preLaunchClipboard = snapshot?.text ?? '';

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(query.isEmpty ? ' ' : query)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open Google Maps.")),
      );
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
      return;
    }
    _applyText(text);
  }

  void _applyText(String text) {
    widget.controller.text = text;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    widget.onChanged?.call(text);
    setState(() => _pasteSuggestion = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: widget.controller,
          label: widget.label,
          hint: widget.hint,
          onChanged: widget.onChanged,
        ),
        if (_pasteSuggestion != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _PasteSuggestionBanner(
            text: _pasteSuggestion!,
            onUse: () => _applyText(_pasteSuggestion!),
            onDismiss: () =>
                setState(() => _pasteSuggestion = null),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            TextButton.icon(
              onPressed: _openMaps,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Open in Google Maps'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste, size: 16),
              label: const Text('Paste'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small dismissable banner surfaced above the field when we notice
/// the clipboard probably holds the address the teacher just copied
/// from Maps. Tap Use → fills the field; tap × → drops the suggestion.
class _PasteSuggestionBanner extends StatelessWidget {
  const _PasteSuggestionBanner({
    required this.text,
    required this.onUse,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.content_paste,
            size: 16,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste this?',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  preview,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUse,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Use'),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            color: theme.colorScheme.onPrimaryContainer,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

/// Tappable display row for a saved address. Tap opens Google Maps
/// externally at the searched address. Use this on detail views where
/// the teacher is looking at a trip / event — not on creation forms
/// (those use [AddressField]).
class AddressRow extends StatelessWidget {
  const AddressRow({
    required this.address,
    this.icon = Icons.place_outlined,
    super.key,
  });

  final String address;
  final IconData icon;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(address.trim())}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open Google Maps.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                address,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor:
                      theme.colorScheme.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
