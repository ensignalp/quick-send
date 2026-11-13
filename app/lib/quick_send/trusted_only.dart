// Quick Send: who can share with this device.
//
// The persisted mode (off / trusted / everyone) applies while the Receive
// screen is not on screen; while it is (tab selected and window visible),
// everyone may share — the same rule as the Android app.

import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Receive visibility as shown in the UI.
enum QsVisibility { hidden, trusted, everyone }

QsVisibility _parse(String mode) => switch (mode) {
  'off' => QsVisibility.hidden,
  'everyone' => QsVisibility.everyone,
  _ => QsVisibility.trusted,
};

String _name(QsVisibility v) => switch (v) {
  QsVisibility.hidden => 'off',
  QsVisibility.trusted => 'trusted',
  QsVisibility.everyone => 'everyone',
};

/// The configured mode (used when the Receive screen is not open).
final shareModeProvider = NotifierProvider<ShareModeNotifier, QsVisibility>((ref) => ShareModeNotifier());

class ShareModeNotifier extends Notifier<QsVisibility> {
  @override
  QsVisibility init() => _parse(ref.read(persistenceProvider).getQsShareMode());

  Future<void> set(QsVisibility mode) async {
    await ref.read(persistenceProvider).setQsShareMode(_name(mode));
    state = mode;
    await applyEffectiveVisibility(ref);
  }
}

/// Whether the Receive screen is actually on screen.
class QsReceiveScreen {
  static bool tabOpen = true;
  static bool windowVisible = false;
  static Ref? _ref;

  static bool get isOpen => tabOpen && windowVisible;

  static void attach(Ref ref) => _ref = ref;

  static Future<void> update({bool? tab, bool? window}) async {
    if (tab != null) tabOpen = tab;
    if (window != null) windowVisible = window;
    final ref = _ref;
    if (ref != null) await applyEffectiveVisibility(ref);
  }
}

/// The mode in effect right now.
QsVisibility effectiveVisibility(Ref ref) => QsReceiveScreen.isOpen ? QsVisibility.everyone : ref.read(shareModeProvider);

/// Starts or stops the receive server to match [effectiveVisibility]. The
/// trusted-only filter itself is applied in the receive controller.
Future<void> applyEffectiveVisibility(Ref ref) async {
  final mode = effectiveVisibility(ref);
  final running = ref.read(serverProvider) != null;
  if (mode == QsVisibility.hidden) {
    if (running) await ref.notifier(serverProvider).stopServer();
  } else if (!running) {
    await ref.notifier(serverProvider).startServerFromSettings();
  }
}
