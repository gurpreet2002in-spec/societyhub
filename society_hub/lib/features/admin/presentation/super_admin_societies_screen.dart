import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_button.dart';

final superAdminSocietiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminSocieties();
});

class SuperAdminSocietiesScreen extends ConsumerStatefulWidget {
  const SuperAdminSocietiesScreen({super.key});

  @override
  ConsumerState<SuperAdminSocietiesScreen> createState() => _SuperAdminSocietiesScreenState();
}

class _SuperAdminSocietiesScreenState extends ConsumerState<SuperAdminSocietiesScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final societiesAsync = ref.watch(superAdminSocietiesProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: const PremiumGlassAppBar(showBranding: true),
      floatingActionButton: PremiumButton(
        onPressed: () => _showAddSocietyDialog(context),
        label: 'New Society',
        icon: Icons.add_business_rounded,
      ),
      body: societiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (societies) {
          if (societies.isEmpty) {
            return const Center(child: Text('No societies found.', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16).copyWith(bottom: 100),
            itemCount: societies.length,
            itemBuilder: (context, i) {
              final soc = societies[i];
              return _buildSocietyCard(context, soc, colors);
            },
          );
        },
      ),
    );
  }

  Widget _buildSocietyCard(BuildContext context, Map<String, dynamic> soc, ColorScheme colors) {
    final bool isActive = soc['subscriptionStatus'] == 'active';
    final planColor = soc['subscriptionPlan'] == 'premium' ? Colors.orange : Colors.blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PremiumCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.maps_home_work_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          soc['name'] ?? 'Society Name',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${soc['city']} \u2022 Reg: ${soc['registrationNumber'] ?? 'N/A'}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: planColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (soc['subscriptionPlan'] ?? 'basic').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: planColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem(Icons.people_rounded, '${soc['totalUsers'] ?? 0} Users', colors.secondary),
                  _buildStatItem(
                    isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    isActive ? 'Active' : 'Suspended',
                    isActive ? Colors.green : Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colors.outlineVariant),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/super_admin/societies/${soc['id']}/admins', extra: {'name': soc['name']}),
                    icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                    label: const Text('Admins'),
                    style: TextButton.styleFrom(foregroundColor: colors.primary),
                  ),
                  const SizedBox(width: 8),
                  if (!isActive) ...[
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(apiServiceProvider).superAdminUpdateSociety(
                            soc['id'], 
                            name: soc['name'], 
                            address: soc['address'], 
                            city: soc['city'],
                            subscriptionStatus: 'active', 
                            subscriptionPlan: soc['subscriptionPlan'] ?? 'basic',
                          );
                          ref.invalidate(superAdminSocietiesProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Society Unsuspended successfully'), backgroundColor: Colors.green)
                            );
                          }
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      },
                      icon: const Icon(Icons.play_circle_filled_rounded, size: 18),
                      label: const Text('Unsuspend'),
                      style: TextButton.styleFrom(foregroundColor: Colors.green),
                    ),
                    const SizedBox(width: 8),
                  ],
                  PremiumButton(
                    onPressed: () => _showEditSocietyDialog(context, soc),
                    label: 'Manage Setup',
                    isSecondary: true,
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  void _showAddSocietyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String plan = 'basic';
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Add New Society', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Society Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Address *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cityCtrl,
                decoration: InputDecoration(
                  labelText: 'City *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: regCtrl,
                decoration: InputDecoration(
                  labelText: 'Registration Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: InputDecoration(
                  labelText: 'Subscription Plan',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                dropdownColor: colors.surfaceContainer,
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Free Trial')),
                  DropdownMenuItem(value: 'basic', child: Text('Basic Tier')),
                  DropdownMenuItem(value: 'premium', child: Text('Premium Tier')),
                ],
                onChanged: (v) => setState(() => plan = v!),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: PremiumButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || cityCtrl.text.isEmpty || addressCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields')));
                      return;
                    }
                    try {
                      await ref.read(apiServiceProvider).superAdminCreateSociety(
                        name: nameCtrl.text, address: addressCtrl.text, city: cityCtrl.text,
                        registrationNumber: regCtrl.text, subscriptionPlan: plan,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      ref.invalidate(superAdminSocietiesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u2705 Society onboarded successfully'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  },
                  label: 'Create Society',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSocietyDialog(BuildContext context, Map<String, dynamic> soc) {
    final nameCtrl = TextEditingController(text: soc['name']);
    final addressCtrl = TextEditingController(text: soc['address']);
    final cityCtrl = TextEditingController(text: soc['city']);
    String status = soc['subscriptionStatus'] ?? 'active';
    String plan = soc['subscriptionPlan'] ?? 'basic';
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Manage Tenant Setup', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Society Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressCtrl,
                decoration: InputDecoration(
                  labelText: 'Address *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cityCtrl,
                decoration: InputDecoration(
                  labelText: 'City *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Account Status',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                dropdownColor: colors.surfaceContainer,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                ],
                onChanged: (v) => setState(() => status = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: plan,
                decoration: InputDecoration(
                  labelText: 'Subscription Plan',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                dropdownColor: colors.surfaceContainer,
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Free Trial')),
                  DropdownMenuItem(value: 'basic', child: Text('Basic Tier')),
                  DropdownMenuItem(value: 'premium', child: Text('Premium Tier')),
                ],
                onChanged: (v) => setState(() => plan = v!),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: PremiumButton(
                  onPressed: () async {
                    try {
                      await ref.read(apiServiceProvider).superAdminUpdateSociety(
                        soc['id'], name: nameCtrl.text, address: addressCtrl.text, city: cityCtrl.text,
                        subscriptionStatus: status, subscriptionPlan: plan,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      ref.invalidate(superAdminSocietiesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u2705 Tenant updated successfully'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  },
                  label: 'Save Subscriptions',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
