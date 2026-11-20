import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
import 'package:localsend_app/quick_send/qs_style.dart';
import 'package:localsend_app/quick_send/update_check_button.dart';
import 'package:localsend_app/util/i18n.dart';
import 'package:localsend_app/widget/quick_send_logo.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

part 'contributors.dart';

part 'packagers.dart';

part 'translators.dart';

final _translatorWithGithubRegex = RegExp(r'(.+) \(@([\w\-_]+)\)');

/// Quick Send repository (also where releases and the issue tracker are).
const _quickSendRepo = 'https://github.com/ensignalp/quick-send';

class AboutPage extends StatelessWidget {
  const AboutPage();

  @override
  Widget build(BuildContext context) {
    final p = QsPalette(context);
    final primaryColor = p.accent;
    final body = TextStyle(color: p.sub, height: 1.45);
    TextStyle heading() => TextStyle(fontWeight: FontWeight.w700, color: p.text);
    Widget open(String url, {bool external = true}) => Icon(external ? Icons.open_in_new : Icons.chevron_right, size: 20, color: p.sub);

    Widget creditTable(Map<String, List<String>> entries, String Function(String key) keyLabel) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        children: [
          for (final e in entries.entries)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 6),
                  child: Text(keyLabel(e.key), style: TextStyle(color: p.text, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(color: p.sub, fontSize: 13),
                      children: e.value
                          .mapIndexed((index, name) => _buildContributor(label: name, primaryColor: primaryColor, newLine: index != 0))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return QsPage(
      title: t.aboutPage.title,
      children: [
        const SizedBox(height: 8),
        const QuickSendLogo(withText: true),
        const SizedBox(height: 6),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) => Text(
            snapshot.hasData ? 'v${snapshot.data!.version}' : '',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub),
          ),
        ),
        const SizedBox(height: 14),
        QsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.aboutPage.description.join('\n\n'), style: body),
                  const SizedBox(height: 12),
                  Text(t.aboutPage.developer, style: heading()),
                  Text('Muhammed Alparslan Sancaktar · Ensignsoft', style: body),
                  const SizedBox(height: 12),
                  Text(t.aboutPage.attribution, style: body),
                ],
              ),
            ),
          ],
        ),
        QsGroup(
          children: [
            const UpdateCheckButton(),
            QsRow(
              title: 'Quick Send · GitHub',
              hint: _quickSendRepo.replaceFirst('https://', ''),
              trailing: open(_quickSendRepo),
              onTap: () async => launchUrl(Uri.parse(_quickSendRepo), mode: LaunchMode.externalApplication),
            ),
            QsRow(
              title: t.aboutPage.projectHomepage,
              hint: 'localsend.org',
              trailing: open('https://localsend.org'),
              onTap: () async => launchUrl(Uri.parse('https://localsend.org')),
            ),
            QsRow(
              title: t.aboutPage.upstreamGithub,
              trailing: open('https://github.com/localsend/localsend'),
              onTap: () async => launchUrl(Uri.parse('https://github.com/localsend/localsend'), mode: LaunchMode.externalApplication),
            ),
            QsRow(
              title: t.aboutPage.upstreamCodeberg,
              trailing: open('https://codeberg.org/localsend/localsend'),
              onTap: () async => launchUrl(Uri.parse('https://codeberg.org/localsend/localsend'), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        QsGroup(
          children: [
            QsRow(
              title: t.aboutPage.apacheLicense,
              trailing: open('https://www.apache.org/licenses/LICENSE-2.0'),
              onTap: () async => launchUrl(Uri.parse('https://www.apache.org/licenses/LICENSE-2.0')),
            ),
            QsRow(
              title: t.aboutPage.licenseNotices,
              trailing: open('', external: false),
              onTap: () async => context.push(() => const LicensePage()),
            ),
            QsRow(
              title: t.aboutPage.debugging,
              trailing: open('', external: false),
              onTap: () async => context.push(() => const DebugPage()),
            ),
          ],
        ),
        QsGroup(
          title: t.aboutPage.author,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: p.sub),
                  children: [
                    TextSpan(text: '© ${DateTime.now().year} '),
                    _buildContributor(label: 'Tien Do Nam (@Tienisto)', primaryColor: primaryColor),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Text(t.aboutPage.contributors, style: heading()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: p.sub, fontSize: 13),
                  children: _contributors
                      .mapIndexed((index, c) => _buildContributor(label: c, primaryColor: primaryColor, newLine: index != 0))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
        QsGroup(title: t.aboutPage.packagers, children: [creditTable(_packagers, (k) => k)]),
        QsGroup(
          title: t.aboutPage.translators,
          children: [
            creditTable({for (final e in _translators.entries) e.key.languageTag: e.value}, (k) => AppLocaleUtils.parse(k).getLocaleName()),
          ],
        ),
      ],
    );
  }
}

/// Displays the contributor name and links to their github profile.
InlineSpan _buildContributor({required String label, required Color primaryColor, bool newLine = false}) {
  final newLineStr = newLine ? '\n' : '';

  if (label.startsWith('@')) {
    // Only github name
    return TextSpan(
      text: '$newLineStr$label',
      style: TextStyle(color: primaryColor),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          await launchUrl(Uri.parse('https://github.com/${label.substring(1)}'), mode: LaunchMode.externalApplication);
        },
    );
  }

  final match = _translatorWithGithubRegex.firstMatch(label);
  if (match != null) {
    // Full name and github name
    final fullName = match.group(1)!;
    final githubName = match.group(2)!;
    return TextSpan(
      children: [
        TextSpan(text: '$newLineStr$fullName'),
        const TextSpan(text: ' '),
        TextSpan(
          text: '@$githubName',
          style: TextStyle(color: primaryColor),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              await launchUrl(Uri.parse('https://github.com/$githubName'), mode: LaunchMode.externalApplication);
            },
        ),
      ],
    );
  }

  // Only full name
  return TextSpan(text: '$newLineStr$label');
}
