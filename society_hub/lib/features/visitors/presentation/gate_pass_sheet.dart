import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// What the guard's scanner reads from the QR code.
const kPassQrPrefix = 'SOCIETYHUB-PASS:';

/// Shows a visitor's gate pass: big pass code + QR, and a Share button so the
/// resident can send it to their guest (WhatsApp, SMS…).
Future<void> showGatePassSheet(
  BuildContext context, {
  required String visitorName,
  required String passCode,
  String? flat,
  String? societyName,
  DateTime? validUntil,
}) {
  String fmt(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  final spaced = passCode.length == 6 ? '${passCode.substring(0, 3)} ${passCode.substring(3)}' : passCode;
  final shareText = [
    'Hi $visitorName, here is your gate pass${societyName != null ? ' for $societyName' : ''}.',
    'Pass code: $spaced',
    if (flat != null) 'Visiting: $flat',
    if (validUntil != null) 'Valid until: ${fmt(validUntil)}',
    'Show this code to the security guard at the gate.',
  ].join('\n');

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Gate pass', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$visitorName${flat != null ? ' • $flat' : ''}', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: QrImageView(data: '$kPassQrPrefix$passCode', size: 200, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(spaced, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6)),
          if (validUntil != null) ...[
            const SizedBox(height: 4),
            Text('Valid until ${fmt(validUntil)} • one entry',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final box = c.findRenderObject() as RenderBox?;
                SharePlus.instance.share(ShareParams(
                  text: shareText,
                  subject: 'Gate pass',
                  sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                ));
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Send to visitor'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('The guard scans the QR or types the code.', style: TextStyle(color: Color(0xFF616161), fontSize: 12)),
        ]),
      ),
    ),
  );
}
