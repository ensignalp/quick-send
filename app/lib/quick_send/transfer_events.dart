// Quick Send: transfer outcomes the home screen reacts to.
//
// Background sends (the desktop's device tiles) are removed silently by the
// upstream send provider when they succeed, so the home screen would never see
// a "sent" state. The provider reports successful sends here first.

import 'dart:async';

import 'package:flutter/foundation.dart';

class QsSentEvent {
  final String fingerprint;
  final String alias;
  final int fileCount;

  const QsSentEvent({required this.fingerprint, required this.alias, required this.fileCount});
}

class QsTransferEvents {
  static final _sent = StreamController<QsSentEvent>.broadcast();

  /// Successful sends (all files delivered).
  static Stream<QsSentEvent> get sent => _sent.stream;

  static void notifySent(QsSentEvent event) => _sent.add(event);
}

/// Devices that just received files from us; their tiles show "Sent" briefly.
final qsRecentlySent = QsRecentlySent();

class QsRecentlySent extends ChangeNotifier {
  final Set<String> _fingerprints = {};

  bool contains(String fingerprint) => _fingerprints.contains(fingerprint);

  void add(String fingerprint) {
    _fingerprints.add(fingerprint);
    notifyListeners();
  }

  void clear() {
    if (_fingerprints.isEmpty) return;
    _fingerprints.clear();
    notifyListeners();
  }
}
