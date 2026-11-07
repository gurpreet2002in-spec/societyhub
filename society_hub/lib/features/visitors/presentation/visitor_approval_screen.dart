import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/api_service.dart';
import '../../../services/notification_service.dart';

/// Full-screen "Visitor at the gate" — the resident approves or declines.
/// Opened from the ringing alert (or its Approve / Decline buttons).
class VisitorApprovalScreen extends ConsumerStatefulWidget {
  final String visitorId;
  final String? initialAction; // 'approve' | 'decline' (tapped on the alert)
  const VisitorApprovalScreen({super.key, required this.visitorId, this.initialAction});

  @override
  ConsumerState<VisitorApprovalScreen> createState() => _VisitorApprovalScreenState();
}

class _VisitorApprovalScreenState extends ConsumerState<VisitorApprovalScreen> {
  Map<String, dynamic>? _v;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _tick;

  ApiService get _api => ref.read(apiServiceProvider);
  late final NotificationService _notif = ref.read(notificationServiceProvider);

  @override
  void initState() {
    super.initState();
    _notif; // read now so it can be used in dispose()
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    // Leaving the screen stops the ringing.
    _notif.cancelVisitorCall(widget.visitorId);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await _api.getVisitor(widget.visitorId);
      if (!mounted) return;
      setState(() {
        _v = v;
        _loading = false;
        if (v == null) _error = 'This visitor request is not available.';
      });
      _listen();
      if (v != null && v['approval_status'] != 'pending') {
        _notif.cancelVisitorCall(widget.visitorId);
      } else if (v != null && widget.initialAction != null) {
        await _respond(widget.initialAction == 'approve');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // Someone else in the flat may answer first — update live.
  void _listen() {
    _channel = Supabase.instance.client
        .channel('visitor-${widget.visitorId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'visitors',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.visitorId),
          callback: (payload) {
            if (!mounted) return;
            setState(() => _v = {...?_v, ...payload.newRecord});
            if (payload.newRecord['approval_status'] != 'pending') {
              _notif.cancelVisitorCall(widget.visitorId);
            }
          },
        )
        .subscribe();
  }

  Future<void> _respond(bool approve, {String? note}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await _api.respondToVisitor(widget.visitorId, approve, note: note);
      _notif.cancelVisitorCall(widget.visitorId);
      if (!mounted) return;
      setState(() {
        _v = {
          ...?_v,
          'approval_status': r['status'],
          'decided_by_name': r['by'],
          if (r['alreadyAnswered'] != true) 'decision_note': note,
        };
      });
      if (r['alreadyAnswered'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r['by'] ?? 'Someone'} already ${r['status'] == 'approved' ? 'approved' : 'declined'} this visitor')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException(message: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  String _waited() {
    final t = DateTime.tryParse('${_v?['requested_at'] ?? ''}')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.isNegative) return 'just now';
    if (d.inMinutes >= 60) return 'waiting ${d.inHours}h ${d.inMinutes % 60}m';
    return 'waiting ${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final status = v?['approval_status'] as String?;
    // Guard already let them in / sent them away before anyone answered.
    final handledAtGate = status == 'pending' && v?['status'] != null && v?['status'] != 'Awaiting approval';
    final pending = status == 'pending' && !handledAtGate;
    final name = '${v?['name'] ?? 'Visitor'}';

    return Scaffold(
      backgroundColor: const Color(0xFF14123A),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _message(Icons.info_outline, _error!, Colors.white70)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: _close,
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pending ? 'VISITOR AT THE GATE' : 'VISITOR',
                        style: const TextStyle(color: Colors.white60, letterSpacing: 2, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('for ${v?['flat_number'] ?? ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      const Spacer(),
                      _Pulse(
                        active: pending,
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if ('${v?['purpose'] ?? ''}'.isNotEmpty)
                        _chip(Icons.local_shipping_outlined, '${v?['purpose']}'),
                      if ('${v?['mobile'] ?? ''}'.isNotEmpty) _chip(Icons.phone_outlined, '${v?['mobile']}'),
                      if ('${v?['vehicle_number'] ?? ''}'.isNotEmpty)
                        _chip(Icons.directions_car_outlined, '${v?['vehicle_number']}'),
                      if (pending) ...[
                        const SizedBox(height: 8),
                        Text(_waited(), style: const TextStyle(color: Colors.white54)),
                      ],
                      const Spacer(),
                      if (pending) ..._answerButtons() else _result(handledAtGate ? 'gate' : status),
                    ]),
                  ),
      ),
    );
  }

  List<Widget> _answerButtons() => [
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final q in const ['Send them up', 'Leave it at the gate', 'Not expecting anyone'])
            ActionChip(
              label: Text(q),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              labelStyle: const TextStyle(color: Colors.white),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              onPressed: _busy ? null : () => _respond(q == 'Send them up', note: q),
            ),
        ]),
        const SizedBox(height: 28),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _roundButton(Icons.close_rounded, 'Decline', Colors.red, () => _respond(false)),
          _roundButton(Icons.check_rounded, 'Approve', Colors.green, () => _respond(true)),
        ]),
        const SizedBox(height: 12),
      ];

  Widget _result(String? status) {
    if (status == 'gate') {
      return Column(children: [
        const Icon(Icons.shield_outlined, size: 64, color: Colors.white70),
        const SizedBox(height: 10),
        Text('Handled at the gate: ${_v?['status']}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _close, child: const Text('Done'))),
      ]);
    }
    final ok = status == 'approved';
    final by = '${_v?['decided_by_name'] ?? 'a resident'}';
    final note = '${_v?['decision_note'] ?? ''}';
    return Column(children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 64, color: ok ? Colors.greenAccent : Colors.redAccent),
      const SizedBox(height: 10),
      Text(ok ? 'Approved by $by' : 'Declined by $by',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      if (note.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('"$note"', style: const TextStyle(color: Colors.white70)),
      ],
      const SizedBox(height: 6),
      Text(ok ? 'The guard has been told to let them in.' : 'The guard has been told.',
          style: const TextStyle(color: Colors.white54)),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: _close, child: const Text('Done')),
      ),
    ]);
  }

  Widget _chip(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white60),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 15))),
        ]),
      );

  Widget _roundButton(IconData icon, String label, Color color, VoidCallback onTap) => Column(children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : onTap,
            child: SizedBox(
              width: 76,
              height: 76,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Icon(icon, color: Colors.white, size: 38),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]);

  Widget _message(IconData icon, String text, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 16)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _close, child: const Text('Close')),
          ]),
        ),
      );
}

/// Gentle pulsing ring around the visitor avatar while it is ringing.
class _Pulse extends StatefulWidget {
  final Widget child;
  final bool active;
  const _Pulse({required this.child, required this.active});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        padding: EdgeInsets.all(6 + 14 * _c.value),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.greenAccent.withValues(alpha: 0.25 * (1 - _c.value)),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
