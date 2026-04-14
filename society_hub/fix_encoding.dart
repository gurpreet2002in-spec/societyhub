import 'dart:io';
import 'dart:convert';

void main() async {
  final dir = Directory('lib');
  
  if (!await dir.exists()) {
    print('lib directory not found');
    return;
  }
  
  await for (var entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
        try {
            // First try reading as UTF-8
            String content = await entity.readAsString(encoding: utf8);
            String newContent = escapeNonAscii(content);
            if (content != newContent) {
                await entity.writeAsString(newContent, encoding: utf8);
                print('Fixed encoding (UTF-8) in: ${entity.path}');
            }
        } catch (e) {
            // If UTF-8 fails
            try {
                // Try reading as latin1 (similar to cp1252)
                String content = await entity.readAsString(encoding: latin1);
                String newContent = escapeNonAscii(content);
                if (content != newContent) {
                    await entity.writeAsString(newContent, encoding: utf8); // write back as utf8
                    print('Fixed encoding (Latin-1 fallback) in: ${entity.path}');
                }
            } catch (e2) {
                print('Failed to read ${entity.path}: $e2');
            }
        }
    }
  }
}

String escapeNonAscii(String text) {
  StringBuffer buffer = StringBuffer();
  for (int i = 0; i < text.runes.length; i++) {
    int codePoint = text.runes.elementAt(i);
    // ASCII is 0-127
    if (codePoint > 127) {
      if (codePoint <= 0xFFFF) {
        String hex = codePoint.toRadixString(16).toUpperCase().padLeft(4, '0');
        buffer.write('\\u$hex');
      } else {
        String hex = codePoint.toRadixString(16).toUpperCase();
        buffer.write('\\u{$hex}');
      }
    } else {
      buffer.writeCharCode(codePoint);
    }
  }
  return buffer.toString();
}
