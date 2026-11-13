// Quick Send: background updates for the Linux AppImage from GitHub Releases.
//
// Flow (only when the build is configured, see docs/RELEASE.md):
//  1. GET https://api.github.com/repos/<repo>/releases/latest (HTTPS only).
//  2. If the tag is newer, download SHA256SUMS.txt, SHA256SUMS.txt.sig and the
//     AppImage asset. Every URL must be https and point at this repository's
//     release downloads; redirects must stay on https.
//  3. Verify the ECDSA P-256 / SHA-256 signature of SHA256SUMS.txt with the
//     public key compiled into this build (QS_UPDATE_PUBLIC_KEY), then the
//     AppImage's SHA-256 against the signed list. Anything that does not verify
//     is deleted and never installed.
//  4. Replace the running AppImage file atomically (rename in the same
//     directory). The running instance keeps its mounted copy; the new version
//     starts with the next launch.
// Builds without a repository or public key never download anything.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:localsend_app/quick_send/update_checker.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

final _logger = Logger('QsAutoUpdate');

/// Base64 of the SubjectPublicKeyInfo (DER) of the release signing key (P-256).
const quickSendUpdatePublicKey = String.fromEnvironment('QS_UPDATE_PUBLIC_KEY');

const _checkInterval = Duration(hours: 12);

/// Outcome of one background update run.
sealed class AutoUpdateResult {
  const AutoUpdateResult();
}

class AutoUpdateInstalled extends AutoUpdateResult {
  final String version;
  const AutoUpdateInstalled(this.version);
}

class AutoUpdateNothing extends AutoUpdateResult {
  const AutoUpdateNothing();
}

class AutoUpdateRejected extends AutoUpdateResult {
  final String reason;
  const AutoUpdateRejected(this.reason);
}

/* ------------------------------------------------------------ verification */

const _p256SpkiPrefix = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, //
  0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
];

/// Parses a base64 P-256 SubjectPublicKeyInfo. Returns null for anything else.
ECPublicKey? parseP256PublicKey(String base64Spki) {
  try {
    final der = base64.decode(base64Spki.trim());
    if (der.length != _p256SpkiPrefix.length + 65) return null;
    for (var i = 0; i < _p256SpkiPrefix.length; i++) {
      if (der[i] != _p256SpkiPrefix[i]) return null;
    }
    final domain = ECCurve_secp256r1();
    final point = domain.curve.decodePoint(der.sublist(_p256SpkiPrefix.length));
    if (point == null) return null;
    return ECPublicKey(point, domain);
  } catch (_) {
    return null;
  }
}

/// Parses a DER ECDSA signature (SEQUENCE { INTEGER r, INTEGER s }).
ECSignature? _parseDerSignature(Uint8List der) {
  try {
    var i = 0;
    int readLength() {
      final first = der[i++];
      if (first < 0x80) return first;
      final bytes = first & 0x7f;
      if (bytes > 2) throw const FormatException('length');
      var len = 0;
      for (var k = 0; k < bytes; k++) {
        len = (len << 8) | der[i++];
      }
      return len;
    }

    BigInt readInt() {
      if (der[i++] != 0x02) throw const FormatException('int');
      final len = readLength();
      final bytes = der.sublist(i, i + len);
      i += len;
      var v = BigInt.zero;
      for (final b in bytes) {
        v = (v << 8) | BigInt.from(b);
      }
      return v;
    }

    if (der[i++] != 0x30) return null;
    final seqLen = readLength();
    if (i + seqLen != der.length) return null;
    final r = readInt();
    final s = readInt();
    if (i != der.length) return null;
    return ECSignature(r, s);
  } catch (_) {
    return null;
  }
}

/// True when [signature] (DER) is a valid ECDSA P-256/SHA-256 signature of [message] by [publicKeyBase64].
bool verifyUpdateSignature({required Uint8List message, required Uint8List signature, required String publicKeyBase64}) {
  final key = parseP256PublicKey(publicKeyBase64);
  final sig = _parseDerSignature(signature);
  if (key == null || sig == null) return false;
  try {
    final signer = Signer('SHA-256/ECDSA')..init(false, PublicKeyParameter<ECPublicKey>(key));
    return signer.verifySignature(message, sig);
  } catch (_) {
    return false;
  }
}

/// Reads `sha256sum` output (hex digest, two spaces, file name) into a map of file name to lowercase hex.
Map<String, String> parseChecksums(String text) {
  final result = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
    if (m != null) result[m.group(2)!.trim()] = m.group(1)!.toLowerCase();
  }
  return result;
}

/// The AppImage asset of a release (CI: Quick-Send-X-linux-x86-64.AppImage, local: Quick_Send-X-x86_64.AppImage).
bool isLinuxAppImageAsset(String name) => RegExp(r'^quick[-_]send.*x86[-_]64\.appimage$', caseSensitive: false).hasMatch(name);

/* ------------------------------------------------------------------ runner */

class QsAutoUpdater {
  static Timer? _timer;
  static bool _running = false;

  /// Whether this build can update itself: Linux AppImage, repository and key configured.
  static bool get supported =>
      Platform.isLinux &&
      (Platform.environment['APPIMAGE'] ?? '').isNotEmpty &&
      quickSendReleasesRepo.isNotEmpty &&
      parseP256PublicKey(quickSendUpdatePublicKey) != null;

  /// Starts periodic checks (first one after a short delay). [enabled] is read before every run.
  static void start({
    required String currentVersion,
    required bool Function() enabled,
    required void Function(String version) onInstalled,
  }) {
    if (!supported || _timer != null) return;
    Future<void> run() async {
      if (!enabled()) return;
      final result = await runOnce(currentVersion: currentVersion);
      if (result is AutoUpdateInstalled) {
        _timer?.cancel(); // one update per session; the next launch runs the new version
        onInstalled(result.version);
      }
    }

    _timer = Timer.periodic(_checkInterval, (_) => unawaited(run()));
    unawaited(Future<void>.delayed(const Duration(seconds: 45), run));
  }

  static Future<AutoUpdateResult> runOnce({required String currentVersion}) async {
    if (_running) return const AutoUpdateNothing();
    _running = true;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'QuickSend-Updater';
    File? temp;
    try {
      final repo = quickSendReleasesRepo;
      final release = await _getJson(client, Uri.https('api.github.com', '/repos/$repo/releases/latest'));
      final tag = release['tag_name'];
      if (tag is! String || !isNewerVersion(tag, currentVersion)) return const AutoUpdateNothing();
      final version = tag.replaceFirst(RegExp('^v'), '');

      final assets = (release['assets'] as List? ?? []).whereType<Map<String, dynamic>>();
      String? urlOf(bool Function(String) match) {
        for (final a in assets) {
          final name = a['name'];
          final url = a['browser_download_url'];
          if (name is String && url is String && match(name)) return url;
        }
        return null;
      }

      final sumsUrl = urlOf((n) => n == 'SHA256SUMS.txt');
      final sigUrl = urlOf((n) => n == 'SHA256SUMS.txt.sig');
      final appUrl = urlOf(isLinuxAppImageAsset);
      if (sumsUrl == null || sigUrl == null || appUrl == null) return const AutoUpdateRejected('release has no signed checksums or AppImage');
      final allowedPrefix = 'https://github.com/$repo/releases/download/';
      for (final u in [sumsUrl, sigUrl, appUrl]) {
        if (!u.startsWith(allowedPrefix)) return AutoUpdateRejected('unexpected download URL: $u');
      }

      final sums = await _getBytes(client, Uri.parse(sumsUrl), maxBytes: 64 * 1024);
      final sig = await _getBytes(client, Uri.parse(sigUrl), maxBytes: 1024);
      if (!verifyUpdateSignature(message: sums, signature: sig, publicKeyBase64: quickSendUpdatePublicKey)) {
        return const AutoUpdateRejected('checksum signature does not verify');
      }
      final assetName = Uri.parse(appUrl).pathSegments.last;
      final expected = parseChecksums(utf8.decode(sums))[assetName];
      if (expected == null) return const AutoUpdateRejected('AppImage is not in the signed checksums');

      final target = File(Platform.environment['APPIMAGE']!);
      temp = File('${target.path}.update-$version');
      final actual = await _download(client, Uri.parse(appUrl), temp);
      if (actual != expected) return const AutoUpdateRejected('AppImage checksum mismatch');

      await Process.run('chmod', ['755', temp.path]);
      await temp.rename(target.path); // atomic within the directory; the running copy stays mounted
      temp = null;
      _logger.info('Installed Quick Send $version');
      return AutoUpdateInstalled(version);
    } catch (e) {
      _logger.warning('Update failed: $e');
      return AutoUpdateRejected('$e');
    } finally {
      if (temp != null && temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
      client.close(force: true);
      _running = false;
    }
  }

  static Future<HttpClientResponse> _open(HttpClient client, Uri uri) async {
    if (uri.scheme != 'https') throw StateError('refusing non-https URL $uri');
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, uri.host == 'api.github.com' ? 'application/vnd.github+json' : 'application/octet-stream');
    final response = await request.close().timeout(const Duration(seconds: 30));
    for (final r in response.redirects) {
      if (r.location.scheme.isNotEmpty && r.location.scheme != 'https') throw StateError('redirect left https');
    }
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: uri);
    return response;
  }

  static Future<Map<String, dynamic>> _getJson(HttpClient client, Uri uri) async {
    final bytes = await _getBytes(client, uri, maxBytes: 2 * 1024 * 1024);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) throw const FormatException('release JSON');
    return decoded;
  }

  static Future<Uint8List> _getBytes(HttpClient client, Uri uri, {required int maxBytes}) async {
    final response = await _open(client, uri);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      builder.add(chunk);
      if (builder.length > maxBytes) throw StateError('response too large');
    }
    return builder.takeBytes();
  }

  /// Streams [uri] into [file] and returns the lowercase hex SHA-256 of what was written.
  static Future<String> _download(HttpClient client, Uri uri, File file) async {
    final response = await _open(client, uri);
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digestSink);
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 120))) {
        hasher.add(chunk);
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    return digestSink.value.toString();
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}
