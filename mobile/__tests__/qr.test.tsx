import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import QRCode from 'qrcode';
import { QrCode } from '../src/qr';

// A real iroh ticket length (sender with relay + direct addresses).
const code = 'blob' + 'a'.repeat(327);

test('a long internet code fits in a scannable QR code', () => {
  // Upper-case base32 uses the alphanumeric mode, as QrCode does.
  const qr = QRCode.create(code.toUpperCase(), { errorCorrectionLevel: 'L' });
  expect(qr.modules.size).toBeLessThanOrEqual(53); // version 9 or lower at level L
});

test('QrCode renders dark modules inside a white quiet zone', async () => {
  let tree: ReactTestRenderer.ReactTestRenderer | undefined;
  await ReactTestRenderer.act(async () => { tree = ReactTestRenderer.create(<QrCode value={code} size={250} />); });
  const root = tree!.root.findAll(n => (n.props.style ?? []).some?.((st: any) => st?.backgroundColor === '#FFFFFF'));
  expect(root.length).toBeGreaterThan(0);
  const dark = tree!.root.findAll(n => n.props.style?.[0]?.backgroundColor === '#000000' || n.props.style?.backgroundColor === '#000000');
  expect(dark.length).toBeGreaterThan(50);
});
