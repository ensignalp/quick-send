// Quick Send: "Over the internet" page (desktop). Send the current selection
// with a code (shown as text and QR code) or receive files with a code.
// Sharing lasts while this page is open.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/internet_transfer.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum _Step { menu, preparing, sharing, enter, receiving, received, error }

class QsInternetPage extends StatefulWidget {
  const QsInternetPage({super.key});

  @override
  State<QsInternetPage> createState() => _QsInternetPageState();
}

class _QsInternetPageState extends State<QsInternetPage> with Refena {
  _Step _step = _Step.menu;
  QsInternetTransfer? _transfer;
  StreamSubscription<QsInternetEvent>? _sub;
  final _codeController = TextEditingController();
  String _code = '';
  bool _peer = false;
  int _sent = 0;
  int _done = 0;
  int _total = 0;
  int _receivedCount = 0;
  String _destination = '';
  String _error = '';

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_transfer?.stop());
    _codeController.dispose();
    super.dispose();
  }

  void _listen(QsInternetTransfer transfer) {
    _transfer = transfer;
    _sub = transfer.events.listen((e) {
      if (!mounted) return;
      setState(() {
        switch (e.type) {
          case 'ticket':
            _code = e.data['ticket'] as String? ?? '';
            _step = _Step.sharing;
          case 'peerConnected':
            _peer = true;
          case 'sent':
            _sent = (e.data['count'] as num?)?.toInt() ?? _sent + 1;
          case 'connecting':
            _step = _Step.receiving;
          case 'progress':
            _step = _Step.receiving;
            _done = (e.data['done'] as num?)?.toInt() ?? 0;
            _total = (e.data['total'] as num?)?.toInt() ?? 0;
          case 'received':
            _receivedCount = (e.data['files'] as List?)?.length ?? 0;
            _step = _Step.received;
          case 'error':
            _error = e.data['message'] as String? ?? '';
            _step = _Step.error;
        }
      });
    });
  }

  Future<void> _send() async {
    final paths = ref.read(selectedSendingFilesProvider).map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    setState(() => _step = _Step.preparing);
    try {
      _listen(await QsInternet.send(paths));
    } catch (e) {
      setState(() {
        _error = '$e';
        _step = _Step.error;
      });
    }
  }

  Future<void> _receive() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    _destination = ref.read(settingsProvider).destination ?? await getDefaultDestinationDirectory();
    setState(() {
      _done = 0;
      _total = 0;
      _step = _Step.receiving;
    });
    try {
      _listen(await QsInternet.receive(code, _destination));
    } catch (e) {
      setState(() {
        _error = '$e';
        _step = _Step.error;
      });
    }
  }

  Future<void> _reset() async {
    await _sub?.cancel();
    await _transfer?.stop();
    _sub = null;
    _transfer = null;
    if (mounted) {
      setState(() {
        _step = _Step.menu;
        _peer = false;
        _sent = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final s = t.qsInternet;
    final files = context.watch(selectedSendingFilesProvider).where((f) => f.path != null).toList();
    final size = files.fold<int>(0, (sum, f) => sum + f.size);
    Widget note(String text, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
      child: Text(text, style: TextStyle(color: color ?? p.sub, height: 1.45)),
    );
    Widget buttons(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: children),
    );

    final List<Widget> body = switch (_step) {
      _Step.menu => [
        note(QsInternet.available ? s.intro : s.unavailable),
        if (QsInternet.available)
          QsGroup(
            children: [
              QsRow(
                title: s.send,
                hint: files.isEmpty ? s.pickFirst : '${t.shareHome.items(n: files.length)} · ${size.asReadableFileSize}',
                trailing: Icon(Icons.upload_rounded, color: files.isEmpty ? p.faint : p.accent),
                onTap: files.isEmpty ? null : _send,
              ),
              QsRow(
                title: s.receive,
                hint: s.receiveHint,
                trailing: Icon(Icons.download_rounded, color: p.accent),
                onTap: () => setState(() => _step = _Step.enter),
              ),
            ],
          ),
      ],
      _Step.preparing => [note(s.preparing)],
      _Step.sharing => [
        note(s.shareCode),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: SizedBox(
              width: 200,
              height: 200,
              child: PrettyQrView.data(
                data: _code,
                errorCorrectLevel: QrErrorCorrectLevel.L,
                decoration: const PrettyQrDecoration(shape: PrettyQrSmoothSymbol(roundFactor: 0, color: Colors.black)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.border, width: 0.8),
          ),
          child: SelectableText(_code, style: TextStyle(fontSize: 12, color: p.text, height: 1.4)),
        ),
        note(_sent > 0 ? s.sent : (_peer ? s.peerConnected : s.waiting), color: _sent > 0 ? p.accent : null),
        buttons([
          OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.stop), label: Text(s.stop)),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _code));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.general.copiedToClipboard)));
            },
            icon: const Icon(Icons.copy),
            label: Text(t.general.copy),
          ),
        ]),
      ],
      _Step.enter => [
        note(s.enterCode),
        TextField(
          controller: _codeController,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          style: TextStyle(fontSize: 13, color: p.text),
          decoration: const InputDecoration(hintText: 'blob…'),
          onSubmitted: (_) => _receive(),
        ),
        buttons([
          OutlinedButton(onPressed: _reset, child: Text(t.general.cancel)),
          FilledButton.icon(onPressed: _receive, icon: const Icon(Icons.download), label: Text(s.receiveButton)),
        ]),
      ],
      _Step.receiving => [
        note(_total > 0 ? '${_done.asReadableFileSize} / ${_total.asReadableFileSize}' : s.connecting),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: _total > 0 ? _done / _total : null, minHeight: 8, color: p.accent, backgroundColor: p.chip),
        ),
        buttons([OutlinedButton(onPressed: _reset, child: Text(t.general.cancel))]),
      ],
      _Step.received => [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t.shareHome.received,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text),
          ),
        ),
        note('${t.shareHome.receivedFiles(n: _receivedCount)} · $_destination'),
        buttons([
          OutlinedButton.icon(
            onPressed: () async => openFolder(folderPath: _destination),
            icon: const Icon(Icons.folder_open),
            label: Text(s.openFolder),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.general.done)),
        ]),
      ],
      _Step.error => [
        note('${s.failed}${_error.isEmpty ? '' : '\n$_error'}', color: p.danger),
        buttons([FilledButton(onPressed: _reset, child: Text(t.general.close))]),
      ],
    };

    return QsPage(title: s.title, children: body);
  }
}
