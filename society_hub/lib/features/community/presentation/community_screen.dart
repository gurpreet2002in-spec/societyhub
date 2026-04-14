import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/community_provider.dart';
import '../../../services/api_service.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = ref.watch(apiServiceProvider).user;
    final isAdmin = user?['role'] == 'admin';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Community', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.campaign_rounded), text: 'Notices'),
            Tab(icon: Icon(Icons.poll_rounded), text: 'Polls'),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Post Notice',
              onPressed: () => _showPostNoticeSheet(context, ref),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NoticesTab(isAdmin: isAdmin),
          _PollsTab(isAdmin: isAdmin),
        ],
      ),
    );
  }

  void _showPostNoticeSheet(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String category = 'general';
    bool isPinned = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              left: 24, right: 24, top: 28),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.campaign_rounded, size: 26),
                SizedBox(width: 10),
                Text('Post Notice', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: 'Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'Message',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: InputDecoration(labelText: 'Category',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
                items: const [
                  DropdownMenuItem(value: 'general', child: Text('\u{1F4E2} General')),
                  DropdownMenuItem(value: 'urgent', child: Text('\u26A0\uFE0F Urgent')),
                  DropdownMenuItem(value: 'event', child: Text('\u{1F389} Event')),
                  DropdownMenuItem(value: 'maintenance', child: Text('\u{1F527} Maintenance')),
                ],
                onChanged: (v) => setState(() => category = v ?? 'general'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: isPinned,
                onChanged: (v) => setState(() => isPinned = v),
                title: const Text('\u{1F4CC} Pin this notice', style: TextStyle(fontWeight: FontWeight.w600)),
                contentPadding: EdgeInsetsDirectional.zero,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
                  try {
                    await ref.read(noticesProvider.notifier)
                        .create(titleCtrl.text, bodyCtrl.text, category, isPinned);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('Post Notice', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticesTab extends ConsumerWidget {
  final bool isAdmin;
  const _NoticesTab({required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotices = ref.watch(noticesProvider);
    final colors = Theme.of(context).colorScheme;

    return asyncNotices.when(
      data: (notices) {
        if (notices.isEmpty) {
          return const Center(child: Text('No notices yet.', style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: notices.length,
          itemBuilder: (ctx, i) {
            final n = notices[i] as Map<String, dynamic>;
            final catColors = {
              'urgent': Colors.red,
              'event': Colors.purple,
              'maintenance': Colors.orange,
              'general': colors.primary,
            };
            final catEmojis = {
              'urgent': '\u26A0\uFE0F', 'event': '\u{1F389}', 'maintenance': '\u{1F527}', 'general': '\u{1F4E2}'
            };
            final color = catColors[n['category']] ?? colors.primary;
            final emoji = catEmojis[n['category']] ?? '\u{1F4E2}';
            final postedBy = n['postedBy']?['name'] ?? 'Admin';
            final createdAt = n['createdAt'] != null
                ? DateFormat('MMM d, yyyy').format(DateTime.parse(n['createdAt']))
                : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.25)),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 8)],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(emoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(n['category']?.toString().toUpperCase() ?? '',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                        ]),
                      ),
                      if (n['isPinned'] == true) ...[
                        const SizedBox(width: 8),
                        const Text('\u{1F4CC}', style: TextStyle(fontSize: 13)),
                      ],
                      const Spacer(),
                      if (isAdmin)
                        GestureDetector(
                          onTap: () => ref.read(noticesProvider.notifier).delete(n['id']),
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Text(n['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(n['body'] ?? '', style: const TextStyle(color: Colors.grey, height: 1.4)),
                    const SizedBox(height: 10),
                    Text('\u2014 $postedBy \u00B7 $createdAt',
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _PollsTab extends ConsumerWidget {
  final bool isAdmin;
  const _PollsTab({required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPolls = ref.watch(pollsProvider);
    final colors = Theme.of(context).colorScheme;

    return asyncPolls.when(
      data: (polls) {
        if (polls.isEmpty) {
          return const Center(child: Text('No active polls.', style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: polls.length,
          itemBuilder: (ctx, i) {
            final p = polls[i] as Map<String, dynamic>;
            final options = (p['options'] as List<dynamic>).cast<String>();
            final voteCounts = (p['voteCounts'] as List<dynamic>).cast<int>();
            final totalVotes = p['totalVotes'] as int? ?? 0;
            final userVote = p['userVote'] as int?;
            final hasVoted = userVote != null;
            final endDate = p['endDate'] != null
                ? DateFormat('MMM d, yyyy').format(DateTime.parse(p['endDate']))
                : '';

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.poll_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p['question'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Ends $endDate \u00B7 $totalVotes votes',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ...List.generate(options.length, (idx) {
                    final count = voteCounts[idx];
                    final pct = totalVotes > 0 ? count / totalVotes : 0.0;
                    final isMyVote = userVote == idx;

                    return GestureDetector(
                      onTap: hasVoted
                          ? null
                          : () async {
                              try {
                                await ref.read(pollsProvider.notifier).vote(p['id'], idx);
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('$e'), backgroundColor: Colors.orange));
                                }
                              }
                            },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isMyVote
                              ? colors.primary.withValues(alpha: 0.12)
                              : colors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isMyVote ? colors.primary : Colors.grey.withValues(alpha: 0.2),
                            width: isMyVote ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(options[idx],
                                    style: TextStyle(
                                        fontWeight: isMyVote ? FontWeight.bold : FontWeight.normal)),
                              ),
                              if (hasVoted)
                                Text('${(pct * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isMyVote ? colors.primary : Colors.grey)),
                            ]),
                            if (hasVoted) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      isMyVote ? colors.primary : Colors.grey.withValues(alpha: 0.5)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  if (!hasVoted)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Tap an option to vote',
                          style: TextStyle(fontSize: 11, color: colors.primary, fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
