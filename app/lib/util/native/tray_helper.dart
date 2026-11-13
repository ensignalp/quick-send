import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/quick_send/trusted_only.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:window_manager/window_manager.dart';

final _logger = Logger('TrayHelper');

enum TrayEntry {
  open,
  sendFiles,
  clipboard,
  modeEveryone,
  modeTrusted,
  modeOff,
  settings,
  close,
}

Future<void> initTray() async {
  if (!checkPlatformHasTray()) {
    return;
  }
  try {
    if (checkPlatform([TargetPlatform.windows])) {
      await tm.trayManager.setIcon(Assets.img.logo);
    } else if (checkPlatform([TargetPlatform.macOS])) {
      // The menu bar icon will created in AppDelegate.swift
      return;
    } else if (checkPlatform([TargetPlatform.linux])) {
      String icon;
      if (await File('/.flatpak-info').exists()) {
        // Icon for Flatpak, which must exist in /app/share/icons/hicolor/*x*/apps.
        icon = 'com.ensignsoft.quicksend-tray';
      } else {
        icon = Assets.img.logo32White.path;
      }
      _logger.info('Using "$icon" as path of system tray icon');
      await tm.trayManager.setIcon(icon);
    } else {
      await tm.trayManager.setIcon(Assets.img.logo32.path);
    }

    await refreshTrayMenu();
    // No Linux implementation for setToolTip available as of tray_manager 0.2.2
    // https://pub.dev/packages/tray_manager#api
    if (!checkPlatform([TargetPlatform.linux])) {
      await tm.trayManager.setToolTip(t.appName);
    }
  } catch (e) {
    _logger.warning('Failed to init tray', e);
  }
}

/// Rebuilds the tray menu (the share mode checkmarks change at runtime).
/// On Linux the tray is an AppIndicator, so any click opens this menu.
Future<void> refreshTrayMenu() async {
  if (!checkPlatformHasTray() || checkPlatform([TargetPlatform.macOS])) return;
  String mode;
  try {
    mode = RefenaScope.defaultRef.read(persistenceProvider).getQsShareMode();
  } catch (_) {
    mode = 'trusted';
  }
  final items = [
    tm.MenuItem(key: TrayEntry.open.name, label: t.qsTray.open),
    tm.MenuItem.separator(),
    tm.MenuItem(key: TrayEntry.sendFiles.name, label: t.qsTray.sendFiles),
    tm.MenuItem(key: TrayEntry.clipboard.name, label: t.qsTray.clipboard),
    tm.MenuItem.separator(),
    tm.MenuItem.submenu(
      label: t.qsTray.receive,
      submenu: tm.Menu(
        items: [
          tm.MenuItem.checkbox(key: TrayEntry.modeEveryone.name, label: t.qsSettings.modeEveryone, checked: mode == 'everyone'),
          tm.MenuItem.checkbox(key: TrayEntry.modeTrusted.name, label: t.qsSettings.modeTrusted, checked: mode == 'trusted'),
          tm.MenuItem.checkbox(key: TrayEntry.modeOff.name, label: t.qsSettings.modeOff, checked: mode == 'off'),
        ],
      ),
    ),
    tm.MenuItem(key: TrayEntry.settings.name, label: t.qsTray.settings),
    tm.MenuItem.separator(),
    tm.MenuItem(key: TrayEntry.close.name, label: t.qsTray.quit),
  ];
  try {
    await tm.trayManager.setContextMenu(tm.Menu(items: items));
  } catch (e) {
    _logger.warning('Failed to set tray menu', e);
  }
}

Future<void> hideToTray() async {
  await windowManager.hide();
  if (checkPlatform([TargetPlatform.macOS])) {
    // This will crash on Windows
    // https://github.com/localsend/localsend/issues/32
    await windowManager.setSkipTaskbar(true);
  }

  unawaited(QsReceiveScreen.update(window: false));

  // Disable animations
  try {
    RefenaScope.defaultRef.notifier(sleepProvider).setState((_) => true);
  } catch (e) {
    _logger.warning('Failed to update sleep state (Refena not yet initialized)', e);
  }
}

Future<void> showFromTray() async {
  await windowManager.show();
  unawaited(QsReceiveScreen.update(window: true));
  await windowManager.focus();
  if (checkPlatform([TargetPlatform.macOS])) {
    // This will crash on Windows
    // https://github.com/localsend/localsend/issues/32
    await windowManager.setSkipTaskbar(false);
  }

  // Enable animations
  try {
    RefenaScope.defaultRef.notifier(sleepProvider).setState((_) => false);
  } catch (e) {
    _logger.warning('Failed to update sleep state (Refena not yet initialized)', e);
  }
}

Future<void> destroyTray() async {
  if (!checkPlatform([TargetPlatform.linux])) {
    await tm.trayManager.destroy();
  }
}
