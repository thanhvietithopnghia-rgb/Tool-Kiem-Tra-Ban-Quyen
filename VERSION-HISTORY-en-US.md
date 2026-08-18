# Computer Configuration and Software License Check Tool — Version History

This document summarizes the main public releases from v1.0 through v4.8.0.1. v4.8 is the direct upgrade from v4.6; verified intermediate work is consolidated into v4.8 instead of being listed as a separate public release.

Current release: **v4.8.0.1**
FileVersion: **4.8.0.1** · Build **2026.08.18**

## v4.8.0.1 — August 18, 2026

- **Safe application updates:** an update is offered only for a newer release, or for a same-version replacement when the installed EXE hash is verified and differs. Missing or invalid hashes fail closed. Check and Apply revalidate the launcher hash, retain a backup, and roll back if the replacement does not start reliably.
- **A new public version:** FileVersion/ProductVersion is now `4.8.0.1` so devices on `4.8.0.0` can receive this release through the user-consented Online update flow; there are no silent updates or telemetry.

## v4.8.0 — August 10, 2026 · in-place updates August 14 and 17, 2026

**v4.8 is a direct upgrade from v4.6, focused on these main changes:**

**In-place maintenance update on August 17, 2026:**

- **Hardware and platform security:** complete TPM Present/Ready/Enabled/Activated and version reporting, Secure Boot fallback, and per-volume BitLocker details; expanded serial/identity collection for BIOS, system, baseboard, chassis, CPU, memory, storage, GPU, monitors, batteries, and networking. Full internal reports retain serials; shareable reports redact identifying values.
- **Software inventory and catalog:** detached-CMS-signed catalog `1.4.0.1` with scope/update-policy metadata and 77 fail-closed rules. Parallel installs at different locations or patch versions remain separate; reports separate license model, technical state, reason, source, evidence, and confidence, with confirmed crack/strong evidence first.
- **Safe remediation:** a generic filename containing “crack” is review-only; only allowlisted Strong/Conclusive evidence can create a candidate. System/driver components are never remediated, and `rarreg.key` alone proves neither valid entitlement nor abuse.
- **Official activation and post-checks:** after tampering evidence is removed, the Tool separates “clean and ready for activation” from “licensed.” Windows returns `ActivationConfirmed = TRUE` only when Software Protection reports `LicenseStatus=1` for the submitted key; Office returns TRUE only when `OSPP.VBS /dstatusall` reports `LICENSED` for the same last five characters. Otherwise it remains FALSE, reports Unactivated/Needs repair, and opens the official activation surface; verified OEM/Retail/MAK or approved organization KMS licensing is preserved.
- **Tool Assistant:** handles more short, misspelled, and follow-up questions; correctly explains that the Tool is provided free of charge, v1.0 was released on 17 July 2026, the source is publicly inspectable but not currently open source, and Undetermined/Unverified/Suspicious/Crack-confirmed are distinct states.

**Report-feedback update on August 14, 2026:**

- **Context-correct assessment:** separates the license model from technical evidence; free/open-source applications no longer request purchase invoices. Only real crack, activator, unauthorized command/task, or tampering indicators enter the evidence table.
- **Specific handling conditions:** `Low` is informational and cannot justify removing an application or bloatware. Unverified, Suspicious, Non-genuine, and Integrity-compromised states have distinct guidance. The Tool targets the exact artifact/command/task and preserves the application.
- **Additional detection:** conservatively detects MAS/PMAS, Activation Program 1.17, and Startup commands that point exactly to `erturk-dev.netlify.app/run`; existing KMSPico coverage remains, with benign PowerShell/Netlify negative fixtures.
- **WinRAR and official sources:** a `rarreg.key` file alone is not treated as abuse and is not automatically removed; an expired trial recommends a license or lawful alternative. MathType and WinRAR links resolve to the vendors' official pages.
- **Parallel installations:** shown only when different versions exist in different locations; duplicate Registry/AppX/shortcut records such as Zalo/Telegram are not counted as separate installs, and the table states that this is not licensing evidence.
- **Reports/PDF:** the software appendix uses a dedicated teal palette with better spacing and contrast; wide tables split into Context/Decision groups, and detailed A4 output uses larger type, line height, padding, repeated headers, and cleaner page breaks.
- **Full/Software PDF hotfix:** renderer-generated official HTTPS references are no longer mistaken for remotely loaded resources by the Offline gate, so detailed PDFs export normally; remote image/CSS/SVG/form content and untrusted links remain blocked. Completion logs now include PDF status, engine, and error details.
- **Tool Assistant:** responds with conclusion–evidence–action structure, distinguishes Windows/Office/third-party software, explains model–status–confidence–remediation, and avoids legal overclaims or automatic remediation.

- **Interface:** clearer layout, better Light/Dark and DPI behavior, and a fix for the **Redacted report** button being clipped or fading on hover.
- **Checks and remediation:** Online and Dry Run now share three checkboxes—**Windows, Office, and Other software**. One or more scopes can be selected, and only those scopes are scanned or handled. Preview, confirmation, backup, and post-verification remain mandatory.
- **Scanning and performance:** faster inventory and assessment, a 76-rule catalog, and more cautious result classification.
- **Reports:** fixes clipped/missing PDF lines, simplifies layout, and supports redacted reports for sharing.
- **Assistant and connectivity:** understands Tool-related questions across 63 structured topics and 481 keywords/phrasing variants, bundled guides, report data, and prior-turn context. Knowledge `1.3.1` uses detached JSON plus a CMS SHA-256 signature, a pinned publisher certificate, downgrade protection, and a previous-cache fallback; it checks after explicit Online consent, keeps growing knowledge outside the EXE, uploads no questions/reports/device data, and enforces Tool-only scope.
- **Safety and privacy:** Offline by default, networking and updates only with consent, elevation only when needed, and no telemetry or silent updates.

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
