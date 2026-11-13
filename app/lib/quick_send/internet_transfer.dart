// Quick Send: transfers between devices on different networks (desktop side).
//
// The transfer itself is done by the bundled `qs-internet` helper
// (packages/qs_internet, iroh): QUIC with hole punching, an encrypted relay as
// fallback, BLAKE3 verification and resumable downloads. This file starts the
// helper and turns its JSON-lines output into [QsInternetEvent]s. The local
// network (LocalSend protocol) code is not involved.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _logger = Logger('QsInternet');

/// One event from the helper: `type` plus the remaining fields.
class QsInternetEvent {
  final String type;
  final Map<String, dynamic> data;

  const QsInternetEvent(this.type, this.data);
}

/// A running send or receive. [events] ends when the helper exits.
class QsInternetTransfer {
  final Process _process;
  final Stream<QsInternetEvent> events;

  QsInternetTransfer._(this._process, this.events);

  /// Stops sharing / cancels the download (the helper exits when its stdin closes).
  Future<void> stop() async {
    try {
      _process.stdin.writeln('stop');
      await _process.stdin.close();
    } catch (_) {}
    unawaited(Future<void>.delayed(const Duration(seconds: 5), () => _process.kill()));
  }
}

class QsInternet {
  /// The helper next to the app executable (bundle root or lib/).
  static File? get helper {
    final dir = File(Platform.resolvedExecutable).parent.path;
    for (final candidate in ['$dir/qs-internet', '$dir/lib/qs-internet']) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    return null;
  }

  static bool get available => (Platform.isLinux || Platform.isWindows || Platform.isMacOS) && helper != null;

  static Future<Directory> _dataDir(String name) async {
    final base = await getApplicationCacheDirectory();
    return Directory('${base.path}/internet/$name');
  }

  static Future<QsInternetTransfer> _start(List<String> args) async {
    final process = await Process.start(helper!.path, args);
    final controller = StreamController<QsInternetEvent>();
    process.stderr.transform(utf8.decoder).listen((line) => _logger.fine(line.trim()));
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              controller.add(QsInternetEvent(json['type'] as String? ?? '', json));
            } catch (_) {
              _logger.warning('Unexpected helper output: $line');
            }
          },
          onDone: () async {
            final code = await process.exitCode;
            if (code != 0 && code != -15 && code != -9) _logger.info('qs-internet exited with $code');
            await controller.close();
          },
        );
    return QsInternetTransfer._(process, controller.stream);
  }

  /// Shares [paths]; emits `ticket`, `peerConnected`, `sent`, `error`.
  static Future<QsInternetTransfer> send(List<String> paths) async {
    final dir = await _dataDir('send-${DateTime.now().microsecondsSinceEpoch}');
    return _start(['send', '--data-dir', dir.path, ...paths]);
  }

  /// Downloads the files of [code] into [destination]; emits `connecting`, `progress`, `received`, `error`.
  /// The store is keyed by the code, so retrying the same code resumes an interrupted download.
  static Future<QsInternetTransfer> receive(String code, String destination) async {
    final dir = await _dataDir('recv-${code.trim().hashCode.toRadixString(16)}');
    return _start(['receive', '--data-dir', dir.path, '--dest', destination, code.trim()]);
  }
}
