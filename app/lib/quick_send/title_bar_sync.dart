// Quick Send: keeps the native (GTK) title bar in the app's light/dark theme.
//
// The window controls are drawn by GTK, outside Flutter. Without this they
// follow only the desktop's colour scheme, so a light app in a dark desktop
// (or the reverse) gets a mismatched title bar. The shell (my_application.cc)
// applies the brightness to its header bar.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('org.localsend.localsend_app/platform');

class QsTitleBarSync extends StatefulWidget {
  final Widget child;

  const QsTitleBarSync({required this.child, super.key});

  @override
  State<QsTitleBarSync> createState() => _QsTitleBarSyncState();
}

class _QsTitleBarSyncState extends State<QsTitleBarSync> {
  Brightness? _sent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Platform.isLinux) return;
    final brightness = Theme.of(context).brightness;
    if (brightness == _sent) return;
    _sent = brightness;
    _channel.invokeMethod<void>('setTitleBarDark', brightness == Brightness.dark).catchError((Object _) {}).ignore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
