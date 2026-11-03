import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

/// Quick Send placeholder mark. Replace this Material icon with final brand art later.
class QuickSendLogo extends StatelessWidget {
  final bool withText;

  const QuickSendLogo({required this.withText});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final mark = Icon(Icons.send_rounded, size: 150, color: color);

    if (!withText) return mark;

    return Column(
      children: [
        mark,
        Text(
          t.appName,
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
