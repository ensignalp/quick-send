import { aggregateProgress, mergeFiles } from '../src/transfers';

test('weights per-file progress by size', () => {
  const files = [{ id: 'a', size: 300 }, { id: 'b', size: 100 }];
  expect(aggregateProgress(files, {})).toBe(0);
  expect(aggregateProgress(files, { a: 1 })).toBeCloseTo(0.75);
  expect(aggregateProgress(files, { a: 1, b: 0.5 })).toBeCloseTo(0.875);
  expect(aggregateProgress(files, { a: 1, b: 1 })).toBe(1);
});

test('handles empty and zero-size files', () => {
  expect(aggregateProgress([], {})).toBe(0);
  expect(aggregateProgress([{ id: 'a', size: 0 }, { id: 'b', size: 0 }], { a: 1 })).toBe(0.5);
  expect(aggregateProgress([{ id: 'a', size: 10 }], { a: 7 })).toBe(1);
});

test('merges picked files without duplicates', () => {
  const a = { uri: 'content://1', id: '1' };
  const b = { uri: 'content://2', id: '2' };
  expect(mergeFiles([a], [a, b])).toEqual([a, b]);
  expect(mergeFiles([], [b, b])).toEqual([b]);
});

import { defaultSettings, parseSettings } from '../src/core';

test('parses stored settings over defaults and drops bad values', () => {
  expect(parseSettings(null)).toEqual(defaultSettings);
  expect(parseSettings('not json')).toEqual(defaultSettings);
  const s = parseSettings(JSON.stringify({ shareMode: 'everyone', quickSave: true, language: 'xx', trusted: [{ fingerprint: 'A', alias: 'Pc' }], animations: 'yes' }));
  expect(s.shareMode).toBe('everyone');
  expect(s.quickSave).toBe(true);
  expect(s.language).toBe(defaultSettings.language);
  expect(s.animations).toBe(true);
  expect(s.trusted).toEqual([{ fingerprint: 'A', alias: 'Pc' }]);
});

import { dayStart, kindOf, kindsOf } from '../src/transfers';

test('file kinds come from the MIME type', () => {
  expect(kindOf('image/jpeg')).toBe('image');
  expect(kindOf('video/mp4')).toBe('video');
  expect(kindOf('application/pdf')).toBe('document');
  expect(kindOf('application/vnd.openxmlformats-officedocument.wordprocessingml.document')).toBe('document');
  expect(kindOf('audio/mpeg')).toBe('audio');
  expect(kindOf('application/zip')).toBe('other');
  expect(kindOf(undefined)).toBe('other');
  expect(kindsOf([{ mimeType: 'image/png' }, { mimeType: 'image/jpeg' }, { mimeType: 'text/plain' }])).toEqual(['image', 'document']);
});

test('dayStart is local midnight', () => {
  const t = new Date(2026, 10, 19, 15, 30).getTime();
  expect(dayStart(t)).toBe(new Date(2026, 10, 19).getTime());
});
