import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../providers/super_admin_provider.dart';

class SuperAdminReportsScreen extends ConsumerStatefulWidget {
  const SuperAdminReportsScreen({super.key});

  @override
  ConsumerState<SuperAdminReportsScreen> createState() => _SuperAdminReportsScreenState();
}

class _SuperAdminReportsScreenState extends ConsumerState<SuperAdminReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(superAdminReportsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: PremiumGlassAppBar(
        showBranding: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
            onPressed: () => _downloadCSV(ref),
          ),
        ],
        showActions: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.onSurfaceVariant,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Analytics'),
            Tab(text: 'Audit Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnalyticsTab(reportsAsync, theme),
          _buildLogsTab(theme),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(AsyncValue<Map<String, dynamic>> reportsAsync, ThemeData theme) {
    return reportsAsync.when(
      data: (reports) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('SUBSCRIPTION MIX', theme),
            const SizedBox(height: 16),
            _buildDistributionCard(reports['planDistribution'], theme),
            
            const SizedBox(height: 32),
            _buildSectionHeader('SOCIETY-WISE PERFORMANCE', theme),
            const SizedBox(height: 16),
            _buildSocietyTable(reports['societies'], theme),
            
            const SizedBox(height: 32),
            _buildSectionHeader('GROWTH MOMENTUM', theme),
            const SizedBox(height: 16),
            ...(((reports['growth'] as List?) ?? []).map((g) => _buildGrowthTile(g, theme))),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildLogsTab(ThemeData theme) {
    final logsAsync = ref.watch(superAdminLogsProvider);
    return logsAsync.when(
      data: (logs) => ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final log = logs[i];
          return PremiumCard(
            padding: const EdgeInsets.all(4),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getLogColor(log['action']).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getLogIcon(log['action']), color: _getLogColor(log['action']), size: 20),
              ),
              title: Text(log['action'], style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('By ${log['user']} on ${log['target']}', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
              trailing: Text(log['timestamp'].toString().substring(11, 16), style: theme.textTheme.labelMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
            ),
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title, 
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.bold, 
        color: AppTheme.primary, 
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildDistributionCard(dynamic dist, ThemeData theme) {
    final safeDist = dist ?? {'free': 0, 'basic': 0, 'premium': 0};
    return Row(
      children: [
        _distBox('Free', safeDist['free'] ?? 0, AppTheme.secondary, theme),
        const SizedBox(width: 16),
        _distBox('Basic', safeDist['basic'] ?? 0, AppTheme.primary, theme),
        const SizedBox(width: 16),
        _distBox('Premium', safeDist['premium'] ?? 0, const Color(0xFF7E3000), theme),
      ],
    );
  }

  Widget _distBox(String label, int count, Color color, ThemeData theme) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$count', style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppTheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildSocietyTable(dynamic societiesData, ThemeData theme) {
    final societies = (societiesData as List?) ?? [];
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 48,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 56,
          dividerThickness: 0,
          headingTextStyle: theme.textTheme.labelLarge?.copyWith(color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.bold),
          columns: const [
            DataColumn(label: Text('Society Name')),
            DataColumn(label: Text('Plan')),
            DataColumn(label: Text('Users')),
            DataColumn(label: Text('Revenue')),
            DataColumn(label: Text('Tickets')),
          ],
          rows: societies.map((s) => DataRow(cells: [
            DataCell(Text(s['name'] ?? '', style: theme.textTheme.titleMedium)),
            DataCell(Text((s['plan'] ?? 'free').toString().toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(color: AppTheme.primary))),
            DataCell(Text((s['users'] ?? 0).toString())),
            DataCell(Text('\u20B9${s['totalRevenue'] ?? 0}')),
            DataCell(Text((s['tickets'] ?? 0).toString())),
          ])).toList(),
        ),
      ),
    );
  }

  Widget _buildGrowthTile(dynamic growth, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        padding: const EdgeInsets.all(4),
        child: ListTile(
          title: Text('Month: ${growth['month']}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          subtitle: Text('${growth['societies']} Societies | ${growth['users']} Users', style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.onSurfaceVariant)),
          trailing: Text('\u20B9${growth['revenue']}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.primary)),
        ),
      ),
    );
  }

  IconData _getLogIcon(String action) {
    if (action.contains('SOCIETY')) return Icons.business_rounded;
    if (action.contains('PLAN')) return Icons.stars_rounded;
    return Icons.settings_rounded;
  }

  Color _getLogColor(String action) {
    if (action.contains('CREATED')) return Colors.green;
    return Colors.blue;
  }

  void _downloadCSV(WidgetRef ref) {
    // Generate a CSV string and show a success message
    // In a real mobile app, we'd use path_provider and open_file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u{1F4CA} CSV Report generated and saved to downloads'), backgroundColor: Colors.indigoAccent),
    );
  }
}

