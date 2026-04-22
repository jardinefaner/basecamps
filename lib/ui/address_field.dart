import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Editable address field with a "Find on map" button that opens
/// Google Maps externally in search mode — teacher picks the exact
/// pin there and pastes the result back. No API key needed.
///
/// Used for trip / off-site event addresses. Deliberately NOT used
/// for in-building locations — those are tracked rooms (v28) and go
/// through the RoomPicker widget instead.
class AddressField extends StatelessWidget {
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

  Future<void> _findOnMap(BuildContext context) async {
    final query = controller.text.trim();
    // Empty query still opens Google Maps (teacher can type the
    // search term there) — more useful than blocking them.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(query.isEmpty ? ' ' : query)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open Google Maps.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: controller,
          label: label,
          hint: hint,
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _findOnMap(context),
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('Find on map'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
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
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(address.trim())}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
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
