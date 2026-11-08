// Quick Send addition (not part of upstream LocalSend).
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _checking ? null : _check,
          icon: _checking
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update_alt),
          label: Text(_checking ? t.aboutPage.checkingUpdates : t.aboutPage.checkUpdates),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(liveRegion: true, child: Text(message)),
          ),
        if (result is UpdateAvailable)
          TextButton(
            onPressed: () => launchUrl(result.releaseUrl, mode: LaunchMode.externalApplication),
            child: Text(t.aboutPage.openRelease),
          ),
      ],
    );
  }
}
