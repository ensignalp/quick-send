// Quick Send: profile photo (desktop). Like on Android it is shown on this
// device only (name pill, info dialog, settings); it is not sent to others.
// The picked image is copied into the app's data folder.

import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/quick_send/portal_file_chooser.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _logger = Logger('QsAvatar');
const _avatarKey = 'qs_avatar_path';

final qsAvatarProvider = NotifierProvider<QsAvatarNotifier, String?>((ref) => QsAvatarNotifier());

class QsAvatarNotifier extends Notifier<String?> {
  @override
  String? init() {
    // Loaded asynchronously; null (letter avatar) until then.
    SharedPreferences.getInstance().then((prefs) {
      final path = prefs.getString(_avatarKey);
      if (path != null && File(path).existsSync()) state = path;
    }).ignore();
    return null;
  }

  /// Lets the user pick an image; returns false when nothing was chosen.
  Future<bool> choose() async {
    String? picked;
    final portal = await PortalFileChooser.open(
      title: t.qsSettings.profilePhoto,
      multiple: false,
      filters: [
        PortalFilter(t.qsSettings.profilePhoto, const ['image/png', 'image/jpeg', 'image/webp', 'image/gif']),
      ],
    );
    if (portal != null) {
      picked = portal.firstOrNull;
    } else {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(label: 'images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']),
        ],
      );
      picked = file?.path;
    }
    if (picked == null) return false;
    try {
      final dir = await getApplicationSupportDirectory();
      final ext = picked.contains('.') ? picked.substring(picked.lastIndexOf('.')).toLowerCase() : '.png';
      // A new name each time so the image cache never shows the previous photo.
      final target = File('${dir.path}/avatar-${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(picked).copy(target.path);
      await _deleteCurrent();
      await (await SharedPreferences.getInstance()).setString(_avatarKey, target.path);
      state = target.path;
      return true;
    } catch (e) {
      _logger.warning('Could not save the profile photo: $e');
      return false;
    }
  }

  Future<void> remove() async {
    await _deleteCurrent();
    await (await SharedPreferences.getInstance()).remove(_avatarKey);
    state = null;
  }

  Future<void> _deleteCurrent() async {
    final current = state;
    if (current != null) {
      try {
        await File(current).delete();
      } catch (_) {}
    }
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}

/// This device's avatar: the profile photo if set, otherwise [fallback] (the letter avatar).
class QsSelfAvatar extends StatelessWidget {
  final double size;
  final Widget fallback;

  const QsSelfAvatar({required this.size, required this.fallback, super.key});

  @override
  Widget build(BuildContext context) {
    final path = context.watch(qsAvatarProvider);
    if (path == null) return fallback;
    return ClipOval(
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
