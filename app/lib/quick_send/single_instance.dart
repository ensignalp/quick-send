// Quick Send: single instance on Linux, independent of the receive server.
//
// LocalSend hands a second launch over through the HTTP server's internal
// `show` endpoint. Quick Send stops that server while sharing is off (see
// trusted_only.dart), so in that mode a second launch (desktop entry, "Send
// with Quick Send", the AppImage) would start a second app instead. The first
// instance therefore also listens on a per-user Unix socket; a later launch
// sends its arguments there and exits.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

final _logger = Logger('QsSingleInstance');

class QsSingleInstance {
  static ServerSocket? _server;

  static File _socketFile() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final dir = runtimeDir != null && runtimeDir.isNotEmpty ? runtimeDir : Directory.systemTemp.path;
    final user = Platform.environment['USER'] ?? 'user';
    return File('$dir/com.ensignsoft.quicksend-$user.sock');
  }

  static InternetAddress _address() => InternetAddress(_socketFile().path, type: InternetAddressType.unix);

  /// Sends [args] to a running instance. Returns `true` when it took them over.
  static Future<bool> handOver(List<String> args) async {
    if (!Platform.isLinux || !_socketFile().existsSync()) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(_address(), 0, timeout: const Duration(milliseconds: 300));
      socket.write('${jsonEncode({'args': args})}\n');
      await socket.flush();
      final reply = await socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 2));
      return reply == 'ok';
    } catch (e) {
      _logger.fine('No running instance on the local socket: $e');
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Listens for later launches; [onLaunch] receives their arguments.
  static Future<void> listen(void Function(List<String> args) onLaunch) async {
    if (!Platform.isLinux || _server != null) return;
    final file = _socketFile();
    try {
      // A socket file without a listener is left over from a crash.
      if (file.existsSync()) file.deleteSync();
      _server = await ServerSocket.bind(_address(), 0);
      _server!.listen((client) => unawaited(_serve(client, onLaunch)));
    } catch (e) {
      _logger.warning('Could not listen for second instances: $e');
    }
  }

  static Future<void> _serve(Socket client, void Function(List<String> args) onLaunch) async {
    try {
      final line = await client.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 2));
      final args = ((jsonDecode(line) as Map<String, dynamic>)['args'] as List).cast<String>();
      onLaunch(args);
      client.write('ok\n');
      await client.flush();
    } catch (e) {
      _logger.warning('Invalid message from a second instance: $e');
    } finally {
      client.destroy();
    }
  }
}
