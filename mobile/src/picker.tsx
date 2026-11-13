// In-app file picker: pill tabs for Images, Videos, Documents and Other.
// Images and videos come from the media library grouped by day; documents
// are listed where Android allows it, with the system picker as a fallback;
// "Other" hands the choice to a content app (Files, Photos, …).

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Easing, FlatList, Image, Pressable, StyleSheet, useWindowDimensions, View } from 'react-native';
import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import { bridge, ContentApp, MediaItem, MediaKind, SharedFile } from './core';
import type { Copy, Language } from './strings';
import { fileIcon, formatSize, IconCircle, Palette, Pill, Text } from './ui';

type Tab = MediaKind | 'other';
const PAGE = 150;
const COLUMNS = 4;

/* ------------------------------------------------------------ thumbnails */

const thumbCache = new Map<string, string | null>();
const thumbWaiters = new Map<string, Promise<string | null>>();

function loadThumb(uri: string, size: number): Promise<string | null> {
  const key = `${uri}@${size}`;
  if (thumbCache.has(key)) return Promise.resolve(thumbCache.get(key) ?? null);
  let pending = thumbWaiters.get(key);
  if (!pending) {
    pending = (bridge?.getThumbnail?.(uri, size) ?? Promise.resolve(null)).catch(() => null).then(result => {
      thumbCache.set(key, result);
      thumbWaiters.delete(key);
      return result;
    });
    thumbWaiters.set(key, pending);
  }
  return pending;
}

/** A media thumbnail rendered natively and cached; shows a tinted placeholder until ready. */
export function Thumb({ item, c, size = 256, style, radius = 0 }: { item: { uri: string; mimeType: string }; c: Palette; size?: number; style?: any; radius?: number }) {
  const [src, setSrc] = useState<string | null>(thumbCache.get(`${item.uri}@${size}`) ?? null);
  const fade = useRef(new Animated.Value(src ? 1 : 0)).current;
  useEffect(() => {
    let alive = true;
    loadThumb(item.uri, size).then(result => {
      if (!alive || !result) return;
      setSrc(result);
      Animated.timing(fade, { toValue: 1, duration: 180, useNativeDriver: true }).start();
    });
    return () => { alive = false; };
  }, [item.uri, size, fade]);
  return <View style={[{ backgroundColor: c.chip, borderRadius: radius, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' }, style]}>
    <MaterialCommunityIcons name={fileIcon(item.mimeType) as any} size={24} color={c.sub} />
    {src && <Animated.Image source={{ uri: src }} resizeMode="cover" style={[StyleSheet.absoluteFill, { opacity: fade }]} />}
  </View>;
}

/* ---------------------------------------------------------------- helpers */

function dayKey(ms: number) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function dayLabel(ms: number, t: Copy, language: Language) {
  const d = new Date(ms);
  const today = new Date();
  const yesterday = new Date(Date.now() - 86_400_000);
  if (dayKey(ms) === dayKey(today.getTime())) return t.today;
  if (dayKey(ms) === dayKey(yesterday.getTime())) return t.yesterday;
  const opts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'long', ...(d.getFullYear() !== today.getFullYear() ? { year: 'numeric' } : {}) };
  try { return d.toLocaleDateString(language === 'tr' ? 'tr-TR' : 'en-GB', opts); } catch { return d.toDateString(); }
}

function formatDuration(ms: number) {
  const total = Math.round(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${String(m).padStart(2, '0')}:${s}`;
}

type Row =
  | { type: 'header'; key: string; label: string; ids: string[] }
  | { type: 'row'; key: string; items: MediaItem[] };

function groupRows(items: MediaItem[], t: Copy, language: Language): Row[] {
  const rows: Row[] = [];
  let current: { key: string; items: MediaItem[] } | null = null;
  const flush = () => {
    if (!current) return;
    rows.push({ type: 'header', key: `h-${current.key}`, label: dayLabel(current.items[0].date, t, language), ids: current.items.map(i => i.id) });
    for (let i = 0; i < current.items.length; i += COLUMNS) rows.push({ type: 'row', key: `r-${current.key}-${i}`, items: current.items.slice(i, i + COLUMNS) });
  };
  for (const item of items) {
    const key = dayKey(item.date);
    if (!current || current.key !== key) { flush(); current = { key, items: [] }; }
    current.items.push(item);
  }
  flush();
  return rows;
}

/* ---------------------------------------------------------------- picker */

export function FilePicker({ t, c, language, topInset, bottomInset, onCancel, onDone }: {
  t: Copy; c: Palette; language: Language; topInset: number; bottomInset: number; onCancel: () => void; onDone: (files: SharedFile[]) => void;
}) {
  const [tab, setTab] = useState<Tab>('images');
  const [selected, setSelected] = useState<Map<string, SharedFile>>(new Map());
  const [media, setMedia] = useState<Record<MediaKind, MediaItem[]>>({ images: [], videos: [], documents: [] });
  const [done, setDone] = useState<Record<MediaKind, boolean>>({ images: false, videos: false, documents: false });
  const [loading, setLoading] = useState(false);
  const [permission, setPermission] = useState<boolean | null>(null);
  const [apps, setApps] = useState<ContentApp[] | null>(null);
  const loadingRef = useRef(false);

  useEffect(() => {
    (async () => {
      let granted = (await bridge?.hasMediaPermission?.().catch(() => false)) ?? false;
      if (!granted) granted = (await bridge?.requestMediaPermission?.().catch(() => false)) ?? false;
      setPermission(granted);
    })();
  }, []);

  const loadMore = useCallback(async (kind: MediaKind) => {
    if (loadingRef.current || done[kind] || !bridge?.queryMedia) return;
    loadingRef.current = true;
    setLoading(true);
    try {
      const page = await bridge.queryMedia(kind, PAGE, media[kind].length);
      setMedia(m => ({ ...m, [kind]: [...m[kind], ...page] }));
      if (page.length < PAGE) setDone(d => ({ ...d, [kind]: true }));
    } catch {
      setDone(d => ({ ...d, [kind]: true }));
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, [done, media]);

  useEffect(() => {
    if (tab === 'other') {
      if (!apps) bridge?.getContentApps?.().then(setApps).catch(() => setApps([]));
      return;
    }
    if ((tab === 'documents' || permission) && media[tab].length === 0 && !done[tab]) loadMore(tab);
  }, [tab, permission, media, done, apps, loadMore]);

  const toggle = (item: SharedFile) => setSelected(current => {
    const next = new Map(current);
    if (next.has(item.id)) next.delete(item.id); else next.set(item.id, item);
    return next;
  });

  const toggleGroup = (ids: string[], items: MediaItem[]) => setSelected(current => {
    const next = new Map(current);
    const all = ids.every(id => next.has(id));
    for (const item of items) if (all) next.delete(item.id); else next.set(item.id, item);
    return next;
  });

  const finishWith = (extra: SharedFile[]) => onDone([...selected.values(), ...extra]);
  const systemPick = async (documentsOnly: boolean) => {
    const files = documentsOnly && bridge?.pickDocuments ? await bridge.pickDocuments().catch(() => []) : await bridge?.pickFiles().catch(() => []) ?? [];
    if (files.length) finishWith(files);
  };

  const titles: Record<Tab, string> = { images: t.pickImages, videos: t.pickVideos, documents: t.pickDocuments, other: t.pickOther };
  const tabs: Array<[Tab, string]> = [['images', t.tabImages], ['videos', t.tabVideos], ['documents', t.tabDocuments], ['other', t.tabOther]];

  return <View style={[styles.root, { backgroundColor: c.bg, paddingTop: topInset }]}>
    <View style={styles.header}>
      <IconCircle icon="chevron-left" color={c.text} label={t.cancelPick} onPress={onCancel} size={30} />
      <Text style={[styles.title, { color: c.text }]} accessibilityRole="header" numberOfLines={1}>{titles[tab]}</Text>
    </View>
    <PillTabs c={c} tabs={tabs} value={tab} onChange={setTab} />

    <View style={styles.flex}>
      {(tab === 'images' || tab === 'videos') && (permission === false
        ? <Empty c={c} icon="image-lock-outline" text={t.mediaDenied}
          actions={[{ label: t.grantAccess, onPress: async () => setPermission((await bridge?.requestMediaPermission?.().catch(() => false)) ?? false), filled: true },
            { label: t.useSystemPicker, onPress: () => systemPick(false) }]} />
        : <MediaGrid key={tab} t={t} c={c} language={language} items={media[tab]} selected={selected} loading={loading || permission === null}
          bottomInset={bottomInset} onToggle={toggle} onToggleGroup={toggleGroup} onEnd={() => loadMore(tab)} />)}
      {tab === 'documents' && <DocumentList t={t} c={c} items={media.documents} selected={selected} loading={loading} bottomInset={bottomInset}
        onToggle={toggle} onBrowse={() => systemPick(true)} onEnd={() => loadMore('documents')} />}
      {tab === 'other' && <AppList t={t} c={c} apps={apps} bottomInset={bottomInset} onSystem={() => systemPick(false)}
        onApp={async app => {
          const files = await bridge?.pickWithApp?.(app.package, app.activity).catch(() => []) ?? [];
          if (files.length) finishWith(files);
        }} />}
    </View>

    {/* Same size as the Receive/Send toggle (App.tsx TabBar): a 212×50 pill holding two 42 px buttons. */}
    <View pointerEvents="box-none" style={[styles.footer, { bottom: bottomInset + 14 }]}>
      <View style={[styles.footerBar, { backgroundColor: c.nav, boxShadow: c.shadow }]}>
        <Pressable onPress={onCancel} accessibilityRole="button" accessibilityLabel={t.cancelPick}
          style={({ pressed }) => [styles.footerButton, pressed && { backgroundColor: c.navActive }]}>
          <MaterialCommunityIcons name="close" size={18} color={c.text} />
          <Text style={[styles.footerText, { color: c.text }]} numberOfLines={1}>{t.cancelPick}</Text>
        </Pressable>
        <Pressable onPress={() => selected.size && finishWith([])} disabled={!selected.size} accessibilityRole="button"
          accessibilityLabel={selected.size ? t.donePickN(selected.size) : t.donePick} accessibilityState={{ disabled: !selected.size }}
          style={({ pressed }) => [styles.footerButton, { backgroundColor: selected.size ? c.accent : 'transparent', opacity: pressed ? 0.8 : 1 }]}>
          <MaterialCommunityIcons name="check" size={18} color={selected.size ? c.onAccent : c.sub} />
          <Text style={[styles.footerText, { color: selected.size ? c.onAccent : c.sub }]} numberOfLines={1}>
            {selected.size ? t.donePickN(selected.size) : t.donePick}
          </Text>
        </Pressable>
      </View>
    </View>
  </View>;
}

/** Pill-shaped tabs with a sliding highlight. */
function PillTabs({ c, tabs, value, onChange }: { c: Palette; tabs: Array<[Tab, string]>; value: Tab; onChange: (tab: Tab) => void }) {
  const [width, setWidth] = useState(0);
  const index = tabs.findIndex(([k]) => k === value);
  const slide = useRef(new Animated.Value(index)).current;
  useEffect(() => {
    Animated.spring(slide, { toValue: index, useNativeDriver: true, speed: 20, bounciness: 5 }).start();
  }, [index, slide]);
  const pill = width / tabs.length;
  return <View style={styles.tabs} onLayout={e => setWidth(e.nativeEvent.layout.width)}>
    {pill > 0 && <Animated.View style={[styles.tabPill, { width: pill, backgroundColor: c.nav,
      transform: [{ translateX: slide.interpolate({ inputRange: [0, tabs.length - 1], outputRange: [0, pill * (tabs.length - 1)] }) }] }]} />}
    {tabs.map(([key, label]) => {
      const active = key === value;
      return <Pressable key={key} onPress={() => onChange(key)} accessibilityRole="tab" accessibilityState={{ selected: active }} accessibilityLabel={label} style={styles.tab}>
        <Text style={[styles.tabText, { color: active ? c.text : c.sub, fontWeight: active ? '700' : '500' }]} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.75}>{label}</Text>
      </Pressable>;
    })}
  </View>;
}

function SelectCircle({ c, checked, light }: { c: Palette; checked: boolean; light?: boolean }) {
  const scale = useRef(new Animated.Value(checked ? 1 : 0)).current;
  useEffect(() => {
    Animated.spring(scale, { toValue: checked ? 1 : 0, useNativeDriver: true, speed: 30, bounciness: 12 }).start();
  }, [checked, scale]);
  return <View style={[styles.circle, { borderColor: light ? '#FFFFFF' : c.sub, backgroundColor: light ? 'rgba(0,0,0,0.18)' : 'transparent' }]}>
    <Animated.View style={[styles.circleFill, { backgroundColor: c.accent, transform: [{ scale }] }]}>
      <MaterialCommunityIcons name="check" size={16} color="#fff" />
    </Animated.View>
  </View>;
}

function MediaGrid({ t, c, language, items, selected, loading, bottomInset, onToggle, onToggleGroup, onEnd }: {
  t: Copy; c: Palette; language: Language; items: MediaItem[]; selected: Map<string, SharedFile>; loading: boolean; bottomInset: number;
  onToggle: (item: MediaItem) => void; onToggleGroup: (ids: string[], items: MediaItem[]) => void; onEnd: () => void;
}) {
  const { width } = useWindowDimensions();
  const tile = Math.floor((width - 4 - (COLUMNS - 1) * 3) / COLUMNS);
  const rows = useMemo(() => groupRows(items, t, language), [items, t, language]);
  const byId = useMemo(() => new Map(items.map(i => [i.id, i])), [items]);
  if (!items.length && !loading) return <Empty c={c} icon="image-off-outline" text={t.nothingHere} />;
  return <FlatList data={rows} keyExtractor={r => r.key} onEndReached={onEnd} onEndReachedThreshold={1.5} initialNumToRender={12} windowSize={9}
    contentContainerStyle={{ paddingBottom: bottomInset + 84 }}
    renderItem={({ item: row }) => row.type === 'header'
      ? <Pressable style={styles.groupHeader} onPress={() => onToggleGroup(row.ids, row.ids.map(id => byId.get(id)!).filter(Boolean))}
        accessibilityRole="checkbox" accessibilityLabel={t.selectGroup(row.label)} accessibilityState={{ checked: row.ids.every(id => selected.has(id)) }}>
        <SelectCircle c={c} checked={row.ids.every(id => selected.has(id))} />
        <Text style={[styles.groupLabel, { color: c.text }]}>{row.label}</Text>
      </Pressable>
      : <View style={styles.gridRow}>
        {row.items.map(item => <MediaTile key={item.id} c={c} item={item} size={tile} checked={selected.has(item.id)} onPress={() => onToggle(item)} />)}
      </View>} />;
}

function MediaTile({ c, item, size, checked, onPress }: { c: Palette; item: MediaItem; size: number; checked: boolean; onPress: () => void }) {
  const press = useRef(new Animated.Value(checked ? 1 : 0)).current;
  useEffect(() => {
    Animated.timing(press, { toValue: checked ? 1 : 0, duration: 160, easing: Easing.out(Easing.quad), useNativeDriver: true }).start();
  }, [checked, press]);
  return <Pressable onPress={onPress} accessibilityRole="checkbox" accessibilityState={{ checked }} accessibilityLabel={item.name}>
    <Animated.View style={{ width: size, height: size, transform: [{ scale: press.interpolate({ inputRange: [0, 1], outputRange: [1, 0.9] }) }] }}>
      <Thumb item={item} c={c} size={256} radius={checked ? 14 : 0} style={{ width: size, height: size }} />
      <View style={styles.tileCheck}><SelectCircle c={c} checked={checked} light /></View>
      {item.duration != null && <View style={styles.duration}>
        <MaterialCommunityIcons name="play" size={14} color="#fff" />
        <Text style={styles.durationText}>{formatDuration(item.duration)}</Text>
      </View>}
    </Animated.View>
  </Pressable>;
}

function docBadge(mime: string): { label: string; bg: string; fg: string; icon?: string } {
  if (mime === 'application/pdf') return { label: 'PDF', bg: '#E53935', fg: '#fff', icon: 'file-pdf-box' };
  if (mime.startsWith('text/')) return { label: 'TXT', bg: '#F2F2F2', fg: '#3A3A3A' };
  if (mime === 'application/epub+zip') return { label: 'EPUB', bg: '#F2F2F2', fg: '#3A3A3A' };
  if (/word|opendocument.text/.test(mime)) return { label: 'DOC', bg: '#2B6CE6', fg: '#fff' };
  if (/excel|spreadsheet/.test(mime)) return { label: 'XLS', bg: '#1E8E4E', fg: '#fff' };
  if (/powerpoint|presentation/.test(mime)) return { label: 'PPT', bg: '#E8622C', fg: '#fff' };
  if (/zip|rar|7z/.test(mime)) return { label: 'ZIP', bg: '#8E6CEF', fg: '#fff' };
  if (mime === 'application/vnd.android.package-archive') return { label: 'APK', bg: '#3DDC84', fg: '#0B3B21' };
  return { label: 'FILE', bg: '#5C6370', fg: '#fff' };
}

function DocumentList({ t, c, items, selected, loading, bottomInset, onToggle, onBrowse, onEnd }: {
  t: Copy; c: Palette; items: MediaItem[]; selected: Map<string, SharedFile>; loading: boolean; bottomInset: number;
  onToggle: (item: MediaItem) => void; onBrowse: () => void; onEnd: () => void;
}) {
  const browse = <Pressable onPress={onBrowse} style={({ pressed }) => [styles.listRow, pressed && { backgroundColor: c.faint }]} accessibilityRole="button" accessibilityLabel={t.browseDocs}>
    <View style={[styles.appIcon, { backgroundColor: c.accentSoft }]}><MaterialCommunityIcons name="folder-search-outline" size={28} color={c.accent} /></View>
    <View style={[styles.listText, { borderBottomColor: c.faint }]}>
      <Text style={[styles.listTitle, { color: c.text }]}>{t.browseDocs}</Text>
      <Text style={[styles.listSub, { color: c.sub }]}>{t.allFilesHint}</Text>
    </View>
  </Pressable>;
  if (!items.length && !loading) return <View>{browse}<Text style={[styles.emptyNote, { color: c.sub }]}>{t.docsEmpty}</Text></View>;
  return <FlatList data={items} keyExtractor={i => i.id} onEndReached={onEnd} onEndReachedThreshold={1.5} ListHeaderComponent={browse}
    contentContainerStyle={{ paddingBottom: bottomInset + 84 }}
    renderItem={({ item }) => {
      const badge = docBadge(item.mimeType);
      const checked = selected.has(item.id);
      return <Pressable onPress={() => onToggle(item)} accessibilityRole="checkbox" accessibilityState={{ checked }} accessibilityLabel={item.name}
        style={({ pressed }) => [styles.listRow, pressed && { backgroundColor: c.faint }]}>
        <SelectCircle c={c} checked={checked} />
        <View style={[styles.docBadge, { backgroundColor: badge.bg }]}>
          {badge.icon ? <MaterialCommunityIcons name={badge.icon as any} size={30} color={badge.fg} /> : <Text style={[styles.docBadgeText, { color: badge.fg }]}>{badge.label}</Text>}
        </View>
        <View style={[styles.listText, { borderBottomColor: c.faint }]}>
          <Text style={[styles.listTitle, { color: c.text }]} numberOfLines={1} ellipsizeMode="middle">{item.name}</Text>
          <Text style={[styles.listSub, { color: c.sub }]}>{formatSize(item.size)}</Text>
        </View>
      </Pressable>;
    }} />;
}

function AppList({ t, c, apps, bottomInset, onSystem, onApp }: { t: Copy; c: Palette; apps: ContentApp[] | null; bottomInset: number; onSystem: () => void; onApp: (app: ContentApp) => void }) {
  const row = (key: string, label: string, sub: string | undefined, icon: React.ReactNode, onPress: () => void) =>
    <Pressable key={key} onPress={onPress} accessibilityRole="button" accessibilityLabel={label} style={({ pressed }) => [styles.listRow, pressed && { backgroundColor: c.faint }]}>
      {icon}
      <View style={[styles.listText, { borderBottomColor: c.faint }]}>
        <Text style={[styles.listTitle, { color: c.text }]} numberOfLines={1}>{label}</Text>
        {!!sub && <Text style={[styles.listSub, { color: c.sub }]}>{sub}</Text>}
      </View>
    </Pressable>;
  return <FlatList data={apps ?? []} keyExtractor={a => a.package} contentContainerStyle={{ paddingBottom: bottomInset + 84 }}
    ListHeaderComponent={row('system', t.allFiles, t.allFilesHint,
      <View style={[styles.appIcon, { backgroundColor: '#F6B73C' }]}><MaterialCommunityIcons name="folder" size={30} color="#fff" /></View>, onSystem)}
    renderItem={({ item }) => row(item.package, item.label, undefined,
      item.icon ? <Image source={{ uri: item.icon }} style={styles.appIcon} /> : <View style={[styles.appIcon, { backgroundColor: c.chip }]}><MaterialCommunityIcons name="apps" size={26} color={c.sub} /></View>,
      () => onApp(item))} />;
}

function Empty({ c, icon, text, actions = [] }: { c: Palette; icon: string; text: string; actions?: Array<{ label: string; onPress: () => void; filled?: boolean }> }) {
  return <View style={styles.empty}>
    <MaterialCommunityIcons name={icon as any} size={44} color={c.sub} />
    <Text style={[styles.emptyText, { color: c.sub }]}>{text}</Text>
    {actions.map(a => <Pill key={a.label} c={c} label={a.label} onPress={a.onPress} filled={a.filled} outlined={!a.filled} />)}
  </View>;
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, paddingTop: 10, paddingBottom: 6, gap: 4 },
  title: { fontSize: 26, fontWeight: '700', flex: 1 },
  tabs: { flexDirection: 'row', marginHorizontal: 14, marginTop: 8, marginBottom: 14, height: 50 },
  tabPill: { position: 'absolute', top: 0, bottom: 0, borderRadius: 25 },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6 },
  tabText: { fontSize: 16 },
  groupHeader: { flexDirection: 'row', alignItems: 'center', gap: 18, paddingHorizontal: 20, paddingTop: 18, paddingBottom: 14 },
  groupLabel: { fontSize: 18, fontWeight: '700' },
  gridRow: { flexDirection: 'row', gap: 3, paddingHorizontal: 2, marginBottom: 3 },
  tileCheck: { position: 'absolute', top: 8, left: 8 },
  circle: { width: 26, height: 26, borderRadius: 13, borderWidth: 1.6, alignItems: 'center', justifyContent: 'center' },
  circleFill: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
  duration: { position: 'absolute', left: 6, bottom: 6, flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 7, paddingVertical: 3,
    borderRadius: 10, backgroundColor: 'rgba(0,0,0,0.55)' },
  durationText: { color: '#fff', fontSize: 12, fontWeight: '600' },
  listRow: { flexDirection: 'row', alignItems: 'center', gap: 16, paddingLeft: 20, paddingRight: 16 },
  listText: { flex: 1, minWidth: 0, paddingVertical: 16, borderBottomWidth: StyleSheet.hairlineWidth },
  listTitle: { fontSize: 17 },
  listSub: { fontSize: 13, marginTop: 3 },
  docBadge: { width: 48, height: 48, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  docBadgeText: { fontSize: 14, fontWeight: '700' },
  appIcon: { width: 48, height: 48, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  emptyNote: { fontSize: 14, lineHeight: 20, paddingHorizontal: 24, paddingTop: 16 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, paddingHorizontal: 32, paddingBottom: 120 },
  emptyText: { fontSize: 15, lineHeight: 21, textAlign: 'center' },
  footer: { position: 'absolute', left: 0, right: 0, alignItems: 'center' },
  footerBar: { flexDirection: 'row', width: 212, height: 50, borderRadius: 25, padding: 4 },
  footerButton: { flex: 1, height: 42, borderRadius: 21, alignItems: 'center', justifyContent: 'center', gap: 1 },
  footerText: { fontSize: 11, fontWeight: '700' },
});
