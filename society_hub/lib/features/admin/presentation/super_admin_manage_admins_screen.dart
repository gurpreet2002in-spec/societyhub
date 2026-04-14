import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final superAdminSocietyAdminsProvider = FutureProvider.family.autoDispose<List<dynamic>, String>((ref, societyId) async {
  return ref.read(apiServiceProvider).getSuperAdminSocietyAdmins(societyId);
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
        label: const Text('New Admin'),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Society Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Admin Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact Number', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
                    return;
                  }
                  try {
                    await ref.read(apiServiceProvider).superAdminCreateSocietyAdmin(
                      societyId,
                      name: nameCtrl.text,
                      email: emailCtrl.text,
                      password: passwordCtrl.text,
                      contactNumber: contactCtrl.text,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    ref.invalidate(superAdminSocietyAdminsProvider(societyId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin created successfully'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: const Text('Create Admin'),
              ),
            ),
          ],
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
