import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, AppState, Keyboard, Linking, Share, Platform, Pressable, ScrollView, StatusBar, StyleSheet, TextInput, useColorScheme, useWindowDimensions, View } from 'react-native';
import { configureFonts, MD3DarkTheme, MD3LightTheme, Modal, PaperProvider, Portal } from 'react-native-paper';
import { SpaceGrotesk_300Light, SpaceGrotesk_400Regular, SpaceGrotesk_500Medium, SpaceGrotesk_600SemiBold, SpaceGrotesk_700Bold, useFonts } from '@expo-google-fonts/space-grotesk';
import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import { checkForUpdate, UpdateResult } from './src/updateCheck';
import { aggregateProgress, mergeFiles } from './src/transfers';
import { copy, Copy, Language } from './src/strings';
import {
  bridge, defaultSettings, Device, HistoryEntry, IncomingTransfer, isPreview, loadSettings, NetworkInfo, Outgoing, randomPin, saveSettings,
  MediaItem, Settings, ShareMode, SharedFile, subscribe,
} from './src/core';
import { FilePicker, Thumb } from './src/picker';
import {
  AppIcon, Avatar, deviceIcon, deviceLabel, Dropdown, fontFor, Text, FadeIn, fileIcon, formatSize, Group, Halo, IconCircle, LetterAvatar, LinearProgress, MotionContext, Palette, palettes,
  Pill, ProgressRing, Pulse, ReceiveGlow, Row, SectionLabel, Separator, Spinner, SuccessBadge, SwitchRow, timeAgo,
} from './src/ui';

type Tab = 'receive' | 'send';
type Screen = 'home' | 'settings' | 'picker';
type Sheet =
  | { kind: 'info' } | { kind: 'files' } | { kind: 'history' } | { kind: 'privacy' } | { kind: 'about' }
  | { kind: 'device'; device: Device } | { kind: 'name' } | { kind: 'restart' } | { kind: 'photo' } | { kind: 'internet' } | null;
type Received = { sender: string; fingerprint?: string; count: number };

const PORT = 53317;

function App() {
  return <SafeAreaProvider><AppContent /></SafeAreaProvider>;
}

function AppContent() {
  const [fontsLoaded] = useFonts({ SpaceGrotesk_300Light, SpaceGrotesk_400Regular, SpaceGrotesk_500Medium, SpaceGrotesk_600SemiBold, SpaceGrotesk_700Bold });
  const systemScheme = useColorScheme();
  const [settings, setSettings] = useState<Settings>(defaultSettings);
  const [loaded, setLoaded] = useState(false);
  const [systemLanguage, setSystemLanguage] = useState<Language>('en');
  const darkMode = settings.appearance === 'system' ? systemScheme !== 'light' : settings.appearance === 'dark';
  const c = palettes[darkMode ? 'dark' : 'light'];
  const t = copy[settings.language ?? systemLanguage];
  const [tab, setTab] = useState<Tab>('receive');
  const [screen, setScreen] = useState<Screen>('home');
  const [sheet, setSheet] = useState<Sheet>(null);
  const [alias, setAlias] = useState('Android');
  const [pin, setPin] = useState<string | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [networkReady, setNetworkReady] = useState(true);
  const [receiverOn, setReceiverOn] = useState(false);
  const [pending, setPending] = useState<IncomingTransfer | null>(null);
  const [received, setReceived] = useState<Received | null>(null);
  const [selected, setSelected] = useState<SharedFile[]>([]);
  const [outgoing, setOutgoing] = useState<Record<string, Outgoing>>({});
  const [message, setMessage] = useState('');
  const insets = useSafeAreaInsets();
  // The browser preview's root is not height-bounded; pin the app to the window so the list scrolls inside.
  const windowHeight = useWindowDimensions().height;

  // Who may share right now: everyone while the Receive screen is open, otherwise the setting.
  const effectiveMode: ShareMode = screen === 'home' && tab === 'receive' ? 'everyone' : settings.shareMode;

  const refs = useRef({ t, settings, effectiveMode, pending, outgoing });
  refs.current = { t, settings, effectiveMode, pending, outgoing };
  const setIncoming = (next: IncomingTransfer | null) => { refs.current.pending = next; setPending(next); };

  const updateSettings = useCallback((patch: Partial<Settings> | ((s: Settings) => Partial<Settings>)) => {
    setSettings(current => {
      const next = { ...current, ...(typeof patch === 'function' ? patch(current) : patch) };
      saveSettings(next);
      return next;
    });
  }, []);

  const addHistory = useCallback((entry: Omit<HistoryEntry, 'id' | 'at'>) =>
    updateSettings(s => ({ history: [{ ...entry, id: `${Date.now()}-${Math.random()}`, at: Date.now() }, ...s.history].slice(0, 50) })), [updateSettings]);

  const updateOutgoing = (transferId: string, update: (o: Outgoing) => Outgoing) => setOutgoing(current => {
    const entry = Object.values(current).find(o => o.id === transferId);
    return entry ? { ...current, [entry.fingerprint]: update(entry) } : current;
  });

  /* ------------------------------------------------------------ startup */

  useEffect(() => {
    loadSettings().then(s => { setSettings(s); setLoaded(true); }).catch(() => setLoaded(true));
    bridge?.getLanguage?.().then(locale => locale === 'tr' && setSystemLanguage('tr')).catch(() => undefined);
    bridge?.getCoreConfig?.().then(cfg => { setAlias(cfg.alias); setPin(cfg.pin); }).catch(() =>
      bridge?.getAppInfo().then(info => info.alias && setAlias(info.alias)).catch(() => undefined));
    if (!bridge) return;

    const subscription = subscribe((event: any) => {
      const { t: tt, settings: st, effectiveMode: mode } = refs.current;
      switch (event.type) {
        case 'devices': setDevices(event.devices ?? []); break;
        case 'device': setDevices(current => mergeDevice(current, event.device)); break;
        case 'sharedFiles': setSelected(event.files ?? []); setTab('send'); setScreen('home'); break;
        case 'transferRequest': {
          const transfer: IncomingTransfer = event.transfer;
          if (event.autoAccepted) {
            // The receiver service already accepted it (trusted device), also when the UI was not running.
            setReceived(null);
            setSheet(null);
            setIncoming({ ...transfer, accepted: true, progress: 0 });
            break;
          }
          const trusted = !!transfer.fingerprint && st.trusted.some(d => d.fingerprint === transfer.fingerprint);
          if (mode === 'trusted' && !trusted) {
            bridge?.respond(transfer.sessionId, false).catch(() => undefined);
            setMessage(tt.declinedUntrusted(transfer.sender));
            break;
          }
          setReceived(null);
          setSheet(null);
          if (st.quickSave || (st.autoAcceptTrusted && trusted)) {
            setIncoming({ ...transfer, accepted: true, progress: 0 });
            bridge?.respond(transfer.sessionId, true).catch(() => undefined);
          } else {
            setIncoming(transfer);
          }
          break;
        }
        case 'transferProgress': {
          const cur = refs.current.pending;
          if (!cur || cur.sessionId !== event.sessionId) break;
          const fileProgress = event.fileId ? { ...cur.fileProgress, [event.fileId]: event.progress } : undefined;
          setIncoming({ ...cur, fileProgress, progress: fileProgress ? aggregateProgress(cur.files, fileProgress) : event.progress });
          break;
        }
        case 'fileReceived': {
          // Fast transfers can end before the last progress event; count saved files to know it completed.
          const cur = refs.current.pending;
          if (cur && cur.sessionId === event.sessionId && event.success) setIncoming({ ...cur, savedFiles: (cur.savedFiles ?? 0) + 1 });
          break;
        }
        case 'transferDecision': {
          const cur = refs.current.pending;
          if (!event.accepted) setIncoming(null);
          else if (cur && cur.sessionId === event.sessionId) setIncoming({ ...cur, accepted: true, progress: cur.progress ?? 0 });
          break;
        }
        case 'sendProgress':
          updateOutgoing(event.transferId, o => {
            const fileProgress = event.fileId ? { ...o.fileProgress, [event.fileId]: event.progress } : o.fileProgress;
            return { ...o, status: 'sending', fileProgress, progress: event.fileId ? aggregateProgress(o.files, fileProgress) : event.progress };
          });
          break;
        case 'sendComplete': {
          const o = Object.values(refs.current.outgoing).find(x => x.id === event.transferId);
          if (o) addHistory({ direction: 'sent', peer: o.alias, count: o.files.length, size: o.files.reduce((s, f) => s + f.size, 0), ok: true });
          updateOutgoing(event.transferId, x => ({ ...x, progress: 1, status: 'sent' }));
          break;
        }
        case 'sendFailed': {
          const o = Object.values(refs.current.outgoing).find(x => x.id === event.transferId);
          if (o && o.status !== 'failed') addHistory({ direction: 'sent', peer: o.alias, count: o.files.length, size: o.files.reduce((s, f) => s + f.size, 0), ok: false });
          updateOutgoing(event.transferId, x => ({ ...x, status: 'failed' }));
          if (event.message) setMessage(event.message);
          break;
        }
        case 'sessionEnd': {
          const cur = refs.current.pending;
          if (cur && cur.sessionId === event.sessionId) {
            const done = !!cur.accepted && ((cur.progress ?? 0) >= 0.999 || (cur.savedFiles ?? 0) >= cur.files.length);
            if (cur.accepted) addHistory({ direction: 'received', peer: cur.sender, count: cur.files.length, size: cur.files.reduce((s, f) => s + f.size, 0), ok: done });
            if (done) setReceived({ sender: cur.sender, fingerprint: cur.fingerprint, count: cur.files.length });
            setIncoming(null);
          }
          break;
        }
        case 'error': setMessage(event.message ?? ''); break;
      }
    });
    const native = bridge;
    native.initialize().then(started => {
      setNetworkReady(started);
      if (!started) setMessage(refs.current.t.permissionDenied);
      return native.getInitialSharedFiles();
    }).then(files => {
      if (files.length) { setSelected(files); setTab('send'); }
    }).catch(() => undefined);
    return () => subscription.remove();
  }, [addHistory]);

  /* ------------------------------------------------------- receive mode */

  useEffect(() => {
    if (!loaded || !bridge) return;
    let cancelled = false;
    (async () => {
      try {
        if (effectiveMode === 'off') {
          await bridge.stopReceiver();
          await bridge.setVisibility('off');
          if (!cancelled) setReceiverOn(false);
        } else {
          await bridge.setVisibility('everyone');
          const ok = await bridge.startReceiver();
          if (!cancelled) setReceiverOn(ok);
        }
      } catch {
        if (!cancelled) setReceiverOn(false);
      }
    })();
    return () => { cancelled = true; };
  }, [effectiveMode, loaded]);

  const restartReceiver = async () => {
    if (!bridge) return;
    await bridge.stopReceiver().catch(() => undefined);
    if (refs.current.effectiveMode !== 'off') setReceiverOn(await bridge.startReceiver().catch(() => false));
  };

  /* ------------------------------------------------------------ actions */

  const clearSelection = () => {
    setSelected([]);
    setOutgoing(current => Object.fromEntries(Object.entries(current).filter(([, o]) => o.status === 'sending' || o.status === 'waiting')));
    setSheet(null);
  };

  const sendTo = async (device: Device) => {
    if (!bridge) { setMessage(t.bridgeMissing); return; }
    const current = outgoing[device.fingerprint];
    if (current && (current.status === 'sending' || current.status === 'waiting')) {
      await bridge.cancel(current.id).catch(() => undefined);
      return;
    }
    if (!selected.length) { openPicker(); return; }
    const files = selected;
    try {
      const id = await bridge.sendFiles(device, files);
      if (id) {
        setOutgoing(o => ({ ...o, [device.fingerprint]: { id, fingerprint: device.fingerprint, alias: device.alias, files, fileProgress: {}, progress: 0, status: 'waiting' } }));
      }
    } catch { setMessage(t.transferFailed); }
  };

  const retryDiscovery = async () => {
    if (!bridge) { setMessage(t.bridgeMissing); return; }
    const ready = await bridge.initialize().catch(() => false);
    setNetworkReady(ready);
    if (!ready) setMessage(t.permissionDenied);
  };

  const answerIncoming = async (accepted: boolean) => {
    if (!pending || !bridge) return;
    await bridge.respond(pending.sessionId, accepted);
    if (!accepted) setIncoming(null);
  };

  const cancelIncoming = async () => {
    if (!pending || !bridge) return;
    await bridge.cancel(pending.sessionId);
    setIncoming(null);
  };

  const isTrusted = (fingerprint?: string) => !!fingerprint && settings.trusted.some(d => d.fingerprint === fingerprint);
  const setTrusted = (fingerprint: string, deviceAlias: string, trusted: boolean) =>
    updateSettings(s => ({
      trusted: trusted ? [...s.trusted.filter(d => d.fingerprint !== fingerprint), { fingerprint, alias: deviceAlias }] : s.trusted.filter(d => d.fingerprint !== fingerprint),
    }));

  const openPicker = () => setScreen('picker');
  const finishPicker = (files: SharedFile[]) => {
    setScreen('home');
    setTab('send');
    if (files.length) {
      setSelected(current => mergeFiles(current, files));
      setOutgoing(current => Object.fromEntries(Object.entries(current).filter(([, o]) => o.status === 'sending' || o.status === 'waiting')));
    }
  };

  const choosePhoto = async () => {
    setSheet(null);
    const uri = await bridge?.pickAvatar?.().catch(() => null);
    if (uri) updateSettings({ avatar: uri });
  };
  const removePhoto = async () => {
    setSheet(null);
    await bridge?.clearAvatar?.().catch(() => undefined);
    updateSettings({ avatar: null });
  };

  const saveCoreConfig = async (nextAlias: string, nextPin: string | null) => {
    setAlias(nextAlias);
    setPin(nextPin);
    await bridge?.setCoreConfig?.(nextAlias, nextPin ?? '').catch(() => undefined);
    setSheet({ kind: 'restart' });
  };

  useEffect(() => {
    if (!message) return;
    const timer = setTimeout(() => setMessage(''), 4000);
    return () => clearTimeout(timer);
  }, [message]);

  // After sending: once every transfer has ended and at least one succeeded (none failed), show "Sent"
  // on the tile for a moment, then confirm with a message, clear the selection and return to Receive.
  useEffect(() => {
    const all = Object.values(outgoing);
    if (!all.length || all.some(o => o.status === 'sending' || o.status === 'waiting' || o.status === 'failed')) return;
    const sent = all.filter(o => o.status === 'sent');
    if (!sent.length) return;
    const timer = setTimeout(() => {
      const count = sent.reduce((n, o) => n + o.files.length, 0);
      setMessage(sent.length === 1 ? t.sentTo(count, sent[0].alias) : t.sentTo(count, sent.map(o => o.alias).join(', ')));
      setSelected([]);
      setOutgoing({});
      setSheet(null);
      setScreen('home');
      setTab('receive');
    }, 1600);
    return () => clearTimeout(timer);
  }, [outgoing, t]);

  useEffect(() => {
    if (!received || !settings.autoFinish) return;
    const timer = setTimeout(() => setReceived(null), 3500);
    return () => clearTimeout(timer);
  }, [received, settings.autoFinish]);

  const theme = useMemo(() => {
    const base = darkMode ? MD3DarkTheme : MD3LightTheme;
    return { ...base, roundness: 6, fonts: configureFonts({ config: { fontFamily: fontFor('400') } }), colors: { ...base.colors, primary: c.accent, background: c.bg, surface: c.card, elevation: { ...base.colors.elevation, level2: c.card } } };
  }, [darkMode, c]);

  if (!fontsLoaded) return <View style={[styles.root, { backgroundColor: c.bg }]} />;

  const modalCard = [styles.sheetCard, { backgroundColor: c.card, marginBottom: insets.bottom + 12, boxShadow: c.shadow }];

  return (
    <MotionContext.Provider value={settings.animations}>
      <PaperProvider theme={theme} settings={{ icon: ({ name, color, size }: any) => <MaterialCommunityIcons name={name} color={color} size={size} /> }}>
        <StatusBar barStyle={darkMode ? 'light-content' : 'dark-content'} />
        <View style={[styles.root, { backgroundColor: c.bg, paddingTop: insets.top },
          Platform.OS === 'web' && ({ position: 'fixed', top: 0, left: 0, right: 0, height: windowHeight } as any)]}>
          {screen === 'picker' ? <FilePicker t={t} c={c} language={settings.language ?? systemLanguage} topInset={0} bottomInset={insets.bottom}
            onCancel={() => setScreen('home')} onDone={finishPicker} /> : screen === 'home' ? <>
            <TopBar t={t} c={c} alias={alias} avatar={settings.avatar} onInfo={() => setSheet({ kind: 'info' })} onSettings={() => setScreen('settings')}
              onHistory={() => setSheet({ kind: 'history' })} onRefresh={retryDiscovery} onInternet={() => setSheet({ kind: 'internet' })} />
            {tab === 'receive'
              ? <ReceiveView key="receive" t={t} c={c} receiverOn={receiverOn} bottomInset={insets.bottom} onSettings={() => setScreen('settings')} />
              : <SendView key="send" t={t} c={c} devices={devices} networkReady={networkReady} selected={selected} outgoing={outgoing}
                trusted={settings.trusted} history={settings.history} bottomInset={insets.bottom}
                onPick={openPicker} onOpenFiles={() => setSheet({ kind: 'files' })} onSend={sendTo} onRetry={retryDiscovery}
                onDeviceMenu={device => setSheet({ kind: 'device', device })} onHistory={() => setSheet({ kind: 'history' })} />}
            <TabBar t={t} c={c} tab={tab} onChange={setTab} bottom={insets.bottom + 14} />
          </> : (
            <SettingsScreen t={t} c={c} settings={settings} update={updateSettings} alias={alias} pin={pin} receiverOn={receiverOn}
              bottomInset={insets.bottom} onBack={() => setScreen('home')} onEditName={() => setSheet({ kind: 'name' })} onPhoto={() => setSheet({ kind: 'photo' })}
              onPin={next => saveCoreConfig(alias, next)} onRestartReceiver={restartReceiver}
              onPrivacy={() => setSheet({ kind: 'privacy' })} onAbout={() => setSheet({ kind: 'about' })}
              onRemoveTrusted={fp => setTrusted(fp, '', false)} />
          )}
          {!!message && (
            <Pressable onPress={() => setMessage('')} accessibilityRole="button" accessibilityLabel={message}
              style={[styles.toast, { backgroundColor: c.toastBg, bottom: insets.bottom + 104 }]}>
              <Text style={{ color: c.toastText }}>{message}</Text>
            </Pressable>
          )}
          <Portal>
            <Modal visible={!!pending || !!received} onDismiss={() => (pending ? (pending.accepted ? undefined : answerIncoming(false)) : setReceived(null))}
              style={styles.modalHost} contentContainerStyle={modalCard}>
              {pending ? <IncomingCard transfer={pending} t={t} c={c} onAccept={() => answerIncoming(true)} onReject={() => answerIncoming(false)} onCancel={cancelIncoming} />
                : received ? <ReceivedCard t={t} c={c} received={received} trusted={isTrusted(received.fingerprint)}
                  onTrust={() => received.fingerprint && setTrusted(received.fingerprint, received.sender, true)} onClose={() => setReceived(null)} /> : null}
            </Modal>
            <Modal visible={!!sheet && !pending && !received} onDismiss={() => setSheet(null)} style={styles.modalHost} contentContainerStyle={modalCard}>
              {sheet?.kind === 'photo' && <PhotoSheet t={t} c={c} alias={alias} avatar={settings.avatar} onChoose={choosePhoto} onRemove={removePhoto} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'internet' && <InternetSheet t={t} c={c} files={selected} onPick={() => { setSheet(null); openPicker(); }}
                onHistory={addHistory} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'info' && <InfoSheet t={t} c={c} alias={alias} avatar={settings.avatar} mode={effectiveMode} receiverOn={receiverOn} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'files' && <FilesSheet t={t} c={c} files={selected} onRemove={id => setSelected(s => s.filter(f => f.id !== id))}
                onAdd={() => { setSheet(null); openPicker(); }} onClear={clearSelection} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'history' && <HistorySheet t={t} c={c} history={settings.history} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'device' && <DeviceSheet t={t} c={c} device={sheet.device} trusted={isTrusted(sheet.device.fingerprint)}
                onTrust={v => setTrusted(sheet.device.fingerprint, sheet.device.alias, v)} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'privacy' && <TextSheet t={t} c={c} title={t.privacyNotice} body={t.privacyText} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'about' && <AboutSheet t={t} c={c} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'name' && <NameSheet t={t} c={c} alias={alias} onSave={name => saveCoreConfig(name, pin)} onClose={() => setSheet(null)} />}
              {sheet?.kind === 'restart' && <RestartSheet t={t} c={c} onRestart={() => bridge?.restartApp?.()} onClose={() => setSheet(null)} />}
            </Modal>
          </Portal>
        </View>
      </PaperProvider>
    </MotionContext.Provider>
  );
}

function mergeDevice(devices: Device[], next: Device): Device[] {
  const exists = devices.some(device => device.fingerprint === next.fingerprint);
  return exists ? devices.map(device => device.fingerprint === next.fingerprint ? next : device) : [...devices, next];
}

/* ------------------------------------------------------------ top / tabs */

function TopBar({ t, c, alias, avatar, onInfo, onSettings, onHistory, onRefresh, onInternet }: {
  t: Copy; c: Palette; alias: string; avatar: string | null; onInfo: () => void; onSettings: () => void; onHistory: () => void; onRefresh: () => void; onInternet: () => void;
}) {
  return <View style={styles.topBar}>
    <View style={styles.topSide} />
    <View style={styles.topCenter}>
      <Pressable onPress={onInfo} accessibilityRole="button" accessibilityLabel={`${t.infoTitle}: ${alias}`}
        style={({ pressed }) => [styles.namePill, { backgroundColor: c.nav, opacity: pressed ? 0.85 : 1, boxShadow: c.shadow }]}>
        <Avatar name={alias} uri={avatar} size={30} />
        <Text style={[styles.nameText, { color: c.text }]} numberOfLines={1}>{alias}</Text>
      </Pressable>
    </View>
    <View style={[styles.topSide, styles.topRight]}>
      <Dropdown c={c} items={[
        { icon: 'refresh', label: t.menuRefresh, onPress: onRefresh },
        { icon: 'history', label: t.menuHistory, onPress: onHistory },
        { icon: 'web', label: t.menuInternet, onPress: onInternet },
        { icon: 'cog-outline', label: t.menuSettings, onPress: onSettings },
      ]} renderAnchor={open => <IconCircle icon="dots-vertical" color={c.text} label={t.menuSettings} onPress={open} />} />
    </View>
  </View>;
}

function TabBar({ t, c, tab, onChange, bottom }: { t: Copy; c: Palette; tab: Tab; onChange: (tab: Tab) => void; bottom: number }) {
  const [width, setWidth] = useState(0);
  const slide = useRef(new Animated.Value(tab === 'receive' ? 0 : 1)).current;
  useEffect(() => {
    Animated.spring(slide, { toValue: tab === 'receive' ? 0 : 1, useNativeDriver: true, speed: 18, bounciness: 6 }).start();
  }, [tab, slide]);
  const half = Math.max(0, (width - 8) / 2);
  const item = (key: Tab, icon: string, label: string) => {
    const active = tab === key;
    return <Pressable key={key} onPress={() => onChange(key)} accessibilityRole="tab" accessibilityState={{ selected: active }} accessibilityLabel={label} style={styles.tabItem}>
      <MaterialCommunityIcons name={icon as any} size={18} color={active ? c.text : c.sub} />
      <Text style={[styles.tabLabel, { color: active ? c.text : c.sub, fontWeight: active ? '700' : '500' }]}>{label}</Text>
    </Pressable>;
  };
  return <View pointerEvents="box-none" style={[styles.tabBarWrap, { bottom }]}>
    <View onLayout={e => setWidth(e.nativeEvent.layout.width)} style={[styles.tabBar, { backgroundColor: c.nav, boxShadow: c.shadow }]}>
      {half > 0 && <Animated.View style={[styles.tabIndicator, { width: half, backgroundColor: c.navActive,
        transform: [{ translateX: slide.interpolate({ inputRange: [0, 1], outputRange: [0, half] }) }] }]} />}
      {item('receive', 'tray-arrow-down', t.receiveTab)}
      {item('send', 'tray-arrow-up', t.sendTab)}
    </View>
  </View>;
}

/* --------------------------------------------------------------- receive */

function ReceiveView({ t, c, receiverOn, bottomInset, onSettings }: { t: Copy; c: Palette; receiverOn: boolean; bottomInset: number; onSettings: () => void }) {
  const { width } = useWindowDimensions();
  return <FadeIn style={styles.flex}>
    <View style={styles.receive}>
      <View style={styles.glowLayer}><ReceiveGlow c={c} size={Math.min(width * 1.25, 640)} /></View>
      <Text style={[styles.readyTitle, { color: c.text }]} accessibilityRole="header">{receiverOn ? t.readyTitle : t.readyOff}</Text>
      <Text style={[styles.readyHint, { color: c.sub }]}>{receiverOn ? t.readyHint : t.readyOffHint}</Text>
    </View>
    <Text style={[styles.settingsNote, { color: c.sub, marginBottom: bottomInset + 84 }]}>
      {t.goSettingsPrefix}
      <Text onPress={onSettings} accessibilityRole="link" style={[styles.link, { color: c.accent }]}>{t.goSettingsLink}</Text>
      {t.goSettingsSuffix}
    </Text>
  </FadeIn>;
}

/* ------------------------------------------------------------------ send */

type SendProps = {
  t: Copy; c: Palette; devices: Device[]; networkReady: boolean; selected: SharedFile[]; outgoing: Record<string, Outgoing>;
  trusted: { fingerprint: string }[]; history: HistoryEntry[]; bottomInset: number;
  onPick: (append: boolean) => void; onOpenFiles: () => void; onSend: (device: Device) => void; onRetry: () => void;
  onDeviceMenu: (device: Device) => void; onHistory: () => void;
};

function SendView(p: SendProps) {
  const { t, c } = p;
  if (!p.selected.length) {
    return <FadeIn style={styles.flex}>
      <View style={styles.choose}>
        <ShareIllustration c={c} />
        <Text style={[styles.chooseTitle, { color: c.text }]}>{t.chooseTitle}</Text>
        <Pill c={c} label={t.chooseButton} onPress={() => p.onPick(false)} filled large />
      </View>
    </FadeIn>;
  }
  return <FadeIn style={styles.flex}>
    <ScrollView style={styles.flex} contentContainerStyle={[styles.sendContent, { paddingBottom: p.bottomInset + 100 }]} showsVerticalScrollIndicator={false}>
      {isPreview && <Text style={[styles.previewNote, { color: c.sub, backgroundColor: c.chip }]}>{t.previewNote}</Text>}
      <SelectionCard t={t} c={c} files={p.selected} onAdd={() => p.onPick(true)} onOpen={p.onOpenFiles} />
      <SectionLabel c={c} text={t.nearby} />
      <View style={[styles.card, styles.nearbyCard, { backgroundColor: c.card }]}>
        {p.devices.length === 0 ? <View style={styles.empty}>
          <Pulse c={c} />
          <Text style={[styles.emptyTitle, { color: c.text }]}>{p.networkReady ? t.searching : t.permissionDenied}</Text>
          <Text style={[styles.hint, styles.center, { color: c.sub }]}>{t.emptyHint}</Text>
          <Pill c={c} label={t.retry} icon="refresh" onPress={p.onRetry} />
        </View> : <>
          <View style={styles.nearbyHint}>
            <Text style={[styles.hint, { color: c.sub }]}>{t.tapDevice}</Text>
            <Spinner size={14} color={c.sub} />
          </View>
          <View style={styles.grid}>
            {p.devices.map(device => <DeviceTile key={device.fingerprint} device={device} t={t} c={c} state={p.outgoing[device.fingerprint]}
              trusted={p.trusted.some(d => d.fingerprint === device.fingerprint)} onPress={() => p.onSend(device)} onLongPress={() => p.onDeviceMenu(device)} />)}
          </View>
        </>}
      </View>
      {p.history.length > 0 && <>
        <SectionLabel c={c} text={t.history} />
        <Pressable onPress={p.onHistory} style={[styles.card, styles.listCard, { backgroundColor: c.card }]}>
          {p.history.slice(0, 3).map((h, i) => <View key={h.id} style={styles.historyItem}>
            {i > 0 && <Separator c={c} />}
            <HistoryRow t={t} c={c} entry={h} />
          </View>)}
        </Pressable>
      </>}
    </ScrollView>
  </FadeIn>;
}

/**
 * Fanned cards above "Choose what to share". When the app may read the media
 * library they show the newest photo, video and document; otherwise generic
 * placeholders.
 */
function ShareIllustration({ c }: { c: Palette }) {
  const [latest, setLatest] = useState<{ images?: MediaItem; videos?: MediaItem; documents?: MediaItem }>({});
  useEffect(() => {
    let alive = true;
    (async () => {
      if (!(await bridge?.hasMediaPermission?.().catch(() => false))) return;
      const pick = async (kind: 'images' | 'videos' | 'documents') => (await bridge?.queryMedia?.(kind, 1, 0).catch(() => []))?.[0];
      const [images, videos, documents] = await Promise.all([pick('images'), pick('videos'), pick('documents')]);
      if (alive) setLatest({ images, videos, documents });
    })();
    return () => { alive = false; };
  }, []);
  const cards: Array<{ key: 'documents' | 'videos' | 'images'; rotate: string; x: number; y: number; icon: string; tint: string }> = [
    { key: 'documents', rotate: '-14deg', x: -78, y: 18, icon: 'file-document-outline', tint: '#7AA7FF' },
    { key: 'videos', rotate: '12deg', x: 78, y: -6, icon: 'play', tint: '#F2A65A' },
    { key: 'images', rotate: '-2deg', x: 0, y: 26, icon: 'image-outline', tint: '#6FD3B5' },
  ];
  return <View style={styles.illustration}>
    {cards.map(card => {
      const item = latest[card.key];
      const visual = item && card.key !== 'documents';
      return <View key={card.key} style={[styles.illCard, { backgroundColor: c.card, borderColor: c.dark ? '#2E2E2E' : '#E6E7EC', boxShadow: c.shadow,
        transform: [{ translateX: card.x }, { translateY: card.y }, { rotate: card.rotate }] }]}>
        {visual
          ? <Thumb item={item} c={c} size={384} radius={18} style={StyleSheet.absoluteFill} />
          : <>
            <View style={[styles.illIcon, { backgroundColor: `${card.tint}33` }]}>
              <MaterialCommunityIcons name={card.icon as any} size={30} color={card.tint} />
            </View>
            {item ? <Text style={[styles.illName, { color: c.text }]} numberOfLines={3}>{item.name}</Text> : <>
              <View style={[styles.illLine, styles.illLineLong, { backgroundColor: c.faint }]} />
              <View style={[styles.illLine, styles.illLineShort, { backgroundColor: c.faint }]} />
            </>}
            <View style={[styles.illBlock, { backgroundColor: c.chip }]} />
          </>}
        {visual && <View style={styles.illBadge}>
          <MaterialCommunityIcons name={card.icon as any} size={18} color="#fff" />
        </View>}
      </View>;
    })}
  </View>;
}

function SelectionCard({ t, c, files, onAdd, onOpen }: { t: Copy; c: Palette; files: SharedFile[]; onAdd: () => void; onOpen: () => void }) {
  const total = files.reduce((sum, f) => sum + f.size, 0);
  return <Pressable onPress={onOpen} accessibilityRole="button" accessibilityLabel={`${t.selectedTitle}: ${t.items(files.length)}`}
    style={({ pressed }) => [styles.card, styles.selectionCard, { backgroundColor: pressed ? c.faint : c.card }]}>
    <View style={styles.thumbStack}>
      {files.slice(0, 3).reverse().map((f, i, arr) => {
        const depth = arr.length - 1 - i;
        const visual = /^(image|video)\//.test(f.mimeType);
        return <View key={f.id} style={[styles.thumb, { backgroundColor: depth ? c.chip : c.accentSoft, borderColor: c.card,
          transform: [{ translateX: depth * -5 }, { rotate: `${depth * -9}deg` }] }]}>
          {visual ? <Thumb item={f} c={c} size={192} radius={12} style={StyleSheet.absoluteFill} />
            : <MaterialCommunityIcons name={fileIcon(f.mimeType) as any} size={26} color={c.accent} />}
        </View>;
      })}
    </View>
    <View style={styles.rowText}>
      <Text style={[styles.rowTitle, { color: c.text }]} numberOfLines={1}>{files.length === 1 ? files[0].name : t.items(files.length)}</Text>
      <Text style={[styles.rowSub, { color: c.sub }]}>{formatSize(total)}</Text>
    </View>
    <Pill c={c} label={t.add} icon="plus" onPress={onAdd} />
  </Pressable>;
}

function DeviceTile({ device, t, c, state, trusted, onPress, onLongPress }: { device: Device; t: Copy; c: Palette; state?: Outgoing; trusted: boolean; onPress: () => void; onLongPress: () => void }) {
  const icon = deviceIcon(device);
  const size = 60;
  const busy = state?.status === 'sending' || state?.status === 'waiting';
  const sub = state?.status === 'waiting' ? t.waiting
    : state?.status === 'sending' ? `${Math.round(state.progress * 100)}%`
      : state?.status === 'sent' ? t.sent : state?.status === 'failed' ? t.failed : deviceLabel(device, t);
  const subColor = state?.status === 'sent' ? c.success : state?.status === 'failed' ? c.danger : busy ? c.accent : c.sub;
  const press = useRef(new Animated.Value(1)).current;
  const pressTo = (v: number) => Animated.spring(press, { toValue: v, useNativeDriver: true, speed: 40, bounciness: 8 }).start();
  return <Pressable onPress={onPress} onLongPress={onLongPress} onPressIn={() => pressTo(0.92)} onPressOut={() => pressTo(1)} accessibilityRole="button" style={styles.tile}
    accessibilityLabel={`${device.alias}, ${sub}${trusted ? `, ${t.trustedBadge}` : ''}${busy ? `, ${t.tapToCancel}` : ''}`}>
    <Animated.View style={[styles.tileAvatar, { width: size + 14, height: size + 14, transform: [{ scale: press }] }]}>
      {busy && <Halo c={c} size={size + 14} />}
      {state?.status === 'sent'
        ? <SuccessBadge c={c} size={size} />
        : icon
          ? <View style={[styles.circle, { width: size, height: size, borderRadius: size / 2, backgroundColor: c.chip }]}>
            <MaterialCommunityIcons name={icon as any} size={30} color={c.accent} />
          </View>
          : <LetterAvatar name={device.alias} size={size} />}
      {busy && <View style={styles.overlay}>
        {state?.status === 'waiting'
          ? <Spinner size={size + 10} color={c.accent} stroke={3.5} />
          : <ProgressRing size={size + 10} stroke={3.5} progress={Math.max(0.03, state!.progress)} color={c.accent} track={c.faint} />}
      </View>}
      {trusted && state?.status !== 'sent' && <View style={[styles.badge, styles.badgeTop, { backgroundColor: c.accent, borderColor: c.card }]}>
        <MaterialCommunityIcons name="shield-check" size={11} color="#fff" />
      </View>}
      {state?.status === 'failed' && <View style={[styles.badge, { backgroundColor: c.danger, borderColor: c.card }]}>
        <MaterialCommunityIcons name="exclamation" size={12} color="#fff" />
      </View>}
    </Animated.View>
    <Text style={[styles.tileName, { color: c.text }]} numberOfLines={1}>{device.alias}</Text>
    <Text style={[styles.tileSub, { color: subColor }]} numberOfLines={1}>{sub}</Text>
  </Pressable>;
}

/* ------------------------------------------------------------- incoming */

function IncomingCard({ transfer, t, c, onAccept, onReject, onCancel }: { transfer: IncomingTransfer; t: Copy; c: Palette; onAccept: () => void; onReject: () => void; onCancel: () => void }) {
  const total = transfer.files.reduce((sum, f) => sum + f.size, 0);
  const progress = transfer.progress ?? 0;
  return <View>
    <View style={styles.row}>
      <View style={styles.ringAvatar}>
        <LetterAvatar name={transfer.sender} size={44} />
        {transfer.accepted && <View style={styles.overlay}><ProgressRing size={54} stroke={3} progress={Math.max(0.03, progress)} color={c.accent} track={c.faint} /></View>}
      </View>
      <View style={styles.rowText}>
        <Text style={[styles.rowTitle, { color: c.text }]} numberOfLines={1}>{transfer.sender}</Text>
        <Text style={[styles.rowSub, { color: c.sub }]}>{t.items(transfer.files.length)} · {formatSize(total)}</Text>
      </View>
      {transfer.accepted && <Text style={[styles.percent, { color: c.accent }]}>{Math.round(progress * 100)}%</Text>}
    </View>
    <Text style={[styles.sheetBigTitle, { color: c.text }]}>{transfer.accepted ? t.receiving : t.acceptTitle}</Text>
    {!transfer.accepted && <Text style={[styles.rowSub, { color: c.sub }]}>{t.wantsToShare(transfer.sender, transfer.files.length)}</Text>}
    <View style={[styles.fileBox, { backgroundColor: c.bg }]}>
      {transfer.files.slice(0, 4).map(file => {
        const fp = transfer.fileProgress?.[file.id];
        return <View key={file.id} style={styles.fileRow}>
          <View style={[styles.fileIcon, { backgroundColor: c.accentSoft }]}>
            <MaterialCommunityIcons name={(fp != null && fp >= 1 ? 'check' : fileIcon(file.mimeType)) as any} size={22} color={c.accent} />
          </View>
          <View style={styles.rowText}>
            <Text style={[styles.fileName, { color: c.text }]} numberOfLines={1}>{file.name}</Text>
            {transfer.accepted && fp != null && fp < 1 ? <LinearProgress c={c} progress={fp} /> : <Text style={[styles.rowSub, { color: c.sub }]}>{formatSize(file.size)}</Text>}
          </View>
        </View>;
      })}
      {transfer.files.length > 4 && <Text style={[styles.rowSub, styles.more, { color: c.sub }]}>+{transfer.files.length - 4}</Text>}
    </View>
    <View style={styles.actions}>
      {transfer.accepted ? <Pill c={c} label={t.cancel} onPress={onCancel} outlined /> : <>
        <Pill c={c} label={t.decline} onPress={onReject} outlined />
        <Pill c={c} label={t.accept} onPress={onAccept} filled />
      </>}
    </View>
  </View>;
}

function ReceivedCard({ t, c, received, trusted, onTrust, onClose }: { t: Copy; c: Palette; received: Received; trusted: boolean; onTrust: () => void; onClose: () => void }) {
  return <View style={styles.centerBlock}>
    <SuccessBadge c={c} size={72} burst />
    <Text style={[styles.sheetBigTitle, styles.center, { color: c.text }]}>{t.allSet}</Text>
    <Text style={[styles.rowSub, styles.center, { color: c.sub }]}>{t.receivedFrom(received.count, received.sender)}</Text>
    <View style={[styles.noteRow, { backgroundColor: c.bg }]}>
      <MaterialCommunityIcons name="shield-check-outline" size={18} color={c.accent} />
      <Text style={[styles.rowSub, styles.flexText, { color: c.sub }]}>{t.verified}</Text>
    </View>
    <View style={[styles.actions, styles.wrapActions]}>
      {!trusted && !!received.fingerprint && <Pill c={c} label={t.trustDevice} icon="shield-check-outline" outlined onPress={onTrust} />}
      {bridge?.openDownloads && <Pill c={c} label={t.viewDownloads} icon="folder-download-outline" outlined onPress={() => { bridge?.openDownloads?.().catch(() => undefined); onClose(); }} />}
      <Pill c={c} label={t.ok} onPress={onClose} filled />
    </View>
  </View>;
}

/* ---------------------------------------------------------------- sheets */

/**
 * Transfers over the internet (iroh): works when the devices are on different networks (mobile data,
 * another Wi-Fi). Sending shows a code to pass on (any messenger); receiving takes that code. Sharing runs
 * while this sheet is open. The local-network flow is not involved.
 */
function InternetSheet({ t, c, files, onPick, onHistory, onClose }: {
  t: Copy; c: Palette; files: SharedFile[]; onPick: () => void;
  onHistory: (entry: Omit<HistoryEntry, 'id' | 'at'>) => void; onClose: () => void;
}) {
  type State =
    | { step: 'menu' } | { step: 'preparing' } | { step: 'sharing'; code: string; peer: boolean; sent: number }
    | { step: 'enter' } | { step: 'receiving'; done: number; total: number } | { step: 'received'; count: number }
    | { step: 'error'; message: string };
  const [state, setState] = useState<State>({ step: 'menu' });
  const [code, setCode] = useState('');
  // Edge-to-edge windows are not resized for the keyboard; lift the sheet above it while typing the code.
  const [keyboard, setKeyboard] = useState(0);
  useEffect(() => {
    const show = Keyboard.addListener('keyboardDidShow', e => setKeyboard(e.endCoordinates.height));
    const hide = Keyboard.addListener('keyboardDidHide', () => setKeyboard(0));
    return () => { show.remove(); hide.remove(); };
  }, []);
  const idRef = useRef<string | null>(null);
  const size = files.reduce((n, f) => n + f.size, 0);

  useEffect(() => {
    const sub = subscribe((event: any) => {
      if (event.type !== 'internet' || event.id !== idRef.current) return;
      const e = event.event ?? {};
      switch (e.type) {
        case 'ticket': setState({ step: 'sharing', code: e.ticket, peer: false, sent: 0 }); break;
        case 'peerConnected': setState(s => s.step === 'sharing' ? { ...s, peer: true } : s); break;
        case 'sent':
          setState(s => s.step === 'sharing' ? { ...s, sent: e.count } : s);
          onHistory({ direction: 'sent', peer: t.internetPeer, count: files.length, size, ok: true });
          break;
        case 'connecting': setState({ step: 'receiving', done: 0, total: 0 }); break;
        case 'progress': setState({ step: 'receiving', done: e.done, total: e.total }); break;
        case 'received':
          setState({ step: 'received', count: (e.files ?? []).length });
          onHistory({ direction: 'received', peer: t.internetPeer, count: (e.files ?? []).length, size: e.size ?? 0, ok: true });
          idRef.current = null;
          break;
        case 'error': setState({ step: 'error', message: e.message ?? '' }); idRef.current = null; break;
      }
    });
    return () => {
      sub.remove();
      if (idRef.current) bridge?.internetCancel?.(idRef.current).catch(() => undefined);
    };
  }, [files.length, onHistory, size, t.internetPeer]);

  const startSend = async () => {
    setState({ step: 'preparing' });
    try { idRef.current = await bridge!.internetSend!(files); } catch (e: any) { setState({ step: 'error', message: e?.message ?? '' }); }
  };
  const startReceive = async () => {
    try {
      setState({ step: 'receiving', done: 0, total: 0 });
      idRef.current = await bridge!.internetReceive!(code.trim());
    } catch (e: any) {
      setState({ step: 'error', message: e?.code === 'invalid_code' ? t.internetInvalid : e?.message ?? '' });
    }
  };
  const stop = () => { if (idRef.current) bridge?.internetCancel?.(idRef.current).catch(() => undefined); idRef.current = null; onClose(); };
  const available = !!bridge?.internetSend;

  return <View style={{ paddingBottom: keyboard }}>
    <SheetHeader t={t} c={c} title={t.internetTitle} onClose={stop} />
    {state.step === 'menu' && <>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: c.sub }]}>{available ? t.internetIntro : t.internetUnavailable}</Text>
      {available && <View style={[styles.group, { backgroundColor: c.bg }]}>
        <Row c={c} title={t.internetSend} hint={files.length ? t.internetSendHint(files.length, formatSize(size)) : t.internetPickFirst}
          onPress={files.length ? startSend : onPick} right={<MaterialCommunityIcons name="upload-network-outline" size={22} color={c.accent} />} />
        <Row c={c} title={t.internetReceive} hint={t.internetReceiveHint} onPress={() => setState({ step: 'enter' })}
          right={<MaterialCommunityIcons name="download-network-outline" size={22} color={c.accent} />} />
      </View>}
    </>}
    {state.step === 'preparing' && <Text style={[styles.rowSub, styles.sheetIntro, { color: c.sub }]}>{t.internetPreparing}</Text>}
    {state.step === 'sharing' && <>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: c.sub }]}>{t.internetShareCode}</Text>
      <View style={[styles.codeBox, { backgroundColor: c.bg, borderColor: c.faint }]}>
        <Text selectable numberOfLines={4} style={[styles.codeText, { color: c.text }]}>{state.code}</Text>
      </View>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: state.sent ? c.success : c.sub }]}>
        {state.sent ? t.internetSent : state.peer ? t.internetPeerConnected : t.internetWaiting}
      </Text>
      <View style={styles.actions}>
        <Pill c={c} label={t.internetStop} icon="stop" outlined onPress={stop} />
        <Pill c={c} label={t.internetShareButton} icon="share-variant" filled onPress={() => { Share.share({ message: state.code }).catch(() => undefined); }} />
      </View>
    </>}
    {state.step === 'enter' && <>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: c.sub }]}>{t.internetEnterCode}</Text>
      <TextInput value={code} onChangeText={setCode} autoFocus multiline autoCapitalize="none" autoCorrect={false}
        accessibilityLabel={t.internetEnterCode} placeholder="blob…" placeholderTextColor={c.sub}
        style={[styles.input, styles.codeInput, { color: c.text, backgroundColor: c.bg, borderColor: code.trim() ? c.accent : c.faint, fontFamily: fontFor('400') }]} />
      <View style={styles.actions}>
        <Pill c={c} label={t.internetReceiveButton} icon="download" filled onPress={() => { if (code.trim()) startReceive(); }} />
      </View>
    </>}
    {state.step === 'receiving' && <>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: c.sub }]}>
        {state.total ? t.internetProgress(formatSize(state.done), formatSize(state.total)) : t.internetConnecting}
      </Text>
      <View style={[styles.progressTrack, { backgroundColor: c.chip }]}>
        <View style={[styles.progressFill, { backgroundColor: c.accent, width: `${state.total ? Math.round((state.done / state.total) * 100) : 4}%` }]} />
      </View>
      <View style={styles.actions}><Pill c={c} label={t.cancel} icon="close" outlined onPress={stop} /></View>
    </>}
    {state.step === 'received' && <>
      <Text style={[styles.infoName, styles.center, { color: c.success }]}>{t.received}</Text>
      <Text style={[styles.rowSub, styles.center, styles.sheetIntro, { color: c.sub }]}>{t.internetReceived(state.count)}</Text>
      <View style={styles.actions}>
        <Pill c={c} label={t.viewDownloads} icon="folder-download-outline" outlined onPress={() => { bridge?.openDownloads?.().catch(() => undefined); }} />
        <Pill c={c} label={t.ok} filled onPress={onClose} />
      </View>
    </>}
    {state.step === 'error' && <>
      <Text style={[styles.rowSub, styles.sheetIntro, { color: c.danger }]}>{t.internetFailed}{state.message ? `\n${state.message}` : ''}</Text>
      <View style={styles.actions}><Pill c={c} label={t.ok} filled onPress={() => setState({ step: 'menu' })} /></View>
    </>}
  </View>;
}

function SheetHeader({ t, c, title, onClose }: { t: Copy; c: Palette; title: string; onClose: () => void }) {
  return <View style={styles.sheetHeader}>
    <Text style={[styles.sheetTitle, { color: c.text }]}>{title}</Text>
    <IconCircle icon="close" color={c.sub} label={t.close} onPress={onClose} size={22} />
  </View>;
}

function InfoSheet({ t, c, alias, avatar, mode, receiverOn, onClose }: { t: Copy; c: Palette; alias: string; avatar: string | null; mode: ShareMode; receiverOn: boolean; onClose: () => void }) {
  const [net, setNet] = useState<NetworkInfo | null>(null);
  const [version, setVersion] = useState('');
  useEffect(() => {
    bridge?.getNetworkInfo?.().then(setNet).catch(() => setNet({ addresses: [], port: PORT }));
    bridge?.getAppInfo().then(info => setVersion(info.version)).catch(() => undefined);
  }, []);
  const [chosenIp, setChosenIp] = useState<string | null>(null);
  const open = receiverOn && mode !== 'off';
  const status = !open ? t.statusOff : mode === 'trusted' ? t.statusTrusted : t.statusEveryone;
  const addresses = net?.addresses ?? [];
  // With several network interfaces, one address is shown and the others are offered in a dropdown.
  const ip = chosenIp && addresses.includes(chosenIp) ? chosenIp : addresses[0];
  return <View>
    <SheetHeader t={t} c={c} title={t.infoTitle} onClose={onClose} />
    <View style={styles.infoHero}>
      <View>
        <Avatar name={alias} uri={avatar} size={64} />
        <View style={[styles.statusDot, { backgroundColor: open ? '#34C759' : c.sub, borderColor: c.card }]} />
      </View>
      <Text style={[styles.infoName, { color: c.text }]} numberOfLines={1}>{alias}</Text>
      <Text style={[styles.rowSub, styles.center, { color: open ? c.accent : c.sub }]}>{status}</Text>
    </View>
    <View style={[styles.infoBox, { backgroundColor: c.bg }]}>
      {net && addresses.length > 1
        ? <Dropdown c={c} align="right" width={250}
          items={addresses.map(a => ({ label: `${a}:${net.port}`, checked: a === ip, onPress: () => setChosenIp(a) }))}
          renderAnchor={openMenu => <Pressable onPress={openMenu} accessibilityRole="button" accessibilityLabel={`${t.address}: ${ip}:${net.port}`}
            style={({ pressed }) => [styles.infoRow, pressed && { opacity: 0.7 }]}>
            <MaterialCommunityIcons name="ip-network-outline" size={20} color={c.sub} />
            <Text style={[styles.infoLabel, { color: c.sub }]}>{t.address}</Text>
            <Text style={[styles.infoValue, { color: c.text }]}>{`${ip}:${net.port}`}</Text>
            <MaterialCommunityIcons name="menu-down" size={20} color={c.sub} />
          </Pressable>} />
        : <InfoRow c={c} icon="ip-network-outline" label={t.address}
          value={net == null ? '…' : ip ? `${ip}:${net.port}` : t.noNetwork} />}
      <InfoRow c={c} icon="lock-outline" label={t.protocol} value={t.protocolValue} />
      {!!version && <InfoRow c={c} icon="information-outline" label={t.version} value={version} />}
    </View>
  </View>;
}

function InfoRow({ c, icon, label, value }: { c: Palette; icon: string; label: string; value: string }) {
  return <View style={styles.infoRow}>
    <MaterialCommunityIcons name={icon as any} size={20} color={c.sub} />
    <Text style={[styles.infoLabel, { color: c.sub }]}>{label}</Text>
    <Text style={[styles.infoValue, { color: c.text }]} selectable>{value}</Text>
  </View>;
}

function FilesSheet({ t, c, files, onRemove, onAdd, onClear, onClose }: { t: Copy; c: Palette; files: SharedFile[]; onRemove: (id: string) => void; onAdd: () => void; onClear: () => void; onClose: () => void }) {
  useEffect(() => { if (!files.length) onClose(); }, [files.length, onClose]);
  const total = files.reduce((sum, f) => sum + f.size, 0);
  return <View>
    <SheetHeader t={t} c={c} title={t.selectedTitle} onClose={onClose} />
    <Text style={[styles.rowSub, styles.sheetSub, { color: c.sub }]}>{t.items(files.length)} · {formatSize(total)}</Text>
    <ScrollView style={styles.sheetScroll}>
      {files.map(file => <View key={file.id} style={styles.fileRow}>
        <View style={[styles.fileIcon, { backgroundColor: c.accentSoft }]}>
          <MaterialCommunityIcons name={fileIcon(file.mimeType) as any} size={22} color={c.accent} />
        </View>
        <View style={styles.rowText}>
          <Text style={[styles.fileName, { color: c.text }]} numberOfLines={1}>{file.name}</Text>
          <Text style={[styles.rowSub, { color: c.sub }]}>{formatSize(file.size)}</Text>
        </View>
        <IconCircle icon="close-circle-outline" color={c.sub} label={`${t.remove} ${file.name}`} onPress={() => onRemove(file.id)} size={20} />
      </View>)}
    </ScrollView>
    <View style={styles.actions}>
      <Pill c={c} label={t.clear} icon="delete-outline" onPress={onClear} outlined />
      <Pill c={c} label={t.add} icon="plus" onPress={onAdd} filled />
    </View>
  </View>;
}

function HistorySheet({ t, c, history, onClose }: { t: Copy; c: Palette; history: HistoryEntry[]; onClose: () => void }) {
  return <View>
    <SheetHeader t={t} c={c} title={t.history} onClose={onClose} />
    {history.length === 0
      ? <Text style={[styles.rowSub, styles.historyEmpty, { color: c.sub }]}>{t.historyEmpty}</Text>
      : <ScrollView style={styles.sheetScroll}>{history.map(h => <HistoryRow key={h.id} t={t} c={c} entry={h} />)}</ScrollView>}
    {history.length > 0 && bridge?.openDownloads && <View style={styles.actions}>
      <Pill c={c} label={t.viewDownloads} icon="folder-download-outline" onPress={() => bridge?.openDownloads?.().catch(() => undefined)} outlined />
    </View>}
  </View>;
}

function HistoryRow({ t, c, entry }: { t: Copy; c: Palette; entry: HistoryEntry }) {
  const icon = !entry.ok ? 'alert-circle-outline' : entry.direction === 'sent' ? 'arrow-top-right' : 'arrow-bottom-left';
  return <View style={styles.historyRow}>
    <View style={[styles.fileIcon, { backgroundColor: entry.ok ? c.accentSoft : c.chip }]}>
      <MaterialCommunityIcons name={icon as any} size={20} color={entry.ok ? c.accent : c.danger} />
    </View>
    <View style={styles.rowText}>
      <Text style={[styles.fileName, { color: c.text }]} numberOfLines={1}>
        {entry.ok ? (entry.direction === 'sent' ? t.sentTo(entry.count, entry.peer) : t.receivedFrom(entry.count, entry.peer)) : `${t.failedLabel} · ${entry.peer}`}
      </Text>
      <Text style={[styles.rowSub, { color: c.sub }]}>{formatSize(entry.size)} · {timeAgo(entry.at, t)}</Text>
    </View>
  </View>;
}

function DeviceSheet({ t, c, device, trusted, onTrust, onClose }: { t: Copy; c: Palette; device: Device; trusted: boolean; onTrust: (v: boolean) => void; onClose: () => void }) {
  return <View>
    <SheetHeader t={t} c={c} title={device.alias} onClose={onClose} />
    <View style={[styles.infoBox, { backgroundColor: c.bg }]}>
      <InfoRow c={c} icon="devices" label={t.device} value={deviceLabel(device, t) + (device.deviceModel ? ` · ${device.deviceModel}` : '')} />
      <InfoRow c={c} icon="ip-network-outline" label={t.address} value={`${device.host}:${device.port}`} />
    </View>
    <Text style={[styles.rowSub, styles.trustHint, { color: c.sub }]}>{t.trustHint}</Text>
    <View style={styles.actions}>
      <Pill c={c} label={trusted ? t.untrustDevice : t.trustDevice} icon={trusted ? 'shield-off-outline' : 'shield-check-outline'}
        onPress={() => { onTrust(!trusted); onClose(); }} filled={!trusted} outlined={trusted} />
    </View>
  </View>;
}

function TextSheet({ t, c, title, body, onClose }: { t: Copy; c: Palette; title: string; body: string; onClose: () => void }) {
  return <View>
    <SheetHeader t={t} c={c} title={title} onClose={onClose} />
    <ScrollView style={styles.sheetScroll}><Text style={[styles.bodyText, { color: c.sub }]}>{body}</Text></ScrollView>
  </View>;
}

function AboutSheet({ t, c, onClose }: { t: Copy; c: Palette; onClose: () => void }) {
  const [version, setVersion] = useState('');
  useEffect(() => { bridge?.getAppInfo().then(info => setVersion(info.version)).catch(() => undefined); }, []);
  return <View>
    <SheetHeader t={t} c={c} title={t.aboutApp} onClose={onClose} />
    <View style={styles.centerBlock}>
      <AppIcon size={76} />
      <Text style={[styles.infoName, { color: c.text }]}>Quick Send</Text>
      {!!version && <Text style={[styles.rowSub, { color: c.sub }]}>{t.version} {version}</Text>}
      <Text style={[styles.rowSub, styles.center, styles.aboutLine, { color: c.sub }]}>{t.developer}</Text>
      <Text style={[styles.rowSub, styles.center, { color: c.sub }]}>{t.attribution}</Text>
      <Text style={[styles.rowSub, styles.center, { color: c.sub }]}>{t.licenses}</Text>
    </View>
    <View style={[styles.group, styles.aboutUpdate, { backgroundColor: c.bg }]}><UpdateCheck t={t} c={c} /></View>
  </View>;
}

function UpdateCheck({ t, c }: { t: Copy; c: Palette }) {
  const [checking, setChecking] = useState(false);
  const [result, setResult] = useState<UpdateResult | null>(null);
  const run = async () => {
    setChecking(true);
    const info = await bridge?.getAppInfo?.().catch(() => null);
    setResult(info ? await checkForUpdate(info.version, info.releasesRepo) : { kind: 'notConfigured' });
    setChecking(false);
  };
  const message = !result ? undefined
    : result.kind === 'available' ? t.updateAvailable(result.version)
      : result.kind === 'upToDate' ? t.upToDate : result.kind === 'failed' ? t.updateFailed : t.updateNotConfigured;
  const open = result?.kind === 'available' ? () => Linking.openURL(result.url) : undefined;
  return <Row c={c} title={checking ? t.checkingUpdates : open ? t.openRelease : t.checkUpdates} hint={message} onPress={checking ? undefined : open ?? run} />;
}

function NameSheet({ t, c, alias, onSave, onClose }: { t: Copy; c: Palette; alias: string; onSave: (name: string) => void; onClose: () => void }) {
  const [value, setValue] = useState(alias);
  const valid = value.trim().length > 0;
  return <View>
    <SheetHeader t={t} c={c} title={t.phoneName} onClose={onClose} />
    <TextInput value={value} onChangeText={setValue} autoFocus maxLength={40} accessibilityLabel={t.phoneName}
      style={[styles.input, { color: c.text, backgroundColor: c.bg, borderColor: valid ? c.accent : c.danger, fontFamily: fontFor('500') }]}
      onSubmitEditing={() => valid && onSave(value.trim())} />
    <Text style={[styles.rowSub, styles.inputHint, { color: valid ? c.sub : c.danger }]}>{valid ? t.phoneNameHint : t.nameEmpty}</Text>
    <View style={styles.actions}>
      <Pill c={c} label={t.cancel} onPress={onClose} outlined />
      <Pill c={c} label={t.save} onPress={() => valid && onSave(value.trim())} filled />
    </View>
  </View>;
}

function PhotoSheet({ t, c, alias, avatar, onChoose, onRemove, onClose }: { t: Copy; c: Palette; alias: string; avatar: string | null; onChoose: () => void; onRemove: () => void; onClose: () => void }) {
  return <View>
    <SheetHeader t={t} c={c} title={t.profilePhoto} onClose={onClose} />
    <View style={styles.infoHero}><Avatar name={alias} uri={avatar} size={96} /></View>
    <Text style={[styles.rowSub, styles.center, { color: c.sub }]}>{t.profileHint}</Text>
    <View style={styles.actions}>
      {!!avatar && <Pill c={c} label={t.removePhoto} icon="delete-outline" onPress={onRemove} outlined />}
      <Pill c={c} label={t.choosePhoto} icon="image-outline" onPress={onChoose} filled />
    </View>
  </View>;
}

function RestartSheet({ t, c, onRestart, onClose }: { t: Copy; c: Palette; onRestart: () => void; onClose: () => void }) {
  return <View>
    <SheetHeader t={t} c={c} title={t.restartTitle} onClose={onClose} />
    <Text style={[styles.bodyText, { color: c.sub }]}>{t.restartBody}</Text>
    <View style={styles.actions}>
      <Pill c={c} label={t.later} onPress={onClose} outlined />
      <Pill c={c} label={t.restartNow} onPress={onRestart} filled />
    </View>
  </View>;
}

/* -------------------------------------------------------------- settings */

type SettingsProps = {
  t: Copy; c: Palette; settings: Settings; update: (patch: Partial<Settings>) => void; alias: string; pin: string | null; receiverOn: boolean;
  bottomInset: number; onBack: () => void; onEditName: () => void; onPhoto: () => void; onPin: (pin: string | null) => void; onRestartReceiver: () => void;
  onPrivacy: () => void; onAbout: () => void; onRemoveTrusted: (fingerprint: string) => void;
};

function SettingsScreen(p: SettingsProps) {
  const { t, c, settings: s, update } = p;
  const [contact, setContact] = useState<string | null>(null);
  useEffect(() => {
    bridge?.getAppInfo().then(info => info.releasesRepo && setContact(`https://github.com/${info.releasesRepo}/issues`)).catch(() => undefined);
  }, []);
  const modeLabel = { off: t.modeOff, trusted: t.modeTrusted, everyone: t.modeEveryone }[s.shareMode];
  return <FadeIn style={styles.flex}>
    <View style={styles.settingsHeader}>
      <IconCircle icon="arrow-left" color={c.text} label={t.back} onPress={p.onBack} />
      <Text style={[styles.settingsTitle, { color: c.text }]} accessibilityRole="header">{t.settings}</Text>
    </View>
    <ScrollView style={styles.flex} contentContainerStyle={[styles.settingsContent, { paddingBottom: p.bottomInset + 32 }]}>
      <Group c={c} title={t.secNearby}>
        <ChoiceRow c={c} title={t.whoCanShare} value={s.shareMode} label={modeLabel} onChange={v => update({ shareMode: v as ShareMode })}
          options={[{ value: 'off', label: t.modeOff }, { value: 'trusted', label: t.modeTrusted }, { value: 'everyone', label: t.modeEveryone }]} />
        <View style={styles.profileRow}>
          <Pressable onPress={p.onPhoto} accessibilityRole="button" accessibilityLabel={t.profilePhoto} hitSlop={6}
            style={({ pressed }) => [styles.profilePhoto, { opacity: pressed ? 0.7 : 1 }]}>
            <Avatar name={p.alias} uri={s.avatar} size={52} />
            <View style={[styles.photoBadge, { backgroundColor: c.accent, borderColor: c.card }]}>
              <MaterialCommunityIcons name="camera" size={12} color="#fff" />
            </View>
          </Pressable>
          <Pressable onPress={p.onEditName} accessibilityRole="button" accessibilityLabel={`${t.phoneName}: ${p.alias}`}
            style={({ pressed }) => [styles.profileName, pressed && { backgroundColor: c.faint }]}>
            <View style={styles.flexText}>
              <Text style={[styles.profileTitle, { color: c.text }]}>{t.phoneName}</Text>
              <Text style={[styles.profileValue, { color: c.accent }]} numberOfLines={1}>{p.alias}</Text>
            </View>
            <MaterialCommunityIcons name="pencil-outline" size={20} color={c.sub} />
          </Pressable>
        </View>
      </Group>

      <Group c={c} title={t.secReceive}>
        <SwitchRow c={c} title={t.quickSave} hint={t.quickSaveDesc} value={s.quickSave} onChange={v => update({ quickSave: v })} />
        <SwitchRow c={c} title={t.autoTrusted} hint={t.autoTrustedDesc} value={s.autoAcceptTrusted} onChange={v => update({ autoAcceptTrusted: v })} />
        <BackgroundRow t={t} c={c} />
        <SwitchRow c={c} title={t.requirePin} hint={p.pin ? t.pinIs(p.pin) : t.requirePinDesc} value={!!p.pin} onChange={v => p.onPin(v ? randomPin() : null)}
          extra={p.pin ? <IconCircle icon="refresh" color={c.sub} label={t.newPin} onPress={() => p.onPin(randomPin())} size={20} /> : undefined} />
        <Row c={c} title={t.destination} value={t.destinationValue} />
        <SwitchRow c={c} title={t.autoFinish} hint={t.autoFinishDesc} value={s.autoFinish} onChange={v => update({ autoFinish: v })} />
        <SwitchRow c={c} title={t.saveHistory} hint={t.saveHistoryDesc} value={s.saveHistory} onChange={v => update({ saveHistory: v })} />
      </Group>

      <Group c={c} title={t.secTrusted}>
        {s.trusted.length === 0
          ? <Row c={c} title={t.trustedEmpty} />
          : s.trusted.map(d => <Row key={d.fingerprint} c={c} title={d.alias} hint={`${d.fingerprint.slice(0, 16)}…`}
            right={<IconCircle icon="delete-outline" color={c.sub} label={`${t.remove} ${d.alias}`} onPress={() => p.onRemoveTrusted(d.fingerprint)} size={22} />} />)}
      </Group>

      <Group c={c} title={t.secLook}>
        <ChoiceRow c={c} title={t.language} value={s.language ?? 'auto'} label={s.language === 'tr' ? 'Türkçe' : s.language === 'en' ? 'English' : t.langAuto}
          onChange={v => update({ language: v === 'auto' ? null : (v as Language) })}
          options={[{ value: 'auto', label: t.langAuto }, { value: 'en', label: 'English' }, { value: 'tr', label: 'Türkçe' }]} />
        <ChoiceRow c={c} title={t.theme} value={s.appearance} label={{ system: t.themeSystem, light: t.themeLight, dark: t.themeDark }[s.appearance]}
          onChange={v => update({ appearance: v as Settings['appearance'] })}
          options={[{ value: 'system', label: t.themeSystem }, { value: 'light', label: t.themeLight }, { value: 'dark', label: t.themeDark }]} />
        <SwitchRow c={c} title={t.animations} value={s.animations} onChange={v => update({ animations: v })} />
      </Group>

      <Group c={c} title={t.secNetwork}>
        <Row c={c} title={t.serverTitle} hint={p.receiverOn ? t.serverRunning(PORT) : t.serverStopped} right={<View style={styles.serverButtons}>
          <IconCircle icon="refresh" color={c.accent} label={t.restart} onPress={p.onRestartReceiver} />
          {p.receiverOn
            ? <IconCircle icon="stop" color={c.danger} label={t.stop} onPress={() => update({ shareMode: 'off' })} />
            : <IconCircle icon="play" color={c.accent} label={t.start} onPress={() => update({ shareMode: s.shareMode === 'off' ? 'trusted' : s.shareMode })} />}
        </View>} />
      </Group>

      <Group c={c} title={t.secPrivacy}>
        <Row c={c} title={t.privacyNotice} onPress={p.onPrivacy} />
      </Group>

      <View style={styles.groupGap} />
      <Group c={c}>
        <AutoUpdateRow t={t} c={c} value={s.autoUpdate} onChange={v => update({ autoUpdate: v })} />
        <Row c={c} title={t.aboutApp} onPress={p.onAbout} />
        {contact ? <Row c={c} title={t.contactUs} onPress={() => Linking.openURL(contact)} /> : null}
      </Group>
    </ScrollView>
  </FadeIn>;
}

/** Battery optimisation status; tapping asks Android to exempt Quick Send (needed for reliable background receiving). */
function BackgroundRow({ t, c }: { t: Copy; c: Palette }) {
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const refresh = useCallback(() => { bridge?.isBatteryUnrestricted?.().then(setAllowed).catch(() => undefined); }, []);
  useEffect(() => {
    refresh();
    const sub = AppState.addEventListener('change', state => state === 'active' && refresh());
    return () => sub.remove();
  }, [refresh]);
  if (allowed === null) return null;
  return <Row c={c} title={t.backgroundReceive} hint={allowed ? t.backgroundOn : t.backgroundOff}
    right={<MaterialCommunityIcons name={allowed ? 'check-circle' : 'battery-alert-variant-outline'} size={22} color={allowed ? c.success : c.danger} />}
    onPress={allowed ? undefined : () => { bridge?.requestBatteryUnrestricted?.().catch(() => undefined); }} />;
}

/** Signed background updates (only in builds with a releases repository and update key). */
function AutoUpdateRow({ t, c, value, onChange }: { t: Copy; c: Palette; value: boolean; onChange: (v: boolean) => void }) {
  const [supported, setSupported] = useState(false);
  useEffect(() => { bridge?.getUpdateSupport?.().then(r => setSupported(r.supported)).catch(() => undefined); }, []);
  return <SwitchRow c={c} title={t.autoUpdate} hint={supported ? t.autoUpdateDesc : t.autoUpdateUnavailable}
    value={supported && value} onChange={v => supported && onChange(v)} />;
}

function ChoiceRow({ c, title, value, label, options, onChange }: { c: Palette; title: string; value: string; label: string; options: Array<{ value: string; label: string }>; onChange: (v: string) => void }) {
  return <Dropdown c={c} align="left" width={240} items={options.map(o => ({ label: o.label, checked: o.value === value, onPress: () => onChange(o.value) }))}
    renderAnchor={open => <Row c={c} title={title} value={label} onPress={open} />} />;
}

const styles = StyleSheet.create({
  root: { flex: 1 }, flex: { flex: 1 }, flexText: { flex: 1 }, center: { textAlign: 'center' },
  centerBlock: { alignItems: 'center' }, circle: { alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  topBar: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingTop: 10, paddingBottom: 6 },
  topSide: { width: 48 }, topRight: { alignItems: 'flex-end' }, topCenter: { flex: 1, alignItems: 'center' },
  namePill: { flexDirection: 'row', alignItems: 'center', maxWidth: 240, gap: 9, paddingLeft: 5, paddingRight: 16, height: 40, borderRadius: 20 },
  nameText: { fontSize: 15, fontWeight: '600', flexShrink: 1 },
  previewBadge: { fontSize: 10, fontWeight: '700', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 8, overflow: 'hidden' },
  tabBarWrap: { position: 'absolute', left: 0, right: 0, alignItems: 'center' },
  tabBar: { flexDirection: 'row', width: 212, height: 50, borderRadius: 25, padding: 4 },
  tabIndicator: { position: 'absolute', top: 4, left: 4, height: 42, borderRadius: 21 },
  tabItem: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 1 },
  tabLabel: { fontSize: 11 },
  receive: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  glowLayer: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  readyTitle: { fontSize: 32, fontWeight: '700', textAlign: 'center' },
  readyHint: { fontSize: 17, lineHeight: 24, textAlign: 'center', marginTop: 12, maxWidth: 360 },
  settingsNote: { fontSize: 14, lineHeight: 20, textAlign: 'center', paddingHorizontal: 32 },
  link: { textDecorationLine: 'underline', fontWeight: '600' },
  choose: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingBottom: 110, gap: 22 },
  illustration: { width: 300, height: 240, alignItems: 'center', justifyContent: 'center', marginBottom: 6 },
  illCard: { position: 'absolute', width: 150, height: 180, borderRadius: 24, borderWidth: 4, padding: 14, gap: 9, overflow: 'hidden' },
  illBadge: { position: 'absolute', top: 10, left: 10, width: 32, height: 32, borderRadius: 16, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center' },
  illName: { fontSize: 13, fontWeight: '600' },
  illIcon: { width: 52, height: 52, borderRadius: 16, alignItems: 'center', justifyContent: 'center', marginBottom: 4 },
  illLine: { height: 9, borderRadius: 5 }, illLineLong: { width: '70%' }, illLineShort: { width: '48%' },
  illBlock: { flex: 1, borderRadius: 12, marginTop: 4 },
  chooseTitle: { fontSize: 26, fontWeight: '700', textAlign: 'center', paddingHorizontal: 24 },
  sendContent: { paddingHorizontal: 16, paddingTop: 8, gap: 12 },
  previewNote: { fontSize: 12, paddingHorizontal: 14, paddingVertical: 9, borderRadius: 14, overflow: 'hidden' },
  card: { borderRadius: 26, padding: 18 },
  selectionCard: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14 },
  thumbStack: { width: 62, height: 60, justifyContent: 'center', alignItems: 'center' },
  thumb: { position: 'absolute', width: 52, height: 52, borderRadius: 14, borderWidth: 2, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  nearbyCard: { paddingHorizontal: 8, paddingTop: 16, paddingBottom: 12 },
  nearbyHint: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginBottom: 12, paddingHorizontal: 10 },
  hint: { fontSize: 13 },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
  tile: { width: '25%', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 2 },
  tileAvatar: { alignItems: 'center', justifyContent: 'center', marginBottom: 6 },
  overlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  badge: { position: 'absolute', right: 4, bottom: 4, width: 20, height: 20, borderRadius: 10, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  badgeTop: { top: 2, bottom: undefined },
  tileName: { fontSize: 13, fontWeight: '600', textAlign: 'center' },
  tileSub: { fontSize: 11.5, marginTop: 1, textAlign: 'center' },
  empty: { alignItems: 'center', paddingHorizontal: 20, paddingVertical: 10, gap: 8 },
  emptyTitle: { fontSize: 15, fontWeight: '600', textAlign: 'center', marginTop: 4 },
  listCard: { paddingVertical: 6, paddingHorizontal: 0, overflow: 'hidden' },
  historyItem: { paddingHorizontal: 12 },
  historyRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 4 },
  historyEmpty: { marginVertical: 24, textAlign: 'center' },
  row: { flexDirection: 'row', alignItems: 'center' },
  rowText: { flex: 1, marginHorizontal: 12, minWidth: 0 },
  rowTitle: { fontSize: 16, fontWeight: '600' },
  rowSub: { fontSize: 13, marginTop: 2 },
  modalHost: { justifyContent: 'flex-end' },
  sheetCard: { marginHorizontal: 12, borderRadius: 28, padding: 20, maxHeight: '86%' },
  sheetHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: -6, marginRight: -10 },
  sheetTitle: { fontSize: 20, fontWeight: '700', flex: 1 },
  sheetSub: { marginBottom: 8 },
  sheetScroll: { maxHeight: 380 },
  sheetBigTitle: { fontSize: 22, fontWeight: '600', marginTop: 18 },
  ringAvatar: { width: 54, height: 54, alignItems: 'center', justifyContent: 'center' },
  percent: { fontSize: 15, fontWeight: '700' },
  fileBox: { borderRadius: 20, padding: 10, marginTop: 14, gap: 4 },
  fileRow: { flexDirection: 'row', alignItems: 'center', padding: 4 },
  fileIcon: { width: 44, height: 44, borderRadius: 12, alignItems: 'center', justifyContent: 'center' },
  fileName: { fontSize: 14, fontWeight: '500' },
  more: { marginLeft: 8 },
  actions: { flexDirection: 'row', justifyContent: 'flex-end', gap: 10, marginTop: 18 },
  wrapActions: { flexWrap: 'wrap', alignSelf: 'stretch' },
  noteRow: { flexDirection: 'row', alignItems: 'center', gap: 8, borderRadius: 14, paddingHorizontal: 12, paddingVertical: 10, marginTop: 14, alignSelf: 'stretch' },
  infoHero: { alignItems: 'center', gap: 4, marginTop: 6, marginBottom: 14 },
  statusDot: { position: 'absolute', right: -1, bottom: -1, width: 18, height: 18, borderRadius: 9, borderWidth: 3 },
  infoName: { fontSize: 20, fontWeight: '700', marginTop: 8 },
  infoBox: { borderRadius: 20, paddingHorizontal: 14, paddingVertical: 6 },
  infoRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, paddingVertical: 10 },
  infoLabel: { fontSize: 13, width: 78 },
  infoValue: { fontSize: 13, fontWeight: '600', flex: 1, textAlign: 'right' },
  howTitle: { fontSize: 15, fontWeight: '700', marginTop: 18, marginBottom: 6 },
  howRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, paddingVertical: 5 },
  trustHint: { marginTop: 14, marginBottom: 2 },
  bodyText: { fontSize: 15, lineHeight: 22, marginTop: 8 },
  aboutLine: { marginTop: 10 },
  aboutUpdate: { marginTop: 16 },
  group: { borderRadius: 22, overflow: 'hidden' },
  // Internet (iroh) sheet
  sheetIntro: { marginBottom: 12, lineHeight: 20 },
  codeBox: { borderWidth: 1, borderRadius: 16, padding: 12, marginBottom: 12 },
  codeText: { fontSize: 12, lineHeight: 17 },
  codeInput: { fontSize: 13, minHeight: 96, textAlignVertical: 'top', marginBottom: 4 },
  progressTrack: { height: 8, borderRadius: 4, overflow: 'hidden', marginBottom: 8 },
  progressFill: { height: 8, borderRadius: 4 },
  input: { fontSize: 17, borderWidth: 2, borderRadius: 16, paddingHorizontal: 16, paddingVertical: 12, marginTop: 14 },
  inputHint: { marginTop: 6 },
  settingsHeader: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingTop: 12, paddingBottom: 4 },
  settingsTitle: { fontSize: 24, fontWeight: '700', marginLeft: 6 },
  settingsContent: { paddingHorizontal: 14, paddingTop: 4 },
  serverButtons: { flexDirection: 'row', alignItems: 'center', marginLeft: 8 },
  groupGap: { height: 18 },
  profileRow: { flexDirection: 'row', alignItems: 'center', paddingLeft: 18 },
  profilePhoto: { paddingVertical: 12 },
  photoBadge: { position: 'absolute', right: -2, bottom: 10, width: 22, height: 22, borderRadius: 11, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  profileName: { flex: 1, flexDirection: 'row', alignItems: 'center', paddingLeft: 16, paddingRight: 22, paddingVertical: 15, minHeight: 76 },
  profileTitle: { fontSize: 17 },
  profileValue: { fontSize: 14, marginTop: 3 },
  toast: { position: 'absolute', left: 20, right: 20, paddingVertical: 14, paddingHorizontal: 18, borderRadius: 16 },
});

export default App;
