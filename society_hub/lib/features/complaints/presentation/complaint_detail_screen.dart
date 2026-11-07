import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/api_service.dart';
import '../../../core/unit_labels.dart';
import '../providers/complaints_provider.dart';

// ─── Shared helpers (also used by the list screen) ─────────────────────────

/// Canonical status: 'Open' | 'In Progress' | 'Escalated' | 'Resolved'.
String complaintStatus(dynamic raw) {
  switch ('${raw ?? ''}'.trim().toLowerCase()) {
    case 'resolved':
      return 'Resolved';
    case 'escalated':
      return 'Escalated';
    case 'in progress':
    case 'in_progress':
    case 'investigating':
    case 'scheduled':
      return 'In Progress';
    default:
      return 'Open';
  }
}

/// Canonical priority: 'Low' | 'Medium' | 'High' | 'Critical'.
String complaintPriority(dynamic raw) {
  switch ('${raw ?? ''}'.trim().toLowerCase()) {
    case 'low':
      return 'Low';
    case 'high':
      return 'High';
    case 'critical':
      return 'Critical';
    default:
      return 'Medium';
  }
}

Color complaintStatusColor(String status) {
  switch (status) {
    case 'Resolved':
      return Colors.green;
    case 'Escalated':
      return Colors.red;
    case 'In Progress':
      return Colors.blue;
    default:
      return Colors.orange;
  }
}

Color complaintPriorityColor(String priority) {
  switch (priority) {
    case 'Critical':
    case 'High':
      return Colors.red;
    case 'Medium':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

String complaintTimeAgo(dynamic iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
  if (d.inDays < 7) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  return DateFormat('d MMM yyyy').format(t);
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = complaintStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(status.toUpperCase(),
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
    );
  }
}

// ─── Detail screen with the update thread ──────────────────────────────────

class ComplaintDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> complaint;
  const ComplaintDetailScreen({super.key, required this.complaint});

  @override
  ConsumerState<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends ConsumerState<ComplaintDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<dynamic> _entries = [];
  bool _loading = true;
  bool _sending = false;
  bool _changed = false;
  late String _status;
  int? _rating;

  @override
  void initState() {
    super.initState();
    _status = complaintStatus(widget.complaint['status']);
    _rating = (widget.complaint['rating'] as num?)?.toInt();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _id => '${widget.complaint['id']}';

  Future<void> _load() async {
    try {
      final rows = await ref.read(apiServiceProvider).getComplaintComments(_id);
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
        // Latest status from the timeline (in case it changed elsewhere).
        for (final e in rows) {
          if (e['status_change'] != null) _status = complaintStatus(e['status_change']);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Could not load updates: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null));
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiServiceProvider).addComplaintComment(_id, text);
      _msgCtrl.clear();
      _changed = true;
      await _load();
    } catch (e) {
      _toast('Could not send: ${e.toString().replaceFirst('Exception: ', '')}', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('Mark as $status?'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note for the resident (optional)',
            hintText: 'e.g. Plumber visiting on Monday 10 am',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Update')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).updateComplaintStatus(_id, status, note: noteCtrl.text);
      _changed = true;
      setState(() => _status = status);
      await _load();
      _toast('Status updated. The resident has been notified.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _rate() async {
    int rating = 5;
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Rate the resolution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    onPressed: () => ss(() => rating = i + 1),
                    icon: Icon(i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber, size: 32),
                  ),
                ),
              ),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(labelText: 'Comment (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).rateTicket(_id, rating, commentCtrl.text);
      _changed = true;
      setState(() => _rating = rating);
      _toast('Thanks for your feedback!');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final user = ref.read(apiServiceProvider).user;
    final myId = '${user?['id'] ?? ''}';
    final isAdmin = user?['role'] == 'admin' || user?['role'] == 'super_admin';
    final isOwner = '${c['user_id']}' == myId;
    final priority = complaintPriority(c['priority']);
    final reporter = c['users'] as Map?;
    final created = DateTime.tryParse('${c['created_at']}')?.toLocal();
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _changed) ref.invalidate(complaintsProvider);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Complaint', style: TextStyle(fontWeight: FontWeight.bold))),
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    // ── Complaint card ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text('${c['title'] ?? 'Complaint'}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            ),
                            StatusChip(_status),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(Icons.flag, size: 14, color: complaintPriorityColor(priority)),
                            const SizedBox(width: 4),
                            Text('$priority priority',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: complaintPriorityColor(priority))),
                            const Spacer(),
                            if (created != null)
                              Text(DateFormat('d MMM yyyy, h:mm a').format(created),
                                  style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
                          ]),
                          if ('${c['description'] ?? ''}'.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('${c['description']}', style: const TextStyle(height: 1.4)),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            isOwner
                                ? 'Raised by you'
                                : 'Raised by ${reporter?['name'] ?? 'resident'}'
                                    '${reporter?['apartment_number'] != null ? ' • ${unitNoun(ref.read(apiServiceProvider).user?['propertyType'] as String?, unitType: reporter!['unit_type'] as String?)} ${reporter!['apartment_number']}' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                          if (_rating != null) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                              Text(' Rated $_rating/5', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ]),
                          ],
                        ],
                      ),
                    ),

                    // ── Admin: status actions ──
                    if (isAdmin) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in const ['In Progress', 'Escalated', 'Resolved', 'Open'])
                            if (s != _status)
                              ActionChip(
                                avatar: Icon(
                                  s == 'Resolved'
                                      ? Icons.check_circle_outline
                                      : s == 'Escalated'
                                          ? Icons.priority_high_rounded
                                          : s == 'Open'
                                              ? Icons.replay_rounded
                                              : Icons.build_outlined,
                                  size: 16,
                                  color: complaintStatusColor(s),
                                ),
                                label: Text(s == 'Open' ? 'Reopen' : 'Mark $s'),
                                onPressed: () => _changeStatus(s),
                              ),
                        ],
                      ),
                    ],

                    // ── Resident: rate when resolved ──
                    if (isOwner && _status == 'Resolved' && _rating == null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _rate,
                        icon: const Icon(Icons.star_outline_rounded, color: Colors.amber),
                        label: const Text('Rate the resolution'),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Text('UPDATES',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Color(0xFF616161))),
                    const SizedBox(height: 10),

                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          isAdmin
                              ? 'No updates yet. Post a comment or change the status to keep the resident informed.'
                              : 'No updates yet. The society admin will post progress here. You can add details below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF616161)),
                        ),
                      )
                    else
                      for (final e in _entries) _buildEntry(Map<String, dynamic>.from(e as Map), myId, colors),
                  ],
                ),
              ),
            ),

            // ── Message box ──
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: isAdmin ? 'Write an update for the resident…' : 'Add a comment…',
                        counterText: '',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(Map<String, dynamic> e, String myId, ColorScheme colors) {
    final mine = '${e['user_id']}' == myId;
    final role = '${e['author_role'] ?? ''}';
    final who = mine
        ? 'You'
        : (role == 'admin' || role == 'super_admin')
            ? '${e['author_name'] ?? 'Admin'} (Admin)'
            : '${e['author_name'] ?? 'Resident'}';
    final when = complaintTimeAgo(e['created_at']);
    final body = '${e['body'] ?? ''}'.trim();
    final statusChange = e['status_change'];

    // Status change → centred event line.
    if (statusChange != null) {
      final s = complaintStatus(statusChange);
      final c = complaintStatusColor(s);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('$who marked it $s • $when',
                  style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
            ],
          ],
        ),
      );
    }

    // Comment → chat bubble (mine on the right).
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: mine ? colors.primary.withValues(alpha: 0.12) : colors.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$who • $when',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(height: 1.35)),
          ],
        ),
      ),
    );
  }
}
