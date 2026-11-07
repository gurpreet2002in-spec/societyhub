import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../../../core/unit_labels.dart';
import '../../../widgets/unit_picker_field.dart';

// Provider for managing users list
final usersProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getUsers();
});

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  String? get _ptype => ref.read(apiServiceProvider).user?['propertyType'] as String?;
  String _noun(Map u) => unitNoun(_ptype, unitType: (u['unit_type'] ?? u['unitType']) as String?);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // The floating button changes on the Guards tab.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final usersAsync = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        actions: [
          IconButton(
            tooltip: 'Add guard',
            onPressed: () => _showAddUserDialog(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          TextButton.icon(
            onPressed: () => context.push('/admin/flats'),
            icon: const Icon(Icons.apartment_rounded),
            label: Text(unitsTitle(_ptype)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: () {
              final n = usersAsync.valueOrNull?.where((u) => u['status'] == 'pending').length ?? 0;
              return n > 0 ? 'Pending ($n)' : 'Pending';
            }()),
            const Tab(text: 'All'),
            const Tab(text: 'Residents'),
            const Tab(text: 'Guards'),
            const Tab(text: 'Admins'),
          ],
          isScrollable: true,
          tabAlignment: TabAlignment.start,
        ),
      ),
      floatingActionButton: _tabController.index == 3
          ? FloatingActionButton.extended(
              onPressed: () => _showAddUserDialog(context),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Add guard'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showInviteDialog(context),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Invite residents'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (users) {
                final members = users.where((u) => (u['status'] ?? 'active') == 'active').toList();
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingList(users, colors),
                    _buildUserList(members, null, colors),
                    _buildUserList(members, 'resident', colors),
                    _buildUserList(members, 'guard', colors),
                    _buildUserList(members, 'admin', colors),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Join requests ─────────────────────────────────────────────────────────
  Widget _buildPendingList(List<dynamic> allUsers, ColorScheme colors) {
    final pending = allUsers.where((u) => u['status'] == 'pending').toList();
    if (pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.how_to_reg_outlined, size: 64, color: colors.primary.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text('No join requests', style: TextStyle(color: Color(0xFF616161), fontSize: 16)),
              const SizedBox(height: 6),
              Text('Residents who register with your society code appear here for approval.',
                  textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF616161), fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: pending.length,
      itemBuilder: (context, i) {
        final u = Map<String, dynamic>.from(pending[i] as Map);
        final created = DateTime.tryParse('${u['created_at']}')?.toLocal();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u['name'] ?? 'New resident', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(u['email'] ?? '', style: TextStyle(color: Color(0xFF616161))),
                const SizedBox(height: 4),
                Text(
                  u['apartment_number'] != null
                      ? '${_noun(u)} ${u['apartment_number']}'
                          '${u['occupancy_type'] == 'owner' ? ' \u2022 Owner' : u['occupancy_type'] == 'tenant' ? ' \u2022 Tenant' : ''}'
                      : '${_noun(u)} not given',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: u['apartment_number'] != null ? Colors.black87 : Colors.orange.shade800,
                  ),
                ),
                if (created != null)
                  Text('Requested ${created.day}/${created.month}/${created.year}',
                      style: TextStyle(color: Color(0xFF616161), fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _decide(u, approve: false),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _decide(u, approve: true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dialog to set flat/house + owner/tenant (+ flat or house in a mixed
  /// society). Returns (number, occupancy, unitType) or null if cancelled.
  Future<(String, String?, String?)?> _askFlat(Map<String, dynamic> u, {required String title, required String button}) async {
    final flatCtrl = TextEditingController(text: '${u['apartment_number'] ?? u['apartmentNumber'] ?? ''}');
    String? occ = u['occupancy_type'] as String?;
    final ptype = _ptype;
    String unit = ((u['unit_type'] ?? u['unitType']) as String?) ??
        (ptype == 'villas' ? 'house' : 'flat');
    // The society's flats / houses list, for suggestions and a "not in list" warning.
    final register = <String, Map<String, dynamic>>{};
    try {
      for (final r in await ref.read(apiServiceProvider).getUnits()) {
        final m = Map<String, dynamic>.from(r as Map);
        register['${m['number']}'] = m;
      }
    } catch (_) {}
    if (!mounted) return null;
    return showDialog<(String, String?, String?)>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, ss) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${u['name'] ?? ''} \u2022 ${u['email'] ?? ''}', style: const TextStyle(color: Color(0xFF616161))),
              const SizedBox(height: 16),
              if (ptype == 'mixed') ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'flat', label: Text('Flat'), icon: Icon(Icons.apartment_rounded)),
                    ButtonSegment(value: 'house', label: Text('House'), icon: Icon(Icons.house_outlined)),
                  ],
                  selected: {unit},
                  onSelectionChanged: (s) => ss(() => unit = s.first),
                ),
                const SizedBox(height: 12),
              ],
              UnitPickerField(
                initialValue: flatCtrl.text,
                allowUnlisted: true,
                label: unitNumberLabel(ptype, unitType: ptype == 'mixed' ? unit : null),
                onChanged: (v) => ss(() {
                  flatCtrl.text = v ?? '';
                  final t = register[v]?['unit_type'] as String?;
                  if (t != null) unit = t;
                }),
              ),
              if (register.isNotEmpty && normalizeUnit(flatCtrl.text).isNotEmpty) ...[
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final r = register[normalizeUnit(flatCtrl.text)];
                  if (r == null) {
                    return Text('\u26A0 ${normalizeUnit(flatCtrl.text)} is not in your list',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800));
                  }
                  final owner = '${r['owner_name'] ?? ''}'.trim();
                  return Text(
                      '\u2713 In your list${owner.isEmpty ? '' : ' \u2022 Owner on record: $owner'}',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700));
                }),
              ],
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'owner', label: Text('Owner')),
                  ButtonSegment(value: 'tenant', label: Text('Tenant')),
                ],
                selected: {if (occ != null) occ!},
                emptySelectionAllowed: true,
                onSelectionChanged: (s) => ss(() => occ = s.isEmpty ? null : s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (flatCtrl.text.trim().isEmpty) return;
                Navigator.pop(dCtx, (flatCtrl.text.trim(), occ, ptype == 'mixed' ? unit : null));
              },
              child: Text(button),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editFlat(Map<String, dynamic> u) async {
    final r = await _askFlat(u, title: 'Change ${_noun(u).toLowerCase()}', button: 'Save');
    if (r == null) return;
    try {
      await ref.read(apiServiceProvider).setUserFlat('${u['id']}', r.$1, r.$2, unitType: r.$3);
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> u, {required bool approve}) async {
    if (approve) {
      // Confirm (and if needed correct) the flat before giving access.
      final r = await _askFlat(u, title: 'Approve ${u['name'] ?? 'resident'}?', button: 'Approve');
      if (r == null) return;
      try {
        final api = ref.read(apiServiceProvider);
        if (r.$1 != '${u['apartment_number'] ?? ''}' || r.$2 != u['occupancy_type'] ||
            (r.$3 != null && r.$3 != u['unit_type'])) {
          await api.setUserFlat('${u['id']}', r.$1, r.$2, unitType: r.$3);
        }
        await api.setUserStatus('${u['id']}', 'active');
        ref.invalidate(usersProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${u['name'] ?? 'Resident'} approved for ${unitNoun(_ptype, unitType: r.$3).toLowerCase()} ${r.$1.toUpperCase()}'),
              backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
        }
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(approve ? 'Approve ${u['name'] ?? 'resident'}?' : 'Reject ${u['name'] ?? 'resident'}?'),
        content: Text(approve
            ? '${u['email']} will get access to your society\'s notices, bills, visitors and other features.'
            : '${u['email']} will not get access. They can send a new request with your code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: approve ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).setUserStatus(u['id'], approve ? 'active' : 'rejected');
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? '${u['name'] ?? 'Resident'} approved' : 'Request rejected'),
          backgroundColor: approve ? Colors.green : Colors.grey.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Invite: show the society join code ────────────────────────────────────
  Future<void> _showInviteDialog(BuildContext context) async {
    String? code;
    String? name;
    try {
      final s = await ref.read(apiServiceProvider).getSocietySettings();
      code = s['join_code']?.toString();
      name = s['name']?.toString();
    } catch (_) {}
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Invite residents'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share this code with residents of ${name ?? 'your society'}. '
                'They enter it when registering in the app, then you approve them under Pending.'),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code ?? 'Code not available yet',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 2),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Close')),
          if (code != null)
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: 'Join ${name ?? 'our society'} on SocietyHub: install the app, tap '
                        '"New resident? Register here" and enter society code $code'));
                Navigator.pop(dCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite message copied. Paste it in WhatsApp.')));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy invite'),
            ),
        ],
      ),
    );
  }

  Widget _buildUserList(List<dynamic> allUsers, String? filterRole, ColorScheme colors) {
    final filtered = allUsers.where((u) {
      final matchRole = filterRole == null || u['role'] == filterRole;
      final matchSearch = _searchQuery.isEmpty ||
          (u['name'] ?? '').toLowerCase().contains(_searchQuery) ||
          (u['email'] ?? '').toLowerCase().contains(_searchQuery);
      return matchRole && matchSearch;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: colors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No users found', style: TextStyle(color: Color(0xFF616161), fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final user = filtered[i];
        return _buildUserCard(context, user, colors);
      },
    );
  }

  Widget _buildUserCard(BuildContext context, Map<String, dynamic> user, ColorScheme colors) {
    final role = user['role'] ?? 'resident';
    final isAdmin = role == 'admin';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isAdmin ? colors.primary.withValues(alpha: 0.12) : colors.secondary.withValues(alpha: 0.12),
          child: Text(
            (user['name'] ?? 'U').substring(0, 1).toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.bold, color: isAdmin ? colors.primary : colors.secondary),
          ),
        ),
        title: Text(user['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user['email'] ?? '', style: const TextStyle(fontSize: 12)),
            if (user['apartmentNumber'] != null)
              Text(
                '${_noun(user)} ${user['apartmentNumber']}'
                '${user['occupancy_type'] == 'owner' ? ' \u2022 Owner' : user['occupancy_type'] == 'tenant' ? ' \u2022 Tenant' : ''}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isAdmin ? colors.primary.withValues(alpha: 0.12) : Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isAdmin ? '\u{1F451} Admin' : '\u{1F3E0} Resident',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isAdmin ? colors.primary : Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _showUserDetailsDialog(context, user),
      ),
    );
  }

  void _showUserDetailsDialog(BuildContext context, Map<String, dynamic> user) {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.primary.withValues(alpha: 0.12),
                  child: Text(
                    (user['name'] ?? 'U')[0].toUpperCase(),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['name'] ?? 'Unknown', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(user['email'] ?? '', style: const TextStyle(color: Color(0xFF616161))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _detailRow(Icons.badge_rounded, 'Role', user['role'] ?? 'resident'),
            _detailRow(unitIcon(_ptype, unitType: user['unit_type'] as String?), _noun(user), user['apartmentNumber'] ?? 'N/A'),
            _detailRow(Icons.key_outlined, 'Owner / Tenant',
                user['occupancy_type'] == 'owner' ? 'Owner' : user['occupancy_type'] == 'tenant' ? 'Tenant' : 'Not set'),
            _detailRow(Icons.phone_rounded, 'Contact', user['contactNumber'] ?? 'N/A'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.door_front_door_outlined),
                label: Text('Change ${_noun(user).toLowerCase()} / owner-tenant'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _editFlat(user);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Change role'),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _pickRole(context, user);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove User'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _removeUser(context, user['id']);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Color(0xFF616161)),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: Color(0xFF616161), fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _pickRole(BuildContext context, Map<String, dynamic> user) async {
    final current = '${user['role'] ?? 'resident'}';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Role for ${user['name'] ?? 'this user'}',
                style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          for (final r in const [
            ('resident', 'Resident', 'Lives in a flat / house', Icons.home_outlined),
            ('guard', 'Security guard', 'Gate dashboard: visitors, vehicles, staff', Icons.shield_outlined),
            ('admin', 'Admin', 'Manages the society', Icons.admin_panel_settings_outlined),
          ])
            ListTile(
              leading: Icon(r.$4),
              title: Text(r.$2),
              subtitle: Text(r.$3),
              trailing: current == r.$1 ? const Icon(Icons.check_rounded, color: Colors.green) : null,
              enabled: current != r.$1,
              onTap: () => Navigator.pop(c, r.$1),
            ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'guard') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Make ${user['name'] ?? 'this user'} a guard?'),
          content: const Text('They will see the gate dashboard instead of the resident app, and are removed from '
              'their flat / house (one role per account). They need to log out and in again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make guard')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await _changeUserRole(context, '${user['id']}', choice);
  }

  Future<void> _changeUserRole(BuildContext context, String userId, String newRole) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.updateUserRole(userId, newRole);
      // A guard has no flat (so they don't appear in the flats list or get rung).
      if (newRole == 'guard') await api.setUserFlat(userId, null, null);
      ref.invalidate(usersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u2705 User role updated to $newRole'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _removeUser(BuildContext context, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove User'),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(apiServiceProvider).deleteUser(userId);
      ref.invalidate(usersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u2705 User removed'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  /// Society admin creates a ready-to-use login for a guard (or resident).
  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: _suggestPassword());
    final phoneCtrl = TextEditingController();
    final flatCtrl = TextEditingController();
    String role = 'guard';
    String occ = 'owner';
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(role == 'guard' ? 'Add security guard' : 'Add resident',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'guard', label: Text('Guard'), icon: Icon(Icons.shield_outlined)),
                    ButtonSegment(value: 'resident', label: Text('Resident'), icon: Icon(Icons.home_outlined)),
                  ],
                  selected: {role},
                  onSelectionChanged: (v) => setState(() => role = v.first),
                ),
                const SizedBox(height: 14),
                TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        labelText: role == 'guard' ? 'Name (e.g. Ramesh or "Main Gate") *' : 'Full name *')),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Login email *',
                    helperText: 'Any email works as the login name, e.g. gate1@yoursociety.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password * (min 8)',
                    suffixIcon: IconButton(
                      tooltip: 'New password',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () => setState(() => passwordCtrl.text = _suggestPassword()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone number')),
                if (role == 'resident') ...[
                  const SizedBox(height: 12),
                  UnitPickerField(
                    allowUnlisted: true,
                    initialValue: flatCtrl.text,
                    onChanged: (v) => flatCtrl.text = v ?? '',
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'owner', label: Text('Owner')),
                      ButtonSegment(value: 'tenant', label: Text('Tenant')),
                    ],
                    selected: {occ},
                    onSelectionChanged: (v) => setState(() => occ = v.first),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty ||
                          passwordCtrl.text.length < 8 || (role == 'resident' && flatCtrl.text.trim().isEmpty)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Fill the required fields (password at least 8 characters)')));
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await ref.read(apiServiceProvider).adminCreateUser(
                              name: nameCtrl.text.trim(),
                              email: emailCtrl.text.trim(),
                              password: passwordCtrl.text,
                              role: role,
                              contactNumber: phoneCtrl.text.trim(),
                              apartmentNumber: role == 'resident' ? flatCtrl.text.trim() : null,
                              occupancyType: role == 'resident' ? occ : null,
                            );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        ref.invalidate(usersProvider);
                        if (context.mounted) {
                          _showLoginDetails(context, nameCtrl.text.trim(), emailCtrl.text.trim(), passwordCtrl.text);
                        }
                      } catch (e) {
                        setState(() => busy = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(e.toString().replaceFirst('Exception: ', '')),
                              duration: const Duration(seconds: 6),
                              backgroundColor: Colors.red));
                        }
                      }
                    },
              child: Text(busy ? 'Creating…' : 'Create login'),
            ),
          ],
        ),
      ),
    );
  }

  String _suggestPassword() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _showLoginDetails(BuildContext context, String name, String email, String password) {
    final text = 'SocietyHub login for $name\nEmail: $email\nPassword: $password';
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('\u2705 Login ready'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Give these details to them. They can log in right away.'),
          const SizedBox(height: 12),
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 8),
          const Text('If this email already had an account, their old password still works.',
              style: TextStyle(fontSize: 12, color: Color(0xFF616161))),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
  }
}

