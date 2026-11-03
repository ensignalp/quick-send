import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:test/test.dart';

void main() {
  group('i18n', () {
    test('Should compile', () {
      // The following test will fail if the i18n file is either not compiled
      // or there are compile-time errors.
      expect(AppLocale.en.translations.general.accept, 'Accept');
    });

    test('All locales should be supported by Flutter', () {
      for (final locale in AppLocale.values) {
        expect(kMaterialSupportedLanguages, contains(locale.languageCode));
      }
    });

    test('Every locale uses the Quick Send product name', () {
      for (final locale in AppLocale.values) {
        expect(locale.translations.appName, 'Quick Send', reason: locale.name);
      }
    });

    test('English and Turkish retain the LocalSend attribution', () async {
      final en = await AppLocale.en.build();
      final tr = await AppLocale.tr.build();
      expect(en.aboutPage.attribution, contains('LocalSend'));
      expect(tr.aboutPage.attribution, contains('LocalSend'));
      expect(en.aboutPage.description.last, contains('Android and Linux'));
      expect(tr.aboutPage.description.last, contains('Android ve Linux'));
    });
  });
}
