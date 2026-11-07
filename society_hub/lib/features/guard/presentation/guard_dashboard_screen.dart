import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/api_service.dart';
import '../../../core/unit_labels.dart';
import '../../../widgets/unit_picker_field.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_button.dart';
import '../../visitors/presentation/gate_pass_sheet.dart' show kPassQrPrefix;

final guardVisitorsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSocietyVisitors();
});

final guardVehiclesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getVehicleLogs();
});

final guardHelpProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getDailyHelpStaff();
});

class GuardDashboardScreen extends ConsumerStatefulWidget {
  const GuardDashboardScreen({super.key});

  @override
  ConsumerState<GuardDashboardScreen> createState() => _GuardDashboardScreenState();
}

class _GuardDashboardScreenState extends ConsumerState<GuardDashboardScreen> with SingleTickerProviderStateMixin {
  String get _unit => unitNoun(ref.read(apiServiceProvider).user?['propertyType'] as String?);

  late TabController _tabController;
  RealtimeChannel? _gateChannel;
  String _vQuery = '';
  String _vFilter = 'today'; // today | inside | waiting | passes | all

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    // Keep the visitor list live (approvals arrive from residents' phones).
    final sid = ref.read(apiServiceProvider).user?['society_id'];
    if (sid != null) {
      _gateChannel = Supabase.instance.client
          .channel('gate-visitors-$sid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'visitors',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'society_id', value: '$sid'),
            callback: (_) {
              if (mounted) ref.invalidate(guardVisitorsProvider);
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    if (_gateChannel != null) Supabase.instance.client.removeChannel(_gateChannel!);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: PremiumGlassAppBar(
        showBranding: false,
        title: const Text('Gate Management'),
        showActions: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Visitors', icon: Icon(Icons.people_rounded)),
            Tab(text: 'Vehicles', icon: Icon(Icons.drive_eta_rounded)),
            Tab(text: 'Staff', icon: Icon(Icons.work_rounded)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sos_rounded, color: Colors.red),
            tooltip: 'SOS — alert admins and guards',
            onPressed: _raiseSos,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Check gate pass',
            onPressed: _checkPass,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search Resident Vehicle',
            onPressed: () => _showSearchResidentVehicleDialog(),
          ),
        ],
      ),
      floatingActionButton: PremiumButton(
        onPressed: () => _handleFabAction(),
        label: _tabController.index == 0 ? 'New Visitor' : (_tabController.index == 1 ? 'New Vehicle' : 'Staff Info'),
        icon: Icons.add_rounded,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisitorsTab(colors),
          _buildVehiclesTab(colors),
          _buildHelpTab(colors),
        ],
      ),
    );
  }

  void _handleFabAction() {
    if (_tabController.index == 0) {
      _showNewVisitorDialog();
    } else if (_tabController.index == 1) {
      _showNewVehicleDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff are managed by Society Admin.')));
    }
  }

  // ── VISITORS TAB ──────────────────────────────────────────────────────────
  Widget _buildVisitorsTab(ColorScheme colors) {
    final visitorsAsync = ref.watch(guardVisitorsProvider);
    return visitorsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (visitors) {
        final now = DateTime.now();
        bool isToday(dynamic v) {
          final t = DateTime.tryParse('${v['created_at'] ?? ''}')?.toLocal();
          return t != null && t.year == now.year && t.month == now.month && t.day == now.day;
        }

        bool activePass(dynamic v) {
          if (v['status'] != 'Pre-approved') return false;
          final until = DateTime.tryParse('${v['pass_valid_until'] ?? ''}');
          return until == null || until.isAfter(DateTime.now().toUtc());
        }

        final counts = {
          'inside': visitors.where((v) => v['status'] == 'Checked-in').length,
          'waiting': visitors.where((v) => v['status'] == 'Awaiting approval' || v['status'] == 'Approved').length,
          'passes': visitors.where(activePass).length,
        };
        final q = _vQuery.toLowerCase();
        final shown = visitors.where((v) {
          switch (_vFilter) {
            case 'today':
              if (!isToday(v) && v['status'] != 'Checked-in') return false;
              break;
            case 'inside':
              if (v['status'] != 'Checked-in') return false;
              break;
            case 'waiting':
              if (v['status'] != 'Awaiting approval' && v['status'] != 'Approved') return false;
              break;
            case 'passes':
              if (!activePass(v)) return false;
              break;
          }
          if (q.isEmpty) return true;
          return '${v['name'] ?? ''}'.toLowerCase().contains(q) ||
              '${v['flat_number'] ?? ''}'.toLowerCase().contains(q) ||
              '${v['mobile'] ?? ''}'.contains(q) ||
              '${v['vehicle_number'] ?? ''}'.toLowerCase().contains(q) ||
              '${v['purpose'] ?? ''}'.toLowerCase().contains(q);
        }).toList();

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (t) => setState(() => _vQuery = t.trim()),
              decoration: InputDecoration(
                hintText: 'Search name, $_unit, phone, vehicle…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              for (final f in [
                ('today', 'Today'),
                ('inside', 'Inside (${counts['inside']})'),
                ('waiting', 'Waiting (${counts['waiting']})'),
                ('passes', 'Passes (${counts['passes']})'),
                ('all', 'All'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _vFilter == f.$1,
                    onSelected: (_) => setState(() => _vFilter = f.$1),
                  ),
                ),
            ]),
          ),
          Expanded(child: _buildList(shown, (v) => _buildVisitorCard(v, colors))),
        ]);
      },
    );
  }

  // ── Gate pass check (type or scan) ────────────────────────────────────────
  Future<void> _checkPass() async {
    final codeCtrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Check gate pass'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: codeCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 7,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(hintText: '000000', counterText: ''),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final scanned = await Navigator.of(c).push<String>(
                  MaterialPageRoute(builder: (_) => const _PassScannerPage()),
                );
                if (scanned != null && c.mounted) Navigator.pop(c, scanned);
              },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR instead'),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, codeCtrl.text), child: const Text('Check')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final api = ref.read(apiServiceProvider);
    Map<String, dynamic> pass;
    try {
      pass = await api.verifyVisitorPass(code);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 48),
          title: const Text('Not valid'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    final letIn = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.verified_rounded, color: Colors.green, size: 48),
        title: Text('Valid pass — ${pass['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_unit: ${pass['flat_number'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if ('${pass['purpose'] ?? ''}'.isNotEmpty) Text('Purpose: ${pass['purpose']}'),
          if ('${pass['mobile'] ?? ''}'.isNotEmpty) Text('Mobile: ${pass['mobile']}'),
          if (pass['created_by_name'] != null) Text('Pass by: ${pass['created_by_name']}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Let in'),
          ),
        ],
      ),
    );
    if (letIn != true) return;
    try {
      await api.checkInVisitor('${pass['id']}');
      ref.invalidate(guardVisitorsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${pass['name']} checked in. The resident has been told.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── SOS ───────────────────────────────────────────────────────────────────
  Future<void> _raiseSos() async {
    final noteCtrl = TextEditingController();
    String? picked;
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          icon: const Icon(Icons.sos_rounded, color: Colors.red, size: 48),
          title: const Text('Send SOS?'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('All admins and guards get an alert with sound right away.'),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in const ['Fire', 'Medical emergency', 'Fight / threat', 'Suspicious person', 'Theft'])
                  ChoiceChip(
                    label: Text(m),
                    selected: picked == m,
                    onSelected: (_) => ss(() => picked = m),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Details (optional)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('SEND SOS'),
            ),
          ],
        ),
      ),
    );
    if (send != true || !mounted) return;
    final msg = [if (picked != null) picked!, if (noteCtrl.text.trim().isNotEmpty) noteCtrl.text.trim()].join(' — ');
    try {
      final n = await ref.read(apiServiceProvider).raiseSos(message: msg.isEmpty ? null : msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n > 0 ? 'SOS sent to $n ${n == 1 ? 'person' : 'people'}.' : 'SOS saved, but no admin or other guard uses the app yet.'),
          backgroundColor: n > 0 ? Colors.green : Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildVisitorCard(Map<String, dynamic> v, ColorScheme colors) {
    final status = '${v['status'] ?? 'Pending'}';
    final isInside = status == 'Checked-in';
    final by = v['decided_by_name'];
    final note = '${v['decision_note'] ?? ''}';
    var subtitle = '$_unit ${v['flat_number']} \u2022 ${v['purpose']}';
    if (status == 'Approved' || status == 'Declined') {
      subtitle += '\n${status == 'Approved' ? '\u2713 Approved' : '\u2717 Declined'} by ${by ?? 'resident'}'
          '${note.isNotEmpty ? ' \u2014 "$note"' : ''}';
    }
    final Widget trailing;
    if (isInside) {
      trailing = _outButton(() => _handleVisitorOut(v['id']));
    } else if (status == 'Pre-approved' || status == 'Approved') {
      trailing = _inButton(() => _handleVisitorIn(v['id']));
    } else if (status == 'Awaiting approval') {
      trailing = OutlinedButton.icon(
        onPressed: () => _showWaitSheet('${v['id']}', null),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
        icon: const Icon(Icons.ring_volume_rounded, size: 18),
        label: const Text('WAITING'),
      );
    } else if (status == 'Declined') {
      trailing = const Text('DECLINED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700));
    } else {
      trailing = Text(status);
    }
    return _buildLogCard(
      title: v['name'] ?? 'Visitor',
      subtitle: subtitle,
      trailing: trailing,
      icon: Icons.person_rounded,
      color: isInside
          ? Colors.green
          : status == 'Awaiting approval'
              ? Colors.orange
              : status == 'Approved'
                  ? Colors.teal
                  : status == 'Declined'
                      ? Colors.red
                      : Colors.grey,
    );
  }

  // ── VEHICLES TAB ──────────────────────────────────────────────────────────
  Widget _buildVehiclesTab(ColorScheme colors) {
    final vehiclesAsync = ref.watch(guardVehiclesProvider);
    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (vehicles) => _buildList(vehicles, (v) => _buildVehicleCard(v, colors)),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v, ColorScheme colors) {
    final isInside = v['status'] == 'Inside';
    return _buildLogCard(
      title: v['vehicle_number'] ?? 'Vehicle',
      subtitle: '$_unit ${v['flat_number']} \u2022 ${v['vehicle_type']}',
      trailing: isInside ? _outButton(() => _handleVehicleOut(v['id'])) : const Text('Out'),
      icon: Icons.drive_eta_rounded,
      color: isInside ? Colors.blue : Colors.grey,
    );
  }

  // ── DAILY HELP TAB ────────────────────────────────────────────────────────
  Widget _buildHelpTab(ColorScheme colors) {
    final helpAsync = ref.watch(guardHelpProvider);
    return helpAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (staff) => _buildList(staff, (s) => _buildStaffCard(s, colors)),
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> s, ColorScheme colors) {
    return _buildLogCard(
      title: s['name'] ?? 'Staff',
      subtitle: s['type']?.toString().toUpperCase() ?? 'OTHER',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _handleMarkAttendance(s['id'], true),
            icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
          ),
          IconButton(
            onPressed: () => _handleMarkAttendance(s['id'], false),
            icon: const Icon(Icons.cancel_rounded, color: Colors.red),
          ),
        ],
      ),
      icon: Icons.work_rounded,
      color: Colors.purple,
    );
  }

  // ── SHARED WIDGETS ────────────────────────────────────────────────────────
  Widget _buildList(List<dynamic> items, Widget Function(Map<String, dynamic>) builder) {
    if (items.isEmpty) return const Center(child: Text('No records found.'));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(guardVisitorsProvider);
        ref.invalidate(guardVehiclesProvider);
        ref.invalidate(guardHelpProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16).copyWith(bottom: 100),
        itemCount: items.length,
        itemBuilder: (context, i) => builder(items[i]),
      ),
    );
  }

  Widget _buildLogCard({required String title, required String subtitle, required Widget trailing, required IconData icon, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: trailing,
        ),
      ),
    );
  }

  Widget _inButton(VoidCallback onPressed) => ElevatedButton(onPressed: onPressed, child: const Text('IN'));
  Widget _outButton(VoidCallback onPressed) => OutlinedButton(
    onPressed: onPressed, 
    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
    child: const Text('OUT'),
  );

  // ── ACTIONS ───────────────────────────────────────────────────────────────
  void _handleVisitorIn(String id) async {
    await ref.read(apiServiceProvider).checkInVisitor(id);
    ref.invalidate(guardVisitorsProvider);
  }

  void _handleVisitorOut(String id) async {
    await ref.read(apiServiceProvider).checkOutVisitor(id);
    ref.invalidate(guardVisitorsProvider);
  }

  void _handleVehicleOut(String id) async {
    await ref.read(apiServiceProvider).checkOutVehicle(id);
    ref.invalidate(guardVehiclesProvider);
  }

  void _handleMarkAttendance(String id, bool present) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final status = present ? 'present' : 'absent';
    await ref.read(apiServiceProvider).markAttendance(id, today, status);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attendance marked: ${present ? 'Present' : 'Absent'}')));
    ref.invalidate(guardHelpProvider);
  }

  Future<void> _showNewVisitorDialog() async {
    final name = TextEditingController();
    final mobile = TextEditingController();
    final otherPurpose = TextEditingController();
    final vehicle = TextEditingController();
    String? flat;
    String purpose = 'Delivery';

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, ss) => _GateForm(
          title: 'New visitor',
          children: [
            UnitPickerField(onChanged: (v) => ss(() => flat = v)),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Visitor name *', prefixIcon: Icon(Icons.person_outline)),
            ),
            TextField(
              controller: mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            _GateLabel('Purpose'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in const ['Delivery', 'Guest', 'Cab', 'Service', 'Other'])
                ChoiceChip(label: Text(p), selected: purpose == p, onSelected: (_) => ss(() => purpose = p)),
            ]),
            if (purpose == 'Other')
              TextField(
                controller: otherPurpose,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Purpose of visit'),
              ),
            TextField(
              controller: vehicle,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Vehicle number (optional)', prefixIcon: Icon(Icons.directions_car_outlined)),
            ),
          ],
          actions: [
            Expanded(
              child: OutlinedButton(onPressed: () => Navigator.pop(sheetCtx, 'in'), child: const Text('Let in now')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(sheetCtx, 'ask'),
                icon: const Icon(Icons.ring_volume_rounded, size: 20),
                label: const Text('Ask resident'),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final purposeText = purpose == 'Other' ? otherPurpose.text.trim() : purpose;
    if (name.text.trim().isEmpty || flat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Select the $_unit and enter the visitor\'s name'), backgroundColor: Colors.red));
      return;
    }
    final api = ref.read(apiServiceProvider);
    try {
      if (choice == 'in') {
        await api.addVisitorEntry(
            name: name.text.trim(),
            mobile: mobile.text.trim(),
            purpose: purposeText,
            flatNumber: flat!,
            vehicleNumber: vehicle.text.trim());
        ref.invalidate(guardVisitorsProvider);
        return;
      }
      final r = await api.requestVisitorApproval(
          name: name.text.trim(),
          mobile: mobile.text.trim(),
          purpose: purposeText,
          flatNumber: flat!,
          vehicleNumber: vehicle.text.trim());
      ref.invalidate(guardVisitorsProvider);
      if (mounted) _showWaitSheet('${r['visitorId']}', r['residents'] as int?);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
      }
    }
  }

  void _showWaitSheet(String visitorId, int? residents) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      showDragHandle: true,
      builder: (_) => _ApprovalWaitSheet(visitorId: visitorId, residents: residents, unit: _unit),
    ).then((_) {
      if (mounted) ref.invalidate(guardVisitorsProvider);
    });
  }

  Future<void> _showNewVehicleDialog() async {
    final vNo = TextEditingController();
    final driver = TextEditingController();
    String? flat;
    String type = 'Car';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, ss) => _GateForm(
          title: 'Vehicle entry',
          children: [
            TextField(
              controller: vNo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Vehicle number *', hintText: 'e.g. UP06AB1234', prefixIcon: Icon(Icons.pin_outlined)),
            ),
            _GateLabel('Type'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in const ['Car', 'Bike', 'Auto', 'Truck', 'Other'])
                ChoiceChip(label: Text(t), selected: type == t, onSelected: (_) => ss(() => type = t)),
            ]),
            UnitPickerField(onChanged: (v) => ss(() => flat = v)),
            TextField(
              controller: driver,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Driver name', prefixIcon: Icon(Icons.person_outline)),
            ),
          ],
          actions: [
            Expanded(
              child: OutlinedButton(onPressed: () => Navigator.pop(sheetCtx, false), child: const Text('Cancel')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(sheetCtx, true),
                icon: const Icon(Icons.login_rounded, size: 20),
                label: const Text('Log entry'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (vNo.text.trim().isEmpty || flat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter the vehicle number and select the $_unit'), backgroundColor: Colors.red));
      return;
    }
    try {
      await ref.read(apiServiceProvider).addVehicleLog(
          vehicleNumber: vNo.text.trim().toUpperCase(),
          vehicleType: type,
          flatNumber: flat!,
          driverName: driver.text.trim());
      ref.invalidate(guardVehiclesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showDialog({required String title, required List<Widget> fields, required Future<void> Function() onConfirm}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: fields)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          PremiumButton(
            onPressed: () async {
              try {
                await onConfirm();
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            label: 'Confirm',
          ),
        ],
      ),
    );
  }

  void _showSearchResidentVehicleDialog() {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search Resident Vehicle'),
        content: TextField(
          controller: searchCtrl,
          decoration: const InputDecoration(
            labelText: 'Registration Number',
            hintText: 'e.g. DL 1C AB 1234',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final regNo = searchCtrl.text.trim();
              if (regNo.isEmpty) return;

              final resident = await ref.read(apiServiceProvider).findResidentByVehicle(regNo);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (resident != null) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Vehicle Found'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Owner: ${resident['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('$_unit: ${resident['apartment_number']}'),
                          Text('Contact: ${resident['contact_number']}'),
                          const SizedBox(height: 12),
                          const Text('This is a verified resident vehicle.', style: TextStyle(color: Colors.green, fontSize: 12)),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('No resident found for this vehicle number.')),
                  );
                }
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}


/// Guard's live view of an approval request: ringing → approved / declined.
class _ApprovalWaitSheet extends ConsumerStatefulWidget {
  final String visitorId;
  final int? residents; // how many people were rung (null = unknown)
  final String unit;
  const _ApprovalWaitSheet({required this.visitorId, required this.residents, required this.unit});

  @override
  ConsumerState<_ApprovalWaitSheet> createState() => _ApprovalWaitSheetState();
}

class _ApprovalWaitSheetState extends ConsumerState<_ApprovalWaitSheet> {
  Map<String, dynamic>? _v;
  RealtimeChannel? _channel;
  Timer? _tick;
  DateTime _askedAt = DateTime.now();
  bool _busy = false;

  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = Supabase.instance.client
        .channel('wait-${widget.visitorId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'visitors',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.visitorId),
          callback: (p) {
            if (mounted) setState(() => _v = {...?_v, ...p.newRecord});
          },
        )
        .subscribe();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await _api.getVisitor(widget.visitorId);
      if (!mounted || v == null) return;
      final asked = DateTime.tryParse('${v['requested_at'] ?? ''}')?.toLocal();
      setState(() {
        _v = v;
        if (asked != null && asked.isBefore(DateTime.now())) _askedAt = asked;
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action, {bool close = true}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (close && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final status = v?['approval_status'] as String? ?? 'pending';
    final waited = DateTime.now().difference(_askedAt);
    final noAnswer = status == 'pending' && waited.inSeconds >= 60;
    final nobody = widget.residents == 0;
    final name = '${v?['name'] ?? 'Visitor'}';
    final flat = '${v?['flat_number'] ?? ''}';
    final by = '${v?['decided_by_name'] ?? 'resident'}';
    final note = '${v?['decision_note'] ?? ''}';
    final mmss = '${waited.inMinutes}:${(waited.inSeconds % 60).toString().padLeft(2, '0')}';

    Widget header(IconData icon, Color color, String title, String sub) => Column(children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
        ]);

    final List<Widget> body;
    if (status == 'approved') {
      body = [
        header(Icons.check_circle_rounded, Colors.green, 'Approved by $by',
            '$name may visit ${widget.unit} $flat${note.isNotEmpty ? '\n"$note"' : ''}'),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : () => _run(() => _api.checkInVisitor(widget.visitorId)),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Let in now'),
        ),
      ];
    } else if (status == 'rejected') {
      body = [
        header(Icons.cancel_rounded, Colors.red, 'Declined by $by',
            'Do not let $name in.${note.isNotEmpty ? '\n"$note"' : ''}'),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : () => _run(() => _api.turnAwayVisitor(widget.visitorId)),
          child: const Text('Turned away — close'),
        ),
      ];
    } else {
      body = [
        if (nobody)
          header(Icons.person_off_outlined, Colors.orange, 'No one to ask',
              'Nobody from ${widget.unit} $flat uses the app yet. Call them, then decide.')
        else ...[
          const SizedBox(height: 4),
          const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 5)),
          const SizedBox(height: 14),
          Text(noAnswer ? 'No answer yet' : 'Ringing ${widget.unit} $flat…',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '$name${widget.residents != null ? ' \u2022 ${widget.residents} ${widget.residents == 1 ? 'person' : 'people'} asked' : ''} \u2022 $mmss',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 20),
        if (noAnswer && !nobody)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await _api.reaskVisitorApproval(widget.visitorId);
                      if (mounted) setState(() => _askedAt = DateTime.now());
                    }, close: false),
            icon: const Icon(Icons.ring_volume_rounded),
            label: const Text('Ring again'),
          ),
        if (noAnswer || nobody) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : () => _run(() => _api.turnAwayVisitor(widget.visitorId)),
                child: const Text('Turn away'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : () => _run(() => _api.checkInVisitor(widget.visitorId)),
                child: const Text('Let in anyway'),
              ),
            ),
          ]),
        ] else
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Wait in background')),
      ];
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
      ),
    );
  }
}


/// Full-screen camera that reads a gate-pass QR and returns its 6-digit code.
class _PassScannerPage extends StatefulWidget {
  const _PassScannerPage();

  @override
  State<_PassScannerPage> createState() => _PassScannerPageState();
}

class _PassScannerPageState extends State<_PassScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue ?? '';
      final text = raw.startsWith(kPassQrPrefix) ? raw.substring(kPassQrPrefix.length) : raw;
      final code = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (code.length == 6) {
        _done = true;
        _controller.stop();
        Navigator.pop(context, code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan gate pass'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Text('Point the camera at the visitor\'s QR code',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ]),
    );
  }
}


/// Clean, evenly spaced form used in the gate bottom sheets.
class _GateForm extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  const _GateForm({required this.title, required this.children, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 14),
              ],
              const SizedBox(height: 22),
              Row(children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class _GateLabel extends StatelessWidget {
  final String text;
  const _GateLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
