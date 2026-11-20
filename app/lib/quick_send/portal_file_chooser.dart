// Quick Send (Linux): the desktop's own file chooser through xdg-desktop-portal
// (org.freedesktop.portal.FileChooser). On GNOME this is the Nautilus-style
// chooser of xdg-desktop-portal-gnome, on KDE the Plasma one.
//
// Returns null when the portal is not available or fails, so callers fall back
// to the previous chooser silently; returns an empty list when the user cancels.
// The last folder is remembered and offered the next time.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _logger = Logger('PortalFileChooser');

const _lastFolderKey = 'qs_last_picker_folder';

/// A filter shown in the chooser: a name and MIME types (e.g. 'image/*').
class PortalFilter {
  final String name;
  final List<String> mimeTypes;

  const PortalFilter(this.name, this.mimeTypes);
}

class PortalFileChooser {
  static Future<String?> _lastFolder() async {
    try {
      final folder = (await SharedPreferences.getInstance()).getString(_lastFolderKey);
      return folder != null && Directory(folder).existsSync() ? folder : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _rememberFolder(String folder) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_lastFolderKey, folder);
    } catch (_) {}
  }

  /// Picks files (or one folder with [directory]). Paths, [] on cancel, null when the portal is unavailable.
  static Future<List<String>?> open({
    required String title,
    bool multiple = true,
    bool directory = false,
    List<PortalFilter> filters = const [],
  }) async {
    if (!Platform.isLinux) return null;
    final client = DBusClient.session();
    StreamSubscription<DBusSignal>? subscription;
    try {
      final portal = DBusRemoteObject(client, name: 'org.freedesktop.portal.Desktop', path: DBusObjectPath('/org/freedesktop/portal/desktop'));
      final version = await portal.getProperty('org.freedesktop.portal.FileChooser', 'version', signature: DBusSignature('u'));
      if (directory && (version as DBusUint32).value < 3) return null; // folder selection needs version 3

      // The reply arrives as a Response signal on a request object whose path is derived from our
      // unique bus name and a token; subscribe before calling so it cannot be missed.
      await client.ping('org.freedesktop.DBus');
      final sender = client.uniqueName.substring(1).replaceAll('.', '_');
      final token = 'quicksend${Random().nextInt(1 << 30)}';
      final requestPath = DBusObjectPath('/org/freedesktop/portal/desktop/request/$sender/$token');
      final response = Completer<DBusSignal>();
      subscription =
          DBusSignalStream(
            client,
            interface: 'org.freedesktop.portal.Request',
            name: 'Response',
            path: requestPath,
          ).listen((signal) {
            if (!response.isCompleted) response.complete(signal);
          });

      final folder = await _lastFolder();
      final options = <String, DBusValue>{
        'handle_token': DBusString(token),
        'modal': const DBusBoolean(true),
        'multiple': DBusBoolean(multiple && !directory),
        if (directory) 'directory': const DBusBoolean(true),
        if (folder != null) 'current_folder': DBusArray.byte([...utf8.encode(folder), 0]),
        if (filters.isNotEmpty)
          'filters': DBusArray(DBusSignature('(sa(us))'), [
            for (final f in filters)
              DBusStruct([
                DBusString(f.name),
                DBusArray(DBusSignature('(us)'), [
                  for (final mime in f.mimeTypes) DBusStruct([const DBusUint32(1), DBusString(mime)]),
                ]),
              ]),
          ]),
      };
      await portal.callMethod(
        'org.freedesktop.portal.FileChooser',
        'OpenFile',
        [const DBusString(''), DBusString(title), DBusDict.stringVariant(options)],
        replySignature: DBusSignature('o'),
      );

      final signal = await response.future;
      final code = (signal.values[0] as DBusUint32).value;
      if (code == 1) return const []; // cancelled
      if (code != 0) return null;
      final results = (signal.values[1] as DBusDict).mapStringVariant();
      final uris = (results['uris'] as DBusArray?)?.mapString().toList() ?? const <String>[];
      final paths = uris.map((u) => Uri.parse(u)).where((u) => u.scheme == 'file').map((u) => u.toFilePath()).toList();
      if (paths.isNotEmpty) {
        await _rememberFolder(directory ? paths.first : File(paths.first).parent.path);
      }
      return paths;
    } catch (e) {
      _logger.info('File chooser portal not available, using the built-in chooser: $e');
      return null;
    } finally {
      await subscription?.cancel();
      await client.close();
    }
  }
}
