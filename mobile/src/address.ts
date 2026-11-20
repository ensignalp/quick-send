// Quick Send: manual sending helpers (IP address with automatic dots, "#" hashtag).
// Same rules as the desktop (app/lib/quick_send/ip_input_formatter.dart).

/**
 * Digits and dots only, at most four parts of at most three digits, each part at most 255. A dot is added as
 * soon as a part cannot grow ("192" -> "192.", "26" -> "26.", "0" -> "0."); a digit that would make a part too
 * large starts the next one. [autoDot] is false while deleting so dots are not re-added.
 */
export function formatIpv4Input(input: string, autoDot = true): string {
  const parts: string[] = [];
  let current = '';
  for (const ch of input) {
    if (ch === '.') {
      if (current && parts.length < 3) { parts.push(current); current = ''; }
      continue;
    }
    if (!/[0-9]/.test(ch)) continue;
    const full = current.length === 3 || current === '0' || Number(current + ch) > 255;
    if (current && full) {
      if (parts.length === 3) continue;
      parts.push(current);
      current = ch;
    } else {
      current += ch;
    }
  }
  let result = [...parts, current].join('.');
  if (autoDot && parts.length < 3 && current) {
    const complete = current.length === 3 || current === '0' || Number(current) * 10 > 255;
    if (complete) result += '.';
  }
  return result;
}

export function isCompleteIpv4(text: string): boolean {
  const parts = text.split('.');
  return parts.length === 4 && parts.every(p => p.length > 0 && p.length <= 3 && Number(p) <= 255);
}

/** "#" entry: the last part of an address, 0–255; returns null for anything else. */
export function formatHashtag(input: string, previous: string): string {
  const digits = input.replace(/[^0-9]/g, '');
  return digits.length > 3 || (digits !== '' && Number(digits) > 255) ? previous : digits;
}

/** Candidate addresses for a hashtag: the number on each of this device's IPv4 networks (/24). */
export function hashtagCandidates(localAddresses: string[], hashtag: string): string[] {
  const prefixes = [...new Set(localAddresses.filter(a => /^\d+\.\d+\.\d+\.\d+$/.test(a)).map(a => a.split('.').slice(0, 3).join('.')))];
  return prefixes.map(p => `${p}.${hashtag}`);
}
