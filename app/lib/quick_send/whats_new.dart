// Quick Send: "What's new" after an update. Shown once, on the first start of
// a version that has an entry here (never on a fresh install).

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/quick_send/qs_style.dart';

/// Versions with a "What's new" page and their items (icon + text).
List<(IconData, String)>? qsWhatsNewItems(String version) {
  final base = version.split('+').first.split('-').first;
  final s = t.qsWhatsNew;
  return switch (base) {
    '1.1.0' => [
      (Icons.public, s.internet),
      (Icons.qr_code_2, s.qrPage),
      (Icons.ads_click, s.manual),
      (Icons.verified_user_outlined, s.trusted),
      (Icons.history, s.history),
      (Icons.account_circle_outlined, s.avatar),
      (Icons.folder_open, s.chooser),
      (Icons.menu_open, s.contextMenu),
      (Icons.web_asset, s.window),
    ],
    _ => null,
  };
}

class QsWhatsNewPage extends StatelessWidget {
  final String version;
  final List<(IconData, String)> items;

  const QsWhatsNewPage({required this.version, required this.items, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return QsPage(
      title: t.qsWhatsNew.title(version: version),
      children: [
        QsGroup(
          children: [
            for (final (icon, text) in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: p.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: p.text)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.general.done)),
        ),
      ],
    );
  }
}
