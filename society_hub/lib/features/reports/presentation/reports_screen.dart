import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final financialReportProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(apiServiceProvider).getFinancialReport());

final maintenanceReportProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(apiServiceProvider).getMaintenanceReport());

final amenityReportProvider = FutureProvider<List<dynamic>>((ref) =>
    ref.watch(apiServiceProvider).getAmenityReport());

final occupancyReportProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(apiServiceProvider).getOccupancyReport());

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Reports & Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '\u{1F4B0} Financial'),
            Tab(text: '\u{1F527} Helpdesk'),
            Tab(text: '\u{1F3CA} Amenities'),
            Tab(text: '\u{1F3E0} Occupancy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FinancialTab(),
          _MaintenanceTab(),
          _AmenityTab(),
          _OccupancyTab(),
        ],
      ),
    );
  }
}

class _FinancialTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(financialReportProvider);
    final colors = Theme.of(context).colorScheme;

    return report.when(
      data: (d) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _headerCard(context, '\u20B9 ${d['totalCollected']}', 'Total Collected',
              'Collection Rate: ${d['collectionRate']}%', colors.primary),
          const SizedBox(height: 16),
          _progressSection(context, 'Collection Rate', double.tryParse(d['collectionRate'].toString()) ?? 0, 100, colors.primary),
          const SizedBox(height: 20),
          _statRow(context, [
            ('Total Invoices', '${d['totalInvoices']}', Colors.blue),
            ('Paid', '${d['paid']}', Colors.green),
            ('Unpaid', '${d['unpaid']}', Colors.orange),
            ('Overdue', '${d['overdue']}', Colors.red),
          ]),
          const SizedBox(height: 20),
          _statCard(context, 'Outstanding Amount', '\u20B9 ${d['totalOutstanding']}', Colors.orange, Icons.warning_amber_rounded),
          const SizedBox(height: 10),
          _statCard(context, 'Total Billed', '\u20B9 ${d['totalBilled']}', colors.primary, Icons.receipt_long),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _MaintenanceTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(maintenanceReportProvider);
    final colors = Theme.of(context).colorScheme;

    return report.when(
      data: (d) {
        final byStatus = d['byStatus'] as Map<String, dynamic>;
        final total = d['total'] as int? ?? 0;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _headerCard(context, '${d['total']}', 'Total Tickets',
                'Avg Resolution: ${d['avgResolutionHours']}h \u00B7 Avg Rating: ${d['avgRating']}\u2605', colors.primary),
            const SizedBox(height: 20),
            const Text('Ticket Status Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...['pending', 'in_progress', 'resolved', 'escalated'].map((status) {
              final count = byStatus[status] as int? ?? 0;
              final pct = total > 0 ? count / total : 0.0;
              final statusColors = {
                'pending': Colors.orange, 'in_progress': Colors.blue,
                'resolved': Colors.green, 'escalated': Colors.red,
              };
              final color = statusColors[status] ?? Colors.grey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(status.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                      const Spacer(),
                      Text('$count tickets', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 10,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _AmenityTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(amenityReportProvider);
    final colors = Theme.of(context).colorScheme;

    return report.when(
      data: (items) {
        final maxBookings = items.isEmpty ? 1 : items.map((a) => a['bookings'] as int).reduce((a, b) => a > b ? a : b);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Amenity Utilization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            const Text('Bookings and revenue per amenity', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            ...items.map((a) {
              final bookings = a['bookings'] as int? ?? 0;
              final revenue = a['revenue'] as double? ?? 0.0;
              final pct = maxBookings > 0 ? bookings / maxBookings : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(a['emoji'] ?? '\u{1F3E2}', style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(a['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                      Text('\u20B9${revenue.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: colors.primary)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('$bookings bookings', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      Text('${(pct * 100).toStringAsFixed(0)}% relative', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _OccupancyTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(occupancyReportProvider);
    final colors = Theme.of(context).colorScheme;

    return report.when(
      data: (d) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _headerCard(context, '${d['occupancyRate']}%', 'Flat Occupancy Rate',
              '${d['occupiedFlats']} of ${d['totalFlats']} flats occupied', colors.primary),
          const SizedBox(height: 16),
          _progressSection(context, 'Flat Occupancy', double.tryParse(d['occupancyRate'].toString()) ?? 0, 100, colors.primary),
          const SizedBox(height: 20),
          _statRow(context, [
            ('Total Flats', '${d['totalFlats']}', Colors.blue),
            ('Occupied', '${d['occupiedFlats']}', Colors.green),
            ('Vacant', '${d['vacantFlats']}', Colors.orange),
            ('Residents', '${d['totalResidents']}', colors.primary),
          ]),
          const SizedBox(height: 20),
          _headerCard(context, '${d['parkingUtilization']}%', 'Parking Utilization',
              '${d['parkingOccupied']} of ${d['parkingTotal']} slots occupied', Colors.indigo),
          const SizedBox(height: 16),
          _progressSection(context, 'Parking Usage', double.tryParse(d['parkingUtilization'].toString()) ?? 0, 100, Colors.indigo),
          const SizedBox(height: 16),
          _statRow(context, [
            ('Total Slots', '${d['parkingTotal']}', Colors.indigo),
            ('Occupied', '${d['parkingOccupied']}', Colors.red),
            ('Available', '${d['parkingAvailable']}', Colors.green),
          ]),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ===== SHARED WIDGETS =====
Widget _headerCard(BuildContext context, String value, String title, String subtitle, Color color) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
      Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
  );
}

Widget _progressSection(BuildContext context, String label, double value, double max, Color color) {
  final pct = max > 0 ? value / max : 0.0;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const Spacer(),
      Text('${value.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]),
    const SizedBox(height: 8),
    ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(value: pct, minHeight: 14, backgroundColor: Colors.grey.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color)),
    ),
  ]);
}

Widget _statRow(BuildContext context, List<(String, String, Color)> items) {
  return Row(
    children: items.map((item) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: item.$3.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: item.$3.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(item.$2, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: item.$3)),
          const SizedBox(height: 2),
          Text(item.$1, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
        ]),
      ),
    )).toList(),
  );
}

Widget _statCard(BuildContext context, String label, String value, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 28),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
      ]),
    ]),
  );
}
