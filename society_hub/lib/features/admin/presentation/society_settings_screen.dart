import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

final societyProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getSocietySettings();
});

class SocietySettingsScreen extends ConsumerStatefulWidget {
  const SocietySettingsScreen({super.key});

  @override
  ConsumerState<SocietySettingsScreen> createState() => _SocietySettingsScreenState();
}

class _SocietySettingsScreenState extends ConsumerState<SocietySettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _regCtrl.dispose();
    super.dispose();
  }

  void _initFromData(Map<String, dynamic> data) {
    if (!_initialized) {
      _nameCtrl.text = data['name'] ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _cityCtrl.text = data['city'] ?? '';
      _regCtrl.text = data['registrationNumber'] ?? '';
      _initialized = true;
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(apiServiceProvider).updateSocietySettings(
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        registrationNumber: _regCtrl.text.trim(),
      );
      ref.invalidate(societyProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('\u00E2\u0153\u2026 Society settings updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final societyAsync = ref.watch(societyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Society Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        actions: [
          _isLoading
              ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator())
              : FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
          const SizedBox(width: 8),
        ],
      ),
      body: societyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          _initFromData(data);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Society headline card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [colors.primary, const Color(0xFF1E1B4B)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.apartment_rounded, color: Colors.white, size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['name'] ?? 'Society', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(data['city'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                          if (data['registrationNumber'] != null)
                            Text('Reg: ${data['registrationNumber']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Society Stats
              _buildSectionLabel('SOCIETY STATS'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _buildStatCard(context, '${data['totalFlats'] ?? 0}', 'Total Flats', Icons.apartment_rounded, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard(context, '${data['totalResidents'] ?? 0}', 'Residents', Icons.people_rounded, Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard(context, '${data['totalBlocks'] ?? 0}', 'Blocks', Icons.domain_rounded, Colors.orange)),
              ]),
              const SizedBox(height: 32),

              // Edit Form
              _buildSectionLabel('SOCIETY DETAILS'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration(context, 'Society Name', Icons.apartment_rounded),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCtrl,
                decoration: _inputDecoration(context, 'Address', Icons.location_on_rounded),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityCtrl,
                decoration: _inputDecoration(context, 'City', Icons.location_city_rounded),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _regCtrl,
                decoration: _inputDecoration(context, 'Registration Number', Icons.badge_rounded),
              ),
              const SizedBox(height: 24),

              // Blocks & Flats
              _buildSectionLabel('BLOCKS & FLATS'),
              const SizedBox(height: 12),
              if (data['blocks'] != null)
                ...(data['blocks'] as List).map((block) => _buildBlockCard(context, block, colors)),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlockCard(BuildContext context, Map<String, dynamic> block, ColorScheme colors) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.domain_rounded, color: colors.primary),
        ),
        title: Text(block['name'] ?? 'Block', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${(block['Flats'] as List?)?.length ?? 0} flats', style: const TextStyle(color: Colors.grey)),
        children: (block['Flats'] as List? ?? []).map<Widget>((flat) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            leading: const Icon(Icons.meeting_room_rounded, size: 20),
            title: Text('Flat ${flat['number']}', style: const TextStyle(fontSize: 14)),
            subtitle: Text('Floor ${flat['floor'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 2));
  }
}

