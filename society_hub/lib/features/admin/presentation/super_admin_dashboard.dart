import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../providers/super_admin_provider.dart';

class SuperAdminDashboard extends ConsumerWidget {
  const SuperAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.read(apiServiceProvider).user;
    final statsAsync = ref.watch(superAdminStatsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.surface,
      appBar: const PremiumGlassAppBar(
        showBranding: true,
      ),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.refresh(superAdminStatsProvider),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 32,
              bottom: 40,
              left: 20,
              right: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WELCOME BACK, ${user?['name']?.toUpperCase() ?? 'SUPER ADMIN'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: AppTheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                
                // Key Metrics
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'Active Societies',
                        value: '${stats['activeSocieties'] ?? 0}',
                        icon: Icons.domain_rounded,
                        color: AppTheme.primary,
                        bgColor: AppTheme.primaryFixed,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MetricCard(
                        title: 'Total Users',
                        value: '${stats['totalUsers'] ?? 0}',
                        icon: Icons.people_alt_rounded,
                        color: AppTheme.secondary,
                        bgColor: AppTheme.secondaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'Monthly MRR',
                        value: '\u20B9${stats['mrr'] ?? '0.00'}',
                        icon: Icons.currency_rupee_rounded,
                        color: const Color(0xFF7E3000), // Tertiary
                        bgColor: const Color(0xFFFFDBCC), // Tertiary fixed
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MetricCard(
                        title: 'Total Revenue',
                        value: '\u20B9${stats['totalRevenue'] ?? '0.00'}',
                        icon: Icons.account_balance_wallet_rounded,
                        color: AppTheme.primary,
                        bgColor: AppTheme.primaryFixed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'Pending Invoices',
                        value: '${stats['pendingInvoices'] ?? 0}',
                        icon: Icons.receipt_long_rounded,
                        color: AppTheme.error,
                        bgColor: AppTheme.errorContainer,
                        onTap: () => context.push('/super_admin/invoices'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 48),

                // Actions
                Text('Platform Management', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),
                
                PremiumCard(
                  padding: EdgeInsets.zero,
                  onTap: () => context.push('/super_admin/societies'),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.maps_home_work_rounded, color: AppTheme.primary),
                    ),
                    title: Text('Society Onboarding', style: theme.textTheme.titleLarge),
                    subtitle: Text('Manage tenants, add new societies, update subscriptions.', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  padding: EdgeInsets.zero,
                  onTap: () => context.push('/super_admin/settings'),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings_suggest_rounded, color: AppTheme.secondary),
                    ),
                    title: Text('Global Settings', style: theme.textTheme.titleLarge),
                    subtitle: Text('Platform configuration and billing setups.', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  padding: EdgeInsets.zero,
                  onTap: () => context.push('/super_admin/reports'),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.analytics_rounded, color: AppTheme.primary),
                    ),
                    title: Text('Platform Reports', style: theme.textTheme.titleLarge),
                    subtitle: Text('View growth charts and revenue distribution.', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.onSurfaceVariant),
                  ),
                )
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title, 
    required this.value, 
    required this.icon, 
    required this.color,
    required this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor, 
              borderRadius: BorderRadius.circular(16)
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 24),
          Text(
            value, 
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppTheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            title, 
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppTheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
