import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_button.dart';

final myVehiclesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getMyVehicles();
});

class ResidentVehiclesScreen extends ConsumerWidget {
  const ResidentVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final vehiclesAsync = ref.watch(myVehiclesProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: const PremiumGlassAppBar(
        showBranding: false,
        title: Text('My Vehicles'),
      ),
      floatingActionButton: PremiumButton(
        onPressed: () => _showAddVehicleDialog(context, ref),
        label: 'Add Vehicle',
        icon: Icons.add_rounded,
      ),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car_rounded, size: 64, color: Color(0xFF616161)),
                  SizedBox(height: 16),
                  Text('No vehicles added yet.', style: TextStyle(color: Color(0xFF616161))),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vehicles.length,
            itemBuilder: (context, i) {
              final v = vehicles[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PremiumCard(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: Icon(
                        v['vehicle_type'] == 'car' ? Icons.directions_car : Icons.directions_bike,
                        color: colors.primary,
                      ),
                    ),
                    title: Text(
                      v['vehicle_number'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Text('${v['brand_model'] ?? 'N/A'} \u2022 ${v['color'] ?? 'N/A'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _handleDelete(context, ref, v['id']),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _handleDelete(BuildContext context, WidgetRef ref, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: const Text('Are you sure you want to remove this vehicle?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(apiServiceProvider).removeMyVehicle(id);
      ref.invalidate(myVehiclesProvider);
    }
  }

  void _showAddVehicleDialog(BuildContext context, WidgetRef ref) {
    final vNo = TextEditingController();
    final model = TextEditingController();
    final color = TextEditingController();
    String type = 'car';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Vehicle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'car', child: Text('Car')),
                    DropdownMenuItem(value: 'bike', child: Text('Bike')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (val) => setState(() => type = val!),
                ),
                TextField(
                  controller: vNo,
                  decoration: const InputDecoration(labelText: 'Vehicle Number (e.g. MH12AB1234)'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextField(controller: model, decoration: const InputDecoration(labelText: 'Brand & Model (e.g. Tata Nexon)')),
                TextField(controller: color, decoration: const InputDecoration(labelText: 'Color')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            PremiumButton(
              onPressed: () async {
                if (vNo.text.isEmpty) return;
                try {
                  await ref.read(apiServiceProvider).addMyVehicle(
                    vehicleNumber: vNo.text,
                    vehicleType: type,
                    brandModel: model.text,
                    color: color.text,
                  );
                  ref.invalidate(myVehiclesProvider);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              label: 'Add',
            ),
          ],
        ),
      ),
    );
  }
}
