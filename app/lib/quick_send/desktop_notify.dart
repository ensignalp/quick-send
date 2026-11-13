// Quick Send: desktop notifications on Linux through the freedesktop
// Notifications D-Bus service (gdbus ships with GLib, so no extra dependency).
// Used for results the user would otherwise miss while the window is hidden.

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

final _logger = Logger('QsNotify');

/// GVariant text for a string (JSON string escapes are valid GVariant escapes).
String _gstr(String value) => jsonEncode(value);

Future<void> qsDesktopNotify(String title, String body) async {
  if (!Platform.isLinux) return;
  try {
    final result = await Process.run('gdbus', [
      'call',
      '--session',
      '--dest',
      'org.freedesktop.Notifications',
      '--object-path',
      '/org/freedesktop/Notifications',
      '--method',
      'org.freedesktop.Notifications.Notify',
      _gstr('Quick Send'),
      'uint32 0', // typed literals: a bare "-1" would be parsed as a gdbus option
      _gstr('com.ensignsoft.quicksend'),
      _gstr(title),
      _gstr(body),
      '@as []',
      '{"desktop-entry": <"com.ensignsoft.quicksend">}',
      'int32 -1',
    ]);
    if (result.exitCode != 0) _logger.warning('Notification failed: ${result.stderr}');
  } catch (e) {
    _logger.warning('Notification failed: $e');
  }
}
