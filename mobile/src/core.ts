// Bridge to the native Quick Send module (Kotlin + Rust LocalSend core), shared
// types and persisted UI settings.

import { NativeEventEmitter, NativeModules } from 'react-native';
import { previewBridge, previewEvents } from './previewBridge';
import type { Language } from './strings';

export type Device = {
  alias: string;
  fingerprint: string;
  host: string;
  port: number;
  protocol: 'http' | 'https';
  deviceModel?: string | null;
  deviceType?: 'MOBILE' | 'DESKTOP' | 'WEB' | 'HEADLESS' | 'SERVER' | null;
};
export type SharedFile = { id: string; uri: string; name: string; mimeType: string; size: number };
export type IncomingFile = { id: string; name: string; mimeType: string; size: number };
export type IncomingTransfer = {
  sessionId: string;
  sender: string;
  fingerprint?: string;
  files: IncomingFile[];
  fileProgress?: Record<string, number>;
  progress?: number;
  accepted?: boolean;
  savedFiles?: number; // files the core reported as saved (fileReceived success)
};
export type Outgoing = {
  id: string;
  fingerprint: string;
  alias: string;
  files: SharedFile[];
  fileProgress: Record<string, number>;
  progress: number;
  status: 'waiting' | 'sending' | 'sent' | 'failed';
};
export type HistoryEntry = { id: string; direction: 'sent' | 'received'; peer: string; count: number; size: number; ok: boolean; at: number };
export type TrustedDevice = { fingerprint: string; alias: string };
export type NetworkInfo = { addresses: string[]; port: number };
export type MediaKind = 'images' | 'videos' | 'documents';
export type MediaItem = SharedFile & { date: number; duration?: number };
export type ContentApp = { label: string; package: string; activity: string; icon: string | null };
export type ShareMode = 'off' | 'trusted' | 'everyone';
export type Appearance = 'system' | 'light' | 'dark';

export type Settings = {
  language: Language | null; // null = follow the system
  avatar: string | null; // file:// URI of the profile photo (shown on this device only)
  appearance: Appearance;
  animations: boolean;
  shareMode: ShareMode; // who can share when the Receive screen is not open
  quickSave: boolean;
  autoAcceptTrusted: boolean;
  autoFinish: boolean;
  saveHistory: boolean;
  autoUpdate: boolean; // download, verify and offer signed updates in the background
  trusted: TrustedDevice[];
  history: HistoryEntry[];
};

export const defaultSettings: Settings = {
  language: null,
  avatar: null,
  appearance: 'system',
  animations: true,
  shareMode: 'trusted',
  quickSave: false,
  autoAcceptTrusted: true,
  autoFinish: false,
  saveHistory: true,
  autoUpdate: true,
  trusted: [],
  history: [],
};

export type QuickSendBridge = {
  initialize: () => Promise<boolean>;
  startReceiver: () => Promise<boolean>;
  stopReceiver: () => Promise<boolean>;
  pickFiles: () => Promise<SharedFile[]>;
  sendFiles: (device: Device, files: SharedFile[]) => Promise<string>;
  respond: (sessionId: string, accepted: boolean) => Promise<void>;
  cancel: (sessionId: string) => Promise<void>;
  setVisibility: (visibility: 'everyone' | 'off') => Promise<void>;
  getInitialSharedFiles: () => Promise<SharedFile[]>;
  getVisibility: () => Promise<'everyone' | 'off'>;
  isReceiverEnabled: () => Promise<boolean>;
  getAppInfo: () => Promise<{ version: string; releasesRepo: string; alias?: string }>;
  getNetworkInfo?: () => Promise<NetworkInfo>;
  openDownloads?: () => Promise<boolean>;
  getSettings?: () => Promise<string | null>;
  setSettings?: (json: string) => Promise<boolean>;
  getCoreConfig?: () => Promise<{ alias: string; pin: string | null }>;
  setCoreConfig?: (alias: string, pin: string) => Promise<boolean>;
  restartApp?: () => void;
  getLanguage?: () => Promise<string>;
  pickDocuments?: () => Promise<SharedFile[]>;
  pickWithApp?: (pkg: string, activity: string) => Promise<SharedFile[]>;
  pickAvatar?: () => Promise<string | null>;
  clearAvatar?: () => Promise<boolean>;
  hasMediaPermission?: () => Promise<boolean>;
  requestMediaPermission?: () => Promise<boolean>;
  queryMedia?: (kind: MediaKind, limit: number, offset: number) => Promise<MediaItem[]>;
  getThumbnail?: (uri: string, size: number) => Promise<string | null>;
  getContentApps?: () => Promise<ContentApp[]>;
  /** Receiving in the background: whether Android battery optimisation is off for Quick Send. */
  isBatteryUnrestricted?: () => Promise<boolean>;
  requestBatteryUnrestricted?: () => Promise<boolean>;
  /** Signed background updates: whether this build can update itself, and a manual run. */
  getUpdateSupport?: () => Promise<{ supported: boolean; canInstall: boolean }>;
  checkUpdateNow?: () => Promise<string>;
  /** Transfers over the internet (iroh). Events arrive as { type: 'internet', id, event }. */
  internetSend?: (files: SharedFile[]) => Promise<string>;
  internetReceive?: (code: string) => Promise<string>;
  internetCancel?: (id: string) => Promise<boolean>;
  addListener: (eventName: string) => void;
  removeListeners: (count: number) => void;
};

const nativeBridge = NativeModules.QuickSend as QuickSendBridge | undefined;
// Expo Go / web have no native module: in development use the simulated preview bridge.
export const isPreview = !nativeBridge && __DEV__;
export const bridge: QuickSendBridge | undefined = nativeBridge ?? (isPreview ? (previewBridge as unknown as QuickSendBridge) : undefined);

export function subscribe(listener: (event: any) => void) {
  const emitter = nativeBridge ? new NativeEventEmitter(NativeModules.QuickSend) : previewEvents;
  return emitter.addListener('QuickSendEvent', listener);
}

/** Merges stored JSON over the defaults, ignoring unknown or malformed values. */
export function parseSettings(json: string | null | undefined): Settings {
  if (!json) return defaultSettings;
  try {
    const raw = JSON.parse(json);
    if (!raw || typeof raw !== 'object') return defaultSettings;
    const pick = <K extends keyof Settings>(key: K, ok: (v: unknown) => boolean): Settings[K] =>
      (ok(raw[key]) ? raw[key] : defaultSettings[key]) as Settings[K];
    const bool = (v: unknown) => typeof v === 'boolean';
    return {
      language: pick('language', v => v === null || v === 'en' || v === 'tr'),
      avatar: pick('avatar', v => v === null || typeof v === 'string'),
      appearance: pick('appearance', v => v === 'system' || v === 'light' || v === 'dark'),
      animations: pick('animations', bool),
      shareMode: pick('shareMode', v => v === 'off' || v === 'trusted' || v === 'everyone'),
      quickSave: pick('quickSave', bool),
      autoAcceptTrusted: pick('autoAcceptTrusted', bool),
      autoFinish: pick('autoFinish', bool),
      saveHistory: pick('saveHistory', bool),
      autoUpdate: pick('autoUpdate', bool),
      trusted: pick('trusted', v => Array.isArray(v) && v.every(d => d && typeof d.fingerprint === 'string' && typeof d.alias === 'string')),
      history: pick('history', v => Array.isArray(v)),
    };
  } catch {
    return defaultSettings;
  }
}

export async function loadSettings(): Promise<Settings> {
  return parseSettings(await bridge?.getSettings?.().catch(() => null));
}

export function saveSettings(settings: Settings) {
  const stored = settings.saveHistory ? settings : { ...settings, history: [] };
  bridge?.setSettings?.(JSON.stringify(stored)).catch(() => undefined);
}

export function randomPin() {
  return String(1000 + Math.floor(Math.random() * 9000));
}
