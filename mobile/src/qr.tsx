// Quick Send: QR codes for "Over the internet" — showing a code to scan, and scanning one with the camera.

import React, { useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import QRCode from 'qrcode';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { Copy } from './strings';
import { Palette, Pill, Text } from './ui';

/** Black-on-white code with a 4-module quiet zone, drawn with Views (runs of dark modules are merged). */
export function QrCode({ value, size }: { value: string; size: number }) {
  const rows = useMemo(() => {
    // Base32 codes go upper-case: the QR alphanumeric mode makes a much smaller, easier to scan code
    // (the app accepts either case).
    const text = /^[a-z0-9]+$/.test(value) ? value.toUpperCase() : value;
    const qr = QRCode.create(text, { errorCorrectionLevel: 'L' });
    const n = qr.modules.size;
    const result: Array<Array<{ start: number; length: number }>> = [];
    for (let y = 0; y < n; y++) {
      const runs: Array<{ start: number; length: number }> = [];
      let x = 0;
      while (x < n) {
        if (qr.modules.get(y, x)) {
          const start = x;
          while (x < n && qr.modules.get(y, x)) x++;
          runs.push({ start, length: x - start });
        } else {
          x++;
        }
      }
      result.push(runs);
    }
    return { n, runs: result };
  }, [value]);
  const quiet = 4;
  const cell = Math.max(1, Math.floor(size / (rows.n + quiet * 2)));
  const inner = cell * rows.n;
  return <View accessibilityRole="image" style={[styles.qrBox, { padding: cell * quiet }]}>
    <View style={{ width: inner, height: inner }}>
      {rows.runs.map((runs, y) => runs.map(run =>
        <View key={`${y}-${run.start}`} style={[styles.dark, { top: y * cell, left: run.start * cell, width: run.length * cell, height: cell }]} />))}
    </View>
  </View>;
}

/** Camera viewfinder that reports the first QR code it reads. */
export function QrScanner({ t, c, onScanned }: { t: Copy; c: Palette; onScanned: (data: string) => void }) {
  const [permission, requestPermission] = useCameraPermissions();
  const [done, setDone] = useState(false);
  if (!permission) return null;
  if (!permission.granted) {
    return <View style={styles.permission}>
      <Text style={[styles.hint, { color: c.sub }]}>{permission.canAskAgain ? t.internetCameraWhy : t.internetCameraDenied}</Text>
      {permission.canAskAgain && <Pill c={c} label={t.internetCameraAllow} icon="camera" filled onPress={() => { requestPermission(); }} />}
    </View>;
  }
  return <View style={[styles.viewfinder, { borderColor: c.accent }]}>
    <CameraView style={StyleSheet.absoluteFill} facing="back" barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
      onBarcodeScanned={done ? undefined : ({ data }) => { setDone(true); onScanned(data); }} />
  </View>;
}

const styles = StyleSheet.create({
  qrBox: { backgroundColor: '#FFFFFF', borderRadius: 20, alignSelf: 'center' },
  dark: { position: 'absolute', backgroundColor: '#000000' },
  viewfinder: { height: 300, borderRadius: 20, overflow: 'hidden', borderWidth: 2, marginBottom: 12 },
  permission: { gap: 12, marginBottom: 12, alignItems: 'flex-start' },
  hint: { lineHeight: 20 },
});
