// Quick Send: user-triggered update check. One GET to the GitHub Releases API
// per button press; never runs automatically or in the background.

export type UpdateResult =
  | { kind: 'available'; version: string; url: string }
  | { kind: 'upToDate' }
  | { kind: 'failed' }
  | { kind: 'notConfigured' };

const repoPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export function parseVersion(raw: string): number[] | null {
  const m = /^v?(\d+)\.(\d+)\.(\d+)/.exec(raw.trim());
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null;
}

export function isNewerVersion(latest: string, current: string): boolean {
  const a = parseVersion(latest);
  const b = parseVersion(current);
  if (!a || !b) {
    return false;
  }
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) {
      return a[i] > b[i];
    }
  }
  return false;
}

export function evaluateRelease(json: any, current: string, repo: string): UpdateResult {
  const tag = json?.tag_name;
  if (typeof tag !== 'string' || !parseVersion(tag)) {
    return { kind: 'failed' };
  }
  if (!isNewerVersion(tag, current)) {
    return { kind: 'upToDate' };
  }
  const prefix = `https://github.com/${repo}/`;
  const html = json?.html_url;
  const url = typeof html === 'string' && html.startsWith(prefix) ? html : `${prefix}releases/latest`;
  return { kind: 'available', version: tag.replace(/^v/, ''), url };
}

export async function checkForUpdate(
  current: string,
  repo: string,
  fetchImpl: typeof fetch = fetch,
): Promise<UpdateResult> {
  if (!repoPattern.test(repo)) {
    return { kind: 'notConfigured' };
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetchImpl(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
      signal: controller.signal,
    });
    if (!response.ok) {
      return { kind: 'failed' };
    }
    return evaluateRelease(await response.json(), current, repo);
  } catch {
    return { kind: 'failed' };
  } finally {
    clearTimeout(timer);
  }
}
