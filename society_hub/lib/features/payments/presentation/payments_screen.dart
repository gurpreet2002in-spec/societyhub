import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/payments_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/premium_glass_app_bar.dart';

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncInvoices = ref.watch(invoicesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: const PremiumGlassAppBar(showBranding: true),
      body: asyncInvoices.when(
        data: (invoices) {
          final pending = invoices
              .where((i) => i['status'] == 'unpaid' || i['status'] == 'overdue')
              .toList();
          final paid = invoices.where((i) => i['status'] == 'paid').toList();
          final totalDues = pending.fold(0.0, (sum, i) => sum + (i['totalAmount'] ?? 0));
          final totalExpenses = paid.fold(0.0, (sum, i) => sum + (i['totalAmount'] ?? 0));
          final balance = totalExpenses - totalDues;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),

                // \u2500\u2500 Page header \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                Text(
                  'FINANCIAL OVERSIGHT',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Society Treasury',
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onSurface,
                    letterSpacing: -1.0,
                  ),
                ),

                const SizedBox(height: 28),

                // \u2500\u2500 Summary bento grid \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.account_balance_wallet_rounded,
                            iconColor: AppTheme.primary,
                            label: 'Total Outstanding',
                            value: '\u20B9${totalDues.toStringAsFixed(0)}',
                            accentColor: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            icon: Icons.payments_rounded,
                            iconColor: const Color(0xFF7E3000),
                            label: 'Total Paid',
                            value: '\u20B9${totalExpenses.toStringAsFixed(0)}',
                            accentColor: const Color(0xFF7E3000),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SummaryCard(
                      icon: Icons.savings_rounded,
                      iconColor: AppTheme.secondary,
                      label: 'Net Balance',
                      value: '\u20B9${balance.abs().toStringAsFixed(0)}',
                      accentColor: AppTheme.secondary,
                      isWide: true,
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // \u2500\u2500 Pending invoices \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                if (pending.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pending Invoices',
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.errorContainer,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          '${pending.length} Due',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF93000A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: pending
                          .asMap()
                          .entries
                          .map((e) => _InvoiceRow(
                                invoice: e.value,
                                isPending: true,
                                isLast: e.key == pending.length - 1,
                                ref: ref,
                                context: context,
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],

                // \u2500\u2500 Financial audit / history \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Financial Audit',
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Recent authorized society payments',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          'Download',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.download_outlined, size: 16, color: AppTheme.primary),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: paid.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No past payments found.',
                              style: GoogleFonts.inter(
                                  color: AppTheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : Column(
                          children: paid
                              .asMap()
                              .entries
                              .map((e) => _InvoiceRow(
                                    invoice: e.value,
                                    isPending: false,
                                    isLast: e.key == paid.length - 1,
                                    ref: ref,
                                    context: context,
                                  ))
                              .toList(),
                        ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (err, _) => Center(
          child: Text('Error: $err',
              style: GoogleFonts.inter(color: AppTheme.error)),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color accentColor;
  final bool isWide;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.accentColor,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: isWide ? 28 : 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final bool isPending;
  final bool isLast;
  final WidgetRef ref;
  final BuildContext context;

  const _InvoiceRow({
    required this.invoice,
    required this.isPending,
    required this.isLast,
    required this.ref,
    required this.context,
  });

  @override
  Widget build(BuildContext mainContext) {
    final title = invoice['title'] ?? 'Maintenance';
    final amount = invoice['totalAmount'] ?? 0;
    final invoiceId = invoice['id'];
    final dueDateStr = invoice['dueDate'];
    DateTime? dueDate;
    if (dueDateStr != null && dueDateStr.toString().isNotEmpty) {
      dueDate = DateTime.tryParse(dueDateStr.toString());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              )
            : BorderRadius.zero,
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPending
                  ? AppTheme.error.withValues(alpha: 0.1)
                  : AppTheme.secondary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPending ? Icons.receipt_long_outlined : Icons.check_circle_outline,
              color: isPending ? AppTheme.error : AppTheme.secondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dueDate != null
                      ? '${isPending ? 'Due' : 'Paid'}: ${DateFormat('MMM dd, yyyy').format(dueDate)}'
                      : 'No date specified',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Connecting to Payment Gateway...',
                                style: GoogleFonts.inter()),
                            backgroundColor: AppTheme.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                        await ref.read(invoicesProvider.notifier).payInvoice(invoiceId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Payment Successful!',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                              backgroundColor: AppTheme.secondary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Payment failed: $e'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'PAY NOW',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Amount + badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\u20B9$amount',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isPending
                      ? AppTheme.errorContainer
                      : const Color(0xFFD4F5DF),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  isPending ? 'PENDING' : 'PAID',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isPending
                        ? const Color(0xFF93000A)
                        : AppTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
