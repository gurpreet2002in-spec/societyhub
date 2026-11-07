import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../models/visitor.dart';
import '../providers/visitor_provider.dart';
import 'gate_pass_sheet.dart';

class VisitorScreen extends ConsumerWidget {
  const VisitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVisitors = ref.watch(visitorsProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Visitors', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/visitors/create'),
        icon: const Icon(Icons.add),
        label: const Text('New gate pass', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: asyncVisitors.when(
        data: (visitors) {
          if (visitors.isEmpty) {
            return const Center(child: Text("No visitors today\u{1F389}", style: TextStyle(color: Color(0xFF616161), fontSize: 16)));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 80.0, top: 8.0),
            itemCount: visitors.length,
            itemBuilder: (context, index) {
              final visitor = visitors[index];
              return _buildVisitorCard(context, ref, visitor);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildVisitorCard(BuildContext context, WidgetRef ref, Visitor visitor) {
    final expired = visitor.status == 'Pre-approved' && !visitor.isActivePass;
    final label = expired ? 'Expired' : visitor.status;
    Color statusColor = expired
        ? Colors.grey
        : (visitor.status == 'Pending' || visitor.status == 'Awaiting approval')
            ? Colors.orange
            : (visitor.status == 'Approved' || visitor.status == 'Pre-approved' || visitor.status == 'Checked-in')
                ? Colors.green
                : visitor.status == 'Declined'
                    ? Colors.red
                    : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(visitor.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)
                  ),
                  child: Text(label.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Text('${visitor.purpose} - ${visitor.mobile}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 16),
            if (visitor.passCode != null)
              Row(
                children: [
                  Icon(Icons.vpn_key, size: 16, color: Color(0xFF616161)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Pass code: ${visitor.passCode}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  if (visitor.isActivePass)
                    TextButton.icon(
                      onPressed: () => showGatePassSheet(
                        context,
                        visitorName: visitor.name,
                        passCode: visitor.passCode!,
                        flat: visitor.flatNumber,
                        societyName: ref.read(apiServiceProvider).user?['societyName'] as String?,
                        validUntil: visitor.passValidUntil,
                      ),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: const Text('Show pass'),
                    ),
                ],
              )
          ],
        ),
      ),
    );
  }
}

