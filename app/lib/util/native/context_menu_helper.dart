import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _logger = Logger('ContextMenuHelper');

/// Quick Send: [label] is the localized menu entry used by the Linux file manager integrations.
Future<bool> enableContextMenu({String label = 'Send with Quick Send'}) async {
  if (defaultTargetPlatform == TargetPlatform.linux) {
    return _enableLinux(label);
  }
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final String script =
        '''
\$TargetPath = "${Platform.resolvedExecutable}"
\$ShortcutFile = "${_getWindowsFilePath(_windowsFileName)}"
\$WScriptShell = New-Object -ComObject WScript.Shell
\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutFile)
\$Shortcut.TargetPath = \$TargetPath
\$Shortcut.Save()
''';
    final result = await Process.run('powershell', ['-Command', script]);
    if (result.stderr != null && result.stderr!.isNotEmpty) {
      throw Exception('Failed to create shortcut: ${result.stderr}');
    }
    return await File(_getWindowsFilePath(_windowsFileName)).exists();
  } catch (e) {
    _logger.severe('Failed to enable context menu: $e');
    return false;
  }
}

Future<bool> disableContextMenu() async {
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        final file = File(_getWindowsFilePath(_windowsFileName));
        if (await file.exists()) {
          await file.delete();
        }
        return true;
      case TargetPlatform.linux:
        for (final file in [..._linuxFiles(), _legacyNautilusScript()]) {
          if (await file.exists()) {
            await file.delete();
          }
        }
        return true;
      default:
        return false;
    }
  } catch (e) {
    return false;
  }
}

Future<bool> isContextMenuEnabled() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return await File(_getWindowsFilePath(_windowsFileName)).exists();
    case TargetPlatform.linux:
      return await _linuxFiles().first.exists();
    default:
      return false;
  }
}

const _windowsFileName = 'Quick Send';

String _getWindowsFilePath(String appName) {
  final appData = Platform.environment['APPDATA'];
  return '$appData/Microsoft/Windows/SendTo/$appName.lnk';
}

// ---------------------------------------------------------------------------
// Quick Send: Linux file manager integration ("Send with Quick Send").
//
// - Nautilus (GNOME Files): a nautilus-python extension adds a top-level
//   context menu item. (Older builds also installed a Nautilus script under
//   Scripts > Quick Send; it is removed when the integration is (re)installed.)
// - Dolphin (KDE): a KIO service menu.
// All of them start the app with the selected paths; an already running
// instance receives them and adds them to the selection.

String _linuxDataHome() {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return xdg;
  }
  return '${Platform.environment['HOME']}/.local/share';
}

/// The first file is the primary marker used by [isContextMenuEnabled].
List<File> _linuxFiles() {
  final data = _linuxDataHome();
  return [
    File('$data/nautilus-python/extensions/quick_send_nautilus.py'),
    File('$data/kio/servicemenus/quick-send.desktop'),
  ];
}

/// The "Scripts > Quick Send" entry installed by earlier builds.
File _legacyNautilusScript() => File('${_linuxDataHome()}/nautilus/scripts/Quick Send');

/// Removes the legacy Nautilus script, if an earlier build installed it.
Future<void> removeLegacyContextMenuScript() async {
  if (defaultTargetPlatform != TargetPlatform.linux) return;
  try {
    final script = _legacyNautilusScript();
    if (await script.exists()) await script.delete();
  } catch (e) {
    _logger.warning('Failed to remove the legacy Nautilus script: $e');
  }
}

/// The command that starts this app (the AppImage when running from one).
String _linuxExecutable() => Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;

/// Quotes an argument for a desktop entry `Exec` key (double quotes; backslashes are escaped twice by the spec).
String _desktopExecQuote(String value) {
  final quoted = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('`', '\\`').replaceAll(r'$', r'\$');
  return '"${quoted.replaceAll('\\', '\\\\')}"';
}

String _pythonString(String value) => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

Future<bool> _enableLinux(String label) async {
  try {
    final exe = _linuxExecutable();
    final files = _linuxFiles();

    await removeLegacyContextMenuScript();

    final extension = files[0];
    await extension.parent.create(recursive: true);
    await extension.writeAsString('''# Installed by Quick Send (Settings > Send with Quick Send).
# Adds "${label.replaceAll('\n', ' ')}" to the Nautilus context menu (requires nautilus-python).
import subprocess

from gi.repository import GObject, Nautilus

EXECUTABLE = ${_pythonString(exe)}
LABEL = ${_pythonString(label)}


class QuickSendMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def _send(self, _menu, files):
        paths = [f.get_location().get_path() for f in files]
        paths = [p for p in paths if p]
        if paths:
            subprocess.Popen([EXECUTABLE, *paths], start_new_session=True)

    def get_file_items(self, *args):
        files = args[-1]
        if not files or any(f.get_uri_scheme() != "file" for f in files):
            return []
        item = Nautilus.MenuItem(name="QuickSend::send", label=LABEL, icon="com.ensignsoft.quicksend")
        item.connect("activate", self._send, files)
        return [item]
''');

    final serviceMenu = files[1];
    await serviceMenu.parent.create(recursive: true);
    await serviceMenu.writeAsString('''[Desktop Entry]
Type=Service
MimeType=all/allfiles;inode/directory;
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
Actions=quickSend

[Desktop Action quickSend]
Name=$label
Icon=com.ensignsoft.quicksend
Exec=${_desktopExecQuote(exe)} %F
''');

    // KDE 6 service menus must be executable.
    await Process.run('chmod', ['+x', serviceMenu.path]);
    return true;
  } catch (e) {
    _logger.severe('Failed to enable Linux context menu: $e');
    return false;
  }
}
