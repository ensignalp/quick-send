// Quick Send desktop design system, kept identical to the Android app
// (mobile/src/ui.tsx): colours, the purple toggle switch, bordered setting
// groups, the receive "ripple" and the Receive/Send pill toggle.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours shared with the Android app. Dark: background #111111, cards #191919.
class QsPalette {
  final bool dark;
  final Color bg;
  final Color card;
  final Color border;
  final Color text;
  final Color sub;
  final Color faint;
  final Color chip;
  final Color accent;
  final Color accentSoft;
  final Color danger;
  final Color nav;
  final Color navActive;
  final Color glow;

  const QsPalette._({
    required this.dark,
    required this.bg,
    required this.card,
    required this.border,
    required this.text,
    required this.sub,
    required this.faint,
    required this.chip,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.nav,
    required this.navActive,
    required this.glow,
  });

  static const light = QsPalette._(
    dark: false,
    bg: Color(0xFFF2F3F7),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE1E3EA),
    text: Color(0xFF17181C),
    sub: Color(0xFF6E7079),
    faint: Color(0xFFE3E4EA),
    chip: Color(0xFFECEDF2),
    accent: Color(0xFF3478F6),
    accentSoft: Color(0xFFE4EDFF),
    danger: Color(0xFFE5484D),
    nav: Color(0xFFFFFFFF),
    navActive: Color(0xFFE7E9EF),
    glow: Color(0xFFC9D9F7),
  );

  static const darkPalette = QsPalette._(
    dark: true,
    bg: Color(0xFF111111),
    card: Color(0xFF191919),
    border: Color(0xFF2A2A2A),
    text: Color(0xFFF2F2F2),
    sub: Color(0xFFA3A3A3),
    faint: Color(0xFF262626),
    chip: Color(0xFF222222),
    accent: Color(0xFF3B82F6),
    accentSoft: Color(0xFF1D2A45),
    danger: Color(0xFFFF6B6B),
    nav: Color(0xFF2A2C31),
    navActive: Color(0xFF45484F),
    glow: Color(0xFF3C4550),
  );

  factory QsPalette(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? darkPalette : light;
}

/* ----------------------------------------------------------------- switch */

const _switchOff = Color.fromRGBO(82, 82, 82, 1);
const _switchOn = Color.fromRGBO(148, 118, 255, 1);

/// 50×30 toggle: a white ring on grey when off; slides right, fills white on purple when on (0.2 s).
class QsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  const QsSwitch({required this.value, required this.onChanged, this.semanticLabel, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 50,
            height: 30,
            decoration: BoxDecoration(color: value ? _switchOn : _switchOff, borderRadius: BorderRadius.circular(20)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? Colors.white : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(8, 8, 8, 0.26), offset: Offset(5, 2), blurRadius: 7)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------- groups */

/// A settings group: section label plus a rounded card with a 0.8 px border.
class QsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const QsGroup({this.title, required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(height: 0.5, thickness: 0.5, indent: 22, endIndent: 22, color: p.faint));
      items.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Text(
              title!,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.sub),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: p.border, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: items),
          ),
        ),
      ],
    );
  }
}

/// A settings row: title, optional blue value and grey hint, optional trailing widget.
class QsRow extends StatelessWidget {
  final String title;
  final String? value;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;

  const QsRow({required this.title, this.value, this.hint, this.trailing, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, color: p.text)),
                    if (value != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(value!, style: TextStyle(fontSize: 13.5, color: p.accent)),
                      ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(hint!, style: TextStyle(fontSize: 13, color: p.sub, height: 1.35)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class QsSwitchRow extends StatelessWidget {
  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const QsSwitchRow({required this.title, this.hint, required this.value, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    return QsRow(
      title: title,
      hint: hint,
      onTap: () => onChanged(!value),
      trailing: QsSwitch(value: value, onChanged: onChanged, semanticLabel: title),
    );
  }
}

/* -------------------------------------------------------------- dropdown */

/// A compact dropdown (value + arrow) that opens an animated menu with a check on the
/// current choice. Used wherever one of several local IP addresses / networks is picked.
class QsDropdown<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? tooltip;
  final TextStyle? style;

  const QsDropdown({required this.value, required this.options, required this.onChanged, this.tooltip, this.style, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final label = options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      color: p.card,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.border, width: 0.8),
      ),
      popUpAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 220), reverseDuration: Duration(milliseconds: 140)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final (v, text) in options)
          PopupMenuItem<T>(
            value: v,
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: TextStyle(color: p.text, fontSize: 14)),
                const SizedBox(width: 12),
                Icon(Icons.check, size: 18, color: v == value ? p.accent : Colors.transparent),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: style ?? TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: p.sub),
          ],
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------- ripple */

/// Layered circles behind "Ready to receive": rings grow out of the centre
/// and fade at the edge in a seamless endless loop (one clock, offset phases).
class QsReceiveGlow extends StatefulWidget {
  final double size;
  final bool animate;

  const QsReceiveGlow({required this.size, this.animate = true, super.key});

  @override
  State<QsReceiveGlow> createState() => _QsReceiveGlowState();
}

class _QsReceiveGlowState extends State<QsReceiveGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _clock.repeat(); // ignore: discarded_futures
    } else {
      _clock.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(QsReceiveGlow old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_clock.isAnimating) _clock.repeat(); // ignore: discarded_futures
    if (!widget.animate && _clock.isAnimating) _clock.stop();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _GlowPainter(phase: _clock.value, color: p.glow, peak: p.dark ? 0.3 : 0.38),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final double phase;
  final Color color;
  final double peak;

  const _GlowPainter({required this.phase, required this.color, required this.peak});

  static const _rings = 6;

  /// Smooth rise and fall over a ring's life (0..1): sin-shaped, zero at both ends.
  double _opacity(double t) => peak * math.pow(math.sin(math.pi * t), 1.4).toDouble() * (1 - t * 0.35);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    for (var i = 0; i < _rings; i++) {
      final t = (phase + i / _rings) % 1.0;
      final paint = Paint()..color = color.withValues(alpha: _opacity(t));
      canvas.drawCircle(center, radius * (0.12 + 0.88 * t), paint);
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.phase != phase || old.color != color;
}

/* ------------------------------------------------------------ tab toggle */

/// The floating Receive / Send pill toggle (212×50) with a sliding highlight.
class QsTabToggle extends StatelessWidget {
  final bool sendSelected;
  final String receiveLabel;
  final String sendLabel;
  final ValueChanged<bool> onChanged;

  const QsTabToggle({required this.sendSelected, required this.receiveLabel, required this.sendLabel, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    Widget item(bool send, IconData icon, String label) {
      final active = send == sendSelected;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () => onChanged(send),
          child: Semantics(
            selected: active,
            button: true,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: active ? p.text : p.sub),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: active ? p.text : p.sub, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 212,
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.nav,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: sendSelected ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.navActive, borderRadius: BorderRadius.circular(21)),
              ),
            ),
          ),
          Row(children: [item(false, Icons.download_rounded, receiveLabel), item(true, Icons.upload_rounded, sendLabel)]),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ pages */

/// A Quick Send page: back arrow, large title, content centred at the settings width.
class QsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  const QsPage({required this.title, required this.children, this.actions, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        scrolledUnderElevation: 0,
        foregroundColor: p.text,
        actions: actions,
        title: Text(
          title,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 32), children: children),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ menus */

/// Shape of Quick Send popup menus (the 3-dot menu, dropdowns, device menu).
ShapeBorder qsMenuShape(QsPalette p) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(20),
  side: BorderSide(color: p.border, width: 0.8),
);

const qsMenuAnimation = AnimationStyle(duration: Duration(milliseconds: 220), reverseDuration: Duration(milliseconds: 140));

/// A Quick Send popup menu entry: icon + label, like the 3-dot menu.
PopupMenuItem<T> qsMenuItem<T>(QsPalette p, T value, IconData icon, String label, {Color? color}) => PopupMenuItem<T>(
  value: value,
  height: 48,
  child: Row(
    children: [
      Icon(icon, size: 20, color: color ?? p.sub),
      const SizedBox(width: 14),
      Flexible(
        child: Text(label, style: TextStyle(color: color ?? p.text, fontSize: 15)),
      ),
    ],
  ),
);
