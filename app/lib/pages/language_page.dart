import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Quick Send: language choice in the app's design language (one bordered group, a check on the active entry).
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final p = QsPalette(context);
    final activeLocale = context.ref.watch(settingsProvider.select((s) => s.locale));
    return QsPage(
      title: t.settingsTab.general.language,
      children: [
        QsGroup(
          children: [
            for (final locale in [null, ...AppLocale.values])
              QsRow(
                title: locale?.getLocaleName() ?? t.settingsTab.general.languageOptions.system,
                trailing: Icon(Icons.check, size: 20, color: locale == activeLocale ? p.accent : Colors.transparent),
                onTap: () async {
                  await context.ref.notifier(settingsProvider).setLocale(locale);
                  if (locale == null) {
                    await LocaleSettings.useDeviceLocale();
                  } else {
                    await LocaleSettings.setLocale(locale);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}
