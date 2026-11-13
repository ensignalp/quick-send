import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/macos_channel.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:win32_registry/win32_registry.dart';

const startHiddenFlag = '--hidden';

final _logger = Logger('AutoStartHelper');

/// Quick Send: the command that starts this app. Inside an AppImage, [Platform.resolvedExecutable] is a
/// temporary mount (/tmp/.mount_*) that is gone after a reboot, so the AppImage file itself is used.
/// Quoted for the desktop entry `Exec` key.
String _linuxExecQuoted() {
  final exe = Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;
  final escaped = exe.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('`', r'\`').replaceAll(r'$', r'\$');
  return '"${escaped.replaceAll(r'\', r'\\')}"';
}

Future<bool> enableAutoStart({required bool startHidden}) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        String contents =
            '''
[Desktop Entry]
Type=Application
Name=${packageInfo.appName}
Comment=${packageInfo.appName} startup script
Exec=${_linuxExecQuoted()}${startHidden ? ' $startHiddenFlag' : ''}
StartupNotify=false
Terminal=false
''';
        final file = File(_getLinuxFilePath(packageInfo.packageName));
        if (!file.parent.existsSync()) {
          file.parent.createSync(recursive: true);
        }
        file.writeAsStringSync(contents);
        return true;
      case TargetPlatform.macOS:
        await setLaunchAtLogin(true);
        await setLaunchAtLoginMinimized(startHidden);
        return true;
      case TargetPlatform.windows:
        _getWindowsRegistryKey().createValue(
          RegistryValue.string(
            _windowsRegistryKeyValue,
            '"${Platform.resolvedExecutable}"${startHidden ? ' $startHiddenFlag' : ''}',
          ),
        );
        return true;
      default:
        return false;
    }
  } catch (e) {
    _logger.warning('Could enable auto start', e);
    return false;
  }
}

Future<bool> disableAutoStart() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        File(_getLinuxFilePath(packageInfo.packageName)).deleteSync();
        break;
      case TargetPlatform.macOS:
        await setLaunchAtLogin(false);
        break;
      case TargetPlatform.windows:
        _getWindowsRegistryKey().deleteValue(_windowsRegistryKeyValue);
        break;
      default:
        break;
    }
    return true;
  } catch (e) {
    _logger.warning('Could disable auto start', e);
    return false;
  }
}

Future<bool> isAutoStartEnabled() async {
  final packageInfo = await PackageInfo.fromPlatform();
  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
      return File(_getLinuxFilePath(packageInfo.packageName)).existsSync();
    case TargetPlatform.macOS:
      return await getLaunchAtLogin();
    case TargetPlatform.windows:
      return _getWindowsRegistryKey().getStringValue(_windowsRegistryKeyValue)?.contains(Platform.resolvedExecutable) ?? false;
    default:
      return false;
  }
}

Future<bool> isAutoStartHidden() async {
  final packageInfo = await PackageInfo.fromPlatform();
  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
      final file = File(_getLinuxFilePath(packageInfo.packageName));
      if (!file.existsSync()) {
        return false;
      }
      return file.readAsStringSync().contains(startHiddenFlag);
    case TargetPlatform.macOS:
      return await getLaunchAtLoginMinimized();
    case TargetPlatform.windows:
      return _getWindowsRegistryKey().getStringValue(_windowsRegistryKeyValue)?.contains(startHiddenFlag) ?? false;
    default:
      return false;
  }
}

const _windowsRegistryKeyValue = 'Quick Send';

RegistryKey _getWindowsRegistryKey() {
  return Registry.openPath(
    RegistryHive.currentUser,
    path: r'Software\Microsoft\Windows\CurrentVersion\Run',
    desiredAccessRights: AccessRights.allAccess,
  );
}

String _getLinuxFilePath(String appName) {
  return '${Platform.environment['HOME']}/.config/autostart/$appName.desktop';
}

/// Quick Send: rewrites an enabled Linux autostart entry when it points at a stale executable
/// (an earlier AppImage mount under /tmp, or an AppImage that has since moved).
Future<void> refreshLinuxAutoStartPath() async {
  if (defaultTargetPlatform != TargetPlatform.linux || !await isAutoStartEnabled()) return;
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final contents = File(_getLinuxFilePath(packageInfo.packageName)).readAsStringSync();
    if (!contents.contains('Exec=${_linuxExecQuoted()}')) {
      await enableAutoStart(startHidden: contents.contains(startHiddenFlag));
      _logger.info('Updated the autostart entry to the current executable');
    }
  } catch (e) {
    _logger.warning('Could not refresh the autostart entry: $e');
  }
}
