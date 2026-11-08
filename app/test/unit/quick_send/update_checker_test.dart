import 'package:localsend_app/quick_send/update_checker.dart';
import 'package:test/test.dart';

void main() {
  group('isNewerVersion', () {
    test('compares semantic versions', () {
      expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
      expect(isNewerVersion('1.0.0', '0.99.99'), isTrue);
      expect(isNewerVersion('v0.1.0', '0.1.0'), isFalse);
      expect(isNewerVersion('0.1.0', '0.2.0'), isFalse);
      expect(isNewerVersion('0.1.1+5', '0.1.0'), isTrue);
    });
    test('rejects malformed input', () {
      expect(isNewerVersion('latest', '0.1.0'), isFalse);
      expect(parseVersion('1.2'), isNull);
    });
  });

  group('evaluateRelease', () {
    const repo = 'owner/quick-send';
    test('reports update with trusted release URL', () {
      final r = evaluateRelease({'tag_name': 'v0.2.0', 'html_url': 'https://github.com/owner/quick-send/releases/tag/v0.2.0'}, '0.1.0', repo);
      expect(r, isA<UpdateAvailable>());
      expect((r as UpdateAvailable).version, '0.2.0');
      expect(r.releaseUrl.toString(), 'https://github.com/owner/quick-send/releases/tag/v0.2.0');
    });
    test('ignores foreign release URLs', () {
      final r = evaluateRelease({'tag_name': 'v0.2.0', 'html_url': 'https://evil.example/x'}, '0.1.0', repo) as UpdateAvailable;
      expect(r.releaseUrl.toString(), 'https://github.com/owner/quick-send/releases/latest');
    });
    test('up to date and failure cases', () {
      expect(evaluateRelease({'tag_name': 'v0.1.0'}, '0.1.0', repo), isA<UpToDate>());
      expect(evaluateRelease({}, '0.1.0', repo), isA<UpdateCheckFailed>());
    });
  });

  test('unconfigured repository makes no request', () async {
    expect(await checkForUpdate('0.1.0', repo: ''), isA<UpdateCheckNotConfigured>());
  });
}
