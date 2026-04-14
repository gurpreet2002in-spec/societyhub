import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/daily_help_provider.dart';

class DailyHelpScreen extends ConsumerWidget {
  const DailyHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHelp = ref.watch(dailyHelpProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Daily Help', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHelpSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Help', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: asyncHelp.when(
        data: (helpers) {
          if (helpers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('\u{1F9F9}', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  const Text('No helpers added yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Add your maid, cook, or driver', style: TextStyle(color: colors.primary)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80, top: 8),
            itemCount: helpers.length,
            itemBuilder: (ctx, i) => _buildHelpCard(ctx, ref, helpers[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildHelpCard(BuildContext context, WidgetRef ref, Map<String, dynamic> h) {
    final typeEmojis = {
      'maid': '\u{1F9F9}', 'cook': '\u{1F468}\u200D\u{1F373}', 'driver': '\u{1F697}', 'watchman': '\u{1F482}', 'other': '\u{1F477}'
    };
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(typeEmojis[h['type']] ?? '\u{1F477}', style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      Text('${h['type']?.toString().toUpperCase()} \u00B7 ${h['mobile']}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: h['isActive'] == true ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(h['isActive'] == true ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: h['isActive'] == true ? Colors.green : Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.schedule, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${h['entryTime']} \u2013 ${h['exitTime']}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 12),
              const Icon(Icons.calendar_month, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(h['workingDays'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                _attendanceChip(context, ref, h['id'], today, 'present', '\u2705 Present'),
                const SizedBox(width: 8),
                _attendanceChip(context, ref, h['id'], today, 'absent', '\u274C Absent'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await ref.read(dailyHelpProvider.notifier).remove(h['id']);
                  },
                  tooltip: 'Remove',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceChip(BuildContext context, WidgetRef ref, String helpId,
      String date, String status, String label) {
    return InkWell(
      onTap: () async {
        await ref.read(dailyHelpProvider.notifier).markAttendance(helpId, date, status);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Marked $status for today'),
              duration: const Duration(seconds: 2)));
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showAddHelpSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    String type = 'maid';
    String entryTime = '08:00';
    String exitTime = '11:00';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              left: 24, right: 24, top: 32),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add Helper', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: 'Full Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mobileCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: 'Mobile Number',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: 'Type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
                items: const [
                  DropdownMenuItem(value: 'maid', child: Text('\u{1F9F9} Maid')),
                  DropdownMenuItem(value: 'cook', child: Text('\u{1F468}\u200D\u{1F373} Cook')),
                  DropdownMenuItem(value: 'driver', child: Text('\u{1F697} Driver')),
                  DropdownMenuItem(value: 'watchman', child: Text('\u{1F482} Watchman')),
                  DropdownMenuItem(value: 'other', child: Text('\u{1F477} Other')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'maid'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || mobileCtrl.text.isEmpty) return;
                  try {
                    await ref.read(dailyHelpProvider.notifier).add({
                      'name': nameCtrl.text,
                      'mobile': mobileCtrl.text,
                      'type': type,
                      'entryTime': entryTime,
                      'exitTime': exitTime,
                    });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save Helper', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
