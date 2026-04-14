import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/parking_provider.dart';
import '../../../services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_glass_app_bar.dart';

class ParkingScreen extends ConsumerWidget {
  const ParkingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSlots = ref.watch(parkingProvider);
    final theme = Theme.of(context);
    final user = ref.read(apiServiceProvider).user;
    final isAdmin = user?['role'] == 'admin';

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.surface,
      appBar: const PremiumGlassAppBar(showBranding: true),
      body: asyncSlots.when(
        data: (slots) {
          final carSlots = slots.where((s) => s['type'] == 'car').toList();
          final bikeSlots = slots.where((s) => s['type'] == 'bike').toList();
          final evSlots = slots.where((s) => s['type'] == 'ev').toList();

          final totalSlots = slots.length;
          final occupied = slots.where((s) => s['status'] == 'occupied').length;
          final available = totalSlots - occupied;

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(parkingProvider),
            child: ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 24,
                left: 16,
                right: 16,
                bottom: 80,
              ),
              children: [
                // Dashboard Header Section
                Text(
                  'FACILITY MANAGEMENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Parking Control Center',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Status Badges
                Row(
                  children: [
                    _buildStatusBadge(
                      label: '$available Available',
                      color: AppTheme.secondary,
                    ),
                    const SizedBox(width: 12),
                    _buildStatusBadge(
                      label: '$occupied Occupied',
                      color: AppTheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Main Layout
                PremiumCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Level P1 - North Wing',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (carSlots.isNotEmpty) ...[
                        _sectionHeader('Car Slots', carSlots.length, theme),
                        _slotGrid(context, ref, carSlots, isAdmin),
                        const SizedBox(height: 32),
                      ],
                      if (bikeSlots.isNotEmpty) ...[
                        _sectionHeader('Bike Slots', bikeSlots.length, theme),
                        _slotGrid(context, ref, bikeSlots, isAdmin),
                        const SizedBox(height: 32),
                      ],
                      if (evSlots.isNotEmpty) ...[
                        _sectionHeader('EV Slots', evSlots.length, theme),
                        _slotGrid(context, ref, evSlots, isAdmin),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStatusBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                )
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '$count slots',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotGrid(BuildContext context, WidgetRef ref, List slots, bool isAdmin) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, 
        crossAxisSpacing: 12, 
        mainAxisSpacing: 12, 
        childAspectRatio: 0.85,
      ),
      itemCount: slots.length,
      itemBuilder: (ctx, i) {
        final s = slots[i] as Map<String, dynamic>;
        final isOccupied = s['status'] == 'occupied';
        final isEv = s['type'] == 'ev';
        final isBike = s['type'] == 'bike';

        final iconData = isEv 
            ? Icons.electric_car
            : isBike ? Icons.motorcycle
            : isOccupied ? Icons.directions_car_filled : Icons.directions_car;
            
        final iconColor = isOccupied ? AppTheme.outlineVariant : AppTheme.secondary;
        final borderColor = isOccupied ? Colors.transparent : AppTheme.primary;
        final bgColor = AppTheme.surfaceContainerLow;

        return GestureDetector(
          onTap: () => isAdmin ? _showSlotActions(ctx, ref, s) : null,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOccupied ? Colors.transparent : borderColor.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      s['slotNumber'] ?? '',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isOccupied ? AppTheme.outlineVariant : AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),
                      Icon(
                        iconData,
                        color: iconColor,
                        size: 32,
                      ),
                      if (isOccupied && s['vehicleNo'] != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s['vehicleNo'],
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSlotActions(BuildContext context, WidgetRef ref, Map<String, dynamic> slot) {
    final isOccupied = slot['status'] == 'occupied';
    final vehicleCtrl = TextEditingController();
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          left: 24,
          right: 24,
          top: 32,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isOccupied ? 'Manage Slot ${slot['slotNumber']}' : 'Assign Slot ${slot['slotNumber']}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isOccupied ? 'Currently occupied by: ${slot['vehicleNo']}' : 'Slot is currently available for allocation',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isOccupied ? AppTheme.error : AppTheme.secondary,
              ),
            ),
            const SizedBox(height: 24),
            if (!isOccupied) ...[
              _buildInputLabel('Vehicle Plate', theme),
              const SizedBox(height: 8),
              TextField(
                controller: vehicleCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. DL12AB3456',
                  hintStyle: const TextStyle(color: AppTheme.outlineVariant),
                  fillColor: AppTheme.surfaceContainerHighest,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (vehicleCtrl.text.isEmpty) return;
                  try {
                    await ref.read(parkingProvider.notifier).allocate(
                      slot['id'], 
                      '', 
                      vehicleCtrl.text, 
                      slot['type'] ?? 'car'
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Slot successfully assigned!'),
                          backgroundColor: AppTheme.secondary,
                        )
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: AppTheme.error)
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 8,
                  shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                ),
                child: const Text('CONFIRM ASSIGNMENT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              ),
            ] else ...[
              OutlinedButton(
                onPressed: () async {
                  try {
                    await ref.read(parkingProvider.notifier).release(slot['id']);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Slot successfully released!'))
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: AppTheme.error)
                      );
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                child: const Text('RELEASE SLOT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppTheme.onSurfaceVariant,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
