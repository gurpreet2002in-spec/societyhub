import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../providers/super_admin_provider.dart';

class SuperAdminInvoicesScreen extends ConsumerWidget {
  const SuperAdminInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(superAdminInvoicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PremiumGlassAppBar(showBranding: true),
      backgroundColor: AppTheme.surface,
      body: invoicesAsync.when(
        data: (invoices) => RefreshIndicator(
          onRefresh: () async => ref.refresh(superAdminInvoicesProvider),
          child: ListView.separated(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 24,
              bottom: 24,
              left: 16,
              right: 16,
            ),
            itemCount: invoices.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final inv = invoices[index];
              final isPaid = inv['status'] == 'paid';
              
              return PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.primaryContainer],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.receipt_long, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv['societyName'], 
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID: ${inv['id']} \u2022 Date: ${inv['date']}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\u20B9${inv['amount']}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPaid ? AppTheme.secondaryContainer : AppTheme.errorContainer,
                            borderRadius: BorderRadius.circular(100), // rounded-full
                          ),
                          child: Text(
                            inv['status'].toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isPaid ? AppTheme.secondary : AppTheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
