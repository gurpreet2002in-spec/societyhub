import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Minimal CSV read / write (Excel & Google Sheets compatible).

String toCsv(List<List<Object?>> rows) {
  String cell(Object? v) {
    final s = v == null ? '' : '$v';
    if (s.contains(RegExp(r'[",\r\n]')) || s.startsWith(' ') || s.endsWith(' ')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    // Stop spreadsheet apps treating a cell as a formula.
    if (s.isNotEmpty && '=+-@'.contains(s[0]) && !RegExp(r'^[+-]?\d').hasMatch(s)) return "'$s";
    return s;
  }

  return rows.map((r) => r.map(cell).join(',')).join('\r\n');
}

List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  // Excel in some regions saves with ';' — pick whichever separator the header uses most.
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ('\t'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? '\t' : ',');

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  return rows;
}

/// Opens the share sheet (Save to Files / Drive / WhatsApp / email…).
/// In a web browser the file is downloaded.
Future<void> shareCsvFile(BuildContext context, String fileName, String csv) async {
  final bytes = Uint8List.fromList(utf8.encode('﻿$csv')); // BOM so Excel reads ₹, names etc.
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
    fileNameOverrides: [fileName],
    subject: fileName,
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

/// Lets the user choose a .csv file. Returns its text, or null if cancelled.
Future<String?> pickCsvText() async {
  final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.single;
  final name = f.name.toLowerCase();
  if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
    throw Exception('Please save the sheet as CSV first (Excel: File → Save As → CSV).');
  }
  final bytes = f.bytes;
  if (bytes == null) throw Exception('Could not read the file.');
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}
