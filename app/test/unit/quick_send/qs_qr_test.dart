import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/quick_send/qs_qr.dart';

void main() {
  test('long base32 codes use a small alphanumeric QR code', () {
    final code = 'blob${'a2' * 160}';
    final image = qsQrImage(code);
    expect(image.moduleCount, lessThanOrEqualTo(53)); // version 9 at level L
  });

  test('other text still works (byte mode)', () {
    expect(qsQrImage('https://192.168.1.2:53317/?pin=12 34').moduleCount, greaterThan(20));
  });
}
