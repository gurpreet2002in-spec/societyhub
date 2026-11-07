import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/complaints_provider.dart';
import '../../../services/api_service.dart';
import 'complaint_detail_screen.dart';

class ComplaintsScreen extends ConsumerWidget {
  const ComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncComplaints = ref.watch(complaintsProvider);
    final colors = Theme.of(context).colorScheme;
    final user = ref.read(apiServiceProvider).user;
    final isAdmin = user?['role'] == 'admin';

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
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(complaintsProvider),
              child: ListView(children: [
                const SizedBox(height: 160),
                Center(
                  child: Text(
                    isAdmin ? 'No complaints in your society \u{1F389}' : 'You have no complaints \u{1F389}',
                    style: const TextStyle(color: Color(0xFF616161), fontSize: 16),
                  ),
                ),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(complaintsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 80.0, top: 8.0),
              itemCount: complaints.length,
              itemBuilder: (context, index) => _buildComplaintCard(
                context,
                ref,
                Map<String, dynamic>.from(complaints[index] as Map),
                '${user?['id'] ?? ''}',
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildComplaintCard(BuildContext context, WidgetRef ref, Map<String, dynamic> ticket, String myId) {
    final title = ticket['title'] ?? 'No Title';
    final desc = '${ticket['description'] ?? ''}';
    final status = complaintStatus(ticket['status']);
    final priority = complaintPriority(ticket['priority']);
    final reporter = ticket['users'] as Map?;
    final isMine = '${ticket['user_id']}' == myId;
    final rating = ticket['rating'];
    final isEscalated = status == 'Escalated';
    final statusColor = complaintStatusColor(status);

    // complaint_comments(count) comes back as [{count: n}]
    int updates = 0;
    final cc = ticket['complaint_comments'];
    if (cc is List && cc.isNotEmpty && cc.first is Map) {
      updates = ((cc.first as Map)['count'] as num?)?.toInt() ?? 0;
    }

    final who = isMine
        ? 'You'
        : '${reporter?['name'] ?? 'Resident'}'
            '${reporter?['apartment_number'] != null ? ' • ${reporter!['apartment_number']}' : ''}';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ComplaintDetailScreen(complaint: ticket)),
      ),
      child: Container(
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
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  StatusChip(status),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.flag, size: 13, color: complaintPriorityColor(priority)),
                const SizedBox(width: 2),
                Text(priority.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: complaintPriorityColor(priority), fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(complaintTimeAgo(ticket['created_at']),
                    style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
              ]),
              if (desc.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65), height: 1.4)),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: Color(0xFF616161)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(who,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                  ),
                  const Spacer(),
                  if (rating != null) ...[
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    Text('$rating/5  ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                  Icon(Icons.forum_outlined, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    updates == 0 ? 'No updates' : '$updates ${updates == 1 ? 'update' : 'updates'}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF616161)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddComplaintDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String priority = 'Medium';

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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('New Request', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    textCapitalization: TextCapitalization.sentences,
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
                    textCapitalization: TextCapitalization.sentences,
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
                      DropdownMenuItem(value: 'Low', child: Text('Low Priority')),
                      DropdownMenuItem(value: 'Medium', child: Text('Medium Priority')),
                      DropdownMenuItem(value: 'High', child: Text('High Priority')),
                      DropdownMenuItem(value: 'Critical', child: Text('Critical (urgent)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => priority = val);
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Please enter a title')));
                        return;
                      }
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
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Submit Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
