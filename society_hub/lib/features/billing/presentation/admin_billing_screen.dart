import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/api_service.dart';
import '../../payments/providers/payments_provider.dart';

class AdminBillingScreen extends ConsumerStatefulWidget {
  const AdminBillingScreen({super.key});

  @override
  ConsumerState<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends ConsumerState<AdminBillingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGenerating = false;

  final _titleController = TextEditingController(text: 'Monthly Maintenance');
  final _amountController = TextEditingController(text: '4500');
  final _taxController = TextEditingController(text: '810');
  DateTime _dueDate = DateTime.now().add(const Duration(days: 15));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final asyncInvoices = ref.watch(invoicesProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Billing Management', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Generate Bills'),
            Tab(text: 'All Invoices'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGenerateBillsTab(context, colors),
          _buildAllInvoicesTab(context, asyncInvoices),
        ],
      ),
    );
  }

  Widget _buildGenerateBillsTab(BuildContext context, ColorScheme colors) {
    final totalAmount = (double.tryParse(_amountController.text) ?? 0) +
        (double.tryParse(_taxController.text) ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.request_quote_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('Bulk Invoice Generator', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                const SizedBox(height: 16),
                Text('\u00E2\u201A\u00B9 ${totalAmount.toStringAsFixed(0)} per flat',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Base + GST combined total. Will be sent to all residents.',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text('Invoice Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Invoice Title',
              hintText: 'e.g. Monthly Maintenance, Water Bill...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              prefixIcon: const Icon(Icons.title),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Base Amount (\u00E2\u201A\u00B9)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    prefixIcon: const Icon(Icons.currency_rupee),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'GST Amount (\u00E2\u201A\u00B9)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    prefixIcon: const Icon(Icons.percent),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dueDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _dueDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Due Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('MMMM dd, yyyy').format(_dueDate),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const Spacer(),
                  const Icon(Icons.edit, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _doGenerate,
              icon: _isGenerating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_isGenerating ? 'Generating...' : 'Generate & Send to All Residents',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This will create individual invoices for every resident in your society. Razorpay payment links will be active.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllInvoicesTab(BuildContext context, AsyncValue<List<dynamic>> asyncInvoices) {
    return asyncInvoices.when(
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(child: Text('No invoices generated yet.', style: TextStyle(color: Colors.grey)));
        }

        final paid = invoices.where((i) => i['status'] == 'paid').length;
        final unpaid = invoices.where((i) => i['status'] == 'unpaid').length;
        final totalCollected = invoices
            .where((i) => i['status'] == 'paid')
            .fold(0.0, (s, i) => s + (i['totalAmount'] ?? 0));

        return Column(
          children: [
            // Summary Row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _statChip('Paid', '$paid', Colors.green),
                  const SizedBox(width: 8),
                  _statChip('Unpaid', '$unpaid', Colors.orange),
                  const SizedBox(width: 8),
                  _statChip('Collected', '\u00E2\u201A\u00B9${totalCollected.toStringAsFixed(0)}', Colors.blue),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: invoices.length,
                itemBuilder: (context, index) {
                  final inv = invoices[index];
                  final isPaid = inv['status'] == 'paid';
                  final residentName = inv['User']?['name'] ?? 'Resident';
                  return _buildAdminInvoiceRow(context, inv, isPaid, residentName);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminInvoiceRow(BuildContext context, Map<String, dynamic> inv, bool isPaid, String residentName) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPaid ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(isPaid ? Icons.check_circle : Icons.receipt_long,
                color: isPaid ? Colors.green : Colors.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(residentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(inv['title'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\u00E2\u201A\u00B9 ${inv['totalAmount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(isPaid ? 'PAID' : 'UNPAID',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.orange)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _doGenerate() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final tax = double.tryParse(_taxController.text) ?? 0;

    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await ref.read(apiServiceProvider).generateBulkInvoices(
          title, amount, tax, _dueDate.toIso8601String());
      ref.invalidate(invoicesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('\u00E2\u0153\u2026 Invoices generated for all residents!'),
            backgroundColor: Colors.green));
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}

