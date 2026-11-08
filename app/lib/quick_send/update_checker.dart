// Quick Send addition (not part of upstream LocalSend).
// User-triggered update check: exactly one GET to the GitHub Releases API per
// button press. Never called automatically or in the background.
// The repository is injected at build time (CI passes github.repository):
//   flutter build linux --dart-define=QS_RELEASES_REPO=owner/repo
import 'dart:convert';
import 'dart:io';

const quickSendReleasesRepo = String.fromEnvironment('QS_RELEASES_REPO');

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  final String version;
  final Uri releaseUrl;
  const UpdateAvailable(this.version, this.releaseUrl);
}

class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed();
}

class UpdateCheckNotConfigured extends UpdateCheckResult {
  const UpdateCheckNotConfigured();
}

final _repoPattern = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

/// Parses "v1.2.3", "1.2.3", "1.2.3+4", "1.2.3-beta" into [major, minor, patch].
List<int>? parseVersion(String raw) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(raw.trim());
  if (m == null) return null;
  return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
}

/// True when [latest] is strictly newer than [current].
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Interprets a GitHub `releases/latest` JSON body.
UpdateCheckResult evaluateRelease(Map<String, dynamic> json, String currentVersion, String repo) {
  final tag = json['tag_name'];
  if (tag is! String || parseVersion(tag) == null) return const UpdateCheckFailed();
  if (!isNewerVersion(tag, currentVersion)) return const UpToDate();
  final expectedPrefix = 'https://github.com/$repo/';
  final html = json['html_url'];
  final url = html is String && html.startsWith(expectedPrefix) ? Uri.parse(html) : Uri.parse('https://github.com/$repo/releases/latest');
  return UpdateAvailable(tag.replaceFirst(RegExp('^v'), ''), url);
}

Future<UpdateCheckResult> checkForUpdate(String currentVersion, {String repo = quickSendReleasesRepo}) async {
  if (!_repoPattern.hasMatch(repo)) return const UpdateCheckNotConfigured();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.https('api.github.com', '/repos/$repo/releases/latest'));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'QuickSend-UpdateCheck');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return const UpdateCheckFailed();
    final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const UpdateCheckFailed();
    return evaluateRelease(decoded, currentVersion, repo);
  } catch (_) {
    return const UpdateCheckFailed();
  } finally {
    client.close(force: true);
  }
}
