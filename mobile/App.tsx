import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  NativeEventEmitter,
  NativeModules,
  ScrollView,
  StatusBar,
  StyleSheet,
  useColorScheme,
  View,
} from 'react-native';
import {
  ActivityIndicator,
  Appbar,
  Avatar,
  Button,
  Card,
  Divider,
  IconButton,
  MD3DarkTheme,
  MD3LightTheme,
  Modal,
  PaperProvider,
  Portal,
  ProgressBar,
  RadioButton,
  Surface,
  Text,
  TouchableRipple,
} from 'react-native-paper';
import MaterialCommunityIcons from 'react-native-vector-icons/MaterialCommunityIcons';
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';

type Language = 'en' | 'tr';
type Screen = 'nearby' | 'receive' | 'settings';
type Device = {
  alias: string;
  fingerprint: string;
  host: string;
  port: number;
  protocol: 'http' | 'https';
  deviceModel?: string;
};
type SharedFile = { id: string; uri: string; name: string; mimeType: string; size: number };
type IncomingTransfer = {
  sessionId: string;
  sender: string;
  files: Array<{ id: string; name: string; mimeType: string; size: number }>;
  progress?: number;
  accepted?: boolean;
};
type Copy = {
  nearby: string; receive: string; settings: string; ready: string; subtitle: string; searching: string;
  empty: string; emptyHint: string; sendFiles: string; receiver: string; receiverOn: string; receiverOff: string;
  receiverHint: string; turnOn: string; turnOff: string; settingsTitle: string; visibility: string; everyone: string;
  off: string; language: string; appearance: string; system: string; light: string; dark: string; about: string;
  attribution: string; developer: string; requestTitle: string; from: string; files: string; accept: string; reject: string;
  sending: string; cancel: string; noFiles: string; transferStarted: string; transferComplete: string; transferFailed: string; bridgeMissing: string;
  permissionDenied: string;
  size: (n: number) => string;
};
type DynamicColors = {
  light: { primary?: string; secondary?: string; tertiary?: string };
  dark: { primary?: string; secondary?: string; tertiary?: string };
};
type QuickSendBridge = {
  initialize: () => Promise<boolean>;
  startReceiver: () => Promise<boolean>;
  stopReceiver: () => Promise<boolean>;
  pickFiles: () => Promise<SharedFile[]>;
  sendFiles: (device: Device, files: SharedFile[]) => Promise<string>;
  respond: (sessionId: string, accepted: boolean) => Promise<void>;
  cancel: (sessionId: string) => Promise<void>;
  setVisibility: (visibility: 'everyone' | 'off') => Promise<void>;
  getDynamicColors: () => Promise<DynamicColors | null>;
  getInitialSharedFiles: () => Promise<SharedFile[]>;
  getVisibility: () => Promise<'everyone' | 'off'>;
  isReceiverEnabled: () => Promise<boolean>;
  addListener: (eventName: string) => void;
  removeListeners: (count: number) => void;
};

const bridge = NativeModules.QuickSend as QuickSendBridge | undefined;
const renderPaperIcon = ({ name, color, size }: any) => (
  <MaterialCommunityIcons name={String(name)} color={color} size={size} />
);

const copy = {
  en: {
    nearby: 'Nearby devices', receive: 'Receive', settings: 'Settings', ready: 'Ready to send',
    subtitle: 'Choose a device on your local network.', searching: 'Searching your local network',
    empty: 'No devices found yet', emptyHint: 'Keep both devices on the same Wi-Fi network and try again.',
    sendFiles: 'Choose files', receiver: 'Receive files', receiverOn: 'Receiving is on',
    receiverOff: 'Receiving is off', receiverHint: 'Keep Quick Send open or enable background receiving.',
    turnOn: 'Turn on receiving', turnOff: 'Turn off receiving', settingsTitle: 'Preferences',
    visibility: 'Device visibility', everyone: 'Everyone', off: 'Off', language: 'Language',
    appearance: 'Appearance', system: 'System', light: 'Light', dark: 'Dark', about: 'About Quick Send',
    attribution: 'Built on LocalSend', developer: 'Muhammed Alparslan Sancaktar · Ensignsoft',
    requestTitle: 'Incoming transfer', from: 'From', files: 'Files', accept: 'Accept', reject: 'Decline',
    sending: 'Sending files', cancel: 'Cancel transfer', noFiles: 'Choose one or more files to send.',
    transferStarted: 'Transfer started', transferComplete: 'Transfer complete', transferFailed: 'The transfer could not be started.',
    bridgeMissing: 'Network transfer is unavailable in this build.', size: (n: number) => formatSize(n),
    permissionDenied: 'Allow local network access to find nearby devices.',
  },
  tr: {
    nearby: 'Yakındaki cihazlar', receive: 'Alma', settings: 'Ayarlar', ready: 'Göndermeye hazır',
    subtitle: 'Yerel ağındaki bir cihazı seç.', searching: 'Yerel ağ aranıyor',
    empty: 'Henüz cihaz bulunamadı', emptyHint: 'İki cihazı aynı Wi-Fi ağına bağlayıp yeniden dene.',
    sendFiles: 'Dosya seç', receiver: 'Dosya al', receiverOn: 'Alım açık',
    receiverOff: 'Alım kapalı', receiverHint: 'Arka planda alım için Quick Send’i açık tut.',
    turnOn: 'Alımı aç', turnOff: 'Alımı kapat', settingsTitle: 'Tercihler',
    visibility: 'Cihaz görünürlüğü', everyone: 'Herkes', off: 'Kapalı', language: 'Dil',
    appearance: 'Görünüm', system: 'Sistem', light: 'Açık', dark: 'Koyu', about: 'Quick Send hakkında',
    attribution: 'LocalSend tabanlıdır', developer: 'Muhammed Alparslan Sancaktar · Ensignsoft',
    requestTitle: 'Gelen aktarım', from: 'Gönderen', files: 'Dosyalar', accept: 'Kabul et', reject: 'Reddet',
    sending: 'Dosyalar gönderiliyor', cancel: 'Aktarımı iptal et', noFiles: 'Göndermek için dosya seç.',
    transferStarted: 'Aktarım başladı', transferComplete: 'Aktarım tamamlandı', transferFailed: 'Aktarım başlatılamadı.',
    bridgeMissing: 'Bu derlemede ağ aktarımı kullanılamıyor.', size: (n: number) => formatSize(n),
    permissionDenied: 'Yakındaki cihazları bulmak için yerel ağ iznini ver.',
  },
} satisfies Record<Language, Copy>;

function formatSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let size = bytes / 1024;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit += 1; }
  return `${size.toFixed(size < 10 ? 1 : 0)} ${units[unit]}`;
}

function App() {
  return <SafeAreaProvider><AppContent /></SafeAreaProvider>;
}

function AppContent() {
  const systemScheme = useColorScheme();
  const [appearance, setAppearance] = useState<'system' | 'light' | 'dark'>('system');
  const darkMode = appearance === 'system' ? systemScheme === 'dark' : appearance === 'dark';
  const [language, setLanguage] = useState<Language>('en');
  const [dynamicColors, setDynamicColors] = useState<DynamicColors | null>(null);
  const [screen, setScreen] = useState<Screen>('nearby');
  const [devices, setDevices] = useState<Device[]>([]);
  const [networkReady, setNetworkReady] = useState(false);
  const [receiverOn, setReceiverOn] = useState(false);
  const [visibility, setVisibility] = useState<'everyone' | 'off'>('everyone');
  const [pending, setPending] = useState<IncomingTransfer | null>(null);
  const [sharedFiles, setSharedFiles] = useState<SharedFile[]>([]);
  const [sending, setSending] = useState(false);
  const [outgoing, setOutgoing] = useState<{ id: string; target: string; progress: number } | null>(null);
  const [message, setMessage] = useState('');
  const insets = useSafeAreaInsets();
  const t = copy[language];
  const copyRef = useRef(t);
  copyRef.current = t;

  useEffect(() => {
    bridge?.getDynamicColors().then(setDynamicColors).catch(() => setDynamicColors(null));
    NativeModules.QuickSend?.getLanguage?.().then((locale: string) => {
      if (locale === 'tr') setLanguage('tr');
    }).catch(() => undefined);
    bridge?.getVisibility().then(setVisibility).catch(() => undefined);
    bridge?.isReceiverEnabled().then(setReceiverOn).catch(() => undefined);
    if (!bridge) return;
    const emitter = new NativeEventEmitter(NativeModules.QuickSend);
    const subscription = emitter.addListener('QuickSendEvent', (event: any) => {
      if (event.type === 'devices') setDevices(event.devices ?? []);
      if (event.type === 'device') setDevices(current => mergeDevice(current, event.device));
      if (event.type === 'transferRequest') setPending(event.transfer);
      if (event.type === 'sharedFiles') setSharedFiles(event.files ?? []);
      if (event.type === 'transferProgress') {
        setPending(current => current?.sessionId === event.sessionId ? { ...current, progress: event.progress } as IncomingTransfer : current);
      }
      if (event.type === 'transferDecision') {
        if (!event.accepted) setPending(null);
        else setPending(current => {
          if (!current || current.sessionId !== event.sessionId) return current;
          return { ...current, accepted: true };
        });
      }
      if (event.type === 'sendProgress') setOutgoing(current => {
        if (!current || current.id !== event.transferId) return current;
        return { ...current, progress: event.progress };
      });
      if (event.type === 'sendComplete') { setOutgoing(current => current?.id === event.transferId ? null : current); setMessage(copyRef.current.transferComplete); }
      if (event.type === 'sendFailed') { setOutgoing(current => current?.id === event.transferId ? null : current); setMessage(event.message ?? copyRef.current.transferFailed); }
      if (event.type === 'sessionEnd') setPending(current => current?.sessionId === event.sessionId ? null : current);
      if (event.type === 'error') setMessage(event.message ?? '');
    });
    bridge.initialize().then(started => {
      setNetworkReady(started);
      if (!started) setMessage(copyRef.current.permissionDenied);
      return bridge.getInitialSharedFiles();
    }).then(files => {
      if (files.length) setSharedFiles(files);
    }).catch(() => undefined);
    return () => subscription.remove();
  }, []);

  const baseTheme = darkMode ? MD3DarkTheme : MD3LightTheme;
  const selectedDynamicColors = darkMode ? dynamicColors?.dark : dynamicColors?.light;
  const theme = useMemo(() => ({
    ...baseTheme,
    colors: {
      ...baseTheme.colors,
      primary: selectedDynamicColors?.primary ?? (darkMode ? '#B7C8FF' : '#315DA8'),
      secondary: selectedDynamicColors?.secondary ?? (darkMode ? '#BBC7E5' : '#52617D'),
      tertiary: selectedDynamicColors?.tertiary ?? (darkMode ? '#DABDE1' : '#6C4F75'),
    },
  }), [baseTheme, darkMode, selectedDynamicColors]);

  const toggleReceiver = async () => {
    if (!bridge) { setMessage(t.bridgeMissing); return; }
    try {
      const success = receiverOn ? await bridge.stopReceiver() : await bridge.startReceiver();
      if (success) setReceiverOn(!receiverOn);
      else setMessage(t.bridgeMissing);
    } catch { setMessage(t.bridgeMissing); }
  };

  const chooseAndSend = async (device: Device) => {
    if (!bridge) { setMessage(t.bridgeMissing); return; }
    try {
      const files = sharedFiles.length ? sharedFiles : await bridge.pickFiles();
      if (!files.length) return;
      setSending(true);
      const id = await bridge.sendFiles(device, files);
      if (id) setOutgoing({ id, target: device.alias, progress: 0 });
      setSharedFiles([]);
    } catch { setMessage(t.transferFailed); }
    finally { setSending(false); }
  };

  const chooseFiles = async () => {
    if (!bridge) { setMessage(t.bridgeMissing); return; }
    try {
      const files = await bridge.pickFiles();
      if (files.length) setSharedFiles(files);
    } catch { setMessage(t.noFiles); }
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
    if (!accepted) setPending(null);
  };

  const cancelIncoming = async () => {
    if (!pending || !bridge) return;
    await bridge.cancel(pending.sessionId);
    setPending(null);
  };

  return (
    <PaperProvider
      theme={theme}
      settings={{ icon: renderPaperIcon }}
    >
      <StatusBar barStyle={darkMode ? 'light-content' : 'dark-content'} />
      <Surface style={[styles.root, { backgroundColor: theme.colors.background }]}>
        <Appbar.Header elevated={false} style={[styles.appbar, { backgroundColor: theme.colors.background }]}>
          <Appbar.Content title="Quick Send" titleStyle={styles.brandTitle} />
          <IconButton icon="cog-outline" accessibilityLabel={t.settings} onPress={() => setScreen('settings')} />
        </Appbar.Header>
        <View style={styles.body}>
          {screen === 'nearby' && <NearbyScreen t={t} theme={theme} devices={devices} networkReady={networkReady} onRetryDiscovery={retryDiscovery} sending={sending} sharedFiles={sharedFiles} outgoing={outgoing} onChoose={chooseAndSend} onChooseFiles={chooseFiles} onClearShared={() => setSharedFiles([])} onCancel={() => outgoing && bridge?.cancel(outgoing.id)} receiverOn={receiverOn} onReceive={() => setScreen('receive')} />}
          {screen === 'receive' && <ReceiveScreen t={t} theme={theme} receiverOn={receiverOn} visibility={visibility} onToggle={toggleReceiver} />}
          {screen === 'settings' && <SettingsScreen t={t} theme={theme} language={language} setLanguage={setLanguage} appearance={appearance} setAppearance={setAppearance} visibility={visibility} setVisibility={async (value: 'everyone' | 'off') => { setVisibility(value); await bridge?.setVisibility(value); }} />}
        </View>
        <Surface elevation={2} style={[styles.bottomBar, { paddingBottom: Math.max(insets.bottom, 8), backgroundColor: theme.colors.surface }]}>
          {(['nearby', 'receive', 'settings'] as Screen[]).map((item, index) => {
            const icons = ['radar', 'inbox-arrow-down-outline', 'cog-outline'];
            const labels = [t.nearby, t.receive, t.settings];
            const selected = screen === item;
            return <TouchableRipple key={item} accessibilityRole="tab" accessibilityState={{ selected }} accessibilityLabel={labels[index]} onPress={() => setScreen(item)} style={styles.navItem} borderless>
              <View style={styles.navContent}>
                <MaterialCommunityIcons name={icons[index]} size={22} color={selected ? theme.colors.onSecondaryContainer : theme.colors.onSurfaceVariant} />
                <Text variant="labelSmall" style={{ color: selected ? theme.colors.onSurface : theme.colors.onSurfaceVariant }}>{labels[index]}</Text>
              </View>
            </TouchableRipple>;
          })}
        </Surface>
        {!!message && <TouchableRipple onPress={() => setMessage('')} accessibilityRole="button" accessibilityLabel={message} style={[styles.toast, { backgroundColor: theme.colors.inverseSurface }]}>
          <Text style={{ color: theme.colors.inverseOnSurface }}>{message}</Text>
        </TouchableRipple>}
        <Portal>
          <Modal visible={!!pending} onDismiss={() => answerIncoming(false)} contentContainerStyle={[styles.modal, { backgroundColor: theme.colors.surface, marginBottom: insets.bottom + 12 }]}>
            {!!pending && <IncomingSheet transfer={pending} t={t} theme={theme} onAccept={() => answerIncoming(true)} onReject={() => answerIncoming(false)} onCancel={cancelIncoming} />}
          </Modal>
        </Portal>
      </Surface>
    </PaperProvider>
  );
}

function mergeDevice(devices: Device[], next: Device): Device[] {
  const exists = devices.some(device => device.fingerprint === next.fingerprint);
  return exists ? devices.map(device => device.fingerprint === next.fingerprint ? next : device) : [...devices, next];
}

function NearbyScreen({ t, theme, devices, networkReady, onRetryDiscovery, sending, sharedFiles, outgoing, onChoose, onChooseFiles, onClearShared, onCancel, receiverOn, onReceive }: any) {
  return <ScrollView style={styles.screen} contentContainerStyle={styles.nearbyContent}>
    <View style={styles.intro}>
      <Text variant="headlineMedium" style={styles.heading}>{t.nearby}</Text>
      <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>{t.subtitle}</Text>
    </View>
    <Surface elevation={1} style={[styles.radarCard, { backgroundColor: theme.colors.surfaceContainerLow }]}>
      <View style={styles.radar}>
        <View style={[styles.radarRing, styles.ringOuter, { borderColor: theme.colors.outlineVariant }]} />
        <View style={[styles.radarRing, styles.ringMiddle, { borderColor: theme.colors.outlineVariant }]} />
        <View style={[styles.radarCore, { backgroundColor: theme.colors.primaryContainer }]}>
          <MaterialCommunityIcons name="send-outline" size={30} color={theme.colors.onPrimaryContainer} />
        </View>
      </View>
      <Text variant="titleMedium" style={styles.centerText}>{devices.length ? `${devices.length} ${t.nearby.toLowerCase()}` : t.searching}</Text>
      <Text variant="bodySmall" style={[styles.centerText, { color: theme.colors.onSurfaceVariant }]}>{receiverOn ? t.receiverOn : t.receiverOff}</Text>
    </Surface>
    <View style={styles.listHeader}><Text variant="titleMedium">{t.nearby}</Text><ActivityIndicator animating size="small" color={theme.colors.primary} /></View>
    {devices.length === 0 ? <Surface style={[styles.emptyCard, { backgroundColor: theme.colors.surfaceContainerLow }]}>
      <MaterialCommunityIcons name="devices" size={30} color={theme.colors.onSurfaceVariant} />
      <Text variant="titleSmall" style={styles.centerText}>{t.empty}</Text>
      <Text variant="bodySmall" style={[styles.centerText, { color: theme.colors.onSurfaceVariant }]}>{t.emptyHint}</Text>
      {!networkReady && <Button mode="text" onPress={onRetryDiscovery}>{t.permissionDenied}</Button>}
    </Surface> : devices.map((device: Device) => <TouchableRipple key={device.fingerprint} onPress={() => onChoose(device)} accessibilityRole="button" accessibilityLabel={`${device.alias}, ${t.sendFiles}`}>
      <Card style={styles.deviceCard}><Card.Content style={styles.deviceRow}>
        <Avatar.Icon size={48} icon="laptop" style={{ backgroundColor: theme.colors.secondaryContainer }} color={theme.colors.onSecondaryContainer} />
        <View style={styles.deviceMeta}><Text variant="titleMedium">{device.alias}</Text><Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>{device.deviceModel ?? device.host}</Text></View>
        <MaterialCommunityIcons name="chevron-right" size={24} color={theme.colors.onSurfaceVariant} />
      </Card.Content></Card>
    </TouchableRipple>)}
    {!!sharedFiles.length && <Surface style={[styles.sharedCard, { backgroundColor: theme.colors.secondaryContainer }]}>
      <MaterialCommunityIcons name="file-multiple-outline" size={21} color={theme.colors.onSecondaryContainer} />
      <Text variant="bodyMedium" numberOfLines={1} style={[styles.sharedFileLabel, { color: theme.colors.onSecondaryContainer }]}>{sharedFiles.length} · {sharedFiles[0].name}</Text>
      <IconButton icon="close" size={18} onPress={onClearShared} accessibilityLabel={t.cancel} />
    </Surface>}
    {!!outgoing && <Surface style={[styles.outgoingCard, { backgroundColor: theme.colors.surfaceContainerLow }]}>
      <View style={styles.outgoingHeading}><Text variant="titleSmall" style={styles.outgoingLabel}>{t.sending} · {outgoing.target}</Text><IconButton icon="close" size={18} onPress={onCancel} accessibilityLabel={t.cancel} /></View>
      <ProgressBar progress={outgoing.progress} />
    </Surface>}
    <View style={styles.bottomActions}>
      <Button mode="contained" icon="file-plus-outline" onPress={onChooseFiles} loading={sending} disabled={sending} contentStyle={styles.mainButton} accessibilityLabel={t.sendFiles}>{t.sendFiles}</Button>
      <Button mode="outlined" icon="inbox-arrow-down-outline" onPress={onReceive} contentStyle={styles.mainButton}>{t.receiver}</Button>
    </View>
  </ScrollView>;
}

function ReceiveScreen({ t, theme, receiverOn, onToggle }: any) {
  return <ScrollView style={styles.screen} contentContainerStyle={styles.receiveContent}>
    <View style={styles.intro}><Text variant="headlineMedium" style={styles.heading}>{t.receiver}</Text><Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>{t.receiverHint}</Text></View>
    <Surface elevation={1} style={[styles.receiveCard, { backgroundColor: theme.colors.surfaceContainerLow }]}>
      <View style={[styles.receiveIcon, { backgroundColor: receiverOn ? theme.colors.primaryContainer : theme.colors.surfaceContainerHighest }]}>
        <MaterialCommunityIcons name={receiverOn ? 'access-point-check' : 'access-point-off'} size={34} color={receiverOn ? theme.colors.onPrimaryContainer : theme.colors.onSurfaceVariant} />
      </View>
      <Text variant="titleLarge" style={styles.centerText}>{receiverOn ? t.receiverOn : t.receiverOff}</Text>
      <Text variant="bodyMedium" style={[styles.centerText, { color: theme.colors.onSurfaceVariant }]}>{t.receiverHint}</Text>
      <Button mode={receiverOn ? 'outlined' : 'contained'} onPress={onToggle} icon={receiverOn ? 'pause' : 'play'} style={styles.receiveToggle}>{receiverOn ? t.turnOff : t.turnOn}</Button>
    </Surface>
  </ScrollView>;
}

function SettingsScreen({ t, theme, language, setLanguage, appearance, setAppearance, visibility, setVisibility }: any) {
  return <ScrollView style={styles.screen} contentContainerStyle={styles.settingsContent}>
    <View style={styles.intro}><Text variant="headlineMedium" style={styles.heading}>{t.settingsTitle}</Text></View>
    <Card style={styles.settingsCard}><Card.Content>
      <Text variant="titleMedium" style={styles.settingHeading}>{t.visibility}</Text>
      <RadioButton.Group value={visibility} onValueChange={setVisibility}>
        <RadioButton.Item label={t.everyone} value="everyone" accessibilityLabel={t.everyone} />
        <RadioButton.Item label={t.off} value="off" accessibilityLabel={t.off} />
      </RadioButton.Group>
      <Divider style={styles.divider} />
      <Text variant="titleMedium" style={styles.settingHeading}>{t.language}</Text>
      <RadioButton.Group value={language} onValueChange={setLanguage}>
        <RadioButton.Item label="English" value="en" />
        <RadioButton.Item label="Türkçe" value="tr" />
      </RadioButton.Group>
      <Divider style={styles.divider} />
      <Text variant="titleMedium" style={styles.settingHeading}>{t.appearance}</Text>
      <RadioButton.Group value={appearance} onValueChange={setAppearance}>
        <RadioButton.Item label={t.system} value="system" />
        <RadioButton.Item label={t.light} value="light" />
        <RadioButton.Item label={t.dark} value="dark" />
      </RadioButton.Group>
    </Card.Content></Card>
    <Card style={styles.settingsCard}><Card.Content>
      <Text variant="titleMedium">{t.about}</Text>
      <Text variant="bodyMedium" style={[styles.aboutText, { color: theme.colors.onSurfaceVariant }]}>{t.developer}</Text>
      <Text variant="bodySmall" style={[styles.aboutSubText, { color: theme.colors.onSurfaceVariant }]}>{t.attribution}</Text>
    </Card.Content></Card>
  </ScrollView>;
}

function IncomingSheet({ transfer, t, theme, onAccept, onReject, onCancel }: any) {
  const total = transfer.files.reduce((sum: number, file: any) => sum + file.size, 0);
  return <View>
    <View style={styles.sheetHandle} />
    <Text variant="headlineSmall" style={styles.sheetTitle}>{t.requestTitle}</Text>
    <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>{t.from} · {transfer.sender}</Text>
    <Text variant="titleSmall" style={styles.fileHeading}>{t.files} · {transfer.files.length} · {t.size(total)}</Text>
    {transfer.files.map((file: any) => <View key={file.id} style={styles.fileRow}>
      <Avatar.Icon size={40} icon="file-outline" style={{ backgroundColor: theme.colors.secondaryContainer }} color={theme.colors.onSecondaryContainer} />
      <View style={styles.deviceMeta}><Text numberOfLines={1} variant="titleSmall">{file.name}</Text><Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>{t.size(file.size)}</Text></View>
    </View>)}
    {transfer.progress != null && <ProgressBar progress={transfer.progress} style={styles.progress} />}
    {!transfer.accepted ? <View style={styles.sheetActions}>
      <Button mode="outlined" onPress={onReject} style={styles.sheetButton}>{t.reject}</Button>
      <Button mode="contained" onPress={onAccept} style={styles.sheetButton}>{t.accept}</Button>
    </View> : <Button mode="outlined" onPress={onCancel} style={styles.receiveToggle}>{t.cancel}</Button>}
  </View>;
}

const styles = StyleSheet.create({
  root: { flex: 1 }, body: { flex: 1 }, screen: { flex: 1, paddingHorizontal: 20, paddingTop: 12 },
  nearbyContent: { flexGrow: 1 }, receiveContent: { flexGrow: 1 }, settingsContent: { flexGrow: 1, paddingBottom: 12 },
  brandTitle: { fontWeight: '700', letterSpacing: 0.1 }, intro: { gap: 5, marginBottom: 18 }, heading: { fontWeight: '600' },
  appbar: { paddingHorizontal: 8 },
  radarCard: { borderRadius: 28, alignItems: 'center', padding: 20, marginBottom: 22 }, radar: { width: 150, height: 150, alignItems: 'center', justifyContent: 'center', marginBottom: 12 },
  radarRing: { position: 'absolute', borderWidth: 1, borderRadius: 100 }, ringOuter: { width: 148, height: 148, opacity: 0.55 }, ringMiddle: { width: 106, height: 106, opacity: 0.75 },
  radarCore: { width: 70, height: 70, borderRadius: 35, alignItems: 'center', justifyContent: 'center' }, centerText: { textAlign: 'center', marginTop: 4 },
  listHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }, emptyCard: { borderRadius: 20, minHeight: 142, alignItems: 'center', justifyContent: 'center', padding: 20, gap: 7 },
  deviceCard: { borderRadius: 20, marginBottom: 9 }, deviceRow: { flexDirection: 'row', alignItems: 'center' }, deviceMeta: { flex: 1, marginHorizontal: 12, minWidth: 0 },
  bottomActions: { marginTop: 'auto', gap: 10, paddingTop: 12, paddingBottom: 14 }, mainButton: { height: 50 }, receiveCard: { borderRadius: 28, padding: 26, alignItems: 'center', gap: 12 },
  receiveIcon: { width: 76, height: 76, borderRadius: 38, alignItems: 'center', justifyContent: 'center', marginBottom: 4 }, receiveToggle: { marginTop: 8, minWidth: 190 },
  settingsCard: { borderRadius: 20, marginBottom: 14 }, settingHeading: { marginTop: 8, marginBottom: 4 }, divider: { marginVertical: 10 },
  bottomBar: { flexDirection: 'row', justifyContent: 'space-around', paddingTop: 7 }, navItem: { minWidth: 92, minHeight: 56, borderRadius: 18 }, navContent: { alignItems: 'center', justifyContent: 'center', gap: 2, minHeight: 56 },
  modal: { position: 'absolute', bottom: 0, left: 0, right: 0, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingHorizontal: 22, paddingBottom: 18, paddingTop: 10 },
  sheetHandle: { width: 36, height: 4, borderRadius: 2, backgroundColor: '#888', alignSelf: 'center', marginBottom: 17 }, sheetTitle: { marginBottom: 6 }, fileHeading: { marginTop: 22, marginBottom: 10 },
  fileRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 7 }, progress: { marginTop: 14, height: 6, borderRadius: 3 }, sheetActions: { flexDirection: 'row', gap: 10, marginTop: 22 }, sheetButton: { flex: 1, minHeight: 46 },
  sharedCard: { flexDirection: 'row', alignItems: 'center', borderRadius: 16, paddingLeft: 12, marginTop: 10 }, sharedFileLabel: { flex: 1 },
  outgoingCard: { borderRadius: 16, padding: 12, marginTop: 10 }, outgoingHeading: { flexDirection: 'row', alignItems: 'center', marginBottom: 4 }, outgoingLabel: { flex: 1 },
  aboutText: { marginTop: 8 }, aboutSubText: { marginTop: 4 },
  toast: { position: 'absolute', bottom: 86, left: 20, right: 20, padding: 14, borderRadius: 12 },
});

export default App;
