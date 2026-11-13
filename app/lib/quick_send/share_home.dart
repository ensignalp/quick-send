// Quick Send: home screen, in the Android app's design language.
//
// Every window size uses the phone layout: the device name pill on top, the
// 3-dot menu on the right (with Settings) and the floating Receive/Send toggle
// at the bottom; Settings opens as a page with a back arrow. The selected tab is the
// LocalSend home controller's tab, so drag & drop, files passed on the command
// line, the tray and keyboard shortcuts switch tabs too. Receive shows the
// "ready" ripple; while it is on screen everyone may share (see
// trusted_only.dart). Send sends files to nearby devices with progress rings.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/assets.gen.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/pages/device_details_page.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/pages/web_share_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/internet_page.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/quick_send/settings_page.dart';
import 'package:localsend_app/quick_send/transfer_events.dart';
import 'package:localsend_app/quick_send/trusted_only.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

typedef _Palette = QsPalette;

class ShareHome extends StatefulWidget {
  const ShareHome();

  @override
  State<ShareHome> createState() => _ShareHomeState();
}

class _ShareHomeState extends State<ShareHome> with Refena {
  HomeTab? _lastTab;
  StreamSubscription<QsSentEvent>? _sentSubscription;
  final List<QsSentEvent> _sent = [];
  Timer? _sentTimer;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) => QsReceiveScreen.attach(ref));
    _sentSubscription = QsTransferEvents.sent.listen((event) {
      qsRecentlySent.add(event.fingerprint);
      _sent.add(event);
      _sentTimer?.cancel();
      _sentTimer = Timer(const Duration(milliseconds: 1600), _afterSent);
    });
  }

  @override
  void dispose() {
    unawaited(_sentSubscription?.cancel());
    _sentTimer?.cancel();
    super.dispose();
  }

  /// After a successful send: confirm it, clear the selection and go back to Receive, so the
  /// send screen does not stay open. Waits while other sends run; stays put if one failed (retry).
  void _afterSent() {
    if (!mounted) return;
    final sessions = ref.read(sendProvider).values;
    if (sessions.any((s) => s.status == SessionStatus.waiting || s.status == SessionStatus.sending)) {
      _sentTimer = Timer(const Duration(milliseconds: 800), _afterSent);
      return;
    }
    final names = _sent.map((e) => e.alias).toSet().join(', ');
    _sent.clear();
    qsRecentlySent.clear();
    if (sessions.any((s) => s.status == SessionStatus.finishedWithErrors)) return;
    context.showSnackBar(t.shareHome.sentTo(name: names));
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    _selectTab(context, HomeTab.receive);
  }

  /// Keeps the "Receive screen is open" state (everyone may share) in sync with the tab.
  void _syncReceiveScreen(HomeTab tab) {
    if (tab == _lastTab) return;
    _lastTab = tab;
    scheduleMicrotask(() => QsReceiveScreen.update(tab: tab == HomeTab.receive));
  }

  @override
  Widget build(BuildContext context) {
    final tab = context.watch(homePageControllerProvider.select((s) => s.currentTab));
    _syncReceiveScreen(tab);
    return ViewModelBuilder(
      provider: (ref) => sendTabVmProvider,
      init: (context) async => context.global.dispatchAsync(SendTabInitAction(context)), // ignore: discarded_futures
      builder: (context, vm) {
        final p = _Palette(context);
        final alias = context.watch(settingsProvider.select((s) => s.alias));
        final Widget content = switch (tab) {
          HomeTab.receive => const _ReceiveView(key: ValueKey('receive'), bottomGap: 86),
          HomeTab.send => _SendView(key: const ValueKey('send'), vm: vm, bottomGap: 100),
          HomeTab.settings => QsSettingsPage(key: const ValueKey('settings'), onBack: () => _selectTab(context, HomeTab.receive)),
        };
        final switcher = AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: content,
        );

        if (tab == HomeTab.settings) return ColoredBox(color: p.bg, child: switcher);
        return ColoredBox(
          color: p.bg,
          child: Stack(
            children: [
              Column(
                children: [
                  _TopBar(alias: alias, vm: vm),
                  Expanded(child: switcher),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: QsTabToggle(
                    sendSelected: tab == HomeTab.send,
                    receiveLabel: t.shareHome.receiveTab,
                    sendLabel: t.shareHome.sendTab,
                    onChanged: (send) => _selectTab(context, send ? HomeTab.send : HomeTab.receive),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _selectTab(BuildContext context, HomeTab tab) => context.redux(homePageControllerProvider).dispatch(ChangeTabAction(tab));

/* ------------------------------------------------------------ navigation */

void _openSettings(BuildContext context) => _selectTab(context, HomeTab.settings);

Future<void> _addFiles(BuildContext context) => AddFileDialog.open(context: context, options: pickerOptions);

Future<void> _pickFiles(BuildContext context) => context.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));

/// Adds the clipboard (text or image) to the selection.
Future<void> _addClipboard(BuildContext context) =>
    context.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: context));

Future<void> _openLink(BuildContext context) async {
  final ref = context.ref;
  if (ref.read(selectedSendingFilesProvider).isEmpty) await _addFiles(context);
  final files = ref.read(selectedSendingFilesProvider);
  if (files.isEmpty || !context.mounted) return;
  await context.push(() => WebSharePage(files: files));
}

class _TopBar extends StatelessWidget {
  final String alias;
  final SendTabVm vm;

  const _TopBar({required this.alias, required this.vm});

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    PopupMenuItem<void Function()> item(IconData icon, String label, void Function() action) => PopupMenuItem(
      value: action,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.sub),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: p.text, fontSize: 15)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: Material(
                color: p.nav,
                shape: const StadiumBorder(),
                elevation: 0,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () async => showDialog<void>(
                    context: context,
                    builder: (_) => _InfoDialog(alias: alias),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LetterAvatar(name: alias, size: 30),
                        const SizedBox(width: 9),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            alias,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<void Function()>(
            tooltip: t.settingsTab.title,
            icon: Icon(Icons.more_vert, color: p.text),
            color: p.card,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.border, width: 0.8),
            ),
            popUpAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 220), reverseDuration: Duration(milliseconds: 140)),
            itemBuilder: (context) => [
              item(Icons.refresh, t.sendTab.scan, () => context.global.dispatchAsync(StartSmartScan())), // ignore: discarded_futures
              item(Icons.content_paste, t.shareHome.clipboard, () => _addClipboard(context)), // ignore: discarded_futures
              item(Icons.ads_click, t.sendTab.manualSending, () => vm.onTapAddress(context)), // ignore: discarded_futures
              item(Icons.history, t.shareHome.history, () => context.push(() => const ReceiveHistoryPage())), // ignore: discarded_futures
              item(Icons.public, t.qsInternet.menu, () => context.push(() => const QsInternetPage())), // ignore: discarded_futures
              item(Icons.help_outline, t.troubleshootPage.title, () => context.push(() => const TroubleshootPage())), // ignore: discarded_futures
              item(Icons.settings_outlined, t.settingsTab.title, () => _openSettings(context)),
            ],
            onSelected: (action) => action(),
          ),
        ],
      ),
    );
  }
}

class _InfoDialog extends StatefulWidget {
  final String alias;

  const _InfoDialog({required this.alias});

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  /// With several network interfaces, one address is shown and the others are offered in a dropdown.
  String? _chosenIp;

  @override
  Widget build(BuildContext context) {
    final alias = widget.alias;
    final p = _Palette(context);
    final running = context.watch(serverProvider) != null;
    final mode = effectiveVisibility(context.ref);
    final ips = context.watch(localIpProvider.select((s) => s.localIps));
    final port = context.watch(settingsProvider.select((s) => s.port));
    final status = !running ? t.shareHome.statusOff : (mode == QsVisibility.trusted ? t.shareHome.statusTrusted : t.shareHome.statusEveryone);
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: p.sub),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: p.sub, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Dialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: p.border, width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.shareHome.infoTitle,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: p.sub),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _LetterAvatar(name: alias, size: 64),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running ? const Color(0xFF34C759) : p.sub,
                        border: Border.all(color: p.card, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                alias,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: running ? p.accent : p.sub),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    if (ips.length > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Icon(Icons.lan_outlined, size: 20, color: p.sub),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 80,
                              child: Text(t.shareHome.address, style: TextStyle(color: p.sub, fontSize: 13)),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: QsDropdown<String>(
                                  value: ips.contains(_chosenIp) ? _chosenIp! : ips.first,
                                  options: [for (final ip in ips) (ip, '$ip:$port')],
                                  onChanged: (ip) => setState(() => _chosenIp = ip),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      row(Icons.lan_outlined, t.shareHome.address, ips.isEmpty ? t.shareHome.noNetwork : '${ips.first}:$port'),
                    row(Icons.lock_outline, t.shareHome.protocol, t.shareHome.protocolValue),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------------------------------------------- receive */

class _ReceiveView extends StatelessWidget {
  /// Space kept free at the bottom (the phone layout's floating toggle).
  final double bottomGap;

  const _ReceiveView({required this.bottomGap, super.key});

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final running = context.watch(serverProvider) != null;
    final animate = context.watch(animationProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final glow = math.min(constraints.maxWidth * 1.25, 640.0);
        return Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: QsReceiveGlow(size: glow, animate: animate),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      running ? t.shareHome.readyTitle : t.shareHome.readyOff,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: p.text),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Text(
                        running ? t.shareHome.readyHint : t.shareHome.readyOffHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, height: 1.4, color: p.sub),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 32,
              right: 32,
              bottom: bottomGap,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 14, height: 1.4, color: p.sub),
                  children: [
                    TextSpan(text: t.shareHome.goSettingsPrefix),
                    TextSpan(
                      text: t.shareHome.goSettingsLink,
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: p.accent),
                      recognizer: TapGestureRecognizer()..onTap = () => _openSettings(context),
                      mouseCursor: SystemMouseCursors.click,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}

/* ------------------------------------------------------------------ send */

class _SendView extends StatelessWidget {
  final SendTabVm vm;

  /// Space kept free at the bottom (the phone layout's floating toggle).
  final double bottomGap;

  const _SendView({required this.vm, required this.bottomGap, super.key});

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    if (vm.selectedFiles.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomGap - 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ShareIllustration(),
              const SizedBox(height: 22),
              Text(
                t.shareHome.chooseTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: qsFontFamily),
                ),
                onPressed: () async => _pickFiles(context),
                child: Text(t.shareHome.chooseButton),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async => _addFiles(context),
                icon: Icon(Icons.add, size: 18, color: p.sub),
                label: Text(t.shareHome.add, style: TextStyle(color: p.sub)),
              ),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomGap),
          children: [
            _SelectionCard(files: vm.selectedFiles),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              child: Text(
                t.shareHome.nearby,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.sub),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(26)),
              child: vm.nearbyDevices.isEmpty
                  ? const _Searching(height: 240)
                  : Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(t.shareHome.tapDevice, style: TextStyle(fontSize: 13, color: p.sub)),
                            const SizedBox(width: 8),
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.sub)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _DeviceGrid(vm: vm),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            Center(child: _QrButton()),
          ],
        ),
      ),
    );
  }
}

/// Fanned cards above "Choose what to share" (document, video, photo).
class _ShareIllustration extends StatelessWidget {
  const _ShareIllustration();

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    Widget card(double angle, Offset offset, IconData icon, Color tint) => Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 150,
          height: 180,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: p.dark ? const Color(0xFF2E2E2E) : const Color(0xFFE6E7EC), width: 4),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: tint, size: 30),
              ),
              const SizedBox(height: 12),
              Container(
                height: 9,
                width: 90,
                decoration: BoxDecoration(color: p.faint, borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(height: 9),
              Container(
                height: 9,
                width: 60,
                decoration: BoxDecoration(color: p.faint, borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: 300,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card(-0.24, const Offset(-78, 18), Icons.description_outlined, const Color(0xFF7AA7FF)),
          card(0.21, const Offset(78, -6), Icons.movie_outlined, const Color(0xFFF2A65A)),
          card(-0.03, const Offset(0, 26), Icons.image_outlined, const Color(0xFF6FD3B5)),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final List<CrossFile> files;

  const _SelectionCard({required this.files});

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final ref = context.ref;
    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    final shown = files.take(3).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(26)),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Transform.translate(
                    offset: Offset((shown.length - 1 - i) * -5.0, 0),
                    child: Transform.rotate(
                      angle: (shown.length - 1 - i) * -0.16,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.card, width: 2),
                        ),
                        child: _Thumb(file: shown[i], radius: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  files.length == 1 ? files.first.name : t.shareHome.items(n: files.length),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 2),
                Text(total.asReadableFileSize, style: TextStyle(fontSize: 13, color: p.sub)),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(backgroundColor: p.chip, foregroundColor: p.accent, shape: const StadiumBorder()),
            onPressed: () async => _addFiles(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(t.shareHome.add),
          ),
          IconButton(
            tooltip: t.shareHome.clear,
            icon: Icon(Icons.close, color: p.sub),
            onPressed: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
          ),
        ],
      ),
    );
  }
}

/* ---------------------------------------------------------- shared parts */

class _QrButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: p.chip,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
      ),
      onPressed: () async => _openLink(context),
      icon: const Icon(Icons.qr_code_2, size: 20),
      label: Text(t.shareHome.qrOrLink),
    );
  }
}

class _Searching extends StatefulWidget {
  final double? height;

  const _Searching({this.height});

  @override
  State<_Searching> createState() => _SearchingState();
}

class _SearchingState extends State<_Searching> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final text = Theme.of(context).textTheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Stack(
              alignment: Alignment.center,
              children: [
                for (final offset in const [0.0, 0.5])
                  Builder(
                    builder: (context) {
                      final v = (_controller.value + offset) % 1;
                      return Opacity(
                        opacity: (1 - v) * 0.45,
                        child: Container(
                          width: 50 + 60 * v,
                          height: 50 + 60 * v,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: p.accent, width: 2),
                          ),
                        ),
                      );
                    },
                  ),
                child!,
              ],
            ),
            child: Container(
              width: 50,
              height: 50,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
              child: Assets.img.logo512White.image(fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(t.shareHome.looking, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            t.shareHome.lookingHint,
            style: text.bodySmall?.copyWith(color: p.sub),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    return widget.height == null
        ? Center(child: content)
        : SizedBox(
            height: widget.height,
            child: Center(child: content),
          );
  }
}

class _DeviceGrid extends StatelessWidget {
  final SendTabVm vm;

  const _DeviceGrid({required this.vm});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a device was just sent to (its tile shows "Sent" until the screen returns to Receive).
    return ListenableBuilder(
      listenable: qsRecentlySent,
      builder: (context, _) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 14,
        children: vm.nearbyDevices.map((device) {
          final favorite = vm.favoriteDevices.findDevice(device);
          return _DeviceTile(device: device, name: favorite?.alias ?? device.alias, trusted: favorite != null, vm: vm);
        }).toList(),
      ),
    );
  }
}

enum _TileStatus { idle, waiting, sending, sent, declined, failed }

class _DeviceTile extends StatelessWidget {
  final Device device;
  final String name;
  final SendTabVm vm;

  final bool trusted;

  const _DeviceTile({required this.device, required this.name, required this.trusted, required this.vm});

  Future<void> _showMenu(BuildContext context, Offset? position) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = position ?? (box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero)));
    final ref = context.ref;
    final p = _Palette(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx, origin.dy, origin.dx, origin.dy),
      color: p.card,
      elevation: 6,
      shape: qsMenuShape(p),
      popUpAnimationStyle: qsMenuAnimation,
      items: [
        qsMenuItem(
          p,
          'trust',
          trusted ? Icons.remove_moderator_outlined : Icons.verified_user_outlined,
          trusted ? t.shareHome.untrust : t.shareHome.trust,
        ),
        qsMenuItem(p, 'details', Icons.info_outline, t.shareHome.details),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case 'trust':
        if (trusted) {
          await ref.redux(favoritesProvider).dispatchAsync(RemoveFavoriteAction(deviceFingerprint: device.fingerprint));
        } else {
          await ref
              .redux(favoritesProvider)
              .dispatchAsync(
                AddFavoriteAction(
                  FavoriteDevice.fromValues(fingerprint: device.fingerprint, ip: device.ip ?? '', port: device.port, alias: device.alias),
                ),
              );
        }
      case 'details':
        await context.push(() => DeviceDetailsPage(device: device));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final text = Theme.of(context).textTheme;
    final ref = context.ref;
    final session = ref.watch(sendProvider).values.firstWhereOrNull((s) => s.target.fingerprint == device.fingerprint);
    var status = session == null && qsRecentlySent.contains(device.fingerprint) ? _TileStatus.sent : _TileStatus.idle;
    double? progress;
    if (session != null) {
      status = switch (session.status) {
        SessionStatus.waiting => _TileStatus.waiting,
        SessionStatus.sending => _TileStatus.sending,
        SessionStatus.finished => _TileStatus.sent,
        SessionStatus.declined => _TileStatus.declined,
        _ => _TileStatus.failed,
      };
      if (status == _TileStatus.sending) {
        final files = session.files.values.where((f) => f.token != null);
        final transfers = ref.watch(fileTransferProvider);
        final total = files.fold<int>(0, (sum, f) => sum + f.file.size);
        final done = files.fold<int>(
          0,
          (sum, f) => sum + (transfers.getProgress(sessionId: session.sessionId, fileId: f.file.id) * f.file.size).round(),
        );
        progress = total == 0 ? 0 : done / total;
      }
    }
    final subtitle = switch (status) {
      _TileStatus.waiting => t.shareHome.waiting,
      _TileStatus.sending => t.shareHome.sending,
      _TileStatus.sent => t.shareHome.sent,
      _TileStatus.declined => t.shareHome.declined,
      _TileStatus.failed => t.shareHome.failed,
      _TileStatus.idle => _typeLabel(device),
    };
    final subColor = switch (status) {
      _TileStatus.idle => p.sub,
      _TileStatus.declined || _TileStatus.failed => p.danger,
      _ => p.accent,
    };
    const size = 60.0;
    final busy = status == _TileStatus.waiting || status == _TileStatus.sending;
    return SizedBox(
      width: 86,
      child: Tooltip(
        message: '${device.alias}\n${device.ip ?? ''}${device.deviceModel != null ? ' · ${device.deviceModel}' : ''}',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async => vm.onTapDeviceMultiSend(context, device),
          onLongPress: () async => _showMenu(context, null),
          onSecondaryTapUp: (details) async => _showMenu(context, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              children: [
                SizedBox(
                  width: size + 14,
                  height: size + 14,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (busy)
                        Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.accentSoft.withValues(alpha: 0.7)),
                        ),
                      if (status == _TileStatus.sent)
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
                          child: Icon(Icons.check, size: 32, color: Theme.of(context).colorScheme.onPrimary),
                        )
                      else if (device.deviceType == DeviceType.mobile && !_looksLikeTablet(device))
                        _LetterAvatar(name: name, size: size)
                      else
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.chip),
                          child: Icon(_looksLikeTablet(device) ? Icons.tablet_android : _desktopIcon(device), size: 28, color: p.accent),
                        ),
                      if (busy)
                        SizedBox(
                          width: size + 8,
                          height: size + 8,
                          child: CircularProgressIndicator(
                            value: status == _TileStatus.sending ? (progress ?? 0).clamp(0.03, 1.0) : null,
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round,
                            color: p.accent,
                          ),
                        ),
                      if (trusted && status != _TileStatus.sent)
                        Positioned(
                          right: 6,
                          top: 4,
                          child: Tooltip(
                            message: t.shareHome.trusted,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.accent,
                                border: Border.all(color: p.card, width: 2),
                              ),
                              child: const Icon(Icons.verified_user, size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      if (status == _TileStatus.declined || status == _TileStatus.failed)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.danger,
                              border: Border.all(color: p.card, width: 2),
                            ),
                            child: const Icon(Icons.priority_high, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  status == _TileStatus.sending && progress != null ? '$subtitle ${(progress * 100).round()}%' : subtitle,
                  style: text.labelSmall?.copyWith(color: subColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _looksLikeTablet(Device device) => RegExp(r'tab|pad', caseSensitive: false).hasMatch('${device.alias} ${device.deviceModel ?? ''}');

IconData _desktopIcon(Device device) {
  if (device.deviceType != DeviceType.desktop) return device.deviceType.icon;
  return RegExp(r'mac|book|laptop', caseSensitive: false).hasMatch('${device.alias} ${device.deviceModel ?? ''}') ? Icons.laptop_mac : Icons.computer;
}

String _typeLabel(Device device) {
  if (_looksLikeTablet(device)) return 'Tablet';
  return switch (device.deviceType) {
    DeviceType.mobile => t.shareHome.phone,
    DeviceType.desktop => t.shareHome.computer,
    DeviceType.web => t.shareHome.browser,
    DeviceType.headless || DeviceType.server => t.shareHome.server,
  };
}

const _avatarGradients = [
  [Color(0xFFA78BFA), Color(0xFF6D8DF7)],
  [Color(0xFF7AA7FF), Color(0xFF5B6CF0)],
  [Color(0xFFFFB27A), Color(0xFFF2786A)],
  [Color(0xFF6FD3B5), Color(0xFF3EA2C9)],
  [Color(0xFFF59AC8), Color(0xFFB57CF2)],
  [Color(0xFF8FC6FF), Color(0xFF6A8BFF)],
];

class _LetterAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _LetterAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = _avatarGradients[name.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) % 1000003) % _avatarGradients.length];
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Rounded file preview: the image itself when available, otherwise a type icon.
class _Thumb extends StatelessWidget {
  final CrossFile file;
  final double radius;

  const _Thumb({required this.file, required this.radius});

  @override
  Widget build(BuildContext context) {
    final p = _Palette(context);
    final fallback = Center(child: Icon(file.fileType.icon, size: 28, color: p.accent));
    Widget child = fallback;
    if (file.thumbnail != null) {
      child = Image.memory(file.thumbnail!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    } else if (file.fileType == FileType.image && file.path != null && !file.path!.startsWith('content://')) {
      child = Image.file(File(file.path!), fit: BoxFit.cover, cacheWidth: 256, errorBuilder: (_, _, _) => fallback);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: p.accentSoft,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}
