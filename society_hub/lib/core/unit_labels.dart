import 'package:flutter/material.dart';

// Words and icons for a resident's home, depending on the society type:
//   'apartments' → Flat, 'villas' → House, 'mixed' → Flat / House.
// unitType ('flat' | 'house') wins when known (e.g. a villa in a mixed society).

const societyTypeLabels = {
  'apartments': 'Apartments / flats only',
  'villas': 'Independent houses / villas only',
  'mixed': 'Both flats and houses / villas',
};

String unitNoun(String? propertyType, {String? unitType}) {
  if (unitType == 'house') return 'House';
  if (unitType == 'flat') return 'Flat';
  switch (propertyType) {
    case 'villas':
      return 'House';
    case 'mixed':
      return 'Flat / House';
    default:
      return 'Flat';
  }
}

String unitNumberLabel(String? propertyType, {String? unitType}) =>
    '${unitNoun(propertyType, unitType: unitType)} number';

String unitHint(String? propertyType, {String? unitType}) {
  if (unitType == 'house' || propertyType == 'villas') return 'e.g. Villa 12 or H-12';
  if (unitType == 'flat' || propertyType == 'apartments' || propertyType == null) return 'e.g. B-402';
  return 'e.g. B-402 or Villa 12';
}

String unitsTitle(String? propertyType) {
  switch (propertyType) {
    case 'villas':
      return 'Houses';
    case 'mixed':
      return 'Flats & Houses';
    default:
      return 'Flats';
  }
}

IconData unitIcon(String? propertyType, {String? unitType}) {
  if (unitType == 'house' || (unitType == null && propertyType == 'villas')) return Icons.house_outlined;
  return Icons.apartment_rounded;
}

/// Same tidy-up the database does: "b 402", "b402", "B_402" → "B-402".
String normalizeUnit(String? s) {
  var t = (s ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s_/\\]+'), '-');
  t = t.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final m = RegExp(r'^([A-Z]+)-?([0-9]+)$').firstMatch(t);
  if (m != null) t = '${m.group(1)}-${m.group(2)}';
  return t;
}
