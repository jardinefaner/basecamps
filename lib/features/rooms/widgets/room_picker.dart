import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/rooms/rooms_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room picker surface used by the activity creation + edit forms.
/// A compact chip grid of tracked rooms plus a "Custom location…"
/// option that falls back to the free-form location string.
///
/// Rooms are the authoritative location for conflict detection; the
/// custom field is an escape hatch for things that aren't rooms
/// (outside the building, ad-hoc descriptions).
class RoomPicker extends ConsumerWidget {
  const RoomPicker({
    required this.selectedRoomId,
    required this.onRoomSelected,
    required this.customLocationController,
    super.key,
  });

  /// The currently-selected room, or null when the teacher is using
  /// the free-form "custom" path.
  final String? selectedRoomId;

  /// Fired when the teacher picks a room OR explicitly picks "Custom"
  /// (passes null). Parent stores the value + clears/populates the
  /// custom controller accordingly.
  final ValueChanged<String?> onRoomSelected;

  /// Free-form location string — used when [selectedRoomId] is null
  /// (custom mode). Shared with the parent so the wizard can persist
  /// it on save.
  final TextEditingController customLocationController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roomsAsync = ref.watch(roomsProvider);
    final usingCustom = selectedRoomId == null;

    return roomsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
      data: (rooms) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'No tracked rooms yet — add some in More → Rooms to '
                  'unlock conflict detection.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final r in rooms)
                  FilterChip(
                    avatar: const Icon(Icons.meeting_room_outlined, size: 16),
                    label: Text(r.name),
                    selected: selectedRoomId == r.id,
                    onSelected: (_) => onRoomSelected(r.id),
                  ),
                FilterChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Custom…'),
                  selected: usingCustom,
                  onSelected: (_) => onRoomSelected(null),
                ),
              ],
            ),
            if (usingCustom) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: customLocationController,
                decoration: const InputDecoration(
                  labelText: 'Custom location',
                  hintText: 'e.g. North corner of the gym · Playground',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Custom locations don't participate in room conflict "
                'detection.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Static helper for resolving the default room to pre-select when the
/// teacher picks groups for an activity. Uses [RoomsRepository.defaultRoomFor]
/// — when a group has a home room, that's the pick. Returns null when
/// multiple groups are picked with conflicting defaults, or no group
/// has one.
Future<Room?> pickDefaultRoomFor({
  required WidgetRef ref,
  required List<String> groupIds,
}) async {
  if (groupIds.isEmpty) return null;
  final repo = ref.read(roomsRepositoryProvider);
  Room? firstHit;
  for (final g in groupIds) {
    final r = await repo.defaultRoomFor(g);
    if (r == null) continue;
    if (firstHit == null) {
      firstHit = r;
    } else if (firstHit.id != r.id) {
      // Two picked groups have different home rooms — no unambiguous
      // default, force the teacher to pick.
      return null;
    }
  }
  return firstHit;
}
