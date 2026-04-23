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
    if (!_looksPasteable(text)) return;
    if (!mounted) return;
    setState(() => _pasteSuggestion = text);
  }

  /// Accept either a plausible street address OR a shared link
  /// (Google Maps, Apple Maps, or any https URL the teacher dropped
  /// into the clipboard) as a paste suggestion. Links win fast —
  /// anything starting with https?:// that parses as a real Uri is
  /// almost certainly what the teacher just shared.
  bool _looksPasteable(String s) {
    if (s.length < 6 || s.length > 2000) return false;
    if (_isUrl(s)) return true;
    // Plain-text address heuristic: ≥2 words, plus a comma (street +
    // city pattern) or a digit (street numbers). Skips random short
    // copies, single words, etc.
    if (s.length < 10) return false;
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
            isUrl: _isUrl(_pasteSuggestion!),
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
    required this.isUrl,
    required this.onUse,
    required this.onDismiss,
  });

  final String text;
  final bool isUrl;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    final title = isUrl ? 'Paste Google Maps link?' : 'Paste this?';
    final icon = isUrl ? Icons.place_outlined : Icons.content_paste;
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
            icon,
            size: 16,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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

/// Returns true when [s] is an http(s) URL that parses cleanly.
/// Used in two places: the paste suggestion (label as link vs
/// address), and [AddressRow] (render + launch behavior).
bool _isUrl(String s) {
  final trimmed = s.trim();
  if (!trimmed.startsWith(RegExp('https?://'))) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  return uri.host.isNotEmpty;
}

/// Tappable display row for a saved address or shared Google Maps
/// link. Behavior branches on the content:
///
///   - If the stored value parses as an http(s) URL → render as a
///     compact "📍 Google Maps location" pill, tap launches the URL
///     directly (drops the teacher at the exact pin the sharer had
///     open, not a text-search reinterpretation of it).
///   - Otherwise → render as the plain address string, tap launches
///     a Google Maps search for the text.
///
/// Both paths use externalApplication mode so the OS-chosen maps app
/// opens (Google Maps on Android, Apple Maps on iOS unless the user
/// set a default).
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
    final trimmed = address.trim();
    // URL stored → open it as-is; the teacher shared a specific pin
    // via Maps' share sheet and we want to respect that pin, not
    // reinterpret the URL as a search term.
    final uri = _isUrl(trimmed)
        ? Uri.parse(trimmed)
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query='
            '${Uri.encodeQueryComponent(trimmed)}',
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
    final trimmed = address.trim();
    final displayText =
        _isUrl(trimmed) ? 'Google Maps location' : trimmed;
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
                displayText,
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
