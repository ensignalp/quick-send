// Quick Send addition (not part of upstream LocalSend).
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/quick_send/update_checker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckButton extends StatefulWidget {
  const UpdateCheckButton({super.key});

  @override
  State<UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<UpdateCheckButton> {
  bool _checking = false;
  UpdateCheckResult? _result;

  Future<void> _check() async {
    setState(() => _checking = true);
    final info = await PackageInfo.fromPlatform();
    final result = await checkForUpdate(info.version);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final message = switch (result) {
      null => null,
      UpdateAvailable(:final version) => t.aboutPage.updateAvailable(version: version),
      UpToDate() => t.aboutPage.upToDate,
      UpdateCheckFailed() => t.aboutPage.updateCheckFailed,
      UpdateCheckNotConfigured() => t.aboutPage.updateCheckUnavailable,
    };
    final p = QsPalette(context);
    // Quick Send design: one row; when an update is available, tapping it opens the release page.
    return Semantics(
      liveRegion: true,
      child: QsRow(
        title: result is UpdateAvailable ? t.aboutPage.openRelease : (_checking ? t.aboutPage.checkingUpdates : t.aboutPage.checkUpdates),
        hint: message,
        trailing: _checking
            ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
            : Icon(result is UpdateAvailable ? Icons.open_in_new : Icons.system_update_alt, size: 20, color: p.sub),
        onTap: _checking
            ? null
            : result is UpdateAvailable
            ? () => launchUrl(result.releaseUrl, mode: LaunchMode.externalApplication)
            : _check,
      ),
    );
  }
}
