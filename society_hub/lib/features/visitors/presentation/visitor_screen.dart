import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/visitor_provider.dart';

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
        onPressed: () => context.go('/visitors/create'),
        icon: const Icon(Icons.add),
        label: const Text('Pre-approve', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: asyncVisitors.when(
        data: (visitors) {
          if (visitors.isEmpty) {
            return const Center(child: Text("No visitors today\u00F0\u0178\u017D\u2030", style: TextStyle(color: Colors.grey, fontSize: 16)));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 80.0, top: 8.0),
            itemCount: visitors.length,
            itemBuilder: (context, index) {
              final visitor = visitors[index];
              return _buildVisitorCard(context, visitor);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildVisitorCard(BuildContext context, dynamic visitor) {
    Color statusColor = visitor.status == 'Pending' ? Colors.orange : (visitor.status == 'Approved' ? Colors.green : Colors.grey);

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
                  child: Text(visitor.status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
                  Icon(Icons.vpn_key, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text('Passcode: ${visitor.passCode}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              )
          ],
        ),
      ),
    );
  }
}

