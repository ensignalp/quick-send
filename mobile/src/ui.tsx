// Shared visual building blocks: palette, primitives and animations.

import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Easing, Image, Modal, Pressable, StyleSheet, TextProps, useWindowDimensions, View } from 'react-native';
import { Text as PaperText } from 'react-native-paper';
import MaterialCommunityIcons from '@expo/vector-icons/MaterialCommunityIcons';
import type { Copy } from './strings';
import type { Device } from './core';

export type Palette = {
  dark: boolean; bg: string; bgTop: string; card: string; border: string; text: string; sub: string; faint: string; chip: string; accent: string; accentSoft: string;
  onAccent: string; danger: string; success: string; shadow: string; toastBg: string; toastText: string; glow: string; nav: string; navActive: string;
};
export const palettes: Record<'light' | 'dark', Palette> = {
  light: {
    dark: false, bg: '#F2F3F7', bgTop: '#FAFBFD', card: '#FFFFFF', border: '#E1E3EA', text: '#17181C', sub: '#6E7079', faint: '#E3E4EA', chip: '#ECEDF2', accent: '#3478F6',
    accentSoft: '#E4EDFF', onAccent: '#FFFFFF', danger: '#E5484D', success: '#3478F6', shadow: '0px 6px 24px rgba(42, 60, 120, 0.08)',
    toastBg: '#23242A', toastText: '#F4F5F7', glow: '#C9D9F7', nav: '#FFFFFF', navActive: '#E7E9EF',
  },
  dark: {
    dark: true, bg: '#111111', bgTop: '#0C0C0C', card: '#191919', border: '#2A2A2A', text: '#F2F2F2', sub: '#A3A3A3', faint: '#262626', chip: '#222222', accent: '#3B82F6',
    accentSoft: '#1D2A45', onAccent: '#FFFFFF', danger: '#FF6B6B', success: '#5B95FF', shadow: '0px 8px 28px rgba(0, 0, 0, 0.45)',
    toastBg: '#E9EAEE', toastText: '#17181C', glow: '#3C4550', nav: '#2A2C31', navActive: '#45484F',
  },
};

/* ----------------------------------------------------------------- fonts */

/** Space Grotesk files per weight (loaded in App with expo-font). */
export const fontFamilies: Record<string, string> = {
  '300': 'SpaceGrotesk_300Light',
  '400': 'SpaceGrotesk_400Regular',
  '500': 'SpaceGrotesk_500Medium',
  '600': 'SpaceGrotesk_600SemiBold',
  '700': 'SpaceGrotesk_700Bold',
};

export function fontFor(weight?: string | number) {
  const w = weight === 'bold' ? '700' : weight === 'normal' || weight == null ? '400' : String(weight);
  return fontFamilies[w] ?? (Number(w) >= 600 ? fontFamilies['700'] : fontFamilies['400']);
}

/** Text in Space Grotesk; `fontWeight` picks the matching font file (Android cannot synthesize weights). */
export function Text(props: TextProps & { variant?: any; children?: React.ReactNode }) {
  const flat = StyleSheet.flatten(props.style) ?? {};
  return <PaperText {...(props as any)} style={[props.style, { fontFamily: fontFor(flat.fontWeight as any), fontWeight: 'normal' }]} />;
}

/** Whether looping/decorative animations run (Settings › Animations). */
export const MotionContext = createContext(true);
const useMotion = () => useContext(MotionContext);

const avatarGradients = [
  ['#A78BFA', '#6D8DF7'],
  ['#7AA7FF', '#5B6CF0'],
  ['#FFB27A', '#F2786A'],
  ['#6FD3B5', '#3EA2C9'],
  ['#F59AC8', '#B57CF2'],
  ['#8FC6FF', '#6A8BFF'],
];

export function formatSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let size = bytes / 1024;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit += 1; }
  return `${size.toFixed(size < 10 ? 1 : 0)} ${units[unit]}`;
}

function hash(text: string) {
  let h = 0;
  for (let i = 0; i < text.length; i += 1) h = (h * 31 + text.charCodeAt(i)) % 1000003;
  return h;
}

const isTabletName = (device: Device) => /tab|pad/i.test(`${device.alias} ${device.deviceModel ?? ''}`);

export function deviceIcon(device: Device): string | null {
  switch (device.deviceType) {
    case 'DESKTOP': return /mac|apple|book|laptop/i.test(`${device.alias} ${device.deviceModel ?? ''}`) ? 'laptop' : 'monitor';
    case 'WEB': return 'web';
    case 'HEADLESS':
    case 'SERVER': return 'server-outline';
    default: return isTabletName(device) ? 'tablet' : null;
  }
}

export function deviceLabel(device: Device, t: Copy) {
  switch (device.deviceType) {
    case 'MOBILE': return isTabletName(device) ? t.tablet : t.phone;
    case 'DESKTOP': return t.pc;
    case 'WEB': return t.web;
    case 'HEADLESS':
    case 'SERVER': return t.server;
    default: return device.deviceModel || t.device;
  }
}

export function fileIcon(mimeType: string) {
  if (mimeType.startsWith('image/')) return 'image-outline';
  if (mimeType.startsWith('video/')) return 'filmstrip';
  if (mimeType.startsWith('audio/')) return 'music-note-outline';
  if (mimeType === 'application/pdf') return 'file-pdf-box';
  if (/zip|compressed|tar|rar|7z/.test(mimeType)) return 'folder-zip-outline';
  if (mimeType === 'application/vnd.android.package-archive') return 'android';
  if (mimeType.startsWith('text/')) return 'file-document-outline';
  return 'file-outline';
}

export function timeAgo(at: number, t: Copy) {
  const mins = Math.floor((Date.now() - at) / 60000);
  if (mins < 1) return t.justNow;
  if (mins < 60) return t.minutesAgo(mins);
  const hours = Math.floor(mins / 60);
  return hours < 24 ? t.hoursAgo(hours) : t.daysAgo(Math.floor(hours / 24));
}

/* ------------------------------------------------------------ primitives */

const markImage = require('../assets/quick-send-mark.png');

/** Quick Send brand mark (support/brand/quick-send-mark.svg), tinted with [color]. */
export function BrandMark({ size, color }: { size: number; color: string }) {
  return <Image source={markImage} accessibilityIgnoresInvertColors style={{ width: size, height: size, tintColor: color }} resizeMode="contain" />;
}

/** Profile photo when set, otherwise the letter avatar. */
export function Avatar({ name, uri, size }: { name: string; uri?: string | null; size: number }) {
  if (!uri) return <LetterAvatar name={name} size={size} />;
  return <Image source={{ uri }} style={{ width: size, height: size, borderRadius: size / 2 }} accessibilityIgnoresInvertColors />;
}

/** App icon: the white mark on the brand blue tile. */
export function AppIcon({ size }: { size: number }) {
  return <View style={[styles.circle, { width: size, height: size, borderRadius: size * 0.23, backgroundColor: '#3478F6',
    experimental_backgroundImage: 'linear-gradient(135deg, #4C8DFF, #2563EB)' } as any]}>
    <BrandMark size={size * 0.56} color="#FFFFFF" />
  </View>;
}

export function LetterAvatar({ name, size }: { name: string; size: number }) {
  const [from, to] = avatarGradients[hash(name) % avatarGradients.length];
  return <View style={[styles.circle, { width: size, height: size, borderRadius: size / 2, backgroundColor: to,
    experimental_backgroundImage: `linear-gradient(135deg, ${from}, ${to})` } as any]}>
    <Text style={{ color: '#fff', fontSize: size * 0.42, fontWeight: '500' }}>{(name.trim()[0] ?? '?').toLocaleUpperCase()}</Text>
  </View>;
}

export function IconCircle({ icon, color, label, onPress, size = 24 }: { icon: string; color: string; label: string; onPress: () => void; size?: number }) {
  return <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={label} hitSlop={6}
    style={({ pressed }) => [styles.iconCircle, pressed && styles.iconPressed]}>
    <MaterialCommunityIcons name={icon as any} size={size} color={color} />
  </Pressable>;
}

export function Pill({ c, label, onPress, icon, filled, outlined, large }: { c: Palette; label: string; onPress: () => void; icon?: string; filled?: boolean; outlined?: boolean; large?: boolean }) {
  const fg = filled ? c.onAccent : c.accent;
  return <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={label}
    style={({ pressed }) => [styles.pill, large && styles.pillLarge, {
      backgroundColor: filled ? c.accent : outlined ? 'transparent' : c.chip,
      borderColor: outlined ? c.faint : 'transparent', opacity: pressed ? 0.8 : 1, transform: [{ scale: pressed ? 0.97 : 1 }],
    }]}>
    {!!icon && <MaterialCommunityIcons name={icon as any} size={large ? 20 : 16} color={fg} />}
    <Text style={[styles.pillText, large && styles.pillTextLarge, { color: fg }]}>{label}</Text>
  </Pressable>;
}

export function SectionLabel({ c, text }: { c: Palette; text: string }) {
  return <Text style={[styles.sectionLabel, { color: c.sub }]}>{text}</Text>;
}

export function Separator({ c }: { c: Palette }) {
  return <View style={[styles.separator, { backgroundColor: c.faint }]} />;
}

/** Settings group: a rounded card of rows separated by hairlines. */
export function Group({ c, title, children }: { c: Palette; title?: string; children: React.ReactNode }) {
  const items = React.Children.toArray(children).filter(Boolean);
  return <View>
    {!!title && <SectionLabel c={c} text={title} />}
    <View style={[styles.group, { backgroundColor: c.card, borderColor: c.border }]}>
      {items.map((child, i) => <View key={i}>{i > 0 && <Separator c={c} />}{child}</View>)}
    </View>
  </View>;
}

export function Row({ c, title, value, hint, onPress, right, danger }: {
  c: Palette; title: string; value?: string; hint?: string; onPress?: () => void; right?: React.ReactNode; danger?: boolean;
}) {
  return <Pressable onPress={onPress} disabled={!onPress} style={({ pressed }) => [styles.row, pressed && { backgroundColor: c.faint }]}>
    <View style={styles.rowText}>
      <Text style={[styles.rowTitle, { color: danger ? c.danger : c.text }]}>{title}</Text>
      {!!value && <Text style={[styles.rowValue, { color: c.accent }]}>{value}</Text>}
      {!!hint && <Text style={[styles.rowHint, { color: c.sub }]}>{hint}</Text>}
    </View>
    {right}
  </Pressable>;
}

export function SwitchRow({ c, title, hint, value, onChange, extra }: { c: Palette; title: string; hint?: string; value: boolean; onChange: (v: boolean) => void; extra?: React.ReactNode }) {
  return <Row c={c} title={title} hint={hint} onPress={() => onChange(!value)} right={<View style={styles.switchWrap}>
    {extra}
    {!!extra && <View style={[styles.vline, { backgroundColor: c.faint }]} />}
    <ToggleSwitch value={value} onChange={onChange} label={title} />
  </View>} />;
}

/* -------------------------------------------------------------- dropdown */

export type DropdownItem = { label: string; icon?: string; checked?: boolean; onPress: () => void };

/**
 * Animated dropdown menu: the panel grows out of its anchor (scale + fade) and
 * shrinks back before closing. `renderAnchor` receives the open function.
 */
export function Dropdown({ c, items, renderAnchor, align = 'right', width = 230 }: {
  c: Palette; items: DropdownItem[]; renderAnchor: (open: () => void) => React.ReactNode; align?: 'left' | 'right'; width?: number;
}) {
  const motion = useMotion();
  const anchorRef = useRef<any>(null);
  const [frame, setFrame] = useState<{ x: number; y: number; w: number; h: number } | null>(null);
  const value = useRef(new Animated.Value(0)).current;
  const { width: screenW, height: screenH } = useWindowDimensions();
  const open = () => anchorRef.current?.measureInWindow((x: number, y: number, w: number, h: number) => {
    setFrame({ x, y, w, h });
    value.setValue(0);
    Animated.spring(value, { toValue: 1, useNativeDriver: true, speed: motion ? 22 : 1000, bounciness: motion ? 5 : 0 }).start();
  });
  const close = (after?: () => void) => {
    Animated.timing(value, { toValue: 0, duration: motion ? 140 : 0, easing: Easing.in(Easing.quad), useNativeDriver: true }).start(() => {
      setFrame(null);
      after?.();
    });
  };
  const panelHeight = items.length * 52 + 12;
  const below = frame ? frame.y + frame.h + 6 + panelHeight < screenH - 24 : true;
  const left = frame ? Math.min(Math.max(12, align === 'right' ? frame.x + frame.w - width : frame.x), screenW - width - 12) : 0;
  const top = frame ? (below ? frame.y + frame.h + 6 : frame.y - panelHeight - 6) : 0;
  return <>
    <View ref={anchorRef} collapsable={false}>{renderAnchor(open)}</View>
    <Modal visible={!!frame} transparent animationType="none" statusBarTranslucent onRequestClose={() => close()}>
      <Pressable style={StyleSheet.absoluteFill} onPress={() => close()} accessibilityLabel="Close menu" />
      {frame && <Animated.View style={[styles.dropdown, {
        left, top, width, backgroundColor: c.card, borderColor: c.border, boxShadow: c.shadow,
        transformOrigin: `${align === 'right' ? '100%' : '0%'} ${below ? '0%' : '100%'}`,
        opacity: value.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0, 1, 1], extrapolate: 'clamp' }),
        transform: [
          { scale: value.interpolate({ inputRange: [0, 1], outputRange: [0.86, 1] }) },
          { translateY: value.interpolate({ inputRange: [0, 1], outputRange: [below ? -8 : 8, 0] }) },
        ],
      } as any]}>
        {items.map(item => <Pressable key={item.label} accessibilityRole="menuitem" accessibilityLabel={item.label}
          onPress={() => close(item.onPress)} style={({ pressed }) => [styles.dropdownItem, pressed && { backgroundColor: c.faint }]}>
          {!!item.icon && <MaterialCommunityIcons name={item.icon as any} size={20} color={c.sub} />}
          <Text style={[styles.dropdownLabel, { color: c.text }]} numberOfLines={1}>{item.label}</Text>
          {item.checked && <MaterialCommunityIcons name="check" size={20} color={c.accent} />}
        </Pressable>)}
      </Animated.View>}
    </Modal>
  </>;
}

/* ---------------------------------------------------------------- switch */

const SWITCH_OFF = 'rgb(82, 82, 82)';
const SWITCH_ON = 'rgb(148, 118, 255)';

/**
 * 50×30 toggle: off is a white ring on grey, on slides right and fills white
 * on purple (0.2 s, like the supplied CSS design).
 */
export function ToggleSwitch({ value, onChange, label }: { value: boolean; onChange: (v: boolean) => void; label: string }) {
  const anim = useRef(new Animated.Value(value ? 1 : 0)).current;
  useEffect(() => {
    Animated.timing(anim, { toValue: value ? 1 : 0, duration: 200, easing: Easing.out(Easing.quad), useNativeDriver: false }).start();
  }, [value, anim]);
  return <Pressable onPress={() => onChange(!value)} accessibilityRole="switch" accessibilityState={{ checked: value }} accessibilityLabel={label} hitSlop={8}>
    <Animated.View style={[styles.switchTrack, { backgroundColor: anim.interpolate({ inputRange: [0, 1], outputRange: [SWITCH_OFF, SWITCH_ON] }) }]}>
      <Animated.View style={[styles.switchKnob, {
        backgroundColor: anim.interpolate({ inputRange: [0, 1], outputRange: ['rgba(255,255,255,0)', 'rgba(255,255,255,1)'] }),
        transform: [{ translateX: anim.interpolate({ inputRange: [0, 1], outputRange: [0, 20] }) }],
      }]} />
    </Animated.View>
  </Pressable>;
}

/* ------------------------------------------------------------- animation */

export function useNow(active: boolean) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [active]);
  return now;
}

function useLoop(duration: number, easing: (v: number) => number = Easing.linear) {
  const motion = useMotion();
  const value = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!motion) { value.setValue(0.5); return; }
    const loop = Animated.loop(Animated.timing(value, { toValue: 1, duration, easing, useNativeDriver: true }));
    loop.start();
    return () => loop.stop();
  }, [value, duration, easing, motion]);
  return value;
}

/**
 * Layered circles behind "Ready to receive": rings grow out of the centre and
 * fade at the edge in an endless, seamless loop (every ring is the same wave
 * at a different phase, so the loop restart is invisible).
 */
export function ReceiveGlow({ c, size }: { c: Palette; size: number }) {
  const RINGS = 6;
  // One slow linear clock drives every ring on the native (UI) thread, so JS work never stalls it.
  const value = useLoop(14000);
  const phases = useMemo(() => Array.from({ length: RINGS }, (_, i) => new Animated.Value(i / RINGS)), []);
  const peak = c.dark ? 0.3 : 0.38;
  return <View pointerEvents="none" style={[styles.glowWrap, { width: size, height: size }]}>
    {phases.map((offset, i) => {
      const phase = Animated.modulo(Animated.add(value, offset), 1) as Animated.AnimatedInterpolation<number>;
      return <Animated.View key={i} renderToHardwareTextureAndroid shouldRasterizeIOS style={{
        position: 'absolute', width: size, height: size, borderRadius: size / 2, backgroundColor: c.glow,
        // Eased in and out over the whole cycle (sine-like), so no ring appears or vanishes abruptly.
        opacity: phase.interpolate({ inputRange: [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1], outputRange: [0, peak * 0.55, peak, peak * 0.85, peak * 0.45, peak * 0.15, 0] }),
        transform: [{ scale: phase.interpolate({ inputRange: [0, 1], outputRange: [0.12, 1] }) }],
      }} />;
    })}
  </View>;
}

/** Search animation: two rings expanding out of the access point. */
export function Pulse({ c }: { c: Palette }) {
  const value = useLoop(1800, Easing.out(Easing.ease));
  const offset = useRef(new Animated.Value(0.5)).current;
  const ring = (v: Animated.Value) => <Animated.View style={[styles.pulseRing, { borderColor: c.accent, opacity: v.interpolate({ inputRange: [0, 1], outputRange: [0.5, 0] }),
    transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [0.6, 1.5] }) }] }]} />;
  return <View style={styles.pulse}>
    {ring(value)}
    {ring(Animated.modulo(Animated.add(value, offset), 1) as any)}
    <View style={[styles.pulseCore, { backgroundColor: c.accent }]}>
      <BrandMark size={30} color={c.onAccent} />
    </View>
  </View>;
}

/** Breathing halo behind an avatar while a transfer runs. */
export function Halo({ c, size }: { c: Palette; size: number }) {
  const value = useLoop(1400, Easing.inOut(Easing.ease));
  const scale = value.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.92, 1.04, 0.92] });
  return <Animated.View style={[styles.halo, { width: size, height: size, borderRadius: size / 2, backgroundColor: c.accentSoft, transform: [{ scale }] }]} />;
}

/** Indeterminate circular spinner (waiting for the receiver to accept). */
export function Spinner({ size, color, stroke = 2 }: { size: number; color: string; stroke?: number }) {
  const value = useLoop(900);
  const rotate = value.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] });
  return <Animated.View style={{ width: size, height: size, borderRadius: size / 2, borderWidth: stroke, borderColor: 'transparent',
    borderTopColor: color, borderRightColor: color, transform: [{ rotate }] }} />;
}

/** Determinate circular progress (two rotating half rings, no SVG); animates towards each new value. */
export function ProgressRing({ size, stroke, progress, color, track }: { size: number; stroke: number; progress: number; color: string; track: string }) {
  const motion = useMotion();
  const target = Math.min(1, Math.max(0, progress));
  const value = useRef(new Animated.Value(target)).current;
  useEffect(() => {
    Animated.timing(value, { toValue: target, duration: motion ? 350 : 0, easing: Easing.out(Easing.cubic), useNativeDriver: true }).start();
  }, [target, value, motion]);
  const half = size / 2;
  const ring = { width: size, height: size, borderRadius: half, borderWidth: stroke, borderColor: color };
  const rightRotate = value.interpolate({ inputRange: [0, 0.5, 1], outputRange: ['0deg', '180deg', '180deg'] });
  const leftRotate = value.interpolate({ inputRange: [0, 0.5, 1], outputRange: ['0deg', '0deg', '180deg'] });
  const leftOpacity = value.interpolate({ inputRange: [0, 0.5, 0.5001, 1], outputRange: [0, 0, 1, 1] });
  return <View style={{ width: size, height: size }}>
    <View style={[StyleSheet.absoluteFill, { borderRadius: half, borderWidth: stroke, borderColor: track }]} />
    <View style={[styles.clip, { left: half, width: half, height: size }]}>
      <Animated.View style={{ position: 'absolute', left: -half, width: size, height: size, transform: [{ rotate: rightRotate }] }}>
        <View style={{ width: half, height: size, overflow: 'hidden' }}><View style={ring} /></View>
      </Animated.View>
    </View>
    <Animated.View style={[styles.clip, { left: 0, width: half, height: size, opacity: leftOpacity }]}>
      <Animated.View style={{ position: 'absolute', left: 0, width: size, height: size, transform: [{ rotate: leftRotate }] }}>
        <View style={{ position: 'absolute', left: half, width: half, height: size, overflow: 'hidden' }}>
          <View style={[ring, { marginLeft: -half }]} />
        </View>
      </Animated.View>
    </Animated.View>
  </View>;
}

/** "Sent / verified": the circle pops in, the check springs in, a ripple (and sparks with `burst`) fades out. */
export function SuccessBadge({ c, size, burst }: { c: Palette; size: number; burst?: boolean }) {
  const motion = useMotion();
  const circle = useRef(new Animated.Value(motion ? 0 : 1)).current;
  const check = useRef(new Animated.Value(motion ? 0 : 1)).current;
  const ripple = useRef(new Animated.Value(motion ? 0 : 1)).current;
  useEffect(() => {
    if (!motion) return;
    Animated.parallel([
      Animated.spring(circle, { toValue: 1, useNativeDriver: true, speed: 14, bounciness: 10 }),
      Animated.sequence([Animated.delay(140), Animated.spring(check, { toValue: 1, useNativeDriver: true, speed: 12, bounciness: 16 })]),
      Animated.timing(ripple, { toValue: 1, duration: 900, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
    ]).start();
  }, [circle, check, ripple, motion]);
  const sparks = burst ? [0, 60, 120, 180, 240, 300] : [];
  return <View style={[styles.centered, { width: size, height: size }]}>
    <Animated.View style={[styles.rippleRing, { width: size, height: size, borderRadius: size / 2, borderColor: c.accent,
      opacity: ripple.interpolate({ inputRange: [0, 1], outputRange: [0.6, 0] }),
      transform: [{ scale: ripple.interpolate({ inputRange: [0, 1], outputRange: [1, 1.7] }) }] }]} />
    {sparks.map(deg => <Animated.View key={deg} style={[styles.spark, { backgroundColor: c.accent,
      opacity: ripple.interpolate({ inputRange: [0, 0.2, 1], outputRange: [0, 1, 0] }),
      transform: [{ rotate: `${deg}deg` }, { translateY: ripple.interpolate({ inputRange: [0, 1], outputRange: [-size * 0.45, -size * 0.85] }) }] }]} />)}
    <Animated.View style={[styles.circle, { width: size, height: size, borderRadius: size / 2, backgroundColor: c.accent,
      transform: [{ scale: circle.interpolate({ inputRange: [0, 1], outputRange: [0.5, 1] }) }], opacity: circle.interpolate({ inputRange: [0, 0.3, 1], outputRange: [0, 1, 1] }) }]}>
      <Animated.View style={{ transform: [{ scale: check }, { rotate: check.interpolate({ inputRange: [0, 1], outputRange: ['-45deg', '0deg'] }) }] }}>
        <MaterialCommunityIcons name="check-bold" size={size * 0.48} color={c.onAccent} />
      </Animated.View>
    </Animated.View>
  </View>;
}

export function LinearProgress({ c, progress }: { c: Palette; progress: number }) {
  const value = useRef(new Animated.Value(progress)).current;
  useEffect(() => {
    Animated.timing(value, { toValue: progress, duration: 300, useNativeDriver: false }).start();
  }, [progress, value]);
  return <View style={[styles.progressTrack, { backgroundColor: c.faint }]}>
    <Animated.View style={[styles.progressFill, { backgroundColor: c.accent, width: value.interpolate({ inputRange: [0, 1], outputRange: ['0%', '100%'] }) }]} />
  </View>;
}

/** Fades and lifts content in when it mounts (tab and screen changes). */
export function FadeIn({ children, style }: { children: React.ReactNode; style?: any }) {
  const motion = useMotion();
  const value = useRef(new Animated.Value(motion ? 0 : 1)).current;
  useEffect(() => {
    if (motion) Animated.timing(value, { toValue: 1, duration: 260, easing: Easing.out(Easing.cubic), useNativeDriver: true }).start();
  }, [value, motion]);
  return <Animated.View style={[style, { opacity: value, transform: [{ translateY: value.interpolate({ inputRange: [0, 1], outputRange: [12, 0] }) }] }]}>
    {children}
  </Animated.View>;
}

export const styles = StyleSheet.create({
  circle: { alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  centered: { alignItems: 'center', justifyContent: 'center' },
  iconCircle: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  iconPressed: { backgroundColor: 'rgba(127,127,140,0.18)' },
  pill: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 18, height: 38, borderRadius: 19, borderWidth: 1, marginTop: 4 },
  pillLarge: { height: 56, borderRadius: 28, paddingHorizontal: 34 },
  pillText: { fontSize: 14, fontWeight: '600' },
  pillTextLarge: { fontSize: 18, fontWeight: '700' },
  sectionLabel: { fontSize: 14, fontWeight: '700', marginTop: 18, marginLeft: 22, marginBottom: 8 },
  separator: { height: StyleSheet.hairlineWidth, marginHorizontal: 22 },
  group: { borderRadius: 26, overflow: 'hidden', borderWidth: 0.8 },
  row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 22, paddingVertical: 15, minHeight: 64 },
  rowText: { flex: 1, minWidth: 0 },
  rowTitle: { fontSize: 17 },
  rowValue: { fontSize: 14, marginTop: 3 },
  rowHint: { fontSize: 13, marginTop: 3, lineHeight: 18 },
  switchWrap: { flexDirection: 'row', alignItems: 'center', gap: 10, marginLeft: 12 },
  switchTrack: { width: 50, height: 30, borderRadius: 20, justifyContent: 'center' },
  switchKnob: { position: 'absolute', left: 5, width: 20, height: 20, borderRadius: 10, borderWidth: 5, borderColor: '#FFFFFF',
    boxShadow: '5px 2px 7px rgba(8, 8, 8, 0.26)' },
  vline: { width: StyleSheet.hairlineWidth, height: 28 },
  glowWrap: { alignItems: 'center', justifyContent: 'center' },
  dropdown: { position: 'absolute', borderRadius: 20, borderWidth: 0.8, paddingVertical: 6, overflow: 'hidden' },
  dropdownItem: { flexDirection: 'row', alignItems: 'center', gap: 14, paddingHorizontal: 18, height: 52 },
  dropdownLabel: { flex: 1, fontSize: 16 },
  pulse: { width: 120, height: 120, alignItems: 'center', justifyContent: 'center' },
  pulseRing: { position: 'absolute', width: 84, height: 84, borderRadius: 42, borderWidth: 2 },
  pulseCore: { width: 60, height: 60, borderRadius: 30, alignItems: 'center', justifyContent: 'center' },
  halo: { position: 'absolute' },
  rippleRing: { position: 'absolute', borderWidth: 3 },
  spark: { position: 'absolute', width: 4, height: 10, borderRadius: 2 },
  clip: { position: 'absolute', top: 0, overflow: 'hidden' },
  progressTrack: { height: 5, borderRadius: 3, overflow: 'hidden', marginTop: 6 },
  progressFill: { height: 5, borderRadius: 3 },
});
