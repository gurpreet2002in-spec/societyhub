import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../services/api_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(apiServiceProvider).user;
    final colors = Theme.of(context).colorScheme;
    final isAdmin = user?['role'] == 'admin';

    return Scaffold(
      backgroundColor: colors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: colors.primary,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                tooltip: 'Edit Profile',
                onPressed: () => context.push('/profile/edit'),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                tooltip: 'Logout',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => ctx.pop(true), child: const Text('Logout')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colors.primary, const Color(0xFF1E1B4B)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.white24,
                        child: Text(
                          (user?['name'] ?? 'R').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?['name'] ?? 'Resident',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAdmin ? '\u00F0\u0178\u2018\u2018 Admin' : '\u00F0\u0178\u008F\u00A0 Resident',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Info Card
                  _buildInfoCard(context, user, colors),
                  const SizedBox(height: 24),

                  // My Account
                  _buildSectionLabel('MY ACCOUNT'),
                  const SizedBox(height: 12),
                  _buildOptionCard(context, [
                    _OptionItem(
                      icon: Icons.directions_car_rounded,
                      color: Colors.blueAccent,
                      title: 'My Vehicles',
                      subtitle: 'Manage your registered vehicles',
                      onTap: () => context.push('/parking'),
                    ),
                    _OptionItem(
                      icon: Icons.group_rounded,
                      color: Colors.green,
                      title: 'My Visitors',
                      subtitle: 'View & manage visitor passes',
                      onTap: () => context.push('/visitors'),
                    ),
                    _OptionItem(
                      icon: Icons.storefront_rounded,
                      color: Colors.orange,
                      title: 'Marketplace Listings',
                      subtitle: 'Items you are selling',
                      onTap: () => context.push('/marketplace'),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // Quick Links
                  _buildSectionLabel('QUICK LINKS'),
                  const SizedBox(height: 12),
                  _buildOptionCard(context, [
                    _OptionItem(
                      icon: Icons.account_balance_wallet_rounded,
                      color: Colors.teal,
                      title: 'My Payments',
                      subtitle: 'Dues & payment history',
                      onTap: () => context.go('/payments'),
                    ),
                    _OptionItem(
                      icon: Icons.construction_rounded,
                      color: Colors.deepOrange,
                      title: 'My Complaints',
                      subtitle: 'Service requests & status',
                      onTap: () => context.go('/complaints'),
                    ),
                    _OptionItem(
                      icon: Icons.cleaning_services_rounded,
                      color: Colors.purple,
                      title: 'Daily Help',
                      subtitle: 'Manage household staff',
                      onTap: () => context.push('/daily-help'),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // Admin Section (visible only to admins)
                  if (isAdmin) ...[
                    _buildSectionLabel('ADMINISTRATION'),
                    const SizedBox(height: 12),
                    _buildOptionCard(context, [
                      _OptionItem(
                        icon: Icons.people_alt_rounded,
                        color: Colors.indigo,
                        title: 'User Management',
                        subtitle: 'Manage residents & staff',
                        onTap: () => context.push('/admin/users'),
                      ),
                      _OptionItem(
                        icon: Icons.apartment_rounded,
                        color: Colors.cyan,
                        title: 'Society Settings',
                        subtitle: 'Configure society details',
                        onTap: () => context.push('/admin/society'),
                      ),
                      _OptionItem(
                        icon: Icons.bar_chart_rounded,
                        color: Colors.green,
                        title: 'Reports & Analytics',
                        subtitle: 'Financial & operational reports',
                        onTap: () => context.push('/reports'),
                      ),
                      _OptionItem(
                        icon: Icons.request_quote_rounded,
                        color: Colors.amber,
                        title: 'Billing Management',
                        subtitle: 'Generate & manage invoices',
                        onTap: () => context.push('/admin/billing'),
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],

                  // Danger Zone
                  _buildSectionLabel('ACCOUNT'),
                  const SizedBox(height: 12),
                  _buildOptionCard(context, [
                    _OptionItem(
                      icon: Icons.lock_reset_rounded,
                      color: Colors.blueGrey,
                      title: 'Change Password',
                      subtitle: 'Update your account password',
                      onTap: () => _showChangePasswordDialog(context, ref),
                    ),
                    _OptionItem(
                      icon: Icons.logout_rounded,
                      color: Colors.red,
                      title: 'Logout',
                      subtitle: 'Sign out of your account',
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to logout?'),
                            actions: [
                              TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => ctx.pop(true),
                                child: const Text('Logout'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) context.go('/login');
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, Map<String, dynamic>? user, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.email_rounded, 'Email', user?['email'] ?? 'N/A', colors),
          const Divider(height: 24),
          _buildInfoRow(Icons.phone_rounded, 'Contact', user?['contactNumber'] ?? 'Not set', colors),
          const Divider(height: 24),
          _buildInfoRow(Icons.apartment_rounded, 'Flat', user?['apartmentNumber'] ?? user?['flatId'] ?? 'N/A', colors),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ColorScheme colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w800, letterSpacing: 2));
  }

  Widget _buildOptionCard(BuildContext context, List<_OptionItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: item.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(item.icon, color: item.color, size: 22),
                ),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: item.onTap,
              ),
              if (i < items.length - 1) const Divider(height: 1, indent: 64),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: currentCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (newCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
                return;
              }
              try {
                await ref.read(apiServiceProvider).changePassword(currentCtrl.text, newCtrl.text);
                if (ctx.mounted) ctx.pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u00E2\u0153\u2026 Password changed successfully!'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}

class _OptionItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OptionItem({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
}

