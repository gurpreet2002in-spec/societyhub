import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../core/unit_labels.dart';

/// Shown to a logged-in resident who is not (yet) an active member of a society:
///  • no society yet       → enter the society code to send a join request
///  • pending              → waiting for the society admin's approval
///  • rejected             → told so, and can send a new request with a code
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  final _codeController = TextEditingController();
  final _flatController = TextEditingController();
  String _occupancy = 'owner';
  bool _busy = false;
  String? _societyName;
  String? _propertyType; // type of the society whose code was typed
  String _unitType = 'flat';
  String? _codeSocietyName;
  Timer? _codeDebounce;

  @override
  void initState() {
    super.initState();
    final u = ref.read(apiServiceProvider).user;
    _flatController.text = '${u?['apartment_number'] ?? ''}';
    if (u?['occupancy_type'] == 'tenant') _occupancy = 'tenant';
    if (u?['unit_type'] == 'house') _unitType = 'house';
    _loadSocietyName();
  }

  @override
  void dispose() {
    _codeDebounce?.cancel();
    _codeController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  Future<void> _loadSocietyName() async {
    try {
      final name = await ref.read(apiServiceProvider).mySocietyName();
      if (mounted) setState(() => _societyName = name);
    } catch (_) {}
  }

  void _onCodeChanged(String value) {
    _codeDebounce?.cancel();
    final code = value.trim();
    if (code.length < 4) {
      setState(() { _codeSocietyName = null; _propertyType = null; });
      return;
    }
    _codeDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final soc = await ref.read(apiServiceProvider).getSocietyByCode(code);
        if (!mounted || _codeController.text.trim() != code) return;
        setState(() {
          _codeSocietyName = soc?['name'];
          _propertyType = soc?['property_type'];
        });
      } catch (_) {}
    });
  }

  String? get _effectiveUnitType {
    switch (_propertyType) {
      case 'villas':
        return 'house';
      case 'mixed':
        return _unitType;
      case 'apartments':
        return 'flat';
      default:
        return null;
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.error : Colors.green,
    ));
  }

  /// Re-reads the profile; moves on once the admin has approved.
  Future<void> _checkAgain() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.refreshProfile();
      final user = api.user;
      if (!mounted) return;
      if (user?['status'] == 'active' && user?['society_id'] != null) {
        context.go(user?['role'] == 'guard' ? '/guard/dashboard' : '/dashboard');
      } else {
        setState(() {});
        _toast('Not approved yet. Please check again later.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _toast('Enter the society code from your society admin.', error: true);
      return;
    }
    if (_flatController.text.trim().isEmpty) {
      _toast('Enter your ${unitNoun(_propertyType ?? 'mixed', unitType: _effectiveUnitType).toLowerCase()} number.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      final society = await api.getSocietyByCode(code);
      if (society == null) throw Exception('Invalid society code. Check it with your society admin.');
      if (society['property_type'] == 'mixed' && _propertyType != 'mixed') {
        setState(() => _propertyType = 'mixed');
        throw Exception('Please choose whether you live in a flat or a house / villa.');
      }
      _propertyType = society['property_type'] ?? _propertyType;
      if (!mounted) return;
      setState(() => _busy = false);
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text('Join ${society['name']}?'),
          content: const Text('Your request goes to the society admin for approval.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Yes, join')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      final name = await api.joinSocietyWithCode(code,
          flat: _flatController.text.trim(), occupancyType: _occupancy, unitType: _effectiveUnitType);
      if (!mounted) return;
      _codeController.clear();
      setState(() => _societyName = name.isEmpty ? society['name']?.toString() : name);
      _toast('Request sent to ${_societyName ?? 'the society'}.');
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(apiServiceProvider).user;
    final status = user?['status'];
    final hasSociety = user?['society_id'] != null;
    final rejected = status == 'rejected';
    final waiting = hasSociety && !rejected;

    final IconData icon;
    final String title;
    final String body;
    if (waiting) {
      icon = Icons.hourglass_top_rounded;
      title = 'Waiting for approval';
      body = 'Your request to join ${_societyName ?? 'your society'} has been sent. '
          'You can use the app as soon as the society admin approves you.';
    } else if (rejected) {
      icon = Icons.block_rounded;
      title = 'Request declined';
      body = '${_societyName ?? 'The society'} admin declined your request. '
          'If this is a mistake, contact them, or enter a society code to send a new request.';
    } else {
      icon = Icons.apartment_rounded;
      title = 'Join your society';
      body = 'Enter the society code you got from your society admin.';
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _logout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log out'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 56, color: AppTheme.primary),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                        fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.onSurface)),
                const SizedBox(height: 12),
                Text(body,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: AppTheme.onSurfaceVariant)),
                if (user?['email'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Signed in as ${user!['email']}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 28),
                if (waiting)
                  FilledButton.icon(
                    onPressed: _busy ? null : _checkAgain,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Check again'),
                  )
                else ...[
                  TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Society code',
                      hintText: 'e.g. EKTA-7F3K',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                    onChanged: _onCodeChanged,
                    onSubmitted: (_) => _busy ? null : _join(),
                  ),
                  if (_codeSocietyName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text('\u2713 $_codeSocietyName',
                          style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  if (_propertyType == 'mixed') ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'flat', label: Text('Flat'), icon: Icon(Icons.apartment_rounded)),
                        ButtonSegment(value: 'house', label: Text('House / Villa'), icon: Icon(Icons.house_outlined)),
                      ],
                      selected: {_unitType},
                      onSelectionChanged: (s) => setState(() => _unitType = s.first),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _flatController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: unitNumberLabel(_propertyType ?? 'mixed', unitType: _effectiveUnitType),
                      hintText: unitHint(_propertyType ?? 'mixed', unitType: _effectiveUnitType),
                      prefixIcon: Icon(unitIcon(_propertyType ?? 'mixed', unitType: _effectiveUnitType)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'owner', label: Text('Owner'), icon: Icon(Icons.home_outlined)),
                      ButtonSegment(value: 'tenant', label: Text('Tenant'), icon: Icon(Icons.key_outlined)),
                    ],
                    selected: {_occupancy},
                    onSelectionChanged: (s) => setState(() => _occupancy = s.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send join request'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
