// Quick Send: QR image for base32 codes ("Over the internet").
//
// Upper-case base32 fits the QR alphanumeric mode, which makes the code much
// smaller (fewer, larger modules) than the byte mode used for arbitrary text.
// The apps accept either case when reading a code.

import 'package:pretty_qr_code/pretty_qr_code.dart';

QrImage qsQrImage(String data, {int errorCorrectLevel = QrErrorCorrectLevel.L}) {
  if (RegExp(r'^[a-z0-9]+$').hasMatch(data)) {
    final upper = data.toUpperCase();
    for (var type = 1; type <= 40; type++) {
      try {
        return QrImage(QrCode(type, errorCorrectLevel)..addAlphaNumeric(upper));
      } catch (_) {
        // Too long for this version, try the next one.
      }
    }
  }
  return QrImage(QrCode.fromData(data: data, errorCorrectLevel: errorCorrectLevel));
}
