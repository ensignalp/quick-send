import 'package:flutter/material.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// Quick Send brand mark (support/brand/quick-send-icon.svg), optionally with the app name.
class QuickSendLogo extends StatelessWidget {
  final bool withText;
  final double size;

  const QuickSendLogo({required this.withText, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final mark = Assets.img.logo512.image(width: size, height: size, filterQuality: FilterQuality.medium);

    if (!withText) return mark;

    return Column(
      children: [
        mark,
        const SizedBox(height: 12),
        Text(
          t.appName,
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
