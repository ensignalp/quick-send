// Quick Send: asks once (Linux, first start) whether the app should start at
// login in the tray. Without it nothing receives files after a reboot until
// the app is opened, including trusted devices that are accepted automatically.

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/native/autostart_helper.dart';

Future<void> showAutoStartOffer(BuildContext context) async {
  final p = QsPalette(context);
  final s = t.qsSettings;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: p.border, width: 0.8),
      ),
      title: Text(s.autostartOfferTitle),
      content: Text(s.autostartOfferBody, style: TextStyle(color: p.sub, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.autostartOfferNo)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.autostartOfferYes)),
      ],
    ),
  );
  if (yes == true) {
    await enableAutoStart(startHidden: true);
  }
}
