# Tool Kiem Tra v5.0 — Version History

This document presents the current public line under one consistent product name: **Tool Kiem Tra v5.0**.

- Display name: **Tool Kiem Tra v5.0**
- Technical ProductVersion/FileVersion: `5.0.0.0`
- Current publication date: `2026-08-31`
- Channel: `ManagedSigned`; the launcher pins the exact release certificate
- Official download: https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v5.0.0.0

## Tool Kiem Tra v5.0

### Inventory and assessment

- Adds Quick, Standard, and Deep scan levels with explicit scope, time, and budget limits.
- Inventories Registry, AppX/MSIX, WinGet, shortcuts, package managers, and bounded portable locations while merging duplicate product-family records.
- Distinguishes confirmed installations, portable copies, residual files, system components, and evidence that is insufficient for a conclusion.
- Sorts applications requiring review by **High → Medium → Low**, then by name.
- Unverified paid, subscription, and trial software explicitly requires a licence check without being automatically labelled non-genuine.
- Windows App Runtime, codecs, platform extensions, VCLibs/UI.Xaml, installers, add-ins, runtime subfeatures, support packages, and driver uninstallers remain in inventory/reports but are omitted from the action list.

### Catalog and Online mode

- The bundled and Online catalog is `1.6.3.0` with 94 conservative product families.
- Broad catalog rules cannot reclassify a recognized support component as a user entitlement target.
- Online catalog downloads require explicit consent, a valid pinned CMS signature, the strict schema, and anti-downgrade checks.
- When the trusted local catalog is newer than the Online source, the Tool keeps the newer local catalog and continues the scan.

### Safe remediation

- Separates Windows, Microsoft Office, and other-software scopes.
- Requires preview, Dry Run, backup, confirmation, and post-verification.
- Only selected items with sufficiently strong evidence are eligible for action; weak or unverified evidence never triggers automatic system changes.
- `VerifiedClean` confirms that the selected trace was removed; it does not prove that a valid licence exists.

### Interface, reporting, and administration

- Provides a responsive high-DPI interface with system, Light, and Dark themes and unclipped Vietnamese/English content.
- Creates HTML, PDF, JSON, and XML reports locally; shared reports redact hardware identifiers by default.
- Supports timelines, signed declarative plugins, a headless CLI, Intune/MDM deployment, and managed fleet exports.
- User-facing titles consistently use **v5.0**; older identifiers remain internal only where required for data compatibility.

### Integrity and release model

- Signs and verifies the EXE, provenance, catalog, and update manifest.
- The launcher validates Authenticode, pinned signer SHA-1/SHA-256 values, BuildId, embedded payloads, and provenance before enabling system-changing actions.
- The current build uses a pinned self-signed certificate with a DigiCert timestamp. Windows may still show `Unknown publisher` or SmartScreen because this is not a public-CA identity.
- The technical version remains `5.0.0.0`; users with an older executable should download the latest v5.0 EXE and replace it manually.

## Microsoft Store note

A separate `StoreSubmission` candidate is under preparation and is not the public release. It binds trust to Microsoft Store package identity/origin and uses its own fail-closed elevation flow.
