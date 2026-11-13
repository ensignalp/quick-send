import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_isolates/util/network_interfaces.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Quick Send: network interface filter in the app's design language.
/// Behaviour is unchanged from LocalSend: either no filter, a whitelist or a blacklist of
/// interface addresses (wildcards allowed), edited as a list.
class NetworkInterfacesPage extends StatefulWidget {
  const NetworkInterfacesPage();

  @override
  State<NetworkInterfacesPage> createState() => _NetworkInterfacesPageState();
}

enum _FilterMode { all, whitelist, blacklist }

class _NetworkInterfacesPageState extends State<NetworkInterfacesPage> {
  List<(String, List<String>)> rawInterfaces = [];

  @override
  void initState() {
    super.initState();

    // ignore: discarded_futures
    getNetworkInterfaces(whitelist: null, blacklist: null).then((value) {
      if (mounted) {
        setState(() {
          rawInterfaces = value.map((e) => (e.name, e.addresses.map((a) => a.address).toList())).toList();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final settings = context.watch(settingsProvider);
    final notifier = context.notifier(settingsProvider);
    final currList = settings.networkWhitelist ?? settings.networkBlacklist ?? [];
    final mode = settings.networkWhitelist != null
        ? _FilterMode.whitelist
        : settings.networkBlacklist != null
        ? _FilterMode.blacklist
        : _FilterMode.all;
    final Future<void> Function(List<String>?) updateFunction = mode == _FilterMode.whitelist
        ? notifier.setNetworkWhitelist
        : notifier.setNetworkBlacklist;

    Future<void> setMode(_FilterMode next) async {
      if (next == mode) return;
      final carried = switch (currList) {
        [] => [''],
        _ => [...currList],
      };
      switch (next) {
        case _FilterMode.all:
          await notifier.setNetworkWhitelist(null);
          await notifier.setNetworkBlacklist(null);
        case _FilterMode.whitelist:
          await notifier.setNetworkWhitelist(carried);
          await notifier.setNetworkBlacklist(null);
        case _FilterMode.blacklist:
          await notifier.setNetworkBlacklist(carried);
          await notifier.setNetworkWhitelist(null);
      }
    }

    String modeLabel(_FilterMode m) => switch (m) {
      _FilterMode.all => t.qsSettings.allNetworks,
      _FilterMode.whitelist => t.networkInterfacesPage.whitelist,
      _FilterMode.blacklist => t.networkInterfacesPage.blacklist,
    };

    return QsPage(
      title: t.networkInterfacesPage.title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Text(t.networkInterfacesPage.info, style: TextStyle(color: p.sub, height: 1.45)),
        ),
        QsGroup(
          title: t.networkInterfacesPage.preview,
          children: [
            for (final (i, e) in rawInterfaces.indexed)
              _InterfaceRow(
                index: i + 1,
                name: e.$1,
                addresses: e.$2,
                ignored: isNetworkIgnoredRaw(
                  networkWhitelist: settings.networkWhitelist,
                  networkBlacklist: settings.networkBlacklist,
                  interface: e.$2,
                ),
              ),
            if (rawInterfaces.isEmpty) QsRow(title: '…'),
          ],
        ),
        QsGroup(
          children: [
            for (final m in _FilterMode.values)
              QsRow(
                title: modeLabel(m),
                trailing: Icon(Icons.check, size: 20, color: m == mode ? p.accent : Colors.transparent),
                onTap: () async => setMode(m),
              ),
          ],
        ),
        if (mode != _FilterMode.all)
          QsGroup(
            title: modeLabel(mode),
            children: [
              ...currList.mapIndexed(
                (i, e) => _AddressField(
                  key: ValueKey('$mode-$i'),
                  value: e,
                  hint: '${t.general.example}: 123.123.123.*',
                  onChanged: (value) async => updateFunction([...currList.sublist(0, i), value, ...currList.sublist(i + 1)]),
                  onDelete: () async {
                    if (currList.length == 1) {
                      await setMode(_FilterMode.all);
                      return;
                    }
                    await updateFunction([...currList.sublist(0, i), ...currList.sublist(i + 1)]);
                  },
                ),
              ),
              QsRow(
                title: t.general.add,
                trailing: Icon(Icons.add, size: 20, color: p.accent),
                onTap: () async => updateFunction([...currList, '']),
              ),
            ],
          ),
      ],
    );
  }
}

class _InterfaceRow extends StatelessWidget {
  final int index;
  final String name;
  final List<String> addresses;
  final bool ignored;

  const _InterfaceRow({required this.index, required this.name, required this.addresses, required this.ignored});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final decoration = ignored ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Icon(ignored ? Icons.wifi_off_rounded : Icons.wifi_rounded, size: 20, color: ignored ? p.faint : p.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$index  $name',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ignored ? p.faint : p.text, decoration: decoration),
                ),
                const SizedBox(height: 2),
                Text(
                  addresses.join(', '),
                  style: TextStyle(fontSize: 13, color: ignored ? p.faint : p.sub, decoration: decoration),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;

  const _AddressField({required this.value, required this.hint, required this.onChanged, required this.onDelete, super.key});

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: StringField(
              value: value,
              onChanged: onChanged,
              builder: (context, controller) => TextField(
                controller: controller,
                style: TextStyle(fontSize: 15, color: p.text),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: p.faint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: Icon(Icons.close, size: 20, color: p.sub),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
