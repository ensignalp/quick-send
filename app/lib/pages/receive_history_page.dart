import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _EntryOption {
  open,
  showInFolder,
  info,
  delete
  ;

  String get label {
    return switch (this) {
      _EntryOption.open => t.receiveHistoryPage.entryActions.open,
      _EntryOption.showInFolder => t.receiveHistoryPage.entryActions.showInFolder,
      _EntryOption.info => t.receiveHistoryPage.entryActions.info,
      _EntryOption.delete => t.receiveHistoryPage.entryActions.deleteFromHistory,
    };
  }
}

const _optionsAll = _EntryOption.values;
final _optionsWithoutOpen = [_EntryOption.info, _EntryOption.delete];

/// Quick Send: type filter of the recent activity page.
enum _TypeFilter { all, images, videos, documents, messages, other }

/// Quick Send: date filter of the recent activity page.
enum _DateFilter { all, today, week, month, range }

class ReceiveHistoryPage extends StatefulWidget {
  const ReceiveHistoryPage({super.key});

  @override
  State<ReceiveHistoryPage> createState() => _ReceiveHistoryPageState();
}

class _ReceiveHistoryPageState extends State<ReceiveHistoryPage> {
  _TypeFilter _type = _TypeFilter.all;
  _DateFilter _date = _DateFilter.all;
  DateTimeRange? _range;

  Future<void> _openFile(
    BuildContext context,
    ReceiveHistoryEntry entry,
    Dispatcher<ReceiveHistoryService, List<ReceiveHistoryEntry>> dispatcher,
  ) async {
    if (entry.path != null) {
      await openFile(
        context,
        entry.fileType,
        entry.path!,
        onDeleteTap: () => dispatcher.dispatchAsync(RemoveHistoryEntryAction(entry.id)),
      );
    }
  }

  bool _matchesType(ReceiveHistoryEntry e) => switch (_type) {
    _TypeFilter.all => true,
    _TypeFilter.images => !e.isMessage && e.fileType == FileType.image,
    _TypeFilter.videos => !e.isMessage && e.fileType == FileType.video,
    _TypeFilter.documents => !e.isMessage && (e.fileType == FileType.pdf || e.fileType == FileType.text),
    _TypeFilter.messages => e.isMessage,
    _TypeFilter.other => !e.isMessage && (e.fileType == FileType.apk || e.fileType == FileType.other),
  };

  bool _matchesDate(ReceiveHistoryEntry e, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final t = e.timestamp.toLocal();
    return switch (_date) {
      _DateFilter.all => true,
      _DateFilter.today => !t.isBefore(day),
      _DateFilter.week => !t.isBefore(day.subtract(const Duration(days: 6))),
      _DateFilter.month => !t.isBefore(day.subtract(const Duration(days: 29))),
      _DateFilter.range => _range == null || (!t.isBefore(_range!.start) && t.isBefore(_range!.end.add(const Duration(days: 1)))),
    };
  }

  String _dayLabel(BuildContext context, DateTime time, DateTime now) {
    final day = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return t.qsHistory.today;
    if (day == today.subtract(const Duration(days: 1))) return t.qsHistory.yesterday;
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final h = t.qsHistory;
    final all = context.watch(receiveHistoryProvider);
    final now = DateTime.now();
    final entries = all.where((e) => _matchesType(e) && _matchesDate(e, now)).toList();
    final dateLabel = switch (_date) {
      _DateFilter.all => h.anyTime,
      _DateFilter.today => h.today,
      _DateFilter.week => h.last7,
      _DateFilter.month => h.last30,
      _DateFilter.range =>
        _range == null
            ? h.pickRange
            : '${MaterialLocalizations.of(context).formatShortDate(_range!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_range!.end)}',
    };
    String typeLabel(_TypeFilter f) => switch (f) {
      _TypeFilter.all => h.all,
      _TypeFilter.images => h.images,
      _TypeFilter.videos => h.videos,
      _TypeFilter.documents => h.documents,
      _TypeFilter.messages => h.messages,
      _TypeFilter.other => h.other,
    };

    // Entries grouped by day, newest first (the provider keeps them in that order).
    final groups = <String, List<ReceiveHistoryEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(_dayLabel(context, e.timestamp.toLocal(), now), () => []).add(e);
    }

    return QsPage(
      title: t.receiveHistoryPage.title,
      actions: [
        if (!checkPlatform([TargetPlatform.iOS]))
          IconButton(
            tooltip: t.receiveHistoryPage.openFolder,
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final configured = context.read(settingsProvider).destination;
              final destination = configured ?? await getDefaultDestinationDirectory();
              await openFolder(folderPath: destination);
            },
          ),
        IconButton(
          tooltip: t.receiveHistoryPage.deleteHistory,
          icon: const Icon(Icons.delete_outline),
          onPressed: all.isEmpty
              ? null
              : () async {
                  final result = await showDialog(context: context, builder: (_) => const HistoryClearDialog());
                  if (context.mounted && result == true) {
                    await context.redux(receiveHistoryProvider).dispatchAsync(RemoveAllHistoryEntriesAction());
                  }
                },
        ),
        const SizedBox(width: 6),
      ],
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (final f in _TypeFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(typeLabel(f)),
                    selected: _type == f,
                    showCheckmark: false,
                    backgroundColor: p.chip,
                    selectedColor: p.navActive,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(color: _type == f ? p.text : p.sub, fontWeight: _type == f ? FontWeight.w700 : FontWeight.w500),
                    onSelected: (_) => setState(() => _type = f),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 18, color: p.sub),
              const SizedBox(width: 8),
              QsDropdown<_DateFilter>(
                value: _date,
                options: [
                  (_DateFilter.all, h.anyTime),
                  (_DateFilter.today, h.today),
                  (_DateFilter.week, h.last7),
                  (_DateFilter.month, h.last30),
                  (_DateFilter.range, _date == _DateFilter.range ? dateLabel : h.pickRange),
                ],
                onChanged: (f) async {
                  if (f == _DateFilter.range) {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(now.year, now.month, now.day),
                      initialDateRange: _range,
                    );
                    if (picked == null) return;
                    setState(() {
                      _range = picked;
                      _date = f;
                    });
                  } else {
                    setState(() => _date = f);
                  }
                },
              ),
            ],
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Column(
              children: [
                Icon(Icons.history, size: 48, color: p.faint),
                const SizedBox(height: 12),
                Text(
                  all.isEmpty ? t.receiveHistoryPage.empty : h.noMatch,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub, fontSize: 16),
                ),
              ],
            ),
          )
        else
          for (final group in groups.entries)
            QsGroup(
              title: group.key,
              children: [for (final entry in group.value) _entryRow(context, p, entry)],
            ),
      ],
    );
  }

  Widget _entryRow(BuildContext context, QsPalette p, ReceiveHistoryEntry entry) {
    Future<void> onTap() async {
      if (entry.isMessage) {
        final vm = ViewProvider((ref) {
          return ReceivePageVm(
            status: SessionStatus.waiting,
            sender: Device(
              signalingId: null,
              ip: '0.0.0.0',
              version: '1.0.0',
              port: 8080,
              https: false,
              fingerprint: 'fingerprint',
              alias: entry.senderAlias,
              deviceModel: 'deviceModel',
              deviceType: DeviceType.web,
              download: true,
              channels: const [],
            ),
            showSenderInfo: false,
            files: [],
            message: entry.fileName,
            onAccept: () {},
            onDecline: () {},
            onClose: () {},
          );
        });

        // ignore: unawaited_futures
        context.push(() => ReceivePage(vm));
        return;
      }
      await _openFile(context, entry, context.redux(receiveHistoryProvider));
    }

    return InkWell(
      onTap: entry.path != null || entry.isMessage ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FilePathThumbnail(path: entry.path, fileType: entry.fileType),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${TimeOfDay.fromDateTime(entry.timestamp.toLocal()).format(context)} · ${entry.fileSize.asReadableFileSize} · ${entry.senderAlias}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.sub),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_EntryOption>(
              color: p.card,
              shape: qsMenuShape(p),
              popUpAnimationStyle: qsMenuAnimation,
              icon: Icon(Icons.more_vert, color: p.sub),
              onSelected: (_EntryOption item) async {
                switch (item) {
                  case _EntryOption.open:
                    await _openFile(context, entry, context.redux(receiveHistoryProvider));
                  case _EntryOption.showInFolder:
                    if (entry.path != null) {
                      await openFolder(folderPath: File(entry.path!).parent.path, fileName: path.basename(entry.path!));
                    }
                  case _EntryOption.info:
                    await showDialog(
                      context: context,
                      builder: (_) => FileInfoDialog(entry: entry),
                    );
                  case _EntryOption.delete:
                    await context.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id));
                }
              },
              itemBuilder: (BuildContext context) => [
                for (final e in (entry.path != null ? _optionsAll : _optionsWithoutOpen))
                  qsMenuItem(
                    p,
                    e,
                    switch (e) {
                      _EntryOption.open => Icons.open_in_new,
                      _EntryOption.showInFolder => Icons.folder_open,
                      _EntryOption.info => Icons.info_outline,
                      _EntryOption.delete => Icons.delete_outline,
                    },
                    e.label,
                    color: e == _EntryOption.delete ? p.danger : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
