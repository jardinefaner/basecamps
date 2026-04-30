import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/vehicles/vehicles_repository.dart';
import 'package:basecamp/features/vehicles/widgets/edit_vehicle_sheet.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:basecamp/ui/adaptive_sheet.dart';
import 'package:basecamp/ui/app_card.dart';
import 'package:basecamp/ui/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/more/vehicles` — list + add + edit program vehicles. Adding
/// vehicles here is what makes the vehicle-check form's picker
/// non-empty; fresh programs land on an empty-state prompting them
/// to add their first vehicle.
class VehiclesScreen extends ConsumerStatefulWidget {
  const VehiclesScreen({super.key});

  @override
  ConsumerState<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends ConsumerState<VehiclesScreen> {
  Future<void> _openSheet({Vehicle? vehicle}) async {
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) => EditVehicleSheet(vehicle: vehicle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSheet,
        icon: const Icon(Icons.add),
        label: const Text('Vehicle'),
      ),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return _EmptyState(onAdd: _openSheet);
          }
          return BreakpointBuilder(
            builder: (context, bp) {
              // Simple row tiles — default `columnsFor` ramp
              // (1 / 1 / 2 / 3) reads well at every width.
              final columns = Breakpoints.columnsFor(context);
              final hSide = bp == Breakpoint.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl;
              final padding = EdgeInsets.only(
                left: hSide,
                right: hSide,
                top: AppSpacing.md,
                bottom: AppSpacing.xxxl * 2,
              );
              Widget tileFor(int i) {
                final v = vehicles[i];
                return _VehicleTile(
                  vehicle: v,
                  onTap: () => _openSheet(vehicle: v),
                );
              }

              if (columns == 1) {
                return ListView.separated(
                  padding: padding,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => tileFor(i),
                );
              }
              return GridView.builder(
                padding: padding,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 96,
                ),
                itemCount: vehicles.length,
                itemBuilder: (_, i) => tileFor(i),
              );
            },
          );
        },
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.vehicle, required this.onTap});

  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Subtitle shows make/model and plate when set; the name alone
    // is the headline. Free-form `.` separator reads cleanly even
    // when one of the two is missing.
    final sub = <String>[];
    if (vehicle.makeModel.isNotEmpty) sub.add(vehicle.makeModel);
    if (vehicle.licensePlate.isNotEmpty) sub.add(vehicle.licensePlate);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.directions_bus_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.name, style: theme.textTheme.titleMedium),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        // Centred column keeps the copy readable at any window width.
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No vehicles yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Add the vans, buses, and cars the program operates. '
              'Once set, vehicle-check forms pick from this list '
              'instead of re-typing make/model + plate every trip.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add vehicle'),
            ),
          ],
        ),
          ),
        ),
    );
  }
}
