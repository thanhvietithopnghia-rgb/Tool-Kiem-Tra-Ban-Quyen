# Computer Configuration and Software License Check Tool — Version History

This document summarizes the core changes in every main public release, from the first release to the current version.

Current release: **Tool Kiểm Tra v5.0**
Technical ProductVersion/FileVersion: `5.0.0.0` · Release date: `August 31, 2026` · Status: `ManagedSigned`

Stable latest-release page:
<https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

## Tool Kiểm Tra v5.0 — August 31, 2026

Tool Kiểm Tra v5.0 is the next upgrade after v4.9, focused on improving the core areas:

- **User experience:** faster startup, a clearer and more responsive interface, Light/Dark support, and direct navigation to the selected function.
- **Inspection and recognition:** Quick, Standard, and Deep levels; Windows, Microsoft Office, and other-software inspection; prioritized actions, search, filters, and comparison with the previous scan.
- **Safe remediation:** separate Windows, Office, and other-software scopes; mandatory preview, Dry Run, backup, confirmation, and post-check; an integrity-checked Backup and Restore Center.
- **Reports and support:** HTML, PDF, JSON, and XML reports; a redacted support bundle and multi-computer management support.
- **Privacy and integrity:** Offline by default with no automatic Internet upload; signature and SHA-256 checks before important operations.

`Unverified` does not mean that software violates its licence.

## v4.9.0.0 — August 22, 2026

- **More accurate recognition:** inventories Registry, AppX/MSIX, WinGet, shortcuts, package managers, and bounded portable locations; distinguishes confirmed installations from portable/residual files and merges duplicate records by product family.
- **Adaptive integrity scanning:** vendor host blocks or disabled licensing services trigger broader Authenticode checks within the exact product directory; evidence no longer leaks between products from the same vendor.
- **Diagnosable licensing and safe remediation:** unreadable data is distinct from unactivated status; reports are read-only; remediation removes only the selected bad key/Activation ID, preserves coexisting genuine licences, and verifies the exact selected scope afterward.
- **Controlled complete uninstall:** an application can be fully removed only after explicit selection and validation of a source-bound MSI/AppX identity; preview, backup, execution result, and absence post-check remain mandatory.
- **Protected release chain:** the EXE, provenance, catalog, and update manifest are signed; online comparison accepts declarative data only from pinned official sources and uploads no software inventory or device data.
- **Policy from v4.9:** the Tool remains free and community-oriented; source is no longer published free of charge, is not open source, and requires the author's prior written approval for access.

## v4.8.0.1 — August 18, 2026

- Separated Windows and Office activation states; incomplete or unreadable Office data is reported as **Unverified** and blocks automatic remediation.
- Made Office KMS restoration safer, preserving coexisting valid Retail/MAK/Subscription licensing without deleting Office accounts or tokens.
- Always shows the complete scanned-software list; only items backed by direct remediation evidence can be selected.
- Application updates verify version, SHA-256, signature, backup, and rollback; there are no silent updates or telemetry.

## v4.8.0.0 — August 10, 2026

- **Broad inventory and assessment:** expanded Windows, Office, third-party software, and hardware checks while separating licence model, technical state, and confidence.
- **Deep scan and signed catalog:** introduced multi-tier evidence and `Unverified` outcomes to avoid conclusions when data is incomplete.
- **Controlled remediation:** scope selection, preview, confirmation, backup, and post-verification are mandatory; weak evidence never removes software or changes the system automatically.
- **Usability:** completed the Dashboard, HTML/PDF reports, local Assistant, and server–workstation management while keeping Offline as the default.

## v4.6 — August 6, 2026

- Expanded the engineering-software catalog while retaining the vendor-neutral deep scanner for products without a dedicated rule.
- Added remediation **Dry Run**, listing the exact intended actions without changing the system.
- Made Online consent fail closed and reduced information exposed by the unauthenticated Enterprise status endpoint.
- Isolated writable versioned data and added staged migration, SHA-256 verification, rollback, and legacy-data preservation.
- Improved deep-scan performance, synchronized release metadata, and added data-lifecycle verification.

## v4.5 — August 6, 2026

- Completed the Light/Dark visual system, action icons, and DPI-aware layout; adopted the product name **Computer Configuration and Software License Check Tool**.
- Inventoried software from Registry, AppX/MSIX, Start Menu, Desktop, and bounded installed/portable locations.
- Added vendor-neutral deep scans, confidence tiers, and explicit reporting of incomplete coverage.
- Added explained, explicit-consent Online comparison without uploading application inventory, paths, keys, or tokens; Offline remained the default.
- Expanded scope selection, backup/restore, timeouts, heartbeat, and HTML/PDF reporting; automatic mode never uninstalls software.

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

- Added the internal-network licence center with Local, Server, and Workstation modes.
- Added pairing, inventory, offline queues, and authenticated/encrypted fleet reporting.
- Protected URL ACL/firewall configuration with confirmation and prevented competing servers in one scope.

## v4.1 — July 23, 2026

- Added the Report Center, certificate auditing, read-only declarative plugins, and licence timeline.
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

- Improved digital-licence, OEM, and Windows licensing-channel recognition.
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

There was no public v4.7 release; v4.8 was the direct public successor to v4.6.

Consistent safety principle: inspection is read-only by default; no telemetry; no unrequested licensing change; remediation requires selection, confirmation, backup, and post-verification.

A new history entry is added only when the official public release name or version number changes. Patches, technical updates, and internal builds within the same version stay in the release notes and do not create separate history entries.
