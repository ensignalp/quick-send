// Quick Send preview bridge — DEVELOPMENT ONLY.
// Used when the native QuickSend module is missing (Expo Go, web preview) so
// the UI can be explored with simulated devices and transfers. It performs no
// networking. Real builds always use the native module backed by packages/core.
// Events mirror the native ones, including per-file progress (`fileId`).

type Listener = (event: any) => void;
type PreviewFile = { id: string; uri: string; name: string; mimeType: string; size: number };
const listeners = new Set<Listener>();
const emit = (event: any) => setTimeout(() => listeners.forEach(l => l(event)), 0);

const devices = [
  { alias: 'Pixel Tablet', fingerprint: 'preview-1', host: '192.168.1.24', port: 53317, protocol: 'https', deviceModel: 'Google', deviceType: 'MOBILE' },
  { alias: 'Fedora Laptop', fingerprint: 'preview-2', host: '192.168.1.31', port: 53317, protocol: 'https', deviceModel: 'Linux', deviceType: 'DESKTOP' },
  { alias: 'Ayşe', fingerprint: 'preview-3', host: '192.168.1.40', port: 53317, protocol: 'https', deviceModel: 'Samsung', deviceType: 'MOBILE' },
  { alias: 'David', fingerprint: 'preview-4', host: '192.168.1.41', port: 53317, protocol: 'https', deviceModel: 'Xiaomi', deviceType: 'MOBILE' },
  { alias: 'Office Desktop', fingerprint: 'preview-5', host: '192.168.1.42', port: 53317, protocol: 'https', deviceModel: 'Windows', deviceType: 'DESKTOP' },
];

const pool: Omit<PreviewFile, 'id' | 'uri'>[] = [
  { name: 'Tatil fotoğrafı.jpg', mimeType: 'image/jpeg', size: 3_400_000 },
  { name: 'Rapor.pdf', mimeType: 'application/pdf', size: 820_000 },
  { name: 'Doğum günü.mp4', mimeType: 'video/mp4', size: 48_000_000 },
  { name: 'Sunum.zip', mimeType: 'application/zip', size: 12_500_000 },
  { name: 'Notlar.txt', mimeType: 'text/plain', size: 4_200 },
  { name: 'Şarkı.mp3', mimeType: 'audio/mpeg', size: 6_100_000 },
];

let receiver = false;
let visibility: 'everyone' | 'off' = 'everyone';
let counter = 0;
let pickIndex = 0;
let demoRequestSent = false; // the simulated incoming request is shown once per session
let storedSettings: string | null = null;
let coreConfig = { alias: 'Galaxy S24', pin: null as string | null };
const cancelled = new Set<string>();

// Simulated media library for the in-app picker (no real files, no thumbnails).
const DAY = 86_400_000;
const now = Date.now();
const fakeMedia = (kind: 'images' | 'videos' | 'documents') => {
  const docs = ['Rapor.pdf', 'Sözleşme.pdf', 'Notlar.txt', 'Bütçe.xlsx', 'Sunum.pptx', 'Kitap.epub', 'Tez taslağı.docx'];
  const count = kind === 'images' ? 22 : kind === 'videos' ? 7 : docs.length;
  return Array.from({ length: count }, (_, i) => {
    const date = now - (kind === 'images' ? Math.floor(i / 6) : i * 3) * DAY - i * 3_600_000;
    if (kind === 'documents') {
      const name = docs[i];
      const ext = name.split('.').pop();
      const mime = ext === 'pdf' ? 'application/pdf' : ext === 'txt' ? 'text/plain' : ext === 'epub' ? 'application/epub+zip' : `application/${ext}`;
      return { id: `m-doc-${i}`, uri: `preview://doc/${i}`, name, mimeType: mime, size: 120_000 + i * 830_000, date };
    }
    const video = kind === 'videos';
    return {
      id: `m-${kind}-${i}`, uri: `preview://${kind}/${i}`, name: video ? `VID_${1000 + i}.mp4` : `IMG_${2000 + i}.jpg`,
      mimeType: video ? 'video/mp4' : 'image/jpeg', size: video ? 20_000_000 + i * 4_000_000 : 1_800_000 + i * 90_000, date,
      ...(video ? { duration: (5 + i * 37) * 1000 } : {}),
    };
  });
};

/** Emits per-file progress one file after another, like the native core. */
function animateFiles(files: { id: string }[], id: string, onTick: (fileId: string, p: number) => void, onDone: () => void) {
  let index = 0;
  let p = 0;
  const timer = setInterval(() => {
    if (cancelled.has(id)) { clearInterval(timer); return; }
    p = Math.min(1, p + 0.2);
    onTick(files[index].id, p);
    if (p >= 1) {
      index += 1;
      p = 0;
      if (index >= files.length) { clearInterval(timer); onDone(); }
    }
  }, 260);
}

export const previewEvents = {
  addListener(_name: string, listener: Listener) {
    listeners.add(listener);
    return { remove: () => listeners.delete(listener) };
  },
};

export const previewBridge = {
  async initialize() {
    setTimeout(() => emit({ type: 'devices', devices: devices.slice(0, 3) }), 800);
    setTimeout(() => emit({ type: 'device', device: devices[3] }), 1600);
    setTimeout(() => emit({ type: 'device', device: devices[4] }), 2400);
    return true;
  },
  async startReceiver() {
    receiver = true;
    const sessionId = `preview-session-${++counter}`;
    const files = pool.slice(0, 3).map((f, i) => ({ id: `in-${i}`, ...f }));
    if (demoRequestSent) return true;
    demoRequestSent = true;
    setTimeout(() => receiver && emit({ type: 'transferRequest', transfer: { sessionId, sender: 'Fedora Laptop', fingerprint: 'preview-2', files } }), 6000);
    return true;
  },
  async stopReceiver() { receiver = false; return true; },
  async pickFiles(): Promise<PreviewFile[]> {
    const count = pickIndex === 0 ? 2 : 1;
    const picked = Array.from({ length: count }, () => {
      const f = pool[pickIndex % pool.length];
      pickIndex += 1;
      return { ...f, id: `pick-${pickIndex}`, uri: `preview://${pickIndex}/${f.name}` };
    });
    return picked;
  },
  async sendFiles(_device: unknown, files: PreviewFile[]) {
    const transferId = `preview-send-${++counter}`;
    emit({ type: 'sendStarted', transferId });
    // The receiver "accepts" after a moment, then files are uploaded one by one.
    setTimeout(() => animateFiles(files, transferId,
      (fileId, progress) => emit({ type: 'sendProgress', transferId, fileId, progress }),
      () => emit({ type: 'sendComplete', transferId })), 1500);
    return transferId;
  },
  async respond(sessionId: string, accepted: boolean) {
    emit({ type: 'transferDecision', sessionId, accepted });
    if (accepted) {
      const files = pool.slice(0, 3).map((_, i) => ({ id: `in-${i}` }));
      animateFiles(files, sessionId,
        (fileId, progress) => emit({ type: 'transferProgress', sessionId, fileId, progress }),
        () => emit({ type: 'sessionEnd', sessionId }));
    }
  },
  async cancel(id: string) {
    cancelled.add(id);
    emit({ type: 'sessionEnd', sessionId: id });
    emit({ type: 'sendFailed', transferId: id, message: 'Cancelled (preview)' });
  },
  async setVisibility(value: 'everyone' | 'off') { visibility = value; },
  async getDynamicColors() { return null; },
  async getInitialSharedFiles() { return []; },
  async getVisibility() { return visibility; },
  async isReceiverEnabled() { return receiver; },
  async getAppInfo() { return { version: '1.0.0', releasesRepo: '', alias: coreConfig.alias }; },
  async getSettings() { return storedSettings; },
  async setSettings(json: string) { storedSettings = json; return true; },
  async getCoreConfig() { return coreConfig; },
  async setCoreConfig(alias: string, pin: string) { coreConfig = { alias: alias || 'Galaxy S24', pin: pin || null }; return true; },
  restartApp() {},
  async getNetworkInfo() { return { addresses: ['192.168.1.20', '10.8.0.4'], port: 53317 }; },
  async openDownloads() { return true; },
  async hasMediaPermission() { return true; },
  async requestMediaPermission() { return true; },
  async queryMedia(kind: 'images' | 'videos' | 'documents', limit: number, offset: number) { return fakeMedia(kind).slice(offset, offset + limit); },
  async getThumbnail() { return null; },
  async getContentApps() { return [{ label: 'Files', package: 'preview.files', activity: 'Main', icon: null }, { label: 'Photos', package: 'preview.photos', activity: 'Main', icon: null }]; },
  async pickWithApp() { return previewBridge.pickFiles(); },
  async pickDocuments() { return previewBridge.pickFiles(); },
  async pickAvatar() { return null; },
  async clearAvatar() { return true; },
  async isBatteryUnrestricted() { return false; },
  async requestBatteryUnrestricted() { return true; },
  async getUpdateSupport() { return { supported: false, canInstall: false }; },
  async checkUpdateNow() { return 'notConfigured'; },
  addListener() {},
  removeListeners() {},
};
