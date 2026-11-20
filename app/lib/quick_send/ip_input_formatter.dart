// Quick Send: IPv4 entry that places the dots by itself (manual sending).
//
// Digits and dots only, at most four parts of at most three digits, each part
// at most 255. A dot is added as soon as the part cannot grow any further
// ("192" -> "192.", "26" -> "26.", "0" -> "0."), and a digit that would make
// a part too large starts the next part instead. Deleting never re-adds dots.

import 'package:flutter/services.dart';

String formatIpv4Input(String input, {bool autoDot = true}) {
  final parts = <String>[];
  var current = '';
  for (final ch in input.split('')) {
    if (ch == '.') {
      if (current.isNotEmpty && parts.length < 3) {
        parts.add(current);
        current = '';
      }
      continue;
    }
    if (!RegExp(r'[0-9]').hasMatch(ch)) continue;
    final grown = current + ch;
    final full = current.length == 3 || current == '0' || int.parse(grown) > 255;
    if (current.isNotEmpty && full) {
      if (parts.length == 3) continue; // fourth part is complete
      parts.add(current);
      current = ch;
    } else {
      current = grown;
    }
  }
  var result = [...parts, current].join('.');
  if (current.isEmpty && parts.isNotEmpty) result = '${parts.join('.')}.';
  if (autoDot && parts.length < 3 && current.isNotEmpty) {
    final complete = current.length == 3 || current == '0' || int.parse(current) * 10 > 255;
    if (complete) result = '$result.';
  }
  return result;
}

/// True for a complete dotted IPv4 address.
bool isCompleteIpv4(String text) {
  final parts = text.split('.');
  return parts.length == 4 && parts.every((p) => p.isNotEmpty && p.length <= 3 && int.parse(p) <= 255);
}

class Ipv4InputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final deleting = newValue.text.length < oldValue.text.length;
    final text = formatIpv4Input(newValue.text, autoDot: !deleting);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The last part of an address for "#" (hashtag) entry: digits only, 0–255.
class HashtagInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final text = digits.length > 3 || (digits.isNotEmpty && int.parse(digits) > 255) ? oldValue.text : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
