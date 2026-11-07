import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../services/api_service.dart';

// Admin forms for setting up a society: polls, amenities and parking slots.
// The database only accepts these writes from that society's admin.

String _err(Object e) => e.toString().replaceFirst('Exception: ', '');

Widget _sheet(BuildContext ctx, {required String title, required List<Widget> children}) {
  return Padding(
    padding: EdgeInsets.only(
      left: 24,
      right: 24,
      top: 24,
      bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
    );

// ─── Create poll ───────────────────────────────────────────────────────────

/// Returns true when a poll was created.
Future<bool> showCreatePollSheet(BuildContext context, WidgetRef ref) async {
  final questionCtrl = TextEditingController();
  final optionCtrls = [TextEditingController(text: 'Yes'), TextEditingController(text: 'No')];
  DateTime? endsAt = DateTime.now().add(const Duration(days: 7));
  bool saving = false;

  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _sheet(ctx, title: 'Create poll', children: [
        TextField(
          controller: questionCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec('Question', hint: 'e.g. Should we install solar panels?'),
        ),
        const SizedBox(height: 16),
        const Text('Options', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (var i = 0; i < optionCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: optionCtrls[i],
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _dec('Option ${i + 1}'),
                ),
              ),
              if (optionCtrls.length > 2)
                IconButton(
                  tooltip: 'Remove option',
                  onPressed: () => ss(() => optionCtrls.removeAt(i)),
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                ),
            ]),
          ),
        if (optionCtrls.length < 6)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ss(() => optionCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
            ),
          ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(endsAt == null ? 'No end date' : 'Ends ${DateFormat('d MMM yyyy').format(endsAt!)}'),
          subtitle: const Text('Voting closes at the end of this day'),
          trailing: TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: endsAt ?? DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                ss(() => endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
              }
            },
            child: const Text('Change'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  ss(() => saving = true);
                  try {
                    await ref.read(apiServiceProvider).createPoll(
                          questionCtrl.text,
                          optionCtrls.map((c) => c.text).toList(),
                          endsAt: endsAt,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    ss(() => saving = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(_err(e)), backgroundColor: Colors.red));
                    }
                  }
                },
          child: saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Publish poll'),
        ),
        const SizedBox(height: 4),
        const Text('Residents get a notification when the poll is published.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF616161))),
      ]),
    ),
  );
  return created == true;
}

// ─── Add / edit amenity ────────────────────────────────────────────────────

const _amenityEmojis = [
  '\u{1F3CA}', // pool
  '\u{1F3CB}️', // gym
  '\u{1F389}', // party hall
  '\u{1F3BE}', // tennis
  '\u{1F3F8}', // badminton
  '\u{1F9D8}', // yoga
  '\u{1F3AE}', // games room
  '\u{1F333}', // garden
  '\u{1F3E2}', // clubhouse
  '\u{1F697}', // guest parking
];

/// Returns true when the list changed (saved or deleted).
Future<bool> showAmenityEditor(BuildContext context, WidgetRef ref, {Map<String, dynamic>? amenity}) async {
  final isEdit = amenity != null;
  final nameCtrl = TextEditingController(text: amenity?['name'] ?? '');
  final descCtrl = TextEditingController(text: amenity?['description'] ?? '');
  final capCtrl = TextEditingController(text: '${amenity?['capacity'] ?? 10}');
  final priceCtrl = TextEditingController(
      text: amenity?['pricePerHour'] == null ? '0' : NumberFormat('0.##').format(amenity!['pricePerHour']));
  String emoji = amenity?['imageEmoji'] ?? _amenityEmojis.first;
  String open = amenity?['openTime'] ?? '06:00';
  String close = amenity?['closeTime'] ?? '22:00';
  bool saving = false;

  Future<String?> pickTime(BuildContext ctx, String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 6, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => _sheet(ctx, title: isEdit ? 'Edit amenity' : 'Add amenity', children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _amenityEmojis)
              ChoiceChip(
                label: Text(e, style: const TextStyle(fontSize: 22)),
                selected: emoji == e,
                onSelected: (_) => ss(() => emoji = e),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Name', hint: 'e.g. Swimming Pool'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec('Description (optional)', hint: 'Rules, location, what to bring…'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: _dec('Capacity', hint: 'people'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec('₹ per hour', hint: '0 = free'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final v = await pickTime(ctx, open);
                if (v != null) ss(() => open = v);
              },
              icon: const Icon(Icons.wb_sunny_outlined),
              label: Text('Opens $open'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final v = await pickTime(ctx, close);
                if (v != null) ss(() => close = v);
              },
              icon: const Icon(Icons.nightlight_outlined),
              label: Text('Closes $close'),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  ss(() => saving = true);
                  try {
                    await ref.read(apiServiceProvider).saveAmenity({
                      'name': nameCtrl.text,
                      'description': descCtrl.text,
                      'capacity': capCtrl.text,
                      'pricePerHour': priceCtrl.text,
                      'imageEmoji': emoji,
                      'openTime': open,
                      'closeTime': close,
                    }, id: isEdit ? '${amenity!['id']}' : null);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    ss(() => saving = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(_err(e)), backgroundColor: Colors.red));
                    }
                  }
                },
          child: saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit ? 'Save changes' : 'Add amenity'),
        ),
        if (isEdit) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: saving
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: Text('Delete ${amenity!['name']}?'),
                        content: const Text('Its bookings are deleted too. This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await ref.read(apiServiceProvider).deleteAmenity('${amenity!['id']}');
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(_err(e)), backgroundColor: Colors.red));
                      }
                    }
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete amenity'),
          ),
        ],
      ]),
    ),
  );
  return changed == true;
}

// ─── Add parking slots ─────────────────────────────────────────────────────

/// Returns true when slots were added.
Future<bool> showAddParkingSlotsSheet(BuildContext context, WidgetRef ref) async {
  final prefixCtrl = TextEditingController(text: 'P-');
  final fromCtrl = TextEditingController(text: '1');
  final toCtrl = TextEditingController(text: '10');
  final singleCtrl = TextEditingController();
  String type = 'car';
  bool range = true;
  bool saving = false;

  List<String> numbers() {
    if (!range) return [singleCtrl.text.trim()];
    final from = int.tryParse(fromCtrl.text.trim()) ?? 0;
    final to = int.tryParse(toCtrl.text.trim()) ?? 0;
    if (from <= 0 || to < from || to - from >= 500) return [];
    return [for (var i = from; i <= to; i++) '${prefixCtrl.text.trim()}$i'];
  }

  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) {
        final preview = numbers();
        return _sheet(ctx, title: 'Add parking slots', children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'car', label: Text('Car'), icon: Icon(Icons.directions_car_outlined)),
              ButtonSegment(value: 'bike', label: Text('Bike'), icon: Icon(Icons.two_wheeler_outlined)),
              ButtonSegment(value: 'ev', label: Text('EV'), icon: Icon(Icons.ev_station_outlined)),
            ],
            selected: {type},
            onSelectionChanged: (s) => ss(() => type = s.first),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add a numbered range'),
            subtitle: const Text('e.g. P-1 to P-40 in one go'),
            value: range,
            onChanged: (v) => ss(() => range = v),
          ),
          const SizedBox(height: 8),
          if (range)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: prefixCtrl,
                  onChanged: (_) => ss(() {}),
                  decoration: _dec('Prefix', hint: 'P-'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fromCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ss(() {}),
                  decoration: _dec('From'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: toCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ss(() {}),
                  decoration: _dec('To'),
                ),
              ),
            ])
          else
            TextField(
              controller: singleCtrl,
              onChanged: (_) => ss(() {}),
              textCapitalization: TextCapitalization.characters,
              decoration: _dec('Slot number', hint: 'e.g. B1-07'),
            ),
          const SizedBox(height: 8),
          Text(
            preview.isEmpty || preview.first.isEmpty
                ? (range ? 'Enter a valid range (max 500 slots at a time).' : 'Enter a slot number.')
                : preview.length == 1
                    ? 'Will add: ${preview.first}'
                    : 'Will add ${preview.length} slots: ${preview.first} … ${preview.last}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF616161)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving || preview.isEmpty || preview.first.isEmpty
                ? null
                : () async {
                    ss(() => saving = true);
                    try {
                      final n = await ref.read(apiServiceProvider).addParkingSlots(preview, type);
                      if (ctx.mounted) {
                        Navigator.pop(ctx, n > 0);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(n == preview.length
                              ? '$n ${n == 1 ? 'slot' : 'slots'} added'
                              : '$n added; ${preview.length - n} already existed and were skipped'),
                        ));
                      }
                    } catch (e) {
                      ss(() => saving = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(_err(e)), backgroundColor: Colors.red));
                      }
                    }
                  },
            child: saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add slots'),
          ),
        ]);
      },
    ),
  );
  return added == true;
}
