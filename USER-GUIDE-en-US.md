# User guide for Machine Configuration and Software Licensing Tool

Developed by Thanh Viet

ManagedSigned version: **v5.0.0.0** · Build **2026.08.24**
Executable: `Tool-Kiem-Tra-v5.0.exe`
v5 ManagedSigned page: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v5.0.0.0>
Latest public Stable page: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

> `ManagedSigned` is for machines that received the administrator trust certificate. It is not public-CA Stable, and public self-update remains disabled.

This guide explains how to use the Tool's features on a Windows computer. Release-specific changes are documented separately in **Version History**; this guide focuses only on actions, result interpretation, and safe operating practices.

## Scope and operating principles

- The tool inventories the computer, checks Windows and Office, reviews installed software, looks for KMS/activator/crack indicators, creates backups, restores safe data, and performs controlled remediation.
- Scan and report functions are read-only by default.
- A function that can change the computer shows the intended action, requires confirmation, creates a backup, and requests Administrator rights.
- The tool does not provide product keys, perform unauthorized activation, use public KMS servers, or remove software merely because its name looks suspicious.
- Full product keys, passwords, and sign-in data are not written to reports.
- Results are technical evidence for administration. Valid usage rights must still be confirmed against an account, invoice, contract, or vendor licensing record.

## Before you run the tool

1. If the tool arrived in a ZIP file, extract it first. Do not run it from inside the archive.
2. Place the Tool executable in a normal folder on a local drive.
3. Close Word, Excel, Outlook, and any application that may be remediated.
4. Prepare a valid account or product key if you expect to change licensing.
5. Ensure the system drive and Desktop have enough free space for backups and report packages.
6. Keep Offline enabled unless you intentionally need a catalog update or authorized LAN management.

A Stable single-file EXE carries a trusted signature and provenance manifest for tamper detection. Verification does not remove every SmartScreen warning and cannot absolutely prevent copying or reverse engineering. Download Stable builds only from <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>, compare SHA-256, Build ID, signature, and provenance data, inspect the certificate with `Get-AuthenticodeSignature`, and scan with Microsoft Defender. Do not disable Defender or SmartScreen. On a managed computer, contact the administrator if AppLocker or WDAC blocks it.

## How to run the Tool

1. Double-click the Tool executable in the release folder.
2. The dashboard opens with the current user's rights and does not request UAC merely to view or scan. If you choose remediation, update, or enterprise administration, verify the named operation and approve UAC only when appropriate.
3. Wait for Control Center to appear. The first launch can take slightly longer while the protected per-user runtime is prepared.
4. Select English or Vietnamese and Light or Dark mode in Settings if needed.
5. Keep the network switch set to Offline for local-only checks.
6. For the first review, select Check everything.
7. Reports redact serial numbers, UUID, Processor ID, and Asset Tag by default. Select the full internal report only when necessary and restrict who receives it.
8. Wait until the status says the task is complete. Do not close the tool while Activity shows a running task.
9. The summary HTML opens in the default browser. Review the main results, then select **Open detailed PDF** inside the HTML for the complete report. Use Open report folder to locate the package later.

You do not need source access, configuration files, or technical documentation to use the executable.

## What v5.0 changes

- ManagedSigned uses a distinct state and enables approved system actions only when Authenticode, timestamp, provenance, and administrator trust all validate on the machine.
- Stable requires a CA-issued/HSM signing certificate, RFC3161 timestamp, valid CMS provenance, a clean source commit, and a fully passing verifier suite.
- Catalog freshness is explicit, and third-party plugins accept only signed declarative metadata from pinned publisher fingerprints.
- Quick, Standard, and Deep scans, system-aware dark/light themes, PerMonitorV2 DPI, and safe fleet exports support larger deployments.
- Remediation is split into Windows, Microsoft Office, and other software; each entry locks the scope from the initial scan through backup, confirmation, and post-check.

- The launcher and provenance manifest verify the signature, pinned certificate, metadata, and Build ID. A modified or unverifiable build is warned about and fails closed for updates and system-changing actions.
- The online catalog is signed, accepts only allowlisted declarative rules, maintains a persistent version floor to prevent downgrades, and retains a previous-cache fallback.
- Insufficient evidence remains **Unverified**; it is not automatically classified as a crack and is not eligible for automatic cleanup.
- Remediation reports **VerifiedClean** only after a new scan satisfies the rule's post-check. Retryable failures, organization policy, and repair/reinstall requirements are reported separately.
- No tool can identify or clean 100% of every product and variation. Preserve the system and review vendor evidence whenever results remain conflicting or incomplete.

## Main screen

- The left navigation contains Overview, Scan, Remediation, Reports, and Settings.
- Four cards show Windows, Office, run mode, and tool integrity.
- Ten task tiles provide the main functions and can be filtered by category.
- Recent activity records the current step, warnings, and final result.
- Copy all log copies diagnostics for support.
- Open report folder opens the latest report location.
- Stop should be used only when a task is taking abnormally long. If remediation is interrupted, preserve the backup and rescan before continuing.
- Offline/Online controls network permission for the current session only. Switching Online does not upload data or automatically start a scan; restarting always returns to Offline.
- **Tool Assistant** sits left of **About**. Enter a question and click **Send** or press **Enter**; use `Shift+Enter` for a new line. Input and Send are temporarily locked while an answer is processed. **Connect Online** grants network access only for the current session and automatically checks signed Tool knowledge; **Sync knowledge** can check again manually.

## Tool Assistant

Tool Assistant understands and answers every Tool-related question supported by available data; it is not limited to a fixed sample-question list. This includes product version, developer, build date, overview and principles; the purpose, use, output and safety notes of every feature; Windows/Office/software status; evidence, errors, reports, catalogs, updates, and Server/Workstation connectivity.

1. Select **Tool Assistant**.
2. Enter a question in the clearly outlined composer; select **Send** or press `Enter`. Use `Shift+Enter` for a new line.
3. Read questions and answers in separate colored message frames. New content scrolls into view and the answer appears in the current submission turn.
4. For a specific error or result, include the related error code, status, or evidence line. Follow-ups such as “how do I use it?”, “what about OEM key recovery?”, or “explain further” retain the immediately preceding Tool topic.

The Assistant combines structured knowledge, the bundled guide, and available report context. Routing prioritizes exact feature names, error codes, and specific phrases before general keywords; it handles natural wording, accent-free text, abbreviations, typing errors, and multi-part questions. A related question with insufficient data is identified as such; only genuinely unrelated content is marked out of scope, using wording adapted to the context instead of one repeated canned reply.

The Assistant remains available Offline on every device through bundled baseline knowledge and that device's own local report context. After explicit Online consent, the Tool downloads only `tool-assistant-knowledge-v1.1.json` and its detached CMS signature from two pinned GitHub paths. It verifies the publisher signature, SHA-256, schema, Tool-only scope, size, compatibility range, and downgrade protection before replacing a backed-up cache. Questions, reports, inventory, paths, keys, and tokens are never uploaded. Growing knowledge is stored under `%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\assistant`, outside the EXE; only this bounded 2 MiB local cache can grow.

## Recommended workflow

1. Run Check everything to create a baseline.
2. Review Windows, Office, Software, scan-source warnings, and coverage information.
3. If a paid application is Unverified, run Software and modification indicators or an advanced scan. Do not assume it is genuine or cracked.
4. Use the Online catalog update only when newer recognition rules are needed, then scan again.
5. Open Remediation only when the report provides evidence and a clear action plan.
6. Select the correct scope, review each item, create a backup, and check only verified items.
7. Reinstall, sign in, or activate from an official source after remediation.
8. Run Check everything again to retain a post-change report.

## Complete audit

Use this function for a new computer, a handover or upgrade review, or whenever one combined report is preferred.

1. Select Check everything.
2. Choose the report privacy level.
3. Wait while hardware, Windows, Office, software, and related indicators are collected.
4. Review the overview cards, then open each detailed section.
5. Read Scan source warnings and Incomplete coverage before making a decision.

The report includes hardware and operating-system data, Windows and Office licensing state, software inventory, KMS/activator indicators, services/tasks, and an overall technical assessment. Completed means the scan finished; it does not mean every license was verified.

## Hardware configuration

Use this function for asset inventory, upgrade planning, or checking TPM, Secure Boot, BIOS/UEFI, and security capabilities.

1. Select Hardware configuration.
2. Choose whether identifying data should be redacted.
3. Wait for CPU, memory, board, firmware, disks, graphics, displays, audio, network, USB, and printers to be read.
4. Review Compatibility in the HTML report if a source was unavailable.

Memory and disk capacity may differ from label values because of unit conversion. TPM, Secure Boot, and BitLocker can show Unsupported or Unavailable depending on Windows and firmware.

## Windows licensing

Use this function to check activation, edition, OEM/Retail/MAK/KMS channel, and KMS configuration.

1. Select Windows licensing.
2. Wait for the Windows licensing services to be queried.
3. Review activation state, channel, last five key characters, and KMS host if present.
4. Compare the result with the Microsoft account, invoice, or organization agreement.

- Licensed means Windows reported an active license at scan time.
- Notification or Unlicensed does not by itself prove a crack.
- OEM_DM may indicate a firmware key, but the installed edition must match.
- Retail or MAK still requires confirmation of the key source and usage rights.
- Volume_KMS is legitimate only for a device covered by an approved organization KMS environment.
- **Activated — entitlement not verified** means the technical activation state is active, but the tool has no account, invoice, or agreement evidence proving usage rights.
- **Unapproved KMS** means direct KMS configuration was found and the server is absent from the organization-provided approved list.
- **Unable to verify licensing** means a licensing source failed, evidence conflicts, or data is insufficient. It is neither genuine approval nor an automatic crack conclusion.

## Microsoft Office licensing

Use this function for Office 2021/2024, LTSC, Microsoft 365 Apps, and other detected Office SKUs.

1. Close all Office applications.
2. Select Microsoft Office licensing.
3. Wait for supported Office components and each SKU to be checked.
4. Review activation state, the last five key characters, channel, and KMS override.
5. For Microsoft 365, also verify the signed-in account inside an Office application.

A computer can contain multiple Office SKUs. Read every row rather than relying on one summary state. Full Office keys are not stored.

## Software & tampering indicators

This function uses the universal deep scan for all detected software.

1. Close the applications being reviewed.
2. Select Software and modification indicators.
3. Choose the report privacy level.
4. Wait for inventory and deep scanning to finish.
5. Find the application and read Status, Confidence, Evidence, Representative path, and Deep-scan coverage together.
6. Review correlated system traces such as hosts, firewall, service, task, autorun, IFEO, or artifacts.
7. Compare the technical result with the vendor account, invoice, and installation source.

The Tool can inspect multiple important EXE/DLL files, Authenticode and HashMismatch results, known bad hashes, services, scheduled tasks, autoruns, hosts/firewall indicators, and bounded system locations.

Important interpretation rules:

- One unsigned file, unusual filename, or isolated keyword is not enough to conclude a crack.
- No crack evidence does not mean a genuine license was verified.
- Unverified is a neutral result, not an error or approval.
- Software & tampering indicators is read-only and does not remove or repair software.

## Windows, Microsoft Office, and other-software remediation

This group can change the system. Use it only after reviewing evidence, closing affected applications, and preparing an official installer or valid license.

Under **Remediation**, choose **Remediate Windows**, **Remediate Microsoft Office**, or **Remediate other software**. That scope remains locked throughout the workflow. The combined tile on **Overview** still supports manual scope selection. Each entry contains four choices:

### Remediate Windows

Inspects and remediates only Windows KMS/Activator evidence, keys/Activation IDs, and licensing configuration. It does not widen into Office or other applications.

### Remediate Microsoft Office

Inspects and remediates only the selected Office SKU/Activation ID, preserves coexisting valid SKUs, and does not change Windows or other software.

### Remediate other software

Acts only on a strongly verified artifact or blocked hosts entry. It never uninstalls the application, resets a vendor licensing store, or widens into Windows/Office.

1. Backup before changes.
2. Inspect and return Windows, Office, or software to an original/unactivated state.
3. Restore automatically from backup.
4. Automatic safe cleanup, ready for legitimate activation.

### Choice 1 – Backup

1. Select Backup before changes.
2. Choose All, Windows, Office, or Other software.
3. Approve Administrator rights.
4. Wait for backup creation and integrity verification.
5. Record the backup path shown in Activity and the report.

The backup does not store complete keys or tokens and cannot be used to restore removed cracks or activators. Do not edit, rename, or move individual backup files.

### Choice 2 – Manual inspection and remediation

This screen offers three ways to proceed. A remediation sub-entry uses its locked scope without widening into another group; the combined Overview tile opens the Windows, Office, and Other software checkboxes:

- **Online:** after explicit consent, the Tool downloads the allowed comparison catalog and scans only the selected scopes; it does not upload the software inventory or machine data.
- **Dry Run — no system changes:** choose the scope and individual items normally, then review the exact file/Registry/service/task targets, intended actions, reasons, backup plan, and restorability. It scans and writes a report only; it does not create a restore point or backup, stop a process/service, delete a file, or edit system state.
- **Inspect and return to original state:** follows the real workflow below. Choosing **Execute for real** after a Dry Run always reopens item selection and requires confirmation again; a simulated plan is never executed automatically.

1. Select Inspect and return to original state.
2. Confirm the locked scope, or from the combined Overview tile select one or more scopes—Windows, Office, and Other software—then choose Continue.
3. Wait for the read-only scan to complete; no change occurs yet.
4. If WMI/CIM, licensing services, or Task Scheduler are incomplete, use Quick repair scan sources and scan again.
5. Review application name, item type, evidence, confidence, and action plan.
6. Every checkbox starts clear. Select only verified items; Select all includes only actionable rows.
7. Review any warning about a shared vendor scope.
8. Confirm the final list and approve UAC.
9. The tool creates and verifies a backup before processing only the checked rows.
10. Wait for post-check and use the next actions in Action Center.

“Ready for activation” means that no crack or unapproved-KMS evidence remains in the scanned scope; it does not mean licensed. After key entry, Windows returns `ActivationConfirmed = TRUE` only when the post-check reports `LicenseStatus=1` for that key, and Office only when the matching SKU/key reports `LICENSED`. Otherwise the result remains FALSE and the Tool opens the official Activation or sign-in/redeem path. For other software, use the vendor-source button; modified binaries may require an official Repair/reinstall first. The Tool preserves a currently valid genuine license and never simulates the “Activate Windows” watermark.

On an unfamiliar computer or when impact is uncertain, run Dry Run first, retain its report, and review it before authorizing real execution.

Depending on evidence, a third-party plan can quarantine an exact confirmed artifact or restore an exact blocked hosts entry. It never resets vendor licensing stores, runs MSI Repair, uninstalls an application, or automatically changes Firewall rules, processes, services, tasks, folders, or Registry entries. All other findings are preserved for manual review and may direct the user to an official repair or reinstall.

After post-verification or Recheck, the remediation list shows only current activator/tampering evidence. An application that is merely Unverified remains in the inventory report for manual review but is not treated as failed cleanup. A standalone activator file in Downloads, Desktop, or TEMP is quarantined only after its exact row is selected and confirmed; protected backup/quarantine paths are excluded from rescans.

### Choice 3 – Restore from backup

1. Select Restore automatically from backup.
2. Choose All, Windows, Office, or Other software.
3. Select the correct backup created on this computer.
4. Wait for verification and review the restorable-item preview.
5. Confirm, approve UAC, and scan again after restoration.

A backup from another computer, an edited backup, or incomplete data is rejected. Removed cracks, activators, invalid tokens, and uninstalled applications are not recreated.

### Choice 4 – Automatic safe cleanup

1. Select Automatic safe cleanup.
2. The tool scans everything and proposes only items with sufficient evidence and a tightly scoped safe plan.
3. Review and confirm the proposal.
4. The tool creates a backup, performs eligible actions, and runs a post-check.
5. Unverified items remain in the inventory report, while valid keys, event history, and software requiring uninstall/reinstall remain available for manual review; they are not re-added as active cleanup residue without current evidence.

No automatic-safe item is not an error. It means the remaining findings require review or do not have enough evidence for an automatic change.

## Restore the OEM key

1. Select Restore OEM key.
2. Wait for firmware, current edition, and activation state to be checked.
3. The full key is not displayed; only a masked value and last five characters are reported.
4. Select No for inspection only.
5. Select Yes only when the firmware key belongs to this computer and the edition is compatible.
6. Review the report and recheck Windows activation.

Do not use an OEM key from another computer or force an unsupported edition change.

## Manage valid licenses

This function includes Local Windows/Office management, Server, and Workstation.

For local management:

1. Select Manage legitimate licenses.
2. Open Local Windows/Office management.
3. Select the required Windows or Office operation.
4. Enter only a key issued by Microsoft, the manufacturer, or an authorized organization.
5. Read the confirmation before installing a key, changing edition, or activating.
6. For Microsoft 365, prefer signing in with an entitled account in Office.

For enterprise management, network access starts disabled. Enable Online only for authorized LAN use. The server creates enrollment data and receives approved workstation reports; a workstation enrolls with a temporary code. Remote license changes remain disabled until the workstation explicitly allows them. Only an authorized administrator should configure server, firewall, CIDR/IP, or remote license actions.

## Advanced inspection

Two read-only Administrator modes are available:

- Seven-group deep scan: Windows licensing, KMS, activators, keys, folders, tasks, and Registry/hosts.
- Twelve-group forensics and scoring: also reviews signatures, licensing logs, Office, Defender/Firewall, Secure Boot, TPM, BitLocker, and change comparison.

1. Select Advanced scan.
2. Choose the required mode.
3. Choose a redacted report if it will be shared.
4. Approve UAC and wait for completion.
5. Read Conclusion, Evidence, Risk score, and Next actions.

The 0–100 score prioritizes review. It is not a legal certification and does not replace the universal scan in Software & tampering indicators.

## Reports & assurance center

The center contains seven actions:

1. Audit Windows/Office digital certificates.
2. Evaluate plugins and extension rules.
3. Verify and export the licensing-change timeline.
4. Install a read-only JSON plugin from a file.
5. Open the protected plugin folder.
6. Open the user guide as HTML/PDF.
7. Open Version and updates.

A valid file signature does not by itself prove a valid license. Install plugins only from trusted sources. The timeline covers records created by this tool on this computer; it is not a replacement for purchase records or a SIEM.

## Software status meanings

- Free or validly bundled: identified as free, open-source, driver, runtime, or system software. This does not verify paid features in a freemium product.
- Verified genuine: a trusted licensing source confirmed entitlement. A valid digital signature alone is insufficient.
- Unactivated: a supported installed product has no active activation state.
- Non-genuine or modified: conclusive evidence or multiple independent strong evidence groups exist.
- Suspicious: notable evidence exists but is not enough for a stronger conclusion.
- Trial or not verified: the product may be a trial, or its licensing state could not be read.
- Unverified: there is insufficient evidence in either direction; it must not be treated as genuine by default.

HashMismatch, a known activator hash, or a replaced licensing module can be strong evidence. One unsigned file, unusual filename, hosts entry, or stopped service usually requires correlation with other evidence.

If Incomplete coverage is reported, check for missing Administrator rights, scan timeout, locked files, or failed WMI/Task Scheduler sources before evaluating the application.

## Online catalog update

The online catalog update is available under **Remediate other software** or the combined Overview remediation tile, on the Inspect and return to original state screen.

1. Open Remediate other software or the combined Overview remediation tile.
2. Select Inspect and return to original state.
3. Select Online connection.
4. Read the privacy notice and consent if you want to continue.
5. Wait for completion, then continue with the other-software scope.

This action downloads recognition rules only. It does not upload software inventory, paths, product keys, tokens, or reports. If it fails, continue Offline with the built-in catalog.

## Reports and saved files

- The only output directory is `Desktop\BaoCao-Tool-Kiem-Tra`; exports do not create per-scan subfolders.
- Related HTML, PDF, JSON/XML, and SHA-256 files share one base name with a millisecond timestamp and sit next to each other.
- The summary HTML, detailed PDF, JSON/XML, and SHA-256 files stay together in that shared folder.
- Only the summary HTML opens after completion. Select **Open detailed PDF** in the HTML to review all tables and evidence; PDF/JSON/XML do not open automatically.
- JSON, XML, and CSV are intended for integration, audit, and structured analysis.
- Use a redacted report for external sharing; keep a full report inside the administration team.
- A full report can contain computer name, user name, IP addresses, paths, and a KMS host, but not a complete product key.
- If the report is not visible, select Open report folder or read the path in Recent activity.

## Long-running tasks and Stop

Software inventory, signature checks, Office queries, WMI, and PDF generation can take time. Recent activity shows whether work is continuing. A slow-task warning does not itself indicate failure.

Use Stop only when necessary. If remediation was already running, some actions may have completed. Preserve the backup, reopen the tool, and run a read-only scan before continuing.

## Common problems

The EXE does not start:

- Extract it from the ZIP and run it from a local drive.
- Download again from `releases/latest`, verify SHA-256, and scan it with Defender. Do not add an exclusion or disable protection merely to force execution.
- Contact the administrator if a managed-device policy blocks it.

An application is missing:

- Run again as Administrator.
- Confirm that the application has an install record, shortcut, or is in a common portable location.
- Start the application once, close it, and scan again if its path was not registered.

Adobe, Camtasia, Premiere, or another paid product is Unverified:

- This is neither genuine approval nor a crack conclusion.
- Review deep-scan coverage, evidence, and scan-source warnings.
- Update the catalog if needed, scan again, and compare with the vendor account or invoice.

Scan sources are incomplete:

- Use Quick repair scan sources in Windows, Office & software KMS/Activator remediation and scan again.
- Changes remain blocked while an important source is unavailable.

Backup is rejected:

- Select a backup created on the current computer.
- Do not edit, rename, or move individual backup contents.
- Run as Administrator.

Online update fails:

- Continue Offline.
- Check Internet access, DNS, proxy, firewall, and system time before retrying.

PDF is not created:

- Use the HTML report; the scan result remains available.
- Check Microsoft Edge or Google Chrome and use Open report folder.

The task appears stuck:

- Read Recent activity to identify the current step.
- Allow more time for signature or Office scanning on a large computer.
- If it no longer responds, use Stop, preserve any backup, reopen the tool, and scan again.

## Final safety rules

- Inspect first, remediate second.
- Do not act on a filename or keyword alone; read evidence and path information.
- Do not select every item mechanically on a production computer.
- Do not remove a key before a valid replacement is available.
- Do not manually edit backups or evidence reports.
- After a change, always run a post-check and reinstall or activate through an official source.
- If the result remains Unverified, leave it unchanged and confirm with the vendor instead of forcing a conclusion.

## Source and use policy from v4.9

The official executable remains free of charge for the community under its accompanying terms. The project welcomes bug reports, proposals, documentation, translations, testing, and technical contributions. Starting with v4.9, source code is no longer published free of charge, is not released under an open-source licence, and is managed by the author through controlled access. This policy protects origin after observed near-verbatim copying and rebranding of the Tool's content, interface, descriptions, and development work without permission or attribution. It does not claim that backend or source code was taken where technical evidence has not established that.

Anyone wishing to review, study, research, security-test, or contribute to the source must first request and receive the author's written approval. Viewing does not itself permit copying, disclosure, modification, repackaging, commercialization, training-data use, rebranding, or removal of attribution. The policy applies from v4.9 onward and does not retroactively alter the terms of older versions. See `SOURCE-POLICY-v4.9.md` and `LICENSE-NOTICE.txt` in the official repository.

## Support

Zalo: 0978 005 017  
Email: thanhvietit.hopnghia@gmail.com

© 2026 Thanh Viet.
