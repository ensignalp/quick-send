// Quick Send desktop settings, organised like the Android app: Nearby sharing,
// Receiving, Trusted devices, Appearance, Desktop, Network, Privacy, About.
// Every option maps to an existing LocalSend setting except the share mode and
// the file manager integration; the complete LocalSend settings stay under
// "All settings".

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/pages/language_page.dart';
import 'package:localsend_app/pages/settings/network_interfaces_page.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/auto_update.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/quick_send/trusted_only.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/native/device_info_helper.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class QsSettingsPage extends StatefulWidget {
  /// Shown as a back arrow when the page replaces the home screen (narrow windows);
  /// in the navigation rail layout there is no back arrow.
  final VoidCallback? onBack;

  const QsSettingsPage({this.onBack, super.key});

  @override
  State<QsSettingsPage> createState() => _QsSettingsPageState();
}

class _QsSettingsPageState extends State<QsSettingsPage> with Refena {
  bool? _contextMenu;
  late bool _autoUpdate = ref.read(persistenceProvider).isQsAutoUpdate();

  @override
  void initState() {
    super.initState();
    if (checkPlatform([TargetPlatform.linux, TargetPlatform.windows])) {
      isContextMenuEnabled().then((v) {
        if (mounted) setState(() => _contextMenu = v);
      }).ignore();
    }
  }

  Future<void> _restartServerIfRunning() async {
    if (ref.read(serverProvider) != null) {
      await ref.notifier(serverProvider).restartServerFromSettings();
    }
  }

  Future<void> _editName(String current) async {
    final controller = TextEditingController(text: current);
    final p = QsPalette(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: p.border, width: 0.8),
        ),
        title: Text(t.settingsTab.network.alias),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              tooltip: t.settingsTab.network.useSystemName,
              icon: const Icon(Icons.computer),
              onPressed: () async {
                final system = await getDeviceName();
                if (system != null) controller.text = system;
              },
            ),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.general.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.general.save)),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty && trimmed != current) {
      await ref.notifier(settingsProvider).setAlias(trimmed);
      await _restartServerIfRunning(); // other devices see the new name after the server restarts
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch(settingsProvider);
    final vm = context.watch(settingsTabControllerProvider);
    final favorites = context.watch(favoritesProvider);
    final mode = context.watch(shareModeProvider);
    final running = context.watch(serverProvider) != null;
    final animations = context.watch(animationProvider);
    final s = t.qsSettings;
    final p = QsPalette(context);

    String modeLabel(QsVisibility v) => switch (v) {
      QsVisibility.hidden => s.modeOff,
      QsVisibility.trusted => s.modeTrusted,
      QsVisibility.everyone => s.modeEveryone,
    };

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.onBack == null
            ? null
            : IconButton(tooltip: MaterialLocalizations.of(context).backButtonTooltip, icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text(
          t.settingsTab.title,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
            children: [
              QsGroup(
                title: s.secNearby,
                children: [
                  _ChoiceRow<QsVisibility>(
                    title: s.whoCanShare,
                    value: mode,
                    label: modeLabel(mode),
                    options: QsVisibility.values.map((v) => (v, modeLabel(v))).toList(),
                    onChanged: (v) async => ref.notifier(shareModeProvider).set(v),
                  ),
                  QsRow(
                    title: t.settingsTab.network.alias,
                    value: settings.alias,
                    trailing: Icon(Icons.edit_outlined, size: 20, color: p.sub),
                    onTap: () async => _editName(settings.alias),
                  ),
                ],
              ),
              QsGroup(
                title: s.secReceive,
                children: [
                  QsSwitchRow(
                    title: s.quickSave,
                    hint: s.quickSaveDesc,
                    value: settings.quickSave,
                    onChanged: (v) async => ref.notifier(settingsProvider).setQuickSave(v),
                  ),
                  QsSwitchRow(
                    title: s.trustedDevices,
                    hint: s.autoAcceptDesc,
                    value: settings.quickSaveFromFavorites,
                    onChanged: (v) async => ref.notifier(settingsProvider).setQuickSaveFromFavorites(v),
                  ),
                  QsRow(
                    title: s.pin,
                    hint: settings.receivePin != null ? s.pinValue(pin: settings.receivePin!) : s.pinDesc,
                    onTap: () async {
                      await ref.notifier(settingsProvider).setReceivePin(settings.receivePin == null ? _randomPin() : null);
                      await _restartServerIfRunning(); // the PIN is enforced by the Rust server
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (settings.receivePin != null)
                          IconButton(
                            tooltip: s.newPin,
                            icon: Icon(Icons.refresh, color: p.sub),
                            onPressed: () async {
                              await ref.notifier(settingsProvider).setReceivePin(_randomPin());
                              await _restartServerIfRunning();
                            },
                          ),
                        QsSwitch(
                          value: settings.receivePin != null,
                          semanticLabel: s.pin,
                          onChanged: (v) async {
                            await ref.notifier(settingsProvider).setReceivePin(v ? _randomPin() : null);
                            await _restartServerIfRunning();
                          },
                        ),
                      ],
                    ),
                  ),
                  if (checkPlatformWithFileSystem())
                    QsRow(
                      title: s.destination,
                      value: settings.destination ?? t.settingsTab.receive.downloads,
                      onTap: () async {
                        final directory = await pickDirectoryPath();
                        if (directory != null) await ref.notifier(settingsProvider).setDestination(directory);
                      },
                      trailing: settings.destination == null
                          ? Icon(Icons.folder_open_outlined, color: p.sub)
                          : TextButton(onPressed: () async => ref.notifier(settingsProvider).setDestination(null), child: Text(s.reset)),
                    ),
                  QsSwitchRow(
                    title: t.settingsTab.receive.autoFinish,
                    hint: s.autoFinishDesc,
                    value: settings.autoFinish,
                    onChanged: (v) async => ref.notifier(settingsProvider).setAutoFinish(v),
                  ),
                  QsSwitchRow(
                    title: t.settingsTab.receive.saveToHistory,
                    hint: s.saveHistoryDesc,
                    value: settings.saveToHistory,
                    onChanged: (v) async => ref.notifier(settingsProvider).setSaveToHistory(v),
                  ),
                ],
              ),
              QsGroup(
                title: s.trustedDevices,
                children: favorites.isEmpty ? [QsRow(title: s.trustedEmpty)] : [for (final f in favorites) _TrustedRow(device: f)],
              ),
              QsGroup(
                title: s.secLook,
                children: [
                  QsRow(
                    title: s.language,
                    value: settings.locale?.getLocaleName() ?? t.settingsTab.general.languageOptions.system,
                    trailing: Icon(Icons.chevron_right, color: p.sub),
                    onTap: () async => context.push(() => const LanguagePage()),
                  ),
                  _ChoiceRow<ThemeMode>(
                    title: s.theme,
                    value: settings.theme,
                    label: switch (settings.theme) {
                      ThemeMode.system => s.themeSystem,
                      ThemeMode.light => s.themeLight,
                      ThemeMode.dark => s.themeDark,
                    },
                    options: [(ThemeMode.system, s.themeSystem), (ThemeMode.light, s.themeLight), (ThemeMode.dark, s.themeDark)],
                    onChanged: (v) async => ref.notifier(settingsProvider).setTheme(v),
                  ),
                  QsSwitchRow(
                    title: s.animations,
                    value: animations,
                    onChanged: (v) async => ref.notifier(settingsProvider).setEnableAnimations(v),
                  ),
                ],
              ),
              if (checkPlatformIsDesktop())
                QsGroup(
                  title: s.secDesktop,
                  children: [
                    QsSwitchRow(title: s.autostart, hint: s.autostartDesc, value: vm.autoStart, onChanged: (_) => vm.onToggleAutoStart(context)),
                    if (vm.autoStart)
                      QsSwitchRow(
                        title: s.startHidden,
                        hint: s.startHiddenDesc,
                        value: vm.autoStartLaunchHidden,
                        onChanged: (_) => vm.onToggleAutoStartLaunchHidden(context),
                      ),
                    if (checkPlatformHasTray())
                      QsSwitchRow(
                        title: s.background,
                        hint: s.backgroundDesc,
                        value: settings.minimizeToTray,
                        onChanged: (v) async => ref.notifier(settingsProvider).setMinimizeToTray(v),
                      ),
                    if (_contextMenu != null)
                      QsSwitchRow(
                        title: s.contextMenu,
                        hint: s.contextMenuDesc,
                        value: _contextMenu!,
                        onChanged: (v) async {
                          final ok = v ? await enableContextMenu(label: s.contextMenuLabel) : await disableContextMenu();
                          if (ok && mounted) setState(() => _contextMenu = v);
                        },
                      ),
                  ],
                ),
              QsGroup(
                title: s.secNetwork,
                children: [
                  QsRow(
                    title: s.serverTitle,
                    hint: running ? s.serverRunning(port: settings.port) : s.serverStopped,
                    trailing: IconButton(
                      tooltip: s.restart,
                      icon: Icon(Icons.refresh, color: p.accent),
                      onPressed: () async => running ? ref.notifier(serverProvider).restartServerFromSettings() : applyEffectiveVisibility(ref),
                    ),
                  ),
                  QsRow(
                    title: s.network,
                    value: settings.networkWhitelist != null || settings.networkBlacklist != null
                        ? (settings.networkWhitelist ?? settings.networkBlacklist)!.join(', ')
                        : s.allNetworks,
                    trailing: Icon(Icons.chevron_right, color: p.sub),
                    onTap: () async => context.push(() => const NetworkInterfacesPage()),
                  ),
                ],
              ),
              QsGroup(
                title: s.secPrivacy,
                children: [
                  QsRow(
                    title: s.privacyNotice,
                    onTap: () async => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: p.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(color: p.border, width: 0.8),
                        ),
                        title: Text(s.privacyNotice),
                        content: Text(s.privacyText, style: TextStyle(color: p.sub, height: 1.45)),
                        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.general.close))],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              QsGroup(
                children: [
                  if (Platform.isLinux)
                    QsSwitchRow(
                      title: s.autoUpdate,
                      hint: QsAutoUpdater.supported ? s.autoUpdateDesc : s.updateUnavailable,
                      value: QsAutoUpdater.supported && _autoUpdate,
                      onChanged: (v) async {
                        if (!QsAutoUpdater.supported) return;
                        await ref.read(persistenceProvider).setQsAutoUpdate(v);
                        setState(() => _autoUpdate = v);
                      },
                    ),
                  QsRow(title: s.aboutApp, onTap: () async => context.push(() => const AboutPage())),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _randomPin() => (Random.secure().nextInt(9000) + 1000).toString();

/// A row whose value is chosen from an animated popup menu.
class _ChoiceRow<T> extends StatelessWidget {
  final String title;
  final T value;
  final String label;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _ChoiceRow({required this.title, required this.value, required this.label, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return Builder(
      builder: (rowContext) => QsRow(
        title: title,
        value: label,
        onTap: () async {
          final box = rowContext.findRenderObject()! as RenderBox;
          final origin = box.localToGlobal(Offset(22, box.size.height - 6));
          final picked = await showMenu<T>(
            context: rowContext,
            color: p.card,
            position: RelativeRect.fromLTRB(origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.border, width: 0.8),
            ),
            popUpAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 220), reverseDuration: Duration(milliseconds: 140)),
            items: [
              for (final (v, text) in options)
                PopupMenuItem<T>(
                  value: v,
                  height: 48,
                  child: SizedBox(
                    width: 200,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(text, style: TextStyle(color: p.text, fontSize: 15)),
                        ),
                        if (v == value) Icon(Icons.check, size: 20, color: p.accent),
                      ],
                    ),
                  ),
                ),
            ],
          );
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
}

class _TrustedRow extends StatelessWidget {
  final FavoriteDevice device;

  const _TrustedRow({required this.device});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return QsRow(
      title: device.alias,
      hint: '${device.ip}:${device.port}',
      trailing: IconButton(
        tooltip: t.qsSettings.remove,
        icon: Icon(Icons.delete_outline, color: p.sub),
        onPressed: () async => context.ref.redux(favoritesProvider).dispatchAsync(RemoveFavoriteAction(deviceFingerprint: device.fingerprint)),
      ),
    );
  }
}
