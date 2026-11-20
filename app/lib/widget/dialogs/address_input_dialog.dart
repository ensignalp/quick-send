import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/ip_input_formatter.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _InputMode {
  hashtag,
  ip
  ;

  String get label {
    return switch (this) {
      _InputMode.hashtag => t.dialogs.addressInput.hashtag,
      _InputMode.ip => t.dialogs.addressInput.ip,
    };
  }
}

/// A dialog to input an hash or address.
/// Pops the dialog with the device if found.
class AddressInputDialog extends StatefulWidget {
  const AddressInputDialog();

  @override
  State<AddressInputDialog> createState() => _AddressInputDialogState();
}

class _AddressInputDialogState extends State<AddressInputDialog> with Refena {
  final _selected = List.generate(_InputMode.values.length, (index) => index == 0);
  _InputMode _mode = _InputMode.hashtag;
  String _input = '';
  bool _fetching = false;
  String? _error;

  /// Quick Send: network (IP prefix) the hashtag is tried on; [_allNetworks] tries every local network.
  static const _allNetworks = '';
  String _network = _allNetworks;

  Future<void> _submit(List<String> localIps, int port, [String? candidate]) async {
    final List<String> candidates;
    final String input = _input.trim();
    if (candidate != null) {
      candidates = [candidate];
    } else if (_mode == _InputMode.ip) {
      candidates = [input];
    } else {
      final networks = _network == _allNetworks ? localIps : localIps.where((ip) => ip.ipPrefix == _network);
      candidates = networks.map((ip) => '${ip.ipPrefix}.$input').toList();
    }

    // Quick Send: with no local IPv4 network found, "#" has nothing to try on; say so instead of doing nothing.
    if (candidates.isEmpty) {
      setState(() => _error = t.qsManual.noNetwork);
      return;
    }

    setState(() {
      _fetching = true;
    });

    final https = ref.read(settingsProvider).https;

    // Quick Send: every answering device is collected. When the number was tried on several
    // networks, the user always picks the device; one is never chosen automatically.
    final found = ValueNotifier<List<Device>>(const []);
    final firstFound = Completer<void>();
    String? error;

    final payload = ref.read(deviceFullInfoProvider).toRegisterDto();

    final List<Future<void>> futures = [
      for (final ip in candidates)
        () async {
          try {
            final response = await ref
                .read(httpProvider)
                .discovery
                .register(
                  protocol: https ? ProtocolType.https : ProtocolType.http,
                  ip: ip,
                  port: port,
                  payload: payload,
                );

            final device = response.body.toDevice(ip, port, https);
            if (!found.value.any((d) => d.fingerprint == device.fingerprint)) {
              found.value = [...found.value, device];
            }
            if (!firstFound.isCompleted) {
              firstFound.complete();
            }
          } catch (e) {
            error = e.toString();
          }
        }(),
    ];
    final allDone = Future.wait(futures);

    // Wait until,
    // - a device is found
    // - all candidates are checked
    await Future.any([firstFound.future, allDone]);

    if (!mounted) {
      return;
    }

    Device? device = found.value.firstOrNull;
    if (device != null && candidates.length > 1) {
      device = await showDialog<Device>(
        context: context,
        builder: (_) => _DeviceChoiceDialog(found: found, searching: allDone),
      );
      if (!mounted) {
        return;
      }
    }

    if (device != null) {
      ref.redux(lastDevicesProvider).dispatch(AddLastDeviceAction(device));
      context.pop(device);
    } else {
      setState(() {
        _fetching = false;
        _error = found.value.isEmpty ? error : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localIps = (ref.watch(localIpProvider.select((info) => info.localIps))).uniqueIpPrefix;
    final settings = ref.watch(settingsProvider);
    final lastDevices = ref.watch(lastDevicesProvider);
    final p = QsPalette(context);
    final hint = TextStyle(color: p.sub, fontSize: 13, height: 1.4);
    final prefix = localIps.firstOrNull?.ipPrefix ?? '192.168.1';
    final canSubmit = !_fetching && (_mode == _InputMode.hashtag ? _input.isNotEmpty : isCompleteIpv4(_input.trim()));

    // Quick Send design; behaviour as in LocalSend: "#" + the last part of an address is tried on this
    // device's own networks (192.168.1.# …), or a full IP address is entered.
    return AlertDialog(
      backgroundColor: p.card,
      shape: qsDialogShape(p),
      title: Text(
        t.dialogs.addressInput.title,
        style: TextStyle(fontWeight: FontWeight.w700, color: p.text),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QsSegmented<_InputMode>(
              value: _mode,
              options: [for (final m in _InputMode.values) (m, m.label)],
              onChanged: (m) => setState(() {
                for (int i = 0; i < _selected.length; i++) {
                  _selected[i] = _InputMode.values[i] == m;
                }
                _mode = m;
                _input = '';
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey('input-$_mode'),
              autofocus: true,
              enabled: !_fetching,
              keyboardType: TextInputType.number,
              inputFormatters: [if (_mode == _InputMode.hashtag) HashtagInputFormatter() else Ipv4InputFormatter()],
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.text, letterSpacing: 0.5),
              decoration: InputDecoration(
                prefixText: _mode == _InputMode.hashtag ? '# ' : null,
                hintText: _mode == _InputMode.hashtag ? '123' : '$prefix.123',
              ),
              onChanged: (s) => setState(() {
                _input = s;
                _error = null;
              }),
              onFieldSubmitted: (s) async {
                if (canSubmit || (_mode == _InputMode.ip && isCompleteIpv4(s.trim()))) await _submit(localIps, settings.port);
              },
            ),
            const SizedBox(height: 10),
            if (_mode == _InputMode.hashtag) ...[
              if (localIps.isEmpty)
                Text(t.qsManual.noNetwork, style: hint)
              else if (localIps.length == 1)
                Text('${t.dialogs.addressInput.ip}: $prefix.${_input.isEmpty ? '…' : _input}', style: hint)
              else
                // Quick Send: several local networks; the user picks which one(s) the number is tried on.
                Row(
                  children: [
                    Text('${t.shareHome.network}: ', style: hint),
                    Flexible(
                      child: QsDropdown<String>(
                        value: localIps.any((ip) => ip.ipPrefix == _network) ? _network : _allNetworks,
                        options: [
                          (_allNetworks, t.qsSettings.allNetworks),
                          for (final ip in localIps) (ip.ipPrefix, '${ip.ipPrefix}.${_input.isEmpty ? '…' : _input}'),
                        ],
                        onChanged: (network) => setState(() => _network = network),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(t.qsManual.hashtagHint, style: hint),
            ] else if (lastDevices.isNotEmpty) ...[
              Text(t.dialogs.addressInput.recentlyUsed, style: hint),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final device in lastDevices)
                    if (device.ip != null)
                      ActionChip(
                        label: Text(device.ip!),
                        backgroundColor: p.chip,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        onPressed: _fetching ? null : () async => _submit(localIps, settings.port, device.ip),
                      ),
                ],
              ),
            ],
            if (_fetching)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
                    const SizedBox(width: 10),
                    Text(t.qsManual.searching, style: hint),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _error == t.qsManual.noNetwork
                      ? null
                      : () async => showDialog(
                          context: context,
                          builder: (_) => ErrorDialog(error: _error!),
                        ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: p.danger, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _error == t.qsManual.noNetwork ? t.qsManual.noNetwork : t.qsManual.notFound,
                          style: TextStyle(color: p.danger, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: canSubmit ? () async => _submit(localIps, settings.port) : null,
          child: Text(t.general.confirm),
        ),
      ],
    );
  }
}

extension on String {
  String get ipPrefix {
    return split('.').take(3).join('.');
  }
}

extension on List<String> {
  List<String> get uniqueIpPrefix {
    final seen = <String>{};
    return where((s) => seen.add(s.ipPrefix)).toList();
  }
}

/// Quick Send: lists the devices that answered on different networks so the user picks one.
/// The list grows while the remaining networks are still being checked.
class _DeviceChoiceDialog extends StatelessWidget {
  final ValueNotifier<List<Device>> found;
  final Future<void> searching;

  const _DeviceChoiceDialog({required this.found, required this.searching});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return AlertDialog(
      backgroundColor: p.card,
      shape: qsDialogShape(p),
      title: Text(t.shareHome.chooseDevice),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.shareHome.chooseDeviceHint),
            const SizedBox(height: 12),
            ValueListenableBuilder<List<Device>>(
              valueListenable: found,
              builder: (context, devices, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final device in devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(device.deviceType.icon),
                      title: Text(device.alias),
                      subtitle: Text([device.ip, device.deviceModel].nonNulls.join(' · ')),
                      onTap: () => Navigator.of(context).pop(device),
                    ),
                ],
              ),
            ),
            FutureBuilder<void>(
              future: searching,
              builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(t.shareHome.searchingNetworks, style: TextStyle(color: p.sub)),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.general.cancel),
        ),
      ],
    );
  }
}
