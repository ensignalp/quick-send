import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/server/web_share_state.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/dialogs/zoom_dialog.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:logging/logging.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('WebSharePage');

enum _ServerState { initializing, running, error, stopping }

/// Shares a link with web browsers, in one of two modes:
/// - send: offers [WebSharePage.files] for download.
/// - receive: serves the upload page so browsers can upload files to this device.
///   Incoming requests are not listed here because they open the receive page
///   like any other incoming request.
class WebSharePage extends StatefulWidget {
  /// The files offered for download (share via link).
  /// `null` serves the upload page instead (receive via link).
  final List<CrossFile>? files;

  const WebSharePage({this.files});

  @override
  State<WebSharePage> createState() => _WebSharePageState();
}

class _WebSharePageState extends State<WebSharePage> with Refena {
  _ServerState _stateEnum = _ServerState.initializing;
  bool _encrypted = false;
  String? _initializedError;

  /// Quick Send: with several local IPs, one link is shown and the IP is chosen from a dropdown.
  String? _chosenIp;

  bool get _sendMode => widget.files != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init(encrypted: false);
    });
  }

  void _init({required bool encrypted}) async {
    final settings = ref.read(settingsProvider);
    setState(() {
      _stateEnum = _ServerState.initializing;
      _encrypted = encrypted;
      _initializedError = null;
    });
    await sleepAsync(500);
    try {
      final files = widget.files;

      // The pin of a previous web share session is kept;
      // receive mode initially uses the receive pin from settings.
      final previousWeb = ref.read(serverProvider)?.web;
      final webPin = previousWeb != null ? previousWeb.pin : (files == null ? settings.receivePin : null);

      if (files != null) {
        // The auto accept setting of a previous web download state is kept.
        await ref
            .notifier(serverProvider)
            .restartServerWithWebDownload(
              alias: settings.alias,
              port: settings.port,
              https: _encrypted,
              files: files,
              pin: webPin,
            );
      } else {
        await ref
            .notifier(serverProvider)
            .restartServer(
              alias: settings.alias,
              port: settings.port,
              https: _encrypted,
              web: WebShareUpload(pin: webPin),
            );
      }
      setState(() {
        _stateEnum = _ServerState.running;
      });
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _stateEnum = _ServerState.error;
          _initializedError = e.toString();
        });
      }
    }
  }

  /// Web share uses unencrypted http by default, so we need to revert to the previous state.
  Future<void> _revertServerState() async {
    await ref.notifier(serverProvider).restartServerFromSettings();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) async {
        if (_stateEnum == _ServerState.initializing || _stateEnum == _ServerState.stopping) {
          return;
        }

        setState(() {
          _stateEnum = _ServerState.stopping;
        });
        await sleepAsync(250);
        try {
          // Also needed in the error state: the failed restart already stopped the old server.
          await _revertServerState();
        } catch (e) {
          _logger.warning('Failed to restore the server', e);
        }
        await sleepAsync(250);

        if (context.mounted) {
          context.pop();
        }
      },
      canPop: false,
      child: Builder(
        builder: (context) {
          final p = QsPalette(context);
          return Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: p.bg,
              scrolledUnderElevation: 0,
              foregroundColor: p.text,
              title: Text(
                _sendMode ? t.webSharePage.title : t.webReceivePage.title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text),
              ),
            ),
            body: Builder(
              builder: (context) {
                if (_stateEnum != _ServerState.running) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_stateEnum == _ServerState.initializing || _stateEnum == _ServerState.stopping) ...[
                            CircularProgressIndicator(color: p.accent),
                            const SizedBox(height: 20),
                            Text(
                              _stateEnum == _ServerState.initializing ? t.webSharePage.loading : t.webSharePage.stopping,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
                            ),
                          ] else if (_initializedError != null) ...[
                            Icon(Icons.error_outline, size: 48, color: p.danger),
                            const SizedBox(height: 10),
                            Text(
                              t.webSharePage.error,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
                            ),
                            const SizedBox(height: 10),
                            SelectableText(_initializedError!, style: TextStyle(color: p.sub)),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                final serverState = context.watch(serverProvider);
                final webDownloadState = serverState?.webDownloadState;
                if (serverState == null || (_sendMode && webDownloadState == null)) {
                  // the server is restarting (e.g. because the pin changed)
                  return Center(child: CircularProgressIndicator(color: p.accent));
                }
                final networkState = context.watch(localIpProvider);
                final settings = context.watch(settingsProvider);
                final pin = serverState.web?.pin;
                final ip = networkState.localIps.contains(_chosenIp) ? _chosenIp : networkState.localIps.firstOrNull;
                final url = ip == null ? null : '${_encrypted ? 'https' : 'http'}://$ip:${serverState.port}';
                final urlWithPin = url == null
                    ? null
                    : switch (pin) {
                        String() => '$url/?pin=${Uri.encodeQueryComponent(pin)}',
                        null => url,
                      };

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
                          child: Text(t.webSharePage.openLink(n: 1), style: TextStyle(color: p.sub, height: 1.45)),
                        ),
                        if (urlWithPin != null && url != null) ...[
                          // Large, high-contrast code with a quiet zone so a phone camera reads it at a distance.
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                              child: SizedBox(
                                width: 240,
                                height: 240,
                                child: PrettyQrView.data(
                                  data: urlWithPin,
                                  errorCorrectLevel: QrErrorCorrectLevel.M,
                                  decoration: const PrettyQrDecoration(shape: PrettyQrSmoothSymbol(roundFactor: 0, color: Colors.black)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          QsGroup(
                            children: [
                              QsRow(
                                title: url,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: t.general.copy,
                                      icon: Icon(Icons.content_copy, size: 20, color: p.sub),
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(text: url));
                                        if (context.mounted && checkPlatformIsDesktop()) {
                                          context.showSnackBar(t.general.copiedToClipboard);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.tv, size: 20, color: p.sub),
                                      onPressed: () async {
                                        await showDialog(
                                          context: context,
                                          builder: (_) => ZoomDialog(
                                            label: url,
                                            listenIncomingWebDownloadRequests: _sendMode,
                                            pin: pin,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              if (networkState.localIps.length > 1)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                                  child: Row(
                                    children: [
                                      Text('${t.shareHome.network}: ', style: TextStyle(color: p.sub)),
                                      Flexible(
                                        child: QsDropdown<String>(
                                          value: ip!,
                                          options: [for (final ip in networkState.localIps) (ip, ip)],
                                          onChanged: (ip) => setState(() => _chosenIp = ip),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (webDownloadState != null)
                          QsGroup(
                            title: t.webSharePage.requests,
                            children: [
                              if (webDownloadState.sessions.isEmpty) QsRow(title: t.webSharePage.noRequests),
                              for (final session in webDownloadState.sessions.values)
                                QsRow(
                                  title: session.deviceInfo,
                                  hint: session.ip,
                                  trailing: session.pending
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: t.general.decline,
                                              icon: Icon(Icons.close, color: p.danger),
                                              onPressed: () => ref.notifier(serverProvider).declineWebDownloadRequest(session.sessionId),
                                            ),
                                            IconButton(
                                              tooltip: t.general.accept,
                                              icon: Icon(Icons.check_circle, color: p.accent),
                                              onPressed: () => ref.notifier(serverProvider).acceptWebDownloadRequest(session.sessionId),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          t.general.accepted,
                                          style: TextStyle(color: p.accent, fontWeight: FontWeight.w600),
                                        ),
                                ),
                            ],
                          ),
                        QsGroup(
                          children: [
                            QsSwitchRow(
                              title: t.webSharePage.encryption,
                              hint: _encrypted ? t.webSharePage.encryptionHint : null,
                              value: _encrypted,
                              onChanged: (value) => _init(encrypted: value),
                            ),
                            QsSwitchRow(
                              title: t.webSharePage.autoAccept,
                              value: webDownloadState != null ? webDownloadState.autoAccept : settings.receiveViaLinkAutoAccept,
                              onChanged: (value) async {
                                if (webDownloadState != null) {
                                  ref.notifier(serverProvider).setWebDownloadAutoAccept(value);
                                } else {
                                  await ref.notifier(settingsProvider).setReceiveViaLinkAutoAccept(value);
                                }
                              },
                            ),
                            QsSwitchRow(
                              title: t.webSharePage.requirePin,
                              hint: pin != null ? t.webSharePage.pinHint(pin: pin) : null,
                              value: pin != null,
                              onChanged: (value) async {
                                if (pin != null) {
                                  await ref.notifier(serverProvider).setWebPin(null);
                                } else {
                                  final String? newPin = await showDialog<String>(
                                    context: context,
                                    builder: (_) => const PinDialog(
                                      obscureText: false,
                                      generateRandom: true,
                                    ),
                                  );

                                  if (newPin != null && newPin.isNotEmpty) {
                                    await ref.notifier(serverProvider).setWebPin(newPin);
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
