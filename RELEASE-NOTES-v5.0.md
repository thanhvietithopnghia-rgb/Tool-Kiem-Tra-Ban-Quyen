# Tool Kiểm Tra v5.0.0.0 — ManagedSigned Preview R5

Canonical release/build label date: 2026-08-26
Final compile/package timestamp: 2026-08-27T01:01:24Z
Status: `ManagedSigned` prerelease (Preview R5) — Authenticode, RFC 3161 timestamp, and provenance are verified on managed machines; this is not the public-CA Stable channel

Preview R4 was published as a prerelease but withdrawn before Stable promotion because its compiled launcher
contained a BuildId that differed from the Bridge/provenance identity. Preview
R5 is rebuilt from source with one canonical BuildId, post-compile EXE/embedded-
Bridge verification, CycloneDX SBOM, and commit-pinned GitHub Actions.

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
- Preview R5 preserves the responsive R4 UI while replacing the release artefact and all release metadata after the BuildId identity correction.
- The attached public-safe R5 test evidence records Windows 11 current/25H2 as Passed and leaves Windows 10 22H2 plus Windows 11 previous/24H2 as Missing (`Passed=1`, `Failed=0`, `Missing=2`); the client VM matrix therefore remains incomplete.
- Unsigned development builds remain a separate mode and keep self-update plus every system-changing action blocked.

## Public Stable Gates Still Required

- Acquire and protect a CA-issued code-signing certificate through an HSM, token, or managed signing service.
- Keep RFC3161 signing on the verified DigiCert HTTP endpoint while the local HTTPS route remains blocked.
- Complete the Windows 10/11 client VM matrix and independent security review evidence.
- Commit the final source snapshot, update and sign provenance, then run the complete Stable build and verifier chain.

Do not represent a `ManagedSigned` artifact as public-CA Stable.
