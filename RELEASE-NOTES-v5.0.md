# Tool Kiểm Tra v5.0.0.0 — ManagedSigned Stable R7

Canonical release/build label date: 2026-08-26
Stable promotion date: 2026-08-30
Status: `ManagedSigned` GitHub Stable (owner-approved self-signed exception) — Authenticode, RFC 3161 timestamp, and provenance are verified on managed machines; this is not a public-CA identity

R7 was rebuilt from the hardened R4 source line after the elevated broker was
updated to reject UNC paths, device namespaces, and Alternate Data Streams.
The owner explicitly approved promotion with the self-signed trust limitation,
an incomplete 1/3 client VM matrix, and no independent review attestation.

## R7 Stable exception highlights

- Elevated-bridge requests now reject unsafe UNC, device-namespace, and ADS paths before crossing the UAC boundary.
- The full managed release verifier passed with `0 errors / 3 disclosed warnings`.
- EXE SHA-256: `63BFB66FFC088C75570FE4C6574FC8134F4434F2BA8B5956865E08AC9F8FE788`.
- The detached update manifest is signed and points v4.9 Stable clients to this exact artifact.
- Fresh unmanaged Windows installations may show `Unknown Publisher`; system-changing actions remain fail-closed until the ManagedSigned trust anchor is installed.

Preview R4 was withdrawn before Stable promotion because its compiled launcher
contained a BuildId that differed from the Bridge/provenance identity. Preview
R5 established the canonical v5.0.0.0 identity. Preview R6 is the hotfix
revision rebuilt from the same release line with scan-source recovery, clearer
process diagnostics, and responsive result messaging.

## R6 hotfix highlights

- ManagedSigned repair calls now pass the trusted-state bridge check, and failed child processes report their exit code.
- Missing scan-result files are distinguished from process failures and stale decision files are cleared before retry.
- Incomplete software scans remain read-only but offer **Repair scan sources** so the user can repair and rescan without changing the system.
- Windows, Microsoft Office, and other-software scope is stated directly in the result window; long Vietnamese/English labels wrap instead of being clipped.
- The safety regression suite includes the ManagedSigned repair bridge probe and the new localized diagnostic tokens.

## Highlights

- Stable release creation now fails closed unless Authenticode uses a valid CA-issued/HSM certificate, Windows trust succeeds, an RFC3161 timestamp exists, provenance CMS matches the source snapshot, and the worktree is clean.
- Software catalogs expose explicit freshness states; external plugins accept only signed declarative metadata from administrator-pinned publisher fingerprints.
- Quick, Standard, and Deep scan levels add explicit budgets and safe include/exclude/root limits.
- The UI follows the system theme, supports dark/light overrides, and declares PerMonitorV2 DPI awareness.
- Fleet JSON/CSV/HTML/PDF export adds redaction and CSV-injection guards; a headless CLI and Intune/MDM scripts support managed deployment.
- ManagedSigned builds use a distinct verified state, permit approved system-changing actions after WinVerifyTrust and provenance both succeed, and keep public self-update disabled.
- The Remediation section now exposes five entries: Windows, Microsoft Office, other software, OEM key recovery, and valid-license management. The first three open their own scope-locked remediation screen directly instead of the shared chooser; the combined Overview entry remains available.
- The Enterprise manager now inherits `5.0.0.0` from the launcher, uses v5.0 names for new firewall/task resources, and retains cleanup compatibility for v4.8/v4.6 resources.
- The sidebar footer now shows only the Thanh Việt copyright line; the redundant software-version line was removed.
- The compact compatibility card no longer shows the redundant "software catalog: fresh/latest" line; catalog freshness enforcement, warning colors, and tooltip details remain active.
- Responsive R4 adds compact navigation when the sidebar is hidden, content-aware tile heights with bounded scrolling on short screens, and clipping checks for Vietnamese/English licence-management controls.
- Preview R5 established the responsive UI and canonical release artefact; Preview R6 carries the scan-source recovery hotfix while retaining the same v5.0.0.0 build identity.
- The attached public-safe R6 test evidence records Windows 11 current/25H2 as Passed and leaves Windows 10 22H2 plus Windows 11 previous/24H2 as Missing (`Passed=1`, `Failed=0`, `Missing=2`); the client VM matrix therefore remains incomplete.
- Unsigned development builds remain a separate mode and keep self-update plus every system-changing action blocked.

## Public-CA Gates Still Open

- Acquire and protect a CA-issued code-signing certificate through an HSM, token, or managed signing service.
- Keep RFC3161 signing on the verified DigiCert HTTP endpoint while the local HTTPS route remains blocked.
- Complete the Windows 10/11 client VM matrix and independent security review evidence.
- Commit the final source snapshot, update and sign provenance, then run the complete Stable build and verifier chain.

R7 is GitHub Stable by explicit owner exception. Do not represent it as public-CA Stable.
