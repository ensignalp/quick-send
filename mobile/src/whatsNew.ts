// Quick Send: "What's new" after an update (shown once per version; see App.tsx).

import type { Language } from './strings';

export type WhatsNewItem = { icon: string; text: string };

const items: Record<string, Record<Language, WhatsNewItem[]>> = {
  '1.1.0': {
    en: [
      { icon: 'qrcode-scan', text: 'Over the internet: show the code as a QR code or scan one with the camera. Sharing stops by itself when the files arrive.' },
      { icon: 'ip-network-outline', text: 'Send to an address: type an IP address (the dots appear by themselves) or # and the last number of the address.' },
      { icon: 'share-variant', text: 'Nearby Quick Send devices now appear in the Android share sheet; pick one to send straight to it.' },
      { icon: 'history', text: 'Recent activity is a page of its own, with filters for images, videos, documents and dates.' },
      { icon: 'keyboard-return', text: 'The back button now returns to the home screen from Settings and Recent activity.' },
    ],
    tr: [
      { icon: 'qrcode-scan', text: 'İnternet üzerinden: kodu QR olarak göster ya da kamerayla QR okut. Dosyalar ulaşınca paylaşım kendiliğinden durur.' },
      { icon: 'ip-network-outline', text: 'Adrese gönder: IP adresini yaz (noktalar kendiliğinden eklenir) ya da # ve adresin son sayısını gir.' },
      { icon: 'share-variant', text: 'Yakındaki Quick Send cihazları artık Android paylaş panelinde; birini seçince dosyalar doğrudan ona gider.' },
      { icon: 'history', text: 'Son etkinlikler artık ayrı bir sayfa; resim, video, belge ve tarih filtreleri var.' },
      { icon: 'keyboard-return', text: 'Geri tuşu artık Ayarlar ve Son etkinlikler’den ana ekrana döner.' },
    ],
  },
};

/** Items for [version], or null when that version has no "What's new". */
export function whatsNewFor(version: string, language: Language): WhatsNewItem[] | null {
  const base = version.replace(/^v/, '').split('+')[0].split('-')[0];
  return items[base]?.[language] ?? null;
}
