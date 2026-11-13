import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/quick_send/trusted_only.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayWatcher extends StatefulWidget {
  final Widget child;

  const TrayWatcher({required this.child, super.key});

  @override
  State<TrayWatcher> createState() => _TrayWatcherState();
}

class _TrayWatcherState extends State<TrayWatcher> with TrayListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() async {
    if (checkPlatform([TargetPlatform.macOS])) {
      await trayManager.popUpContextMenu();
    } else {
      await showFromTray();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final entry = TrayEntry.values.firstWhereOrNull((e) => e.name == menuItem.key);
    final ref = RefenaScope.defaultRef;
    Future<void> setMode(QsVisibility mode) async {
      await ref.notifier(shareModeProvider).set(mode);
      await refreshTrayMenu();
    }

    switch (entry) {
      case TrayEntry.open:
        await showFromTray();
      case TrayEntry.sendFiles:
      case TrayEntry.clipboard:
        await showFromTray();
        ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
        final context = Routerino.context;
        if (context.mounted) {
          await ref.global.dispatchAsync(
            PickFileAction(option: entry == TrayEntry.clipboard ? FilePickerOption.clipboard : FilePickerOption.file, context: context),
          );
        }
      case TrayEntry.modeEveryone:
        await setMode(QsVisibility.everyone);
      case TrayEntry.modeTrusted:
        await setMode(QsVisibility.trusted);
      case TrayEntry.modeOff:
        await setMode(QsVisibility.hidden);
      case TrayEntry.settings:
        await showFromTray();
        ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.settings));
      case TrayEntry.close:
        exit(0);
      case null:
    }
  }
}
