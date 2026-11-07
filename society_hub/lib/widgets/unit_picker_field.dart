import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/unit_labels.dart';
import '../services/api_service.dart';

/// One flat / house the picker can offer.
class UnitOption {
  final String number;
  final String? unitType; // flat | house
  final String? owner;
  final String? block;
  final List<String> residents;
  const UnitOption(this.number, {this.unitType, this.owner, this.block, this.residents = const []});
}

/// The society's flats / houses, from the admin's list. When that list is
/// still empty, falls back to numbers already used by residents and parking.
final societyUnitsProvider = FutureProvider.autoDispose<List<UnitOption>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final byNumber = <String, UnitOption>{};

  List<dynamic> users = [];
  try {
    users = await api.getUsers();
  } catch (_) {}
  final residentsOf = <String, List<String>>{};
  for (final u in users) {
    final n = '${u['apartment_number'] ?? ''}'.trim();
    if (n.isEmpty || u['status'] != 'active') continue;
    residentsOf.putIfAbsent(n, () => []).add('${u['name'] ?? ''}'.trim());
  }

  try {
    for (final r in await api.getUnits()) {
      final n = '${r['number'] ?? ''}'.trim();
      if (n.isEmpty) continue;
      byNumber[n] = UnitOption(
        n,
        unitType: r['unit_type'] as String?,
        owner: (r['owner_name'] as String?)?.trim(),
        block: (r['block'] as String?)?.trim(),
        residents: residentsOf[n] ?? const [],
      );
    }
  } catch (_) {}

  if (byNumber.isEmpty) {
    for (final e in residentsOf.entries) {
      byNumber[e.key] = UnitOption(e.key, residents: e.value);
    }
  }

  final list = byNumber.values.toList()..sort((a, b) => _naturalCompare(a.number, b.number));
  return list;
});

int _naturalCompare(String a, String b) {
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

/// A form field for choosing a flat / house of this society.
/// Tapping it opens a searchable list: typing "101" shows A-101, B-101 …
/// with the owner's name, so nobody has to type the number by hand.
class UnitPickerField extends ConsumerStatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? label;
  final bool required;

  /// Allow a number that is not in the society's list (admins only).
  /// When the society has no list yet, typing a number is always allowed.
  final bool allowUnlisted;

  const UnitPickerField({
    super.key,
    required this.onChanged,
    this.initialValue,
    this.label,
    this.required = true,
    this.allowUnlisted = false,
  });

  @override
  ConsumerState<UnitPickerField> createState() => _UnitPickerFieldState();
}

class _UnitPickerFieldState extends ConsumerState<UnitPickerField> {
  String? _value;

  @override
  void initState() {
    super.initState();
    final v = normalizeUnit(widget.initialValue);
    _value = v.isEmpty ? null : v;
  }

  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UnitSearchSheet(allowUnlisted: widget.allowUnlisted, selected: _value),
    );
    if (picked == null || !mounted) return;
    setState(() => _value = picked);
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ptype = ref.read(apiServiceProvider).user?['propertyType'] as String?;
    final units = ref.watch(societyUnitsProvider).valueOrNull ?? const <UnitOption>[];
    UnitOption? match;
    for (final u in units) {
      if (u.number == _value) match = u;
    }
    final label = widget.label ?? unitNumberLabel(ptype);
    final details = [
      if (match?.owner != null && match!.owner!.isNotEmpty) 'Owner: ${match.owner}',
      if (match?.block != null && match!.block!.isNotEmpty) 'Block ${match.block}',
    ].join(' • ');

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: _value == null,
        decoration: InputDecoration(
          labelText: widget.required ? '$label *' : label,
          hintText: 'Tap to search',
          prefixIcon: Icon(unitIcon(ptype, unitType: match?.unitType)),
          suffixIcon: const Icon(Icons.search_rounded),
          helperText: details.isEmpty ? null : details,
        ),
        child: _value == null
            ? null
            : Text(_value!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _UnitSearchSheet extends ConsumerStatefulWidget {
  final bool allowUnlisted;
  final String? selected;
  const _UnitSearchSheet({required this.allowUnlisted, this.selected});

  @override
  ConsumerState<_UnitSearchSheet> createState() => _UnitSearchSheetState();
}

class _UnitSearchSheetState extends ConsumerState<_UnitSearchSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<UnitOption> _filter(List<UnitOption> all) {
    if (_q.isEmpty) return all;
    final norm = normalizeUnit(_q);
    final digits = _q.replaceAll(RegExp(r'[^0-9]'), '');
    final text = _q.toLowerCase();
    int rank(UnitOption u) {
      if (u.number == norm) return 0;
      final tail = RegExp(r'(\d+)$').firstMatch(u.number)?.group(1);
      if (digits.isNotEmpty && tail == digits) return 1; // "101" → A-101, B-101
      if (u.number.startsWith(norm)) return 2;
      return 3;
    }

    final hits = all.where((u) {
      return (norm.isNotEmpty && u.number.contains(norm)) ||
          (digits.isNotEmpty && u.number.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) ||
          (u.owner ?? '').toLowerCase().contains(text) ||
          u.residents.any((r) => r.toLowerCase().contains(text)) ||
          (u.block ?? '').toLowerCase() == text;
    }).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : _naturalCompare(a.number, b.number);
      });
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final ptype = ref.read(apiServiceProvider).user?['propertyType'] as String?;
    final async = ref.watch(societyUnitsProvider);
    final noun = unitNoun(ptype).toLowerCase();
    final height = MediaQuery.of(context).size.height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text('Select $noun',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: 'Type number or owner name, e.g. 101',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() {
                          _ctrl.clear();
                          _q = '';
                        }),
                      ),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load the list: $e')),
              data: (all) {
                final hits = _filter(all);
                final typed = normalizeUnit(_q);
                final canUseTyped = typed.isNotEmpty &&
                    (widget.allowUnlisted || all.isEmpty) &&
                    !all.any((u) => u.number == typed);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    if (all.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No ${unitsTitle(ptype).toLowerCase()} have been added to this society yet. '
                          'Ask the admin to add them (Admin → ${unitsTitle(ptype)}). Meanwhile you can type the number.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    if (canUseTyped)
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text('Use "$typed"'),
                        subtitle: Text(all.isEmpty ? 'Typed by hand' : 'Not in the society list'),
                        onTap: () => Navigator.pop(context, typed),
                      ),
                    if (all.isNotEmpty && hits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No $noun matches "$_q".',
                            textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF616161))),
                      ),
                    for (final u in hits)
                      ListTile(
                        selected: u.number == widget.selected,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(unitIcon(ptype, unitType: u.unitType),
                              color: Theme.of(context).colorScheme.primary, size: 20),
                        ),
                        title: Text(u.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            if ((u.owner ?? '').isNotEmpty) 'Owner: ${u.owner}',
                            if (u.residents.isNotEmpty) '${u.residents.length} living here',
                            if ((u.block ?? '').isNotEmpty) 'Block ${u.block}',
                          ].join(' • ').ifEmpty('No one registered yet'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: u.number == widget.selected ? const Icon(Icons.check_rounded) : null,
                        onTap: () => Navigator.pop(context, u.number),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
