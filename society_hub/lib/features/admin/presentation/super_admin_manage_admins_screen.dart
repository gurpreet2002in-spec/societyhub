import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final superAdminSocietyAdminsProvider = FutureProvider.family.autoDispose<List<dynamic>, String>((ref, societyId) async {
  return ref.read(apiServiceProvider).getSuperAdminSocietyAdmins(societyId);
});

final allResidentsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getAllResidents();
});

final allSocietiesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSuperAdminSocieties();
});

class SuperAdminManageAdminsScreen extends ConsumerWidget {
  final String societyId;
  final String societyName;

  const SuperAdminManageAdminsScreen({
    super.key,
    required this.societyId,
    required this.societyName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminsAsync = ref.watch(superAdminSocietyAdminsProvider(societyId));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Admins: $societyName', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAdminDialog(context, ref),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Admin'),
      ),
      body: adminsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (admins) {
          if (admins.isEmpty) {
            return const Center(child: Text('No admins found for this society.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16).copyWith(bottom: 80),
            itemCount: admins.length,
            itemBuilder: (ctx, idx) {
              final admin = admins[idx];
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.primary.withValues(alpha: 0.1)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primary.withValues(alpha: 0.1),
                    child: Text(admin['name'][0].toUpperCase(), style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(admin['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(admin['email']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: () => _confirmDeleteAdmin(context, ref, admin),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddAdminDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    String? selectedResidentId;
    bool isExisting = false;
    String selectedSocietyId = societyId; // pre-selected: the society this screen is for
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isExisting ? 'Promote Resident' : 'Create New Admin', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => setLocalState(() => isExisting = !isExisting),
                    icon: Icon(isExisting ? Icons.add_circle_outline : Icons.search_rounded),
                    label: Text(isExisting ? 'New Account' : 'From Residents'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Society this admin will manage.
              Consumer(
                builder: (ctx, sheetRef, _) => sheetRef.watch(allSocietiesProvider).when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error loading societies: $e'),
                  data: (societies) => DropdownButtonFormField<String>(
                    value: societies.any((s) => s['id'].toString() == selectedSocietyId)
                        ? selectedSocietyId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Society'),
                    items: societies.map((s) => DropdownMenuItem<String>(
                      value: s['id'].toString(),
                      child: Text(
                        '${s['name']}${s['city'] != null && '${s['city']}'.isNotEmpty ? ' · ${s['city']}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setLocalState(() => selectedSocietyId = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (isExisting) ...[
                // The bottom sheet is its own route, so it must watch the
                // provider with its own ref (Consumer); watching through the
                // screen's ref never rebuilds the sheet and the spinner stays.
                Consumer(
                  builder: (ctx, sheetRef, _) => sheetRef.watch(allResidentsProvider).when(
                    loading: () => const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Error loading residents: $e'),
                    data: (residents) {
                      if (residents.isEmpty) return const Text('No residents found to promote.');
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Select Resident'),
                        items: residents.map((r) => DropdownMenuItem<String>(
                          value: r['id'].toString(),
                          child: Text('${r['name']} (${r['email']})', overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) {
                          final r = residents.firstWhere((res) => res['id'].toString() == v);
                          nameCtrl.text = r['name'] ?? '';
                          emailCtrl.text = r['email'] ?? '';
                          selectedResidentId = v;
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact Number')),
              ] else ...[
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Admin Name')),
                const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address')),
                const SizedBox(height: 12),
                TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min. 8 characters)')),
                const SizedBox(height: 12),
                TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact Number')),
              ],
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: isSaving ? null : () async {
                    if (emailCtrl.text.trim().isEmpty ||
                        (!isExisting && (nameCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty))) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields')));
                      return;
                    }
                    if (!isExisting && passwordCtrl.text.length < 8) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 8 characters')));
                      return;
                    }
                    setLocalState(() => isSaving = true);
                    try {
                      await ref.read(apiServiceProvider).superAdminCreateSocietyAdmin(
                        selectedSocietyId,
                        name: nameCtrl.text,
                        email: emailCtrl.text,
                        password: passwordCtrl.text,
                        contactNumber: contactCtrl.text,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      ref.invalidate(superAdminSocietyAdminsProvider(societyId));
                      ref.invalidate(superAdminSocietyAdminsProvider(selectedSocietyId));
                      ref.invalidate(allResidentsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(isExisting ? 'Resident promoted to admin' : 'Admin account created. They can log in now.'),
                            backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (ctx.mounted) setLocalState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(e.toString().replaceFirst('Exception: ', '')),
                            backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isExisting ? 'Confirm Promotion' : 'Create Admin'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAdmin(BuildContext context, WidgetRef ref, dynamic admin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Admin'),
        content: Text('Are you sure you want to delete ${admin['name']}? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(apiServiceProvider).superAdminDeleteUser(admin['id']);
                ref.invalidate(superAdminSocietyAdminsProvider(societyId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin deleted successfully'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
