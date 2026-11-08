import { checkForUpdate, evaluateRelease, isNewerVersion } from '../src/updateCheck';

const repo = 'owner/quick-send';

test('compares versions', () => {
  expect(isNewerVersion('v0.2.0', '0.1.9')).toBe(true);
  expect(isNewerVersion('0.1.0', '0.1.0')).toBe(false);
  expect(isNewerVersion('0.1.0', '0.2.0')).toBe(false);
  expect(isNewerVersion('latest', '0.1.0')).toBe(false);
});

test('evaluates releases and rejects foreign URLs', () => {
  expect(evaluateRelease({ tag_name: 'v0.2.0', html_url: `https://github.com/${repo}/releases/tag/v0.2.0` }, '0.1.0', repo))
    .toEqual({ kind: 'available', version: '0.2.0', url: `https://github.com/${repo}/releases/tag/v0.2.0` });
  expect(evaluateRelease({ tag_name: 'v0.2.0', html_url: 'https://evil.example' }, '0.1.0', repo))
    .toEqual({ kind: 'available', version: '0.2.0', url: `https://github.com/${repo}/releases/latest` });
  expect(evaluateRelease({ tag_name: 'v0.1.0' }, '0.1.0', repo)).toEqual({ kind: 'upToDate' });
  expect(evaluateRelease({}, '0.1.0', repo)).toEqual({ kind: 'failed' });
});

test('makes no request when not configured', async () => {
  const fetchImpl = jest.fn();
  expect(await checkForUpdate('0.1.0', '', fetchImpl as any)).toEqual({ kind: 'notConfigured' });
  expect(fetchImpl).not.toHaveBeenCalled();
});

test('makes exactly one request when configured', async () => {
  const fetchImpl = jest.fn().mockResolvedValue({ ok: true, json: async () => ({ tag_name: 'v0.1.0' }) });
  expect(await checkForUpdate('0.1.0', repo, fetchImpl as any)).toEqual({ kind: 'upToDate' });
  expect(fetchImpl).toHaveBeenCalledTimes(1);
  expect(fetchImpl.mock.calls[0][0]).toBe(`https://api.github.com/repos/${repo}/releases/latest`);
});
