# Computer Configuration and Software License Check Tool — Version History

This document summarizes the core changes in the main public releases.

Current ManagedSigned version: **v5.0.0.0**
FileVersion: **5.0.0.0** · Build **2026.08.24**

Stable latest-release page:
<https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

## v5.0.0.0 — August 24, 2026 — ManagedSigned prerelease

- **Trusted release chain:** Stable fails closed without a CA-issued/HSM certificate, RFC3161 timestamp, source-bound CMS provenance, and a clean worktree.
- **Catalogs and plugins:** Fresh/Warning/Stale/Future/Invalid states; external plugins accept only signed declarative metadata from administrator-pinned publishers.
- **Flexible scanning:** Quick, Standard, and Deep levels with explicit budgets and safe include/exclude/root limits.
- **UI and deployment:** system-aware themes, dark/light overrides, PerMonitorV2 DPI, safe fleet export, a headless CLI, and Intune/MDM scripts.
- **Five-entry remediation:** the Remediation section contains Windows, Microsoft Office, other software, OEM key recovery, and valid-license management. The first three open their dedicated locked-scope screen directly; scope remains fixed through Dry Run, backup, confirmation, and post-check.
- **Cleaner status card:** the redundant "software catalog: fresh/latest" line is hidden while freshness enforcement, warning colors, and tooltip details remain active.
- **Version synchronization:** server/workstation UI takes its version from the launcher; new infrastructure names use v5.0 while legacy v4.8/v4.6 cleanup remains compatible.
- **Current state:** approved administration is enabled only on machines that trust the ManagedSigned certificate; public self-update remains disabled and this is not public-CA Stable.

## v4.9.0.0 — August 22, 2026

- **More accurate recognition:** inventories Registry, AppX/MSIX, WinGet, shortcuts, package managers, and bounded portable locations; distinguishes confirmed installations from portable/residual files and merges duplicate records by product family.
- **Adaptive integrity scanning:** vendor host blocks or disabled licensing services trigger broader Authenticode checks within the exact product directory; evidence no longer leaks between products from the same vendor.
- **Diagnosable licensing and safe remediation:** unreadable data is distinct from unactivated status; reports are read-only; remediation removes only the selected bad key/Activation ID, preserves coexisting genuine licences, and verifies the exact selected scope afterward.
- **Controlled complete uninstall:** an application can be fully removed only after explicit selection and validation of a source-bound MSI/AppX identity; the preview, backup, execution result, and absence post-check remain mandatory.
- **Protected release chain:** the EXE, provenance, catalog, and update manifest are signed; online comparison accepts declarative data only from pinned official sources and uploads no software inventory or device data.
- **Policy from v4.9:** the Tool remains free and community-oriented; source is no longer published free of charge, is not open source, and requires the author's prior written approval for access.

## v4.8.0.0 — August 10, 2026

- **Broad inventory and assessment:** expanded Windows, Office, third-party software, and hardware checks while separating licence model, technical state, and confidence.
- **Deep scan and signed catalog:** introduced multi-tier evidence and `Unverified` outcomes to avoid conclusions when data is incomplete.
- **Controlled remediation:** scope selection, preview, confirmation, backup, and post-verification are mandatory; weak evidence never removes software or changes the system automatically.
- **Usability:** completed the Dashboard, HTML/PDF reports, local Assistant, and server–workstation management while keeping Offline as the default.

## v4.6 — August 6, 2026

Focus: no-change remediation simulation, broader engineering-software recognition, and an isolated data lifecycle instead of sharing the v4.4/v4.5 write root.  
Platform/technology: C#/.NET Framework 4 AnyCPU; Windows PowerShell 3+/WinForms; JSON catalog 1.2; DataSchema 2.0; SHA-256/HMAC/DPAPI; LAN HTTP with AES-256-CBC + HMAC-SHA256 application envelopes.

- Expanded the software catalog to `1.2.0.0` with 45 product rules, including 16 CAD/CAM/CAE, BIM, simulation, structural, GIS, EDA, measurement, and rendering groups. Unknown products still use the vendor-neutral deep scanner.
- Added a deep-scan performance hotfix with per-directory caching, lighter .NET enumeration, a reusable Authenticode runspace pool, and an adaptive 6/3/1 signature profile by risk. Source scope, depth, artifact inspection, and correlated system evidence are unchanged, and all limits remain reportable.
- Added **Dry Run** for KMS/Activator remediation. It lists the exact file, Registry, service, task, KMS/key, MSI Repair, or uninstall action plus backup/restorability without creating a restore point, backup, or system change. Real execution reopens item selection and requires confirmation again.
- Fixed online-catalog consent to fail closed: omitted consent or explicit `false` exits with code `2` before any network operation, and the wrapper no longer replaces the caller's value with `true`.
- Reduced unauthenticated `GET /tool/v1/status` to exactly `Accepted`, `ProtocolVersion`, and `ToolVersion`; server identity, addresses, bind settings, CIDRs, and client counts are not disclosed. Business endpoints retain authenticated envelopes and rate limiting.
- Moved writable state to `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6`, with `DataSchemaVersion=2.0`, `ProducerVersion`, a migration lock, and machine-readable state. Migration uses a staging copy, SHA-256 verification, transactional commit, and rollback; v4.4/v4.5 data remains unchanged, while old logs/backups are read-only references.
- Added v4.6 launcher, Enterprise agent, and audit mutexes, with launcher-side detection of an active v4.4/v4.5 process before migration. Old cryptographic labels remain only as compatibility identifiers for migrated timeline and secret material.
- Synchronized v4.6 across module/report/safety/capability/catalog metadata, documentation, User-Agent, and verifiers. Added `VERIFY-DATA-LIFECYCLE.ps1` for one-time migration, legacy preservation, idempotency, and rollback fixtures.

## v4.5 — August 6, 2026

- Completed the shared Light/Dark visual system, colored action icons, DPI-aware text layout, and the new product name **Computer Configuration and Software License Check Tool**.
- Inventories all software found through Uninstall Registry data, AppX/MSIX, Start Menu, Desktop, and bounded installed/portable locations; compares licensing models and technical evidence without treating “no evidence” as genuine.
- Added a vendor-neutral deep scan for every detected application: multiple EXE/DLL Authenticode checks, trusted known-bad hashes, artifacts, and correlated system tampering evidence; weighted signature budgeting preserves broad coverage while prioritizing paid/trial/evidence-bearing software, and incomplete coverage is reported explicitly.
- Added **Connect online**, with an explanation and explicit consent before downloading a fixed HTTPS comparison catalog; no application inventory, paths, keys, or tokens are uploaded, and Offline remains the default.
- Lists all other-software results and allows individual or Select-all handling for every Non-genuine/Suspicious scope; backup is mandatory before reset, Repair, cleanup, or manual uninstall/reinstall actions.
- Makes every Non-genuine/Suspicious application manually selectable and adds a generic scope-locked plan for exact artifact quarantine, hosts restoration, validated MSI Repair, or manual uninstall for an official reinstall. Automatic mode never uninstalls software.
- Split scanning into All, Windows and Office, and Other software scopes; extended Backup/Restore to the same scopes; added timeouts, heartbeats, and on-demand HTML/PDF generation to reduce apparent hangs.
- Optimized all 44 embedded payloads by choosing Deflate or raw per resource, then decompressing and verifying SHA-256 before launch without removing a module or reducing scan coverage.
- Rewrote the synchronized Vietnamese/English v4.5 end-user guides in the task-by-task style used by v4.4: what changed, how to run the EXE, all ten tasks, software status, deep scanning, safe remediation, reports, and troubleshooting; packaging internals were removed from the user guide.

## v4.4 — July 31, 2026

- Added safe automatic remediation for allowlisted, backup-capable items, with preview, confirmation, protected backup, and post-scan verification.
- Completed Vietnamese/English localization across the dashboard, dialogs, reports, and child modules while preserving language-neutral machine status codes.
- Refreshed the Fluent-style dashboard, Inspect/Remediate/Reports filters, Settings dialog, and bundled vector icons for Light/Dark modes.
- Optimized bounded Office/file scanning and added Copy full log, Open report folder, and non-blocking VM/Remote Desktop notices.

## v4.3 — July 30–31, 2026

- Upgraded the dashboard to schema 2.0 with DPI/screen-size adaptation and a safe Stop action for child tasks.
- Standardized Offline-by-default behavior, Vietnamese/English operation, Local/Server/Workstation management, and HTML/PDF/JSON/XML reports.
- Expanded software, signature, autorun, service, task, and installation-source inventory without breaking earlier report contracts.

## v4.2 — July 24–25, 2026

- Added the internal-network license center with Local, Server, and Workstation modes.
- Added pairing, inventory, offline queues, and authenticated/encrypted fleet reporting.
- Protected URL ACL/firewall configuration with confirmation and prevented competing servers in one scope.

## v4.1 — July 23, 2026

- Added the Report Center, certificate auditing, read-only declarative plugins, and license timeline.
- Standardized HTML, PDF, JSON, XML, and SHA-256 manifest export; protected timeline records with DPAPI/HMAC/hash chaining.
- Added release-signing checks, the About window, and product capability groups.

## v4.0 — July 23, 2026

- Replaced the traditional menu with a WinForms dashboard containing status cards, ten actions, Light/Dark modes, and DPI-aware layout.
- Added report schemas, safety-policy modules, regression verification, and native x64/x86 Windows-tool resolution.
- Introduced the KMS/Activator remediation center with preview, confirmation, backup, and post-checks.

## v3.9 — July 22, 2026

- Upgraded reports to schema 1.3, added fallback scan sources, and made schema verification a release gate.
- Reduced false positives involving legitimate Windows processes, old PowerShell history, hosts entries, and inactive Office SKUs.
- Optimized per-run caching and refreshed data before post-checks.

## v3.8 — July 22, 2026

- Added deeper Windows/Office scans and confidence-based evidence aggregation.
- Improved detailed reports, remediation guidance, and partial-source failure handling.

## v3.7 — July 22, 2026

- Added integrity, file-signature, and common licensing-tampering checks.
- Standardized detection states shared by the interface and reports.

## v3.6 — July 22, 2026

- Expanded multi-version/multi-SKU Office inspection and unusual KMS configuration detection.
- Added technical logging and post-remediation verification.

## v3.5 — July 21, 2026

- Added integrity-protected Windows/Office licensing backup and restore.
- Required Administrator rights, preview, and confirmation before system changes.

## v3.4 — July 21, 2026

- Improved digital-license, OEM, and Windows licensing-channel recognition.
- Added safe local-key inspection with only partial key display.

## v3.3 — July 20, 2026

- Expanded software, process, service, and scheduled-task inventory related to activation.
- Improved report export and result messages.

## v3.2 — July 20, 2026

- Added Office inspection alongside Windows and distinguished multiple licensing types.
- Improved error handling when system tools are unavailable or return incomplete data.

## v3.1 — July 20, 2026

- Added computer configuration, operating-system architecture, and core hardware inspection.
- Reorganized logs and conclusions by function group.

## v3.0 — July 20, 2026

- Unified configuration and licensing inspection into one workflow.
- Added function selection and a combined report.

## v2.9 — July 20, 2026

- Improved KMS/Activator detection and avoided conclusions based on one weak indicator.
- Added manual guidance when evidence is insufficient.

## v2.8 — July 20, 2026

- Expanded Windows/Office activation queries across multiple system sources.
- Standardized error codes and diagnostic details.

## v2.7 — July 20, 2026

- Added service, scheduled-task, and network-configuration checks related to activation.
- Added confirmation before potentially state-changing actions.

## v2.6 — July 20, 2026

- Improved Windows PowerShell/.NET Framework and x86/x64 compatibility.
- Added exception handling so scans continue when an individual source fails.

## v2.5 — July 18, 2026

- Added Microsoft Office inspection with version and licensing-channel details.
- Improved text reports and result-copying support.

## v2.4 — July 18, 2026

- Expanded computer configuration and Windows status information.
- Improved the interface and task organization.

## v1.3 — July 18, 2026

- Added OEM/firmware-key and basic activation checks.
- Improved error messages and user guidance.

## v1.2 — July 18, 2026

- Added result export and the first Office checks.
- Improved Vietnamese Unicode handling.

## v1.1 — July 18, 2026

- Added a selection interface and basic computer details.
- Improved compatibility across Windows versions.

## v1.0 — July 17, 2026

- Initial release for computer configuration and Windows activation inspection.
- Stored results locally and never connected to the Internet automatically.

---

Consistent safety principle: inspection is read-only by default; no telemetry; no unrequested licensing change; remediation requires selection, confirmation, backup, and post-verification.
