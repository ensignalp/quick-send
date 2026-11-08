# Phase 7 — Quick Share interoperability research (no code)

Status: research only. Nothing here has been implemented, and no external code has been added.
**Decision needed from the product owner.**

> Confidence note: protocol details below come from public reverse-engineering
> write-ups and open-source implementations as I understand them. They are not
> verified against a running device in this repo. Verify every point (especially
> licenses) at the source before committing to an option.

## 1. What compatibility would require

Quick Share (formerly Nearby Share) runs on top of Google's **Nearby Connections**
stack. That stack is unrelated to LocalSend's REST/HTTPS protocol. To interoperate,
Quick Send would need a **second, parallel protocol stack**:

| Layer | What is needed |
|---|---|
| Discovery | mDNS/DNS-SD service advertising with an encoded endpoint ID and device info (Wi-Fi LAN). Real phones often also rely on **BLE advertisements** to wake or discover peers. Without BLE, discovery from phones is unreliable. |
| Transport | Wi-Fi LAN TCP sockets. Optional upgrades: Wi-Fi Direct, hotspot, Bluetooth. |
| Framing | Length-prefixed **protobuf** frames (Nearby Connections offline wire format). |
| Handshake | **UKEY2** key exchange (ECDH P-256) and a PIN/auth-string derivation shown to users. |
| Encryption | Google **SecureMessage/SecureGCM** (AES-CBC + HMAC-SHA256) wrapping all frames after UKEY2. |
| App layer | Quick Share "sharing" protobufs: introduction, file metadata, accept/reject, payload transfer chunks, keep-alive. |
| Visibility | Recent Android versions restrict "Everyone" visibility, and contact-only visibility uses Google account certificates. **Contacts mode cannot be reproduced** by third parties. Only "Everyone" (temporary) mode is reachable. |

Sending *to* phones is harder than receiving from them. Phones usually discover
targets over BLE first, and desktop implementations without BLE support are mostly
receive-only or need a manual workaround.

## 2. Existing open-source implementations

| Project | Language | License (verify) | Notes |
|---|---|---|---|
| google/nearby | C++ | Apache-2.0 | Google's own Nearby Connections and Quick Share code (Windows-focused). License-compatible with this project. Very large, Bazel-based, hard to embed. |
| NearDrop (grishka) | Swift (macOS) | Permissive, believed to be Unlicense; verify | Receive-centric. Best readable protocol documentation (PROTOCOL.md). |
| rquickshare | Rust + Tauri | **GPL-3.0** | Linux/macOS, the most complete open desktop implementation. **Cannot be linked or copied into Quick Send** without relicensing the combined work under GPL-3.0. |
| Other small Python/Go experiments | various | varies | Mostly incomplete. |

## 3. License impact

- Quick Send is Apache-2.0 (from LocalSend). Apache-2.0 code **can** flow into GPL-3.0 projects, but **not the other way round**. Including rquickshare code, or deriving from it closely, makes the distributed binary GPL-3.0. The prompt's rules forbid this.
- Options that stay clean:
  - reimplement from protocol documentation, without copying GPL code (clean-room discipline);
  - reuse Apache-2.0 google/nearby code;
  - reuse permissive code (verify NearDrop's license).
- **Trademark:** the feature must not be called "Quick Share" in the UI. A neutral wording such as "Compatible with nearby Android sharing" also needs legal review.
- **Protocol stability:** Google can change the protocol, certificates or visibility rules at any time. Breakage is out of our control.

## 4. Options and rough effort

| Option | Scope | Rough effort (1 experienced dev) | Risk |
|---|---|---|---|
| A. Do nothing | LocalSend protocol only | 0 | Users need Quick Send or LocalSend on both sides |
| B. Linux receive-only (Wi-Fi LAN, mDNS, UKEY2, protobuf), clean-room Rust module | Phone → Linux | 6–10 weeks | Medium: discovery from phones may need BLE |
| C. B plus Linux send with BLE (BlueZ) | Bidirectional on Linux | +6–10 weeks | High: BLE on Linux and firewall issues, protocol drift |
| D. Android ↔ Quick Share | — | not feasible in practice | Android already ships Quick Share. A third-party app cannot replace the system service or contacts mode. |
| E. Embed google/nearby (Apache-2.0) | Bidirectional | 8–14 weeks, mostly build/integration | High build complexity (Bazel, C++ on Flutter/Linux) |

## 5. Recommendation

Keep Option A for the 1.0 release. If cross-ecosystem receive is a must, prototype
Option B as an **isolated, optional Rust crate** with a separate feature flag. It
should be clean-room, carry no GPL code, have its own NOTICE entry, and come with a
legal review of naming. Re-evaluate after a two-week spike that tests phone →
Linux discovery without BLE.
