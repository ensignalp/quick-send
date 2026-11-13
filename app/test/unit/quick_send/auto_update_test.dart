import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/quick_send/auto_update.dart';

// Vectors produced with OpenSSL:
//   openssl ecparam -name prime256v1 -genkey -noout -out k.pem
//   openssl ec -in k.pem -pubout -outform DER | base64 -w0
//   openssl dgst -sha256 -sign k.pem -out sums.sig sums.txt
const _pub = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEoZv8acS89pamY7c17xLO8DaD2R1mjJo1j7ZcAJ6sNwjZTHmZSyt58yfY3/W4xe23TjwAg+Bhet7xB60XD81clg==';
const _other = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEOzxwOdgqqAlsFqItc4640UB64m3us04fbYo5vO1ygaYF3//iA0lYuCajv95PZINsjcZ7a5FuPE0RXljazi3a1Q==';
const _sig = 'MEUCIQCLByXKD1Ky+WjZewQD+IxEvV8NP7WPwRgE2MgXAxOdHgIgdpbqnD/E5LH4aWDT6EombrSLFIY0BUmcP6/r7crI64U=';
const _msg = 'YWJjMTIzICBRdWljay1TZW5kLTEuMi4wLWxpbnV4LXg4Ni02NC5BcHBJbWFnZQo=';

void main() {
  final message = base64.decode(_msg);
  final signature = base64.decode(_sig);

  test('accepts an OpenSSL signature from the configured key', () {
    expect(verifyUpdateSignature(message: message, signature: signature, publicKeyBase64: _pub), isTrue);
  });

  test('rejects a tampered checksum list', () {
    final tampered = Uint8List.fromList(message)..[0] ^= 1;
    expect(verifyUpdateSignature(message: tampered, signature: signature, publicKeyBase64: _pub), isFalse);
  });

  test('rejects a signature from another key', () {
    expect(verifyUpdateSignature(message: message, signature: signature, publicKeyBase64: _other), isFalse);
  });

  test('rejects missing or malformed keys and signatures', () {
    expect(verifyUpdateSignature(message: message, signature: signature, publicKeyBase64: ''), isFalse);
    expect(verifyUpdateSignature(message: message, signature: Uint8List(8), publicKeyBase64: _pub), isFalse);
    expect(parseP256PublicKey('AAAA'), isNull);
  });

  test('parses sha256sum output and matches release asset names', () {
    final sums = parseChecksums('${'a' * 64}  Quick-Send-v1.2.0-android.apk\n${'B' * 64} *Quick-Send-1.2.0-linux-x86-64.AppImage\nnoise\n');
    expect(sums['Quick-Send-v1.2.0-android.apk'], 'a' * 64);
    expect(sums['Quick-Send-1.2.0-linux-x86-64.AppImage'], 'b' * 64);
    expect(isLinuxAppImageAsset('Quick-Send-1.2.0-linux-x86-64.AppImage'), isTrue);
    expect(isLinuxAppImageAsset('Quick_Send-1.2.0-x86_64.AppImage'), isTrue);
    expect(isLinuxAppImageAsset('Quick-Send-1.2.0-linux-arm-64.AppImage'), isFalse);
    expect(isLinuxAppImageAsset('evil.AppImage'), isFalse);
  });
}
