import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../providers/super_admin_provider.dart';
import '../../../widgets/premium_glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/premium_button.dart';

class SuperAdminSettingsScreen extends ConsumerStatefulWidget {
  const SuperAdminSettingsScreen({super.key});

  @override
  ConsumerState<SuperAdminSettingsScreen> createState() => _SuperAdminSettingsScreenState();
}

class _SuperAdminSettingsScreenState extends ConsumerState<SuperAdminSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _razorpayIdCtrl;
  late TextEditingController _razorpaySecretCtrl;
  bool _maintenanceMode = false;
  bool _gatewayActive = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _razorpayIdCtrl = TextEditingController();
    _razorpaySecretCtrl = TextEditingController();
  }

  void _loadInitialData(Map<String, dynamic> settings) {
    if (_nameCtrl.text.isEmpty) {
      _nameCtrl.text = settings['platformName'] ?? '';
      _emailCtrl.text = settings['supportEmail'] ?? '';
      _razorpayIdCtrl.text = settings['payment']?['razorpayKeyId'] ?? '';
      _razorpaySecretCtrl.text = settings['payment']?['razorpayKeySecret'] ?? '';
      _maintenanceMode = settings['maintenanceMode'] ?? false;
      _gatewayActive = settings['payment']?['gatewayActive'] ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(superAdminSettingsProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: PremiumGlassAppBar(
        showBranding: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: PremiumButton(
                onPressed: _saveAll,
                label: 'Save All',
                icon: Icons.check_circle_outline_rounded,
              ),
            ),
          ),
        ],
        showActions: false,
      ),
      body: settingsAsync.when(
        data: (settings) {
          _loadInitialData(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildHeader('GENERAL SYSTEM SETTINGS', colors),
                _buildTextField('Platform Brand Name', _nameCtrl, Icons.branding_watermark_rounded),
                _buildTextField('Support Email Address', _emailCtrl, Icons.contact_support_rounded),
                _buildSwitchTile(
                   title: 'System Maintenance Mode',
                   subtitle: 'If enabled, all users will see a maintenance screen.',
                   value: _maintenanceMode,
                   onChanged: (v) => setState(() => _maintenanceMode = v),
                   colors: colors,
                ),

                const SizedBox(height: 32),
                _buildHeader('RAZORPAY GATEWAY CREDENTIALS', colors),
                Text('These credentials are used for society-to-platform billing.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 16),
                _buildTextField('Razorpay Key ID', _razorpayIdCtrl, Icons.vpn_key_rounded),
                _buildTextField('Razorpay Key Secret', _razorpaySecretCtrl, Icons.security_rounded, obscure: true),
                _buildSwitchTile(
                   title: 'Enable Payment Processing',
                   subtitle: 'Toggle global payment processing status.',
                   value: _gatewayActive,
                   onChanged: (v) => setState(() => _gatewayActive = v),
                   colors: colors,
                ),

                const SizedBox(height: 32),
                _buildHeader('SUBSCRIPTION PLANS (READ-ONLY)', colors),
                Text('To edit plans, tap individual tiers below:', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 16),
                ...(settings['plans'] as List).map((plan) => _buildPlanCard(plan, colors)),
                
                const SizedBox(height: 80),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSwitchTile({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged, required ColorScheme colors}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: SwitchListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6), fontSize: 13)),
          value: value,
          onChanged: onChanged,
          activeThumbColor: colors.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildHeader(String title, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title, 
        style: TextStyle(
          fontSize: 11, 
          fontWeight: FontWeight.w900, 
          color: colors.primary, 
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, IconData icon, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _buildPlanCard(dynamic plan, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(plan['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Price: \u20B9${plan['price']} / month', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6))),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colors.primary),
          onTap: () => _showPlanDialog(plan),
        ),
      ),
    );
  }

  void _showPlanDialog(dynamic plan) {
    final priceCtrl = TextEditingController(text: '${plan['price']}');
    final nameCtrl = TextEditingController(text: plan['name']);
    final colors = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceContainerLowest,
        title: Text('Configure ${plan['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Display Name')),
            const SizedBox(height: 12),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Monthly Rate (\u20B9)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          PremiumButton(
            onPressed: () async {
               // Logic to update a single plan in the list
               final api = ref.read(apiServiceProvider);
               final currentSettings = await api.getSuperAdminSettings();
               final plans = List<dynamic>.from(currentSettings['plans']);
               final idx = plans.indexWhere((p) => p['id'] == plan['id']);
               if (idx != -1) {
                 plans[idx]['name'] = nameCtrl.text;
                 plans[idx]['price'] = double.tryParse(priceCtrl.text) ?? 0;
                 await api.updateSuperAdminSetting('plans', plans);
                 ref.invalidate(superAdminSettingsProvider);
               }
               if (ctx.mounted) Navigator.pop(ctx);
            },
            label: 'Update',
            isSecondary: true,
          ),
        ],
      ),
    );
  }

  Future<void> _saveAll() async {
    final api = ref.read(apiServiceProvider);
    try {
      await Future.wait([
        api.updateSuperAdminSetting('platformName', _nameCtrl.text),
        api.updateSuperAdminSetting('supportEmail', _emailCtrl.text),
        api.updateSuperAdminSetting('maintenanceMode', _maintenanceMode),
        api.updateSuperAdminSetting('payment', {
          'razorpayKeyId': _razorpayIdCtrl.text,
          'razorpayKeySecret': _razorpaySecretCtrl.text,
          'gatewayActive': _gatewayActive,
        }),
      ]);
      ref.invalidate(superAdminSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u2705 Platform settings saved successfully'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\u274C Save failed: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

