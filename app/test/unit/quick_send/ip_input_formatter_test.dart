import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/quick_send/ip_input_formatter.dart';

/// Types [keys] one by one through the formatter, like a user would.
String type(String keys, {String start = ''}) {
  final f = Ipv4InputFormatter();
  var value = TextEditingValue(text: start);
  for (final k in keys.split('')) {
    value = f.formatEditUpdate(value, TextEditingValue(text: value.text + k));
  }
  return value.text;
}

void main() {
  test('dots are added automatically', () {
    expect(type('192168123'), '192.168.123.');
    // A short part needs its dot typed ("1" + "12" vs "112" is ambiguous); the auto dot after 168 is not doubled.
    expect(type('192168.1.123'), '192.168.1.123');
    expect(type('100011'), '100.0.11');
    expect(type('17216.2545'), '172.16.254.5');
  });

  test('typed dots are kept, doubled dots are ignored', () {
    expect(type('10.0.0.1'), '10.0.0.1');
    expect(type('10..5'), '10.5');
    expect(type('1.2.3.4.5'), '1.2.3.45');
  });

  test('parts never exceed 255 and letters are dropped', () {
    expect(type('300'), '30.0.');
    expect(type('25a6'), '25.6');
    expect(isCompleteIpv4('192.168.1.123'), isTrue);
    expect(isCompleteIpv4('192.168.1.'), isFalse);
    expect(isCompleteIpv4('256.1.1.1'), isFalse);
  });

  test('deleting does not re-add a dot', () {
    final f = Ipv4InputFormatter();
    final out = f.formatEditUpdate(const TextEditingValue(text: '192.'), const TextEditingValue(text: '192'));
    expect(out.text, '192');
  });

  test('hashtag accepts 0-255 only', () {
    final f = HashtagInputFormatter();
    expect(f.formatEditUpdate(const TextEditingValue(text: '12'), const TextEditingValue(text: '123')).text, '123');
    expect(f.formatEditUpdate(const TextEditingValue(text: '25'), const TextEditingValue(text: '256')).text, '25');
    expect(f.formatEditUpdate(const TextEditingValue(text: ''), const TextEditingValue(text: '#7')).text, '7');
  });
}
