import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/complaints_provider.dart';
import '../../../services/api_service.dart';

class ComplaintsScreen extends ConsumerWidget {
  const ComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncComplaints = ref.watch(complaintsProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Maintenance', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddComplaintDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Request', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: asyncComplaints.when(
        data: (complaints) {
          if (complaints.isEmpty) {
            return const Center(child: Text("No open maintenance requests\u{1F389}", style: TextStyle(color: Colors.grey, fontSize: 16)));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 80.0, top: 8.0),
            itemCount: complaints.length,
            itemBuilder: (context, index) {
              return _buildComplaintCard(context, ref, complaints[index]);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildComplaintCard(BuildContext context, WidgetRef ref, Map<String, dynamic> ticket) {
    final title = ticket['title'] ?? 'No Title';
    final desc = ticket['description'] ?? '';
    final status = ticket['status'] ?? 'pending';
    final priority = ticket['priority'] ?? 'medium';
    final submittedBy = ticket['submittedBy']?['name'] ?? 'Self';
    final category = ticket['category'] ?? 'general';
    final id = ticket['id'];
    final isResolved = status == 'resolved';
    final isEscalated = status == 'escalated';
    final user = ref.read(apiServiceProvider).user;
    final isAdmin = user?['role'] == 'admin';

    final statusColors = {
      'pending': Colors.orange,
      'in_progress': Colors.blue,
      'resolved': Colors.green,
      'escalated': Colors.red,
    };
    final statusColor = statusColors[status] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEscalated ? Colors.red.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.1),
          width: isEscalated ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                )
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(category.toUpperCase(),
                    style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.flag, size: 13, color: _getPriorityColor(priority)),
              const SizedBox(width: 2),
              Text(priority.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: _getPriorityColor(priority), fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            Text(desc, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), height: 1.4)),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(submittedBy, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                const Spacer(),
                // Admin actions
                if (isAdmin && !isResolved && !isEscalated) ...[  
                  _actionChip('Resolve', Colors.green, () async {
                    await ref.read(apiServiceProvider).resolveTicket(id);
                    ref.invalidate(complaintsProvider);
                  }),
                  const SizedBox(width: 6),
                  _actionChip('Escalate', Colors.red, () async {
                    await ref.read(apiServiceProvider).escalateTicket(id);
                    ref.invalidate(complaintsProvider);
                  }),
                ],
                // Resident rating for resolved
                if (isResolved && ticket['residentRating'] == null)
                  _actionChip('\u2B50 Rate', Colors.amber, () => _showRatingDialog(context, ref, id)),
                if (ticket['residentRating'] != null)
                  Row(children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    Text('${ticket['residentRating']}/5',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showRatingDialog(BuildContext context, WidgetRef ref, String id) {
    int rating = 5;
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rate Resolution', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How satisfied are you with the resolution?'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => ss(() => rating = i + 1),
                  child: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: Colors.amber, size: 36),
                )),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                decoration: InputDecoration(
                  labelText: 'Comment (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await ref.read(apiServiceProvider).rateTicket(id, rating, commentCtrl.text);
                ref.invalidate(complaintsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Submit Rating'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String p) {
    if (p == 'high' || p == 'critical') return Colors.red;
    if (p == 'medium') return Colors.orange;
    return Colors.blueGrey;
  }

  void _showAddComplaintDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String priority = 'medium';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32))
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('New Request', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Issue Title',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                      labelText: 'Priority',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low Priority')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium Priority')),
                      DropdownMenuItem(value: 'high', child: Text('High Priority')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => priority = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.isEmpty) return;
                      try {
                        await ref.read(apiServiceProvider).addComplaint(
                          titleController.text,
                          descController.text,
                          priority,
                        );
                        ref.invalidate(complaintsProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: const Text('Submit Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          }
        );
      }
    );
  }
}
