import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_options_page.dart';
import 'package:localsend_app/pages/verify_page.dart';
import 'package:localsend_app/pages/web_share_page.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceivePageVm {
  final SessionStatus? status;
  final Device sender;

  /// Show verify button and device model.
  final bool showSenderInfo;
  final List<FileDto> files;
  final String? message;
  final bool isLink;
  final void Function() onAccept;
  final void Function() onDecline;
  final void Function() onClose;

  ReceivePageVm({
    required this.status,
    required this.sender,
    required this.showSenderInfo,
    required this.files,
    required this.message,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  }) : isLink = message != null && !message.trim().contains(RegExp(r'\s')) && (Uri.tryParse(message.trim())?.isAbsolute ?? false);
}

class ReceivePage extends StatefulWidget {
  final ViewProvider<ReceivePageVm> vm;

  const ReceivePage(this.vm);

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with Refena {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch(
      widget.vm,
      listener: (prev, next) {
        if (prev.status != next.status) {
          // ignore: discarded_futures
          TaskbarHelper.visualizeStatus(next.status);
        }
      },
    );

    if (vm.status == null && vm.message == null) {
      return const Scaffold(
        body: SizedBox(),
      );
    }

    final senderFavoriteEntry = ref.watch(favoritesProvider.select((state) => state.findDevice(vm.sender)));

    return ViewModelBuilder(
      provider: (ref) => widget.vm,
      dispose: (ref) {
        ref.dispose(widget.vm);
        unawaited(TaskbarHelper.clearProgressBar());
      },
      builder: (context, vm) {
        return PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              vm.onDecline();
            }
          },
          canPop: true,
          child: Builder(
            builder: (context) {
              final p = QsPalette(context);
              final alias = senderFavoriteEntry?.alias ?? vm.sender.alias;
              final height = MediaQuery.of(context).size.height;
              final smallUi = height < 600;
              return Scaffold(
                backgroundColor: p.bg,
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, smallUi ? 16 : 28, 20, 20),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    if (vm.showSenderInfo)
                                      Container(
                                        width: smallUi ? 64 : 84,
                                        height: smallUi ? 64 : 84,
                                        decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                                        child: Icon(vm.sender.deviceType.icon, size: smallUi ? 30 : 40, color: p.accent),
                                      ),
                                    const SizedBox(height: 14),
                                    Text(
                                      alias,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: smallUi ? 22 : 26, fontWeight: FontWeight.w700, color: p.text),
                                    ),
                                    if (vm.showSenderInfo && vm.sender.deviceModel != null) ...[
                                      const SizedBox(height: 8),
                                      _Chip(label: vm.sender.deviceModel!),
                                    ],
                                    const SizedBox(height: 14),
                                    Text(
                                      vm.message != null
                                          ? (vm.isLink ? t.receivePage.subTitleLink : t.receivePage.subTitleMessage)
                                          : t.receivePage.subTitle(n: vm.files.length),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 15, color: p.sub, height: 1.4),
                                    ),
                                    const SizedBox(height: 18),
                                    if (vm.message == null) _FileSummary(files: vm.files),
                                    if (vm.showSenderInfo && vm.message == null) ...[
                                      const SizedBox(height: 14),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _QsButton(
                                            icon: Icons.verified_user_outlined,
                                            label: t.verifyPage.title,
                                            onPressed: !vm.sender.https
                                                ? null
                                                : () async => await context.push(
                                                    () => VerifyPage(
                                                      fingerprint: CombinedFingerprint.load(context, vm.sender.fingerprint),
                                                    ),
                                                  ),
                                          ),
                                          _QsButton(
                                            icon: Icons.tune,
                                            label: t.receiveOptionsPage.title,
                                            onPressed: () async {
                                              await context.push(() => ReceiveOptionsPage(vm));
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (vm.message != null) ...[
                                      Container(
                                        constraints: const BoxConstraints(maxHeight: 160),
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: p.card,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: p.border, width: 0.8),
                                        ),
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(16),
                                          child: SelectableText(vm.message!, style: TextStyle(color: p.text, fontSize: 15)),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          if (vm.showSenderInfo)
                                            _QsButton(
                                              icon: Icons.verified_user_outlined,
                                              label: t.verifyPage.title,
                                              onPressed: () async => await context.push(
                                                () => VerifyPage(
                                                  fingerprint: CombinedFingerprint.load(context, vm.sender.fingerprint),
                                                ),
                                              ),
                                            ),
                                          _QsButton(
                                            icon: Icons.copy,
                                            label: t.general.copy,
                                            onPressed: () {
                                              unawaited(
                                                Clipboard.setData(ClipboardData(text: vm.message!)),
                                              );
                                              if (checkPlatformIsDesktop()) {
                                                context.showSnackBar(t.general.copiedToClipboard);
                                              }
                                              vm.onAccept();
                                              context.global.dispatch(NavigateAction.popUntil<WebSharePage>());
                                            },
                                          ),
                                          if (vm.isLink)
                                            _QsButton(
                                              icon: Icons.open_in_new,
                                              label: t.general.open,
                                              primary: true,
                                              onPressed: () {
                                                // ignore: discarded_futures
                                                launchUrl(Uri.parse(vm.message!), mode: LaunchMode.externalApplication);
                                                vm.onAccept();
                                                context.global.dispatch(NavigateAction.popUntil<WebSharePage>());
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _Actions(vm),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Up to four file names with sizes, then "+N".
class _FileSummary extends StatelessWidget {
  final List<FileDto> files;

  const _FileSummary({required this.files});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    if (files.isEmpty) return const SizedBox();
    const shown = 4;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border, width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final f in files.take(shown))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(f.fileType.icon, size: 20, color: p.sub),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(f.size.asReadableFileSize, style: TextStyle(fontSize: 13, color: p.sub)),
                ],
              ),
            ),
          if (files.length > shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('+${files.length - shown}', style: TextStyle(fontSize: 13, color: p.sub)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: p.sub, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Quick Send pill button: neutral chip, filled accent ([primary]) or red text ([danger]).
class _QsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final double height;

  const _QsButton({required this.icon, required this.label, required this.onPressed, this.primary = false, this.danger = false, this.height = 42});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final fg = primary ? Colors.white : (danger ? p.danger : p.text);
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: primary ? p.accent : p.chip,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final ReceivePageVm vm;

  const _Actions(this.vm);

  @override
  Widget build(BuildContext context) {
    final selectedFiles = context.watch(selectedReceivingFilesProvider);

    if (vm.message != null) {
      return Center(
        child: _QsButton(
          icon: Icons.close,
          label: t.general.close,
          height: 50,
          onPressed: () {
            vm.onAccept();
            context.global.dispatch(NavigateAction.popUntil<WebSharePage>());
          },
        ),
      );
    }

    if (vm.status == SessionStatus.canceledBySender) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              t.receivePage.canceled,
              style: TextStyle(color: QsPalette(context).danger, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: _QsButton(
              icon: Icons.close,
              label: t.general.close,
              height: 50,
              onPressed: () {
                vm.onClose();
                context.global.dispatch(NavigateAction.popUntil<WebSharePage>());
              },
            ),
          ),
        ],
      );
    }

    void decline() {
      vm.onDecline();
      context.global.dispatch(NavigateAction.popUntil<WebSharePage>());
    }

    final onAccept = selectedFiles.isEmpty ? null : vm.onAccept;

    return Column(
      children: [
        Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            final keyboard = HardwareKeyboard.instance;
            if (event is! KeyDownEvent || keyboard.isControlPressed || keyboard.isShiftPressed || keyboard.isAltPressed || keyboard.isMetaPressed) {
              return KeyEventResult.ignored;
            }
            switch (event.logicalKey) {
              case LogicalKeyboardKey.escape:
                decline();
                return KeyEventResult.handled;
              // Only while no button is focused, so that Enter still activates the focused button.
              case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter when node.hasPrimaryFocus:
                onAccept?.call();
                return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _QsButton(icon: Icons.close, label: t.general.decline, danger: true, height: 50, onPressed: decline),
              const SizedBox(width: 12),
              _QsButton(icon: Icons.check, label: t.general.accept, primary: true, height: 50, onPressed: onAccept),
            ],
          ),
        ),
      ],
    );
  }
}
