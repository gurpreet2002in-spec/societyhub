import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../../../core/unit_labels.dart';
import '../../../core/csv_utils.dart';

/// Everything the Flats / Houses register needs.
final flatsDirectoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final users = await api.getUsers();
  List<dynamic> slots = [];
  try {
    slots = await api.getParkingSlots();
  } catch (_) {}
  List<dynamic> units = [];
  try {
    units = await api.getUnits();
  } catch (_) {}
  int? totalFlats;
  try {
    final s = await api.getSocietySettings();
    totalFlats = (s['total_flats'] as num?)?.toInt();
  } catch (_) {}
  return {'users': users, 'slots': slots, 'units': units, 'totalFlats': totalFlats};
});

/// Natural sort: A-2 before A-10.
int _flatCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final na = int.tryParse(pa[i]), nb = int.tryParse(pb[i]);
    final c = (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

String _s(Object? v) => v == null ? '' : '$v'.trim();

/// One flat / house with everything linked to it.
class _Unit {
  final String number;
  final Map<String, dynamic>? reg; // row in the register (null = not added yet)
  final List<Map<String, dynamic>> people;
  final List<Map<String, dynamic>> parking;
  _Unit(this.number, this.reg, this.people, this.parking);

  List<Map<String, dynamic>> get active => people.where((u) => u['status'] == 'active').toList();
  bool get occupied => active.isNotEmpty;
  bool get hasOwner => active.any((u) => u['occupancy_type'] == 'owner');
  bool get hasTenant => active.any((u) => u['occupancy_type'] == 'tenant');
  String? get unitType =>
      (reg?['unit_type'] as String?) ??
      people.map((u) => u['unit_type'] as String?).firstWhere((t) => t != null, orElse: () => null);
}

class FlatsScreen extends ConsumerStatefulWidget {
  const FlatsScreen({super.key});

  @override
  ConsumerState<FlatsScreen> createState() => _FlatsScreenState();
}

class _FlatsScreenState extends ConsumerState<FlatsScreen> {
  String _query = '';
  // all | vacant | owner | tenant | parking | unlisted | flat | house
  String _filter = 'all';
  List<_Unit> _lastUnits = const [];
  List<Map<String, dynamic>> _lastSlots = const [];
  int? _target; // "Total flats / houses" from Society Settings
  int _listed = 0;

  ApiService get _api => ref.read(apiServiceProvider);
  String? get _ptype => _api.user?['propertyType'] as String?;
  String get _noun => unitNoun(_ptype).toLowerCase();

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _reload() => ref.invalidate(flatsDirectoryProvider);

  // ───────────────────────────────────────────────────────────── build ──
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(flatsDirectoryProvider);
    final colors = Theme.of(context).colorScheme;
    final ptype = _ptype;
    final title = unitsTitle(ptype);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'many':
                  _addMany();
                  break;
                case 'import':
                  _import();
                  break;
                case 'export':
                  _export();
                  break;
                case 'template':
                  _template();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'many',
                child: ListTile(leading: Icon(Icons.playlist_add_rounded), title: Text('Add many at once')),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(leading: Icon(Icons.file_upload_outlined), title: Text('Import from CSV / Excel')),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Export full list (CSV)')),
              ),
              PopupMenuItem(
                value: 'template',
                child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Blank import template')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMenu,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add ${ptype == 'mixed' ? 'flat / house' : _noun}'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) {
          final users = List<Map<String, dynamic>>.from(
              (d['users'] as List).map((u) => Map<String, dynamic>.from(u as Map)));
          final slots = List<Map<String, dynamic>>.from(
              (d['slots'] as List).map((s) => Map<String, dynamic>.from(s as Map)));
          final regRows = List<Map<String, dynamic>>.from(
              (d['units'] as List).map((s) => Map<String, dynamic>.from(s as Map)));
          final totalSetting = d['totalFlats'] as int?;

          // ── Merge register + residents + parking by number ──
          final reg = {for (final r in regRows) _s(r['number']): r};
          final people = <String, List<Map<String, dynamic>>>{};
          final noFlat = <Map<String, dynamic>>[];
          for (final u in users) {
            if (u['status'] == 'rejected') continue;
            final f = _s(u['apartment_number']);
            if (f.isEmpty) {
              if (u['role'] == 'resident') noFlat.add(u);
              continue;
            }
            people.putIfAbsent(f, () => []).add(u);
          }
          final parking = <String, List<Map<String, dynamic>>>{};
          for (final s in slots) {
            final f = _s(s['flat_id']);
            if (f.isNotEmpty) parking.putIfAbsent(f, () => []).add(s);
          }
          final numbers = {...reg.keys, ...people.keys, ...parking.keys}.toList()..sort(_flatCompare);
          final all = [
            for (final n in numbers) _Unit(n, reg[n], people[n] ?? const [], parking[n] ?? const []),
          ];
          _lastUnits = all;
          _lastSlots = slots;
          _target = totalSetting;
          _listed = reg.length;

          // Total = what Society Settings says, or the list if it is bigger.
          final total = [totalSetting ?? 0, reg.length, all.length].reduce((a, b) => a > b ? a : b);
          final missing = (totalSetting ?? 0) - reg.length;
          final occupied = all.where((u) => u.occupied).length;
          final vacant = total - occupied < 0 ? 0 : total - occupied;
          final tenanted = all.where((u) => u.hasTenant).length;
          final unlisted = reg.isEmpty ? 0 : all.where((u) => u.reg == null).length;

          final q = _query.toLowerCase();
          final shown = all.where((u) {
            switch (_filter) {
              case 'vacant':
                if (u.occupied) return false;
                break;
              case 'owner':
                if (!u.hasOwner) return false;
                break;
              case 'tenant':
                if (!u.hasTenant) return false;
                break;
              case 'parking':
                if (u.parking.isEmpty) return false;
                break;
              case 'unlisted':
                if (u.reg != null) return false;
                break;
              case 'flat':
              case 'house':
                if (u.unitType != _filter) return false;
                break;
            }
            if (q.isEmpty) return true;
            return u.number.toLowerCase().contains(q) ||
                _s(u.reg?['owner_name']).toLowerCase().contains(q) ||
                _s(u.reg?['owner_phone']).contains(q) ||
                _s(u.reg?['block']).toLowerCase() == q ||
                u.people.any((p) => _s(p['name']).toLowerCase().contains(q) || _s(p['contact_number']).contains(q)) ||
                u.parking.any((s) =>
                    _s(s['slot_number']).toLowerCase().contains(q) || _s(s['vehicle_no']).toLowerCase().contains(q));
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Row(children: [
                  _stat('$total', 'Total', Colors.indigo),
                  const SizedBox(width: 8),
                  _stat('$occupied', 'Occupied', Colors.green),
                  const SizedBox(width: 8),
                  _stat('$vacant', 'Vacant', Colors.grey),
                  const SizedBox(width: 8),
                  _stat('$tenanted', 'Tenants', Colors.orange),
                  const SizedBox(width: 8),
                  _stat('${parking.length}', 'Parking', Colors.blue),
                ]),
                if (reg.isEmpty || missing > 0)
                  Card(
                    margin: const EdgeInsets.only(top: 12),
                    elevation: 0,
                    color: colors.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            missing > 0
                                ? '${reg.length} of $totalSetting ${title.toLowerCase()} added — $missing still to add'
                                : 'Create your ${title.toLowerCase()} list',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text(
                            'Society Settings only stores the total. Add each number once (with the owner and parking) '
                            'so you can assign residents and parking to it. "Add many" creates them all in one go.'),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                              onPressed: _addMany,
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: const Text('Add many at once')),
                          OutlinedButton.icon(
                              onPressed: _import,
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Import CSV')),
                        ]),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ActionChip(
                      avatar: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Add many'),
                      onPressed: _addMany),
                  ActionChip(
                      avatar: const Icon(Icons.file_upload_outlined, size: 18),
                      label: const Text('Import'),
                      onPressed: _import),
                  ActionChip(
                      avatar: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Export'),
                      onPressed: _export),
                ]),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search $_noun, owner, resident, phone, slot or vehicle…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in [
                      ('all', 'All'),
                      if (ptype == 'mixed') ('flat', 'Flats'),
                      if (ptype == 'mixed') ('house', 'Houses'),
                      ('vacant', 'Vacant'),
                      ('owner', 'Owner living'),
                      ('tenant', 'Tenants'),
                      ('parking', 'With parking'),
                      if (unlisted > 0) ('unlisted', 'Not in list ($unlisted)'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.$2),
                          selected: _filter == f.$1,
                          onSelected: (_) => setState(() => _filter = f.$1),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (noFlat.isNotEmpty && _query.isEmpty && _filter == 'all')
                  Card(
                    color: Colors.orange.shade50,
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                      title: Text(
                          '${noFlat.length} ${noFlat.length == 1 ? 'resident has' : 'residents have'} no $_noun number'),
                      subtitle: Text(noFlat.map((u) => u['name'] ?? u['email']).join(', ')),
                      trailing: TextButton(
                        onPressed: () => context.push('/admin/users'),
                        child: const Text('Fix in Users'),
                      ),
                    ),
                  ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      all.isEmpty ? 'Nothing here yet. Tap "Add" or import your list.' : 'Nothing matches.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF616161)),
                    ),
                  ),
                for (final u in shown) _unitCard(u, ptype, showUnlisted: reg.isNotEmpty),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFF616161))),
        ]),
      ),
    );
  }

  Widget _unitCard(_Unit u, String? ptype, {required bool showUnlisted}) {
    final colors = Theme.of(context).colorScheme;
    final owner = _s(u.reg?['owner_name']);
    final where = [
      if (_s(u.reg?['block']).isNotEmpty) 'Block ${_s(u.reg?['block'])}',
      if (_s(u.reg?['floor']).isNotEmpty) 'Floor ${_s(u.reg?['floor'])}',
    ].join(' • ');
    final status = !u.occupied
        ? 'Vacant'
        : u.hasOwner && u.hasTenant
            ? 'Owner + Tenant'
            : u.hasTenant
                ? 'Tenant living'
                : u.hasOwner
                    ? 'Owner living'
                    : 'Occupied';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openUnit(u),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(unitIcon(ptype, unitType: u.unitType), size: 16, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(u.number, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: colors.primary)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(where.isEmpty ? status : '$status  •  $where',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
              if (showUnlisted && u.reg == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Text('NOT IN LIST',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
                ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF616161)),
            ]),
            if (owner.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.badge_outlined, size: 16, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(child: Text('Owner: $owner', style: const TextStyle(fontWeight: FontWeight.w600))),
                if (_s(u.reg?['owner_phone']).isNotEmpty)
                  Text(_s(u.reg?['owner_phone']), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ]),
            ],
            if (u.people.isNotEmpty) const SizedBox(height: 6),
            for (final p in u.people)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(p['occupancy_type'] == 'tenant' ? Icons.key_outlined : Icons.home_outlined,
                      size: 16, color: p['occupancy_type'] == 'tenant' ? Colors.orange : Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${p['name'] ?? p['email'] ?? 'Resident'}'
                      '${p['occupancy_type'] == 'owner' ? ' (Owner)' : p['occupancy_type'] == 'tenant' ? ' (Tenant)' : ''}'
                      '${p['role'] == 'admin' ? ' • Admin' : ''}',
                    ),
                  ),
                  if (p['status'] == 'pending')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                      child: const Text('PENDING', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
            if (u.parking.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in u.parking) _slotChip(s),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _slotChip(Map<String, dynamic> s, {VoidCallback? onDeleted}) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        s['type'] == 'bike'
            ? Icons.two_wheeler_outlined
            : s['type'] == 'ev'
                ? Icons.ev_station_outlined
                : Icons.directions_car_outlined,
        size: 16,
      ),
      label: Text('${_s(s['slot_number'])}${_s(s['vehicle_no']).isNotEmpty ? ' • ${_s(s['vehicle_no'])}' : ''}'),
      onDeleted: onDeleted,
    );
  }

  // ───────────────────────────────────────────────────────── add menu ──
  Future<void> _addMenu() async {
    final noun = _ptype == 'mixed' ? 'flat / house' : _noun;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text('Add one $noun'),
            subtitle: const Text('Number, owner, block / floor'),
            onTap: () => Navigator.pop(c, 'one'),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Add many at once'),
            subtitle: Text(_ptype == 'villas' ? 'e.g. Villa 1 to Villa 100' : 'e.g. Block A, floors 1–10, 4 per floor'),
            onTap: () => Navigator.pop(c, 'many'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import from CSV / Excel'),
            subtitle: const Text('Numbers with owners and parking'),
            onTap: () => Navigator.pop(c, 'import'),
          ),
        ]),
      ),
    );
    if (v == 'one') _editUnit(null);
    if (v == 'many') _addMany();
    if (v == 'import') _import();
  }

  // ───────────────────────────────────────────────────── unit details ──
  Future<void> _openUnit(_Unit u) async {
    final ptype = _ptype;
    final reg = u.reg;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(unitIcon(ptype, unitType: u.unitType), color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${unitNoun(ptype, unitType: u.unitType)} ${u.number}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 12),
            if (reg == null)
              Card(
                elevation: 0,
                color: Colors.red.shade50,
                child: ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.red.shade700),
                  title: const Text('Not in your list yet'),
                  subtitle: const Text('A resident or parking slot uses this number.'),
                  trailing: FilledButton(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _editUnit(null, number: u.number, unitType: u.unitType);
                    },
                    child: const Text('Add'),
                  ),
                ),
              )
            else ...[
              _row(Icons.badge_outlined, 'Owner', _s(reg['owner_name']).isEmpty ? 'Not added' : _s(reg['owner_name'])),
              if (_s(reg['owner_phone']).isNotEmpty) _row(Icons.phone_outlined, 'Phone', _s(reg['owner_phone'])),
              if (_s(reg['owner_email']).isNotEmpty) _row(Icons.email_outlined, 'Email', _s(reg['owner_email'])),
              if (_s(reg['block']).isNotEmpty) _row(Icons.domain_outlined, 'Block', _s(reg['block'])),
              if (_s(reg['floor']).isNotEmpty) _row(Icons.stairs_outlined, 'Floor', _s(reg['floor'])),
              if (_s(reg['notes']).isNotEmpty) _row(Icons.notes_outlined, 'Notes', _s(reg['notes'])),
            ],
            const Divider(height: 28),
            Text('Living here (app users)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (u.people.isEmpty)
              const Text('Nobody has registered for this number yet.', style: TextStyle(color: Color(0xFF616161))),
            for (final p in u.people)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(p['occupancy_type'] == 'tenant' ? Icons.key_outlined : Icons.home_outlined),
                title: Text('${p['name'] ?? p['email'] ?? 'Resident'}'),
                subtitle: Text([
                  p['occupancy_type'] == 'owner'
                      ? 'Owner'
                      : p['occupancy_type'] == 'tenant'
                          ? 'Tenant'
                          : 'Owner/Tenant not set',
                  if (p['status'] == 'pending') 'Waiting for approval',
                  if (_s(p['contact_number']).isNotEmpty) _s(p['contact_number']),
                ].join(' • ')),
              ),
            const Divider(height: 28),
            Row(children: [
              Expanded(child: Text('Parking', style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _assignParking(u.number);
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Assign slot'),
              ),
            ]),
            if (u.parking.isEmpty) const Text('No parking slot.', style: TextStyle(color: Color(0xFF616161))),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in u.parking)
                _slotChip(s, onDeleted: () {
                  Navigator.pop(sheetCtx);
                  _freeSlot(s, u.number);
                }),
            ]),
            if (reg != null) ...[
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _deleteUnit(u);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _editUnit(reg);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Color(0xFF616161)),
          const SizedBox(width: 10),
          SizedBox(width: 64, child: Text(label, style: const TextStyle(color: Color(0xFF616161)))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  // ───────────────────────────────────────────────────── add / edit ──
  Future<void> _editUnit(Map<String, dynamic>? reg, {String? number, String? unitType}) async {
    final ptype = _ptype;
    final numCtrl =
        TextEditingController(text: _s(reg?['number']).isNotEmpty ? _s(reg?['number']) : (number ?? ''));
    final blockCtrl = TextEditingController(text: _s(reg?['block']));
    final floorCtrl = TextEditingController(text: _s(reg?['floor']));
    final nameCtrl = TextEditingController(text: _s(reg?['owner_name']));
    final phoneCtrl = TextEditingController(text: _s(reg?['owner_phone']));
    final emailCtrl = TextEditingController(text: _s(reg?['owner_email']));
    final notesCtrl = TextEditingController(text: _s(reg?['notes']));
    String type = (reg?['unit_type'] as String?) ?? unitType ?? (ptype == 'villas' ? 'house' : 'flat');
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, ss) {
          final noun = unitNoun(ptype, unitType: ptype == 'mixed' ? type : null);
          InputDecoration deco(String label, {String? hint, IconData? icon}) => InputDecoration(
                labelText: label,
                hintText: hint,
                prefixIcon: icon == null ? null : Icon(icon),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              );
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(reg == null ? 'Add ${noun.toLowerCase()}' : 'Edit ${_s(reg['number'])}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (ptype == 'mixed') ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'flat', label: Text('Flat'), icon: Icon(Icons.apartment_rounded)),
                      ButtonSegment(value: 'house', label: Text('House / Villa'), icon: Icon(Icons.house_outlined)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => ss(() => type = s.first),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: numCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: deco('$noun number *',
                      hint: unitHint(ptype, unitType: ptype == 'mixed' ? type : null),
                      icon: unitIcon(ptype, unitType: type)),
                ),
                if (reg != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Text('Changing the number also updates its residents and parking.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF616161))),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: blockCtrl, decoration: deco('Block / Tower / Lane'))),
                  const SizedBox(width: 10),
                  SizedBox(width: 110, child: TextField(controller: floorCtrl, decoration: deco('Floor'))),
                ]),
                const SizedBox(height: 20),
                Text('Owner', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: deco('Owner name', icon: Icons.badge_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: deco('Owner phone', icon: Icons.phone_outlined)),
                const SizedBox(height: 12),
                TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: deco('Owner email', icon: Icons.email_outlined)),
                const SizedBox(height: 12),
                TextField(controller: notesCtrl, maxLines: 2, decoration: deco('Notes')),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (normalizeUnit(numCtrl.text).isEmpty) {
                            _toast('Enter the ${noun.toLowerCase()} number', error: true);
                            return;
                          }
                          ss(() => saving = true);
                          try {
                            await _api.saveUnit(
                              id: reg == null ? null : '${reg['id']}',
                              number: numCtrl.text,
                              unitType: type,
                              block: blockCtrl.text,
                              floor: floorCtrl.text,
                              ownerName: nameCtrl.text,
                              ownerPhone: phoneCtrl.text,
                              ownerEmail: emailCtrl.text,
                              notes: notesCtrl.text,
                            );
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            _reload();
                            _toast(reg == null ? '${normalizeUnit(numCtrl.text)} added' : 'Saved');
                          } catch (e) {
                            ss(() => saving = false);
                            _toast(_err(e), error: true);
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteUnit(_Unit u) async {
    final reg = u.reg;
    if (reg == null) return;
    final extra = [
      if (u.people.isNotEmpty) '${u.people.length} resident(s) will show as "not in list" (their accounts stay).',
      if (u.parking.isNotEmpty) '${u.parking.length} parking slot(s) will be freed.',
    ].join('\n');
    final ok =
        await _confirm('Delete ${u.number}?', extra.isEmpty ? 'This removes it from the list.' : extra, 'Delete');
    if (!ok) return;
    try {
      await _api.deleteUnit('${reg['id']}');
      _reload();
      _toast('${u.number} deleted');
    } catch (e) {
      _toast(_err(e), error: true);
    }
  }

  // ───────────────────────────────────────────────────────── parking ──
  Future<void> _freeSlot(Map<String, dynamic> s, String number) async {
    final ok = await _confirm(
        'Free slot ${_s(s['slot_number'])}?', 'It will no longer be assigned to $number.', 'Free slot');
    if (!ok) return;
    try {
      await _api.releaseParking('${s['id']}');
      _reload();
      _toast('Slot freed');
    } catch (e) {
      _toast(_err(e), error: true);
    }
  }

  Future<void> _assignParking(String number) async {
    final free = _lastSlots.where((s) => _s(s['flat_id']).isEmpty).toList()
      ..sort((a, b) => _flatCompare(_s(a['slot_number']), _s(b['slot_number'])));
    if (free.isEmpty) {
      _toast('No free parking slots. Add slots in Parking first.', error: true);
      return;
    }
    Map<String, dynamic> slot = free.first;
    final vehicleCtrl = TextEditingController();
    String vType = 'car';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text('Parking for $number'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Map<String, dynamic>>(
              initialValue: slot,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Free slot'),
              items: [
                for (final s in free)
                  DropdownMenuItem(value: s, child: Text('${_s(s['slot_number'])}  (${_s(s['type'])})')),
              ],
              onChanged: (v) {
                if (v != null) ss(() => slot = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vehicleCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Vehicle number (optional)', hintText: 'e.g. MH12AB1234'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'car', label: Text('Car')),
                ButtonSegment(value: 'bike', label: Text('Bike')),
                ButtonSegment(value: 'ev', label: Text('EV')),
              ],
              selected: {vType},
              onSelectionChanged: (s) => ss(() => vType = s.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.allocateParking('${slot['id']}', number, vehicleCtrl.text.trim(), vType);
      _reload();
      _toast('Slot ${_s(slot['slot_number'])} assigned to $number');
    } catch (e) {
      _toast(_err(e), error: true);
    }
  }

  // ─────────────────────────────────────────────────────── add many ──
  Future<void> _addMany() async {
    final ptype = _ptype;
    String mode = ptype == 'villas' ? 'range' : 'floors';
    String type = ptype == 'villas' ? 'house' : 'flat';
    final blockCtrl = TextEditingController();
    final fromCtrl = TextEditingController(text: '1');
    // For houses, pre-fill "1 to <total from Society Settings>".
    final toCtrl = TextEditingController(
        text: ptype == 'villas' ? '${(_target ?? 0) > 0 ? _target : 50}' : '10');
    final perFloorCtrl = TextEditingController(text: '4');
    final prefixCtrl = TextEditingController(text: ptype == 'villas' ? 'Villa' : '');

    List<String> generate() {
      final a = int.tryParse(fromCtrl.text.trim()) ?? -1;
      final b = int.tryParse(toCtrl.text.trim()) ?? -2;
      if (a < 0 || b < a || b - a > 2000) return [];
      final out = <String>[];
      if (mode == 'floors') {
        final per = int.tryParse(perFloorCtrl.text.trim()) ?? 0;
        if (per < 1 || per > 99) return [];
        final block = blockCtrl.text.trim().toUpperCase();
        for (var f = a; f <= b; f++) {
          for (var i = 1; i <= per; i++) {
            final n = '$f${i.toString().padLeft(2, '0')}';
            out.add(normalizeUnit(block.isEmpty ? n : '$block-$n'));
          }
        }
      } else {
        final p = prefixCtrl.text.trim();
        for (var n = a; n <= b; n++) {
          out.add(normalizeUnit(p.isEmpty ? '$n' : '$p-$n'));
        }
      }
      return out.length > 3000 ? [] : out;
    }

    final numbers = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, ss) {
        final list = generate();
        final preview = list.isEmpty
            ? 'Check the numbers above'
            : list.length <= 6
                ? list.join(', ')
                : '${list.take(3).join(', ')} … ${list.skip(list.length - 2).join(', ')}';
        InputDecoration deco(String l, {String? h}) =>
            InputDecoration(labelText: l, hintText: h, isDense: true);
        Widget numField(TextEditingController ctrl, String label) => Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => ss(() {}),
                decoration: deco(label),
              ),
            );
        return AlertDialog(
          title: const Text('Add many at once'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'floors', label: Text('By floor')),
                  ButtonSegment(value: 'range', label: Text('Simple range')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => ss(() => mode = s.first),
              ),
              if (ptype == 'mixed') ...[
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'flat', label: Text('Flats')),
                    ButtonSegment(value: 'house', label: Text('Houses')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => ss(() => type = s.first),
                ),
              ],
              const SizedBox(height: 14),
              if (mode == 'floors') ...[
                TextField(
                  controller: blockCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => ss(() {}),
                  decoration: deco('Block / Tower (optional)', h: 'e.g. A'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  numField(fromCtrl, 'From floor'),
                  const SizedBox(width: 8),
                  numField(toCtrl, 'To floor'),
                ]),
                const SizedBox(height: 10),
                Row(children: [numField(perFloorCtrl, 'Flats on each floor')]),
              ] else ...[
                TextField(
                  controller: prefixCtrl,
                  onChanged: (_) => ss(() {}),
                  decoration: deco('Start with (optional)', h: 'e.g. Villa, H, Plot'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  numField(fromCtrl, 'From number'),
                  const SizedBox(width: 8),
                  numField(toCtrl, 'To number'),
                ]),
              ],
              const SizedBox(height: 14),
              Text(list.isEmpty ? preview : '${list.length} will be added: $preview',
                  style: TextStyle(color: list.isEmpty ? Colors.red : Colors.grey.shade700, fontSize: 12)),
              if ((_target ?? 0) > 0) ...[
                const SizedBox(height: 4),
                Text('Society total: $_target • already in list: $_listed',
                    style: const TextStyle(color: Color(0xFF616161), fontSize: 11)),
              ],
              const SizedBox(height: 4),
              const Text('Numbers already in the list are kept as they are.',
                  style: TextStyle(color: Color(0xFF616161), fontSize: 11)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: list.isEmpty ? null : () => Navigator.pop(c, list), child: const Text('Add')),
          ],
        );
      }),
    );
    if (numbers == null || numbers.isEmpty) return;
    final block = mode == 'floors' ? blockCtrl.text.trim().toUpperCase() : '';
    final rows = <Map<String, dynamic>>[
      for (final n in numbers)
        {
          'number': n,
          'type': type,
          if (block.isNotEmpty) 'block': block,
          if (mode == 'floors') 'floor': _floorOf(n),
        },
    ];
    await _runImport(rows, title: 'Added');
  }

  /// "A-305" → "3", "1204" → "12" (last two digits are the flat on that floor).
  String _floorOf(String number) {
    final m = RegExp(r'(\d+)$').firstMatch(number);
    if (m == null) return '';
    final d = m.group(1)!;
    return d.length > 2 ? '${int.parse(d.substring(0, d.length - 2))}' : '0';
  }

  // ──────────────────────────────────────────────── import / export ──
  static const _headers = [
    'Number', 'Type', 'Block', 'Floor', 'Owner name', 'Owner phone', 'Owner email', 'Parking', 'Notes',
  ];

  static const _headerKeys = <String, String>{
    'number': 'number', 'no': 'number', 'flat': 'number', 'flatno': 'number', 'flatnumber': 'number',
    'house': 'number', 'houseno': 'number', 'housenumber': 'number', 'unit': 'number', 'unitno': 'number',
    'unitnumber': 'number', 'flathouse': 'number', 'flathouseno': 'number', 'flathousenumber': 'number',
    'villa': 'number', 'villano': 'number', 'plot': 'number', 'plotno': 'number', 'apartment': 'number',
    'type': 'type', 'unittype': 'type', 'kind': 'type',
    'block': 'block', 'tower': 'block', 'wing': 'block', 'building': 'block', 'lane': 'block',
    'floor': 'floor',
    'owner': 'owner_name', 'ownername': 'owner_name', 'name': 'owner_name',
    'ownerphone': 'owner_phone', 'phone': 'owner_phone', 'mobile': 'owner_phone', 'contact': 'owner_phone',
    'ownermobile': 'owner_phone', 'ownercontact': 'owner_phone', 'phoneno': 'owner_phone', 'mobileno': 'owner_phone',
    'owneremail': 'owner_email', 'email': 'owner_email', 'emailid': 'owner_email',
    'parking': 'parking', 'parkingslot': 'parking', 'parkingslots': 'parking', 'slot': 'parking',
    'slots': 'parking', 'parkingno': 'parking',
    'notes': 'notes', 'note': 'notes', 'remarks': 'notes',
  };

  static String _key(String h) => _headerKeys[h.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')] ?? '';

  static String? _type(String v) {
    final t = v.toLowerCase();
    if (t.contains('house') || t.contains('villa') || t.contains('bungalow') || t.contains('plot')) return 'house';
    if (t.contains('flat') || t.contains('apart')) return 'flat';
    return null;
  }

  Future<void> _import() async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
                'Use a CSV file with a header row, e.g. Number, Type, Block, Floor, Owner name, Owner phone, '
                'Owner email, Parking. From Excel / Google Sheets: save or download as CSV.',
                style: TextStyle(color: Color(0xFF616161))),
          ),
          ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Choose CSV file'),
              onTap: () => Navigator.pop(c, 'file')),
          ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('Paste from a spreadsheet'),
              onTap: () => Navigator.pop(c, 'paste')),
          ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Get blank template'),
              onTap: () => Navigator.pop(c, 'template')),
        ]),
      ),
    );
    if (how == null) return;
    if (how == 'template') {
      await _template();
      return;
    }

    String? text;
    try {
      text = how == 'file' ? await pickCsvText() : await _pasteDialog();
    } catch (e) {
      _toast(_err(e), error: true);
      return;
    }
    if (text == null || text.trim().isEmpty) return;

    final table = parseCsv(text);
    if (table.isEmpty) {
      _toast('The file is empty', error: true);
      return;
    }
    var keys = table.first.map(_key).toList();
    var data = table.skip(1).toList();
    if (!keys.contains('number')) {
      // No header row: first column is the number.
      keys = ['number', for (var i = 1; i < table.first.length; i++) ''];
      data = table;
    }
    final rows = <Map<String, dynamic>>[];
    for (final r in data) {
      final m = <String, dynamic>{};
      for (var i = 0; i < keys.length && i < r.length; i++) {
        final k = keys[i];
        if (k.isEmpty || r[i].isEmpty || m.containsKey(k)) continue; // first matching column wins
        m[k] = k == 'type' ? _type(r[i]) : r[i];
      }
      if (m['number'] != null) rows.add(m);
    }
    if (rows.isEmpty) {
      _toast('No $_noun numbers found. Check the "Number" column.', error: true);
      return;
    }
    final found = {for (final k in keys) if (k.isNotEmpty) k.replaceAll('_', ' ')}.join(', ');
    if (!mounted) return;
    final ok = await _confirm(
      'Import ${rows.length} rows?',
      'Columns found: $found.\n\nNew numbers are added; existing ones are updated (blank cells keep the saved '
          'value). Parking slots listed are assigned, and created if missing.',
      'Import',
    );
    if (!ok) return;
    await _runImport(rows, title: 'Import done');
  }

  Future<String?> _pasteDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Paste rows'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Number, Owner name, Owner phone\nA-101, Ravi Kumar, 9876543210',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Next')),
        ],
      ),
    );
  }

  Future<void> _runImport(List<Map<String, dynamic>> rows, {required String title}) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    int added = 0, updated = 0, skipped = 0, parked = 0;
    final errs = <String>[];
    Object? error;
    try {
      // Send in chunks so a big society doesn't time out.
      for (var i = 0; i < rows.length; i += 500) {
        final end = i + 500 > rows.length ? rows.length : i + 500;
        final part = await _api.importUnits(rows.sublist(i, end));
        added += (part['added'] as num?)?.toInt() ?? 0;
        updated += (part['updated'] as num?)?.toInt() ?? 0;
        skipped += (part['skipped'] as num?)?.toInt() ?? 0;
        parked += (part['parkingAssigned'] as num?)?.toInt() ?? 0;
        errs.addAll(List<String>.from(part['errors'] as List? ?? const []));
      }
    } catch (e) {
      error = e;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    _reload();
    if (!mounted) return;
    if (error != null) {
      _toast(_err(error), error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text([
            '$added added',
            if (updated > 0) '$updated already there (updated)',
            if (parked > 0) '$parked parking slots assigned',
            if (skipped > 0) '$skipped rows skipped',
            if (errs.isNotEmpty) '\nProblems:\n• ${errs.join('\n• ')}',
          ].join('\n')),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _export() async {
    final units = _lastUnits;
    if (units.isEmpty) {
      _toast('Nothing to export yet', error: true);
      return;
    }
    String occ(Map p) => p['occupancy_type'] == 'owner'
        ? 'Owner'
        : p['occupancy_type'] == 'tenant'
            ? 'Tenant'
            : '';
    final rows = <List<Object?>>[
      [..._headers, 'Status', 'Residents (app)', 'Resident phones', 'Vehicles', 'In list'],
      for (final u in units)
        [
          u.number,
          u.unitType == 'house' ? 'House' : 'Flat',
          _s(u.reg?['block']),
          _s(u.reg?['floor']),
          _s(u.reg?['owner_name']),
          _s(u.reg?['owner_phone']),
          _s(u.reg?['owner_email']),
          u.parking.map((s) => _s(s['slot_number'])).join('; '),
          _s(u.reg?['notes']),
          u.occupied ? (u.hasTenant ? 'Tenant living' : 'Owner living') : 'Vacant',
          u.people
              .map((p) =>
                  '${_s(p['name'])}${occ(p).isEmpty ? '' : ' (${occ(p)})'}${p['status'] == 'pending' ? ' [pending]' : ''}')
              .join('; '),
          u.people.map((p) => _s(p['contact_number'])).where((x) => x.isNotEmpty).join('; '),
          u.parking.map((s) => _s(s['vehicle_no'])).where((x) => x.isNotEmpty).join('; '),
          u.reg == null ? 'No' : 'Yes',
        ],
    ];
    final d = DateTime.now();
    final stamp = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final name = '${unitsTitle(_ptype).replaceAll(' & ', '_').toLowerCase()}_$stamp.csv';
    try {
      await shareCsvFile(context, name, toCsv(rows));
    } catch (e) {
      _toast('Could not export: ${_err(e)}', error: true);
    }
  }

  Future<void> _template() async {
    final ptype = _ptype;
    final rows = <List<Object?>>[
      _headers,
      if (ptype != 'villas') ['A-101', 'Flat', 'A', '1', 'Ravi Kumar', '9876543210', 'ravi@example.com', 'P-01', ''],
      if (ptype != 'villas') ['A-102', 'Flat', 'A', '1', '', '', '', '', 'Vacant'],
      if (ptype != 'apartments') ['VILLA-12', 'House', 'Lane 2', '', 'Sunita Shah', '9123456780', '', 'P-21; P-22', ''],
    ];
    try {
      await shareCsvFile(context, 'import_template.csv', toCsv(rows));
    } catch (e) {
      _toast('Could not create the template: ${_err(e)}', error: true);
    }
  }
}
