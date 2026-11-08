// Quick Send preview bridge — DEVELOPMENT ONLY.
// Used when the native QuickSend module is missing (Expo Go, web preview) so
// the UI can be explored with simulated devices and transfers. It performs no
// networking. Real builds always use the native module backed by packages/core.

type Listener = (event: any) => void;
const listeners = new Set<Listener>();
const emit = (event: any) => setTimeout(() => listeners.forEach(l => l(event)), 0);

const devices = [
  { alias: 'Pixel Tablet', fingerprint: 'preview-1', host: '192.168.1.24', port: 53317, protocol: 'https', deviceModel: 'Android' },
  { alias: 'Fedora Laptop', fingerprint: 'preview-2', host: '192.168.1.31', port: 53317, protocol: 'https', deviceModel: 'Linux' },
  { alias: 'Office Desktop', fingerprint: 'preview-3', host: '192.168.1.40', port: 53317, protocol: 'https', deviceModel: 'Linux' },
];

const sampleFiles = [
  { id: 'f1', uri: 'preview://photo.jpg', name: 'Tatil fotoğrafı.jpg', mimeType: 'image/jpeg', size: 3_400_000 },
  { id: 'f2', uri: 'preview://report.pdf', name: 'Rapor.pdf', mimeType: 'application/pdf', size: 820_000 },
];

function animate(onTick: (p: number) => void, onDone: () => void) {
  let p = 0;
  const timer = setInterval(() => {
    p = Math.min(1, p + 0.1);
    onTick(p);
    if (p >= 1) { clearInterval(timer); onDone(); }
  }, 300);
}

let receiver = false;
let visibility: 'everyone' | 'off' = 'everyone';
let counter = 0;

export const previewEvents = {
  addListener(_name: string, listener: Listener) {
    listeners.add(listener);
    return { remove: () => listeners.delete(listener) };
  },
};

export const previewBridge = {
  async initialize() {
    setTimeout(() => emit({ type: 'devices', devices: devices.slice(0, 2) }), 800);
    setTimeout(() => emit({ type: 'device', device: devices[2] }), 2000);
    return true;
  },
  async startReceiver() {
    receiver = true;
    const sessionId = `preview-session-${++counter}`;
    setTimeout(() => receiver && emit({
      type: 'transferRequest',
      transfer: { sessionId, sender: 'Fedora Laptop', files: sampleFiles.map(({ id, name, mimeType, size }) => ({ id, name, mimeType, size })) },
    }), 2500);
    return true;
  },
  async stopReceiver() { receiver = false; return true; },
  async pickFiles() { return sampleFiles; },
  async sendFiles(_device: unknown, _files: unknown[]) {
    const transferId = `preview-send-${++counter}`;
    animate(progress => emit({ type: 'sendProgress', transferId, progress }), () => emit({ type: 'sendComplete', transferId }));
    return transferId;
  },
  async respond(sessionId: string, accepted: boolean) {
    emit({ type: 'transferDecision', sessionId, accepted });
    if (accepted) {
      animate(progress => emit({ type: 'transferProgress', sessionId, progress }), () => emit({ type: 'sessionEnd', sessionId }));
    }
  },
  async cancel(id: string) {
    emit({ type: 'sessionEnd', sessionId: id });
    emit({ type: 'sendFailed', transferId: id, message: 'Cancelled (preview)' });
  },
  async setVisibility(value: 'everyone' | 'off') { visibility = value; },
  async getDynamicColors() { return null; },
  async getInitialSharedFiles() { return []; },
  async getVisibility() { return visibility; },
  async isReceiverEnabled() { return receiver; },
  async getAppInfo() { return { version: '0.1.0', releasesRepo: '' }; },
  addListener() {},
  removeListeners() {},
};
