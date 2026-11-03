# Upstream sync strategy

The `upstream` remote tracks `https://github.com/localsend/localsend.git`. The
Quick Send repository is a downstream fork; this checkout has no Quick Send
publishing remote configured.

## Boundaries

- Keep `packages/core`, `packages/localsend_isolates`, protocol models, HTTPS
  transport, certificate generation and fingerprint checks, and receiver
  approval behavior as close to upstream as possible.
- Keep Quick Send identity, Android application UI, packaging and release
  workflows in their own files/directories where practical.
- Preserve upstream `LICENSE`, per-file copyright headers, contributor credits,
  and protocol behavior. `NOTICE` records the fork attribution.
- Do not merge upstream app branding, logos, platform claims, donation links, or
  privacy-policy links into the Quick Send product UI.

## Sync procedure

1. Fetch and inspect upstream before choosing a version: `git fetch upstream`.
2. Review the upstream changelog and protocol/core diffs first. Prefer a
   dedicated sync branch and merge upstream commits rather than copying files.
3. Resolve conflicts in application code by retaining protocol and security
   fixes, then reapplying the Quick Send UI and identity changes documented in
   [QUICK_SEND_CHANGES.md](QUICK_SEND_CHANGES.md).
4. Regenerate derived files using the pinned Flutter/FVM and Rust toolchains;
   do not hand-edit generated localization or binding output.
5. Run the Flutter analysis/tests, Rust tests and clippy, and platform builds
   affected by the sync. Verify TLS fingerprint validation and receiver
   approval remain in the receive path.
6. Test interoperability with a LocalSend client on the same LAN before
   releasing a protocol-affecting sync. The Quick Send brand must remain separate
   from the upstream product identity while About retains the attribution.

## Current protocol boundary

The REST/HTTPS and multicast discovery implementation is inherited from
LocalSend. Quick Send does not add a network service or endpoint. The upstream
protocol uses TCP and UDP port 53317; changes to those routes, payloads, ports,
certificate checks, or approval semantics require a separate compatibility
review and documentation update.
