import 'package:flutter/material.dart';

/// Curated palette for groups. Hex strings are the storage format
/// (matches the `Groups.colorHex` column); [Color] objects drive the
/// chips and swatches. Keeping the list small on purpose — a
/// well-lit dozen reads as "pick one" instead of "design a
/// group-chromatics-system from scratch".
class GroupColor {
  const GroupColor({
    required this.hex,
    required this.color,
    required this.name,
  });

  final String hex;
  final Color color;
  final String name;
}

const List<GroupColor> groupColors = <GroupColor>[
  GroupColor(hex: 'FF6B6B', color: Color(0xFFFF6B6B), name: 'Coral'),
  GroupColor(hex: 'F59E0B', color: Color(0xFFF59E0B), name: 'Amber'),
  GroupColor(hex: 'FACC15', color: Color(0xFFFACC15), name: 'Sun'),
  GroupColor(hex: '10B981', color: Color(0xFF10B981), name: 'Leaf'),
  GroupColor(hex: '06B6D4', color: Color(0xFF06B6D4), name: 'Lagoon'),
  GroupColor(hex: '3B82F6', color: Color(0xFF3B82F6), name: 'Sky'),
  GroupColor(hex: '6366F1', color: Color(0xFF6366F1), name: 'Indigo'),
  GroupColor(hex: 'A855F7', color: Color(0xFFA855F7), name: 'Violet'),
  GroupColor(hex: 'EC4899', color: Color(0xFFEC4899), name: 'Rose'),
  GroupColor(hex: '78716C', color: Color(0xFF78716C), name: 'Stone'),
];

/// Turn a stored hex string ("FF6B6B" or "#FF6B6B") into a Color.
/// Returns null for null/empty/unparseable inputs.
Color? groupColorFromHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color(value);
}
