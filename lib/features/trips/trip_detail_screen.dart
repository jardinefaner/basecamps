import 'package:basecamp/features/children/children_repository.dart';
import 'package:basecamp/features/forms/polymorphic/definitions/vehicle_check.dart';
import 'package:basecamp/features/forms/polymorphic/generic_form_screen.dart';
import 'package:basecamp/features/trips/trips_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/address_field.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:basecamp/ui/undo_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripProvider(tripId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Delete trip',
            onPressed: () => _confirmDelete(context, ref),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (trip) {
          if (trip == null) {
            return const Center(child: Text('Trip not found'));
          }
          final dateLabel = DateFormat.yMMMMEEEEd().format(trip.date);

          // Header — trip name + date / time range / location / groups.
          // Becomes the left column on wide screens, otherwise leads the
          // vertical stack.
          Widget buildHeader() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.name, style: theme.textTheme.displaySmall),
                const SizedBox(height: AppSpacing.sm),
                _MetaRow(icon: Icons.calendar_today_outlined, text: dateLabel),
                if (trip.departureTime != null || trip.returnTime != null)
                  _MetaRow(
                    icon: Icons.schedule_outlined,
                    text: _formatRange(
                      trip.departureTime,
                      trip.returnTime,
                    ),
                  ),
                if (trip.location != null && trip.location!.isNotEmpty)
                  // Tappable address row — opens Google Maps externally
                  // searched at the saved address. No API key / billing
                  // setup, just a URL scheme deep link.
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: AddressRow(address: trip.location!),
                  ),
                _GroupsRow(tripId: trip.id),
              ],
            );
          }

          // Body sections — attendance, notes, itinerary, journal, and
          // the vehicle-check shortcut. Each renders as its own widget
          // so we can reuse the list unchanged between narrow and wide
          // layouts.
          final bodySections = <Widget>[
            if (trip.notes != null && trip.notes!.isNotEmpty) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notes', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(trip.notes!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _RosterCard(tripId: trip.id),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Itinerary', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Coming soon — ordered stops with times and notes.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trip journal', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Coming soon — photos, observations, and notes from this trip.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Shortcut into the vehicle-check form, prefilled with this
            // trip id so the submission writes back to `tripId` on the
            // typed column. Staff doing pre-trip checks never have to
            // re-pick the trip they're already looking at.
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).push<void>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => GenericFormScreen(
                    definition: vehicleCheckForm,
                    prefillTripId: trip.id,
                  ),
                ),
              ),
              icon: const Icon(Icons.directions_bus_outlined),
              label: const Text('Run vehicle check'),
            ),
          ];

          return BreakpointBuilder(
            builder: (context, breakpoint) {
              // Narrow: existing single-column scroll. Header leads the
              // body sections vertically.
              if (breakpoint.index < Breakpoint.expanded.index) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    buildHeader(),
                    const SizedBox(height: AppSpacing.xl),
                    ...bodySections,
                  ],
                );
              }
              // Wide: 40% header on the left (identity / date / groups),
              // 60% scrolling body on the right. Trip details are
              // lightweight text, so a bit more space for the roster
              // and itinerary on the right reads better.
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 40,
                      child: SingleChildScrollView(
                        child: buildHeader(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      flex: 60,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: bodySections,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(tripsRepositoryProvider);
    final trip = await repo.getTrip(tripId);
    if (trip == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    final confirmed = await confirmDeleteWithUndo(
      context: context,
      title: 'Delete trip?',
      message: 'This also removes the trip from the calendar. Photos '
          'and observations tagged to this trip are kept. '
          "You'll get a 5-second window to undo.",
      onDelete: () => repo.deleteTrip(tripId),
      undoLabel: '"${trip.name}" removed',
      onUndo: () => repo.restoreTrip(trip),
    );
    if (!confirmed) return;
    navigator.pop();
  }

  String _formatRange(String? start, String? end) {
    String format(String hhmm) {
      final parts = hhmm.split(':');
      final h = int.parse(parts[0]);
      final m = parts[1];
      final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final period = h < 12 ? 'a' : 'p';
      return m == '00' ? '$hour12$period' : '$hour12:$m$period';
    }

    if (start != null && end != null) {
      return '${format(start)} – ${format(end)}';
    }
    if (start != null) return 'From ${format(start)}';
    if (end != null) return 'Back by ${format(end)}';
    return 'All day';
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _GroupsRow extends ConsumerWidget {
  const _GroupsRow({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupIdsAsync = ref.watch(tripGroupsProvider(tripId));
    return groupIdsAsync.maybeWhen(
      data: (groupIds) {
        if (groupIds.isEmpty) {
          return const _MetaRow(
            icon: Icons.groups_outlined,
            text: 'All groups',
          );
        }
        final names = <String>[];
        for (final id in groupIds) {
          final group = ref.watch(groupProvider(id)).asData?.value;
          if (group != null) names.add(group.name);
        }
        if (names.isEmpty) return const SizedBox.shrink();
        return _MetaRow(
          icon: Icons.groups_outlined,
          text: names.join(' + '),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RosterCard extends ConsumerWidget {
  const _RosterCard({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupIdsAsync = ref.watch(tripGroupsProvider(tripId));
    final kidsAsync = ref.watch(childrenProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Who's going", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          groupIdsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (groupIds) {
              return kidsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => Text('Error: $err'),
                data: (children) {
                  final attending = children
                      .where(
                        (k) =>
                            groupIds.isEmpty ||
                            (k.groupId != null && groupIds.contains(k.groupId)),
                      )
                      .toList();
                  if (attending.isEmpty) {
                    return Text(
                      'No children assigned to these groups yet.',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  return Text(
                    '${attending.length} '
                    '${attending.length == 1 ? "child" : "children"}: '
                    '${attending.take(3).map((k) => k.firstName).join(", ")}'
                    '${attending.length > 3 ? " + ${attending.length - 3} more" : ""}',
                    style: theme.textTheme.bodyMedium,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
