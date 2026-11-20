import { formatHashtag, formatIpv4Input, hashtagCandidates, isCompleteIpv4 } from '../src/address';

const type = (keys: string) => [...keys].reduce((text, k) => formatIpv4Input(text + k), '');

test('IP entry adds the dots like on the desktop', () => {
  expect(type('192168.1.123')).toBe('192.168.1.123');
  expect(type('100011')).toBe('100.0.11');
  expect(type('17216.2545')).toBe('172.16.254.5');
  expect(type('10..5')).toBe('10.5');
  expect(type('300')).toBe('30.0.');
  expect(formatIpv4Input('192', false)).toBe('192');
  expect(isCompleteIpv4('192.168.1.123')).toBe(true);
  expect(isCompleteIpv4('192.168.1.')).toBe(false);
});

test('hashtag is 0-255 and tried on every local /24 network', () => {
  expect(formatHashtag('123', '12')).toBe('123');
  expect(formatHashtag('256', '25')).toBe('25');
  expect(formatHashtag('#7', '')).toBe('7');
  expect(hashtagCandidates(['192.168.1.20', '10.8.0.4', 'fe80::1', '192.168.1.30'], '7')).toEqual(['192.168.1.7', '10.8.0.7']);
});
