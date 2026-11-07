import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/api_service.dart';
import '../providers/visitor_provider.dart';
import 'gate_pass_sheet.dart';

/// Resident: create a gate pass for an expected visitor (pass code + QR).
class CreatePassScreen extends ConsumerStatefulWidget {
  const CreatePassScreen({super.key});

  @override
  ConsumerState<CreatePassScreen> createState() => _CreatePassScreenState();
}

class _CreatePassScreenState extends ConsumerState<CreatePassScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  String _purpose = 'Guest';
  int _validHours = 24;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the visitor\'s name')));
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final pass = await ref.read(visitorsProvider.notifier).preapproveVisitor(
            _nameController.text.trim(),
            _mobileController.text.trim(),
            _purpose,
            now,
            validUntil: now.add(Duration(hours: _validHours)),
          );
      if (!mounted) return;
      if (pass?.passCode != null) {
        final user = ref.read(apiServiceProvider).user;
        await showGatePassSheet(
          context,
          visitorName: pass!.name,
          passCode: pass.passCode!,
          flat: pass.flatNumber,
          societyName: user?['societyName'] as String?,
          validUntil: pass.passValidUntil,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '').replaceFirst(RegExp(r'^PostgrestException\(message: '), '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          filled: true,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('New gate pass')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'Your visitor gets a 6-digit code and QR. The guard scans it and lets them in — no call needed.',
            style: TextStyle(color: Color(0xFF616161)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: deco('Visitor name *'),
          ),
          const SizedBox(height: 16),
          TextField(controller: _mobileController, keyboardType: TextInputType.phone, decoration: deco('Mobile number')),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _purpose,
            decoration: deco('Purpose'),
            items: const [
              DropdownMenuItem(value: 'Guest', child: Text('Guest')),
              DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
              DropdownMenuItem(value: 'Cab', child: Text('Cab')),
              DropdownMenuItem(value: 'Service', child: Text('Service / Repair')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _purpose = val);
            },
          ),
          const SizedBox(height: 20),
          const Text('Valid for', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4 hours')),
              ButtonSegment(value: 24, label: Text('1 day')),
              ButtonSegment(value: 72, label: Text('3 days')),
              ButtonSegment(value: 168, label: Text('7 days')),
            ],
            selected: {_validHours},
            onSelectionChanged: (v) => setState(() => _validHours = v.first),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: Text(_busy ? 'Creating…' : 'Create pass', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
