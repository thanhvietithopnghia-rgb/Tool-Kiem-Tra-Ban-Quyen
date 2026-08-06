# User guide for Machine Configuration and Software Licensing Tool v4.6

Developed by Thanh Viet  
Applies to version 4.6.0.0 · Build 2026.08.06

This guide is for people running the tool on a Windows computer. It explains what changed in v4.6, how to start the executable, how to use every function, and how to interpret the results.

## What is new in v4.6

- Broader software inventory from installed-program records, Store applications, shortcuts, and common installation locations.
- A universal deep scan for every detected application rather than a small list of vendors. The scan examines multiple EXE/DLL files, digital signatures, activator traces, hosts entries, services, tasks, and correlated evidence.
- More conservative conclusions. Non-genuine or modified is used only for conclusive evidence or multiple independent strong evidence groups. Insufficient data remains Suspicious or Unverified.
- Remediation now covers Windows, Office, and other software with selectable scan scopes and individual item selection.
- Backup and restore scopes for All, Windows, Office, or Other software, with backup verification before a change is allowed.
- An optional, consent-based Online catalog update. The tool does not upload software inventory, paths, product keys, tokens, or reports.
- Improved Light/Dark interface, Vietnamese/English localization, DPI layout, Stop, Copy all log, and Open report folder controls.
- Improved HTML/PDF reports, scan-coverage warnings, time limits, and progress feedback.
- A smaller single executable while retaining the complete scan, remediation, and reporting feature set.
- Catalog `1.2.0.0` with 45 product rules, including 16 engineering groups covering CAD/CAE/BIM, simulation, structural tools, GIS, EDA, measurement, and rendering.
- A **Dry Run — no system changes** action that lists exact targets, actions, backup expectations, and restorability without creating a restore point or changing anything.
- A v4.6 writable-data root with schema 2.0. First launch can migrate legacy configuration, plugins, timeline, and Enterprise data through a SHA-256-verified staging copy; legacy data is retained and a failed migration rolls back.

## Scope and operating principles

- The tool inventories the computer, checks Windows and Office, reviews installed software, looks for KMS/activator/crack indicators, creates backups, restores safe data, and performs controlled remediation.
- Scan and report functions are read-only by default.
- A function that can change the computer shows the intended action, requires confirmation, creates a backup, and requests Administrator rights.
- The tool does not provide product keys, perform unauthorized activation, use public KMS servers, or remove software merely because its name looks suspicious.
- Full product keys, passwords, and sign-in data are not written to reports.
- Results are technical evidence for administration. Valid usage rights must still be confirmed against an account, invoice, contract, or vendor licensing record.

## Before you run the tool

1. If the tool arrived in a ZIP file, extract it first. Do not run it from inside the archive.
2. Place Tool-Kiem-Tra-v4.6.exe in a normal folder on a local drive.
3. Close Word, Excel, Outlook, and any application that may be remediated.
4. Prepare a valid account or product key if you expect to change licensing.
5. Ensure the system drive and Desktop have enough free space for backups and reports.
6. Keep Offline enabled unless you intentionally need a catalog update or authorized LAN management.

If Windows SmartScreen or security software displays a warning, continue only when the file came from a source you trust. On a managed computer, contact the administrator if AppLocker, WDAC, or another policy blocks the tool.

## How to run Tool-Kiem-Tra-v4.6.exe

1. Double-click Tool-Kiem-Tra-v4.6.exe.
2. Select Yes at the User Account Control prompt so the tool can read Registry, services, tasks, file signatures, and licensing state completely.
3. Wait for Control Center to appear. The first launch can take slightly longer while the protected runtime is prepared.
4. Select English or Vietnamese and Light or Dark mode in Settings if needed.
5. Keep the network switch set to Offline for local-only checks.
6. For the first review, select Check everything.
7. When asked about privacy, choose a redacted report if it will be shared outside the administration team.
8. Wait until the status says the task is complete. Do not close the tool while Activity shows a running task.
9. The HTML report opens in the default browser. Use Open report folder to locate it later.

You do not need to open source files, configuration files, or technical documentation to use the executable.

## Main screen

- The left navigation contains Overview, Scan, Remediation, Reports, and Settings.
- Four cards show Windows, Office, run mode, and tool integrity.
- Ten task tiles provide the main functions and can be filtered by category.
- Recent activity records the current step, warnings, and final result.
- Copy all log copies diagnostics for support.
- Open report folder opens the latest report location.
- Stop should be used only when a task is taking abnormally long. If remediation is interrupted, preserve the backup and rescan before continuing.
- Offline/Online only controls network permission. Switching Online does not upload data or automatically start a scan.

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

## Microsoft Office licensing

Use this function for Office 2021/2024, LTSC, Microsoft 365 Apps, and other detected Office SKUs.

1. Close all Office applications.
2. Select Microsoft Office licensing.
3. Wait for supported Office components and each SKU to be checked.
4. Review activation state, the last five key characters, channel, and KMS override.
5. For Microsoft 365, also verify the signed-in account inside an Office application.

A computer can contain multiple Office SKUs. Read every row rather than relying on one summary state. Full Office keys are not stored.

## Software & tampering indicators

This function uses the new v4.6 universal deep scan for all detected software.

1. Close the applications being reviewed.
2. Select Software and modification indicators.
3. Choose the report privacy level.
4. Wait for inventory and deep scanning to finish.
5. Find the application and read Status, Confidence, Evidence, Representative path, and Deep-scan coverage together.
6. Review correlated system traces such as hosts, firewall, service, task, autorun, IFEO, or artifacts.
7. Compare the technical result with the vendor account, invoice, and installation source.

v4.6 can inspect multiple important EXE/DLL files, Authenticode and HashMismatch results, known bad hashes, services, scheduled tasks, autoruns, hosts/firewall indicators, and bounded system locations.

Important interpretation rules:

- One unsigned file, unusual filename, or isolated keyword is not enough to conclude a crack.
- No crack evidence does not mean a genuine license was verified.
- Unverified is a neutral result, not an error or approval.
- Software & tampering indicators is read-only and does not remove or repair software.

## Windows, Office & software KMS/Activator remediation

This group can change the system. Use it only after reviewing evidence, closing affected applications, and preparing an official installer or valid license.

The menu contains four choices:

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

This screen offers two ways to proceed:

- **Dry Run — no system changes:** choose the scope and individual items normally, then review the exact file/Registry/service/task targets, intended actions, reasons, backup plan, and restorability. It scans and writes a report only; it does not create a restore point or backup, stop a process/service, delete a file, or edit system state.
- **Inspect and return to original state:** follows the real workflow below. Choosing **Execute for real** after a Dry Run always reopens item selection and requires confirmation again; a simulated plan is never executed automatically.

1. Select Inspect and return to original state.
2. Choose Scan all, Scan Windows and Office, or Scan other software.
3. Wait for the read-only scan to complete; no change occurs yet.
4. If WMI/CIM, licensing services, or Task Scheduler are incomplete, use Quick repair scan sources and scan again.
5. Review application name, item type, evidence, confidence, and action plan.
6. Every checkbox starts clear. Select only verified items; Select all includes only actionable rows.
7. Review any warning about a shared vendor scope.
8. Confirm the final list and approve UAC.
9. The tool creates and verifies a backup before processing only the checked rows.
10. Wait for post-check and use the next actions in Action Center.

On an unfamiliar computer or when impact is uncertain, run Dry Run first, retain its report, and review it before authorizing real execution.

Depending on evidence, a third-party plan can quarantine an exact artifact, restore an exact hosts entry, run a verified MSI Repair, reset a supported licensing component, or direct the user to an official reinstall. Uninstall/reinstall plans are never selected automatically.

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
5. Unverified items, valid keys, event history, and software requiring uninstall/reinstall remain for manual review.

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
6. Open this v4.6 guide as HTML/PDF.
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

The update is available in Windows, Office & software KMS/Activator remediation on the Inspect and return to original state screen.

1. Open Windows, Office & software KMS/Activator remediation.
2. Select Inspect and return to original state.
3. Select Online connection.
4. Read the privacy notice and consent if you want to continue.
5. Wait for completion, return, and select a scan scope.

This action downloads recognition rules only. It does not upload software inventory, paths, product keys, tokens, or reports. If it fails, continue Offline with the built-in catalog.

## Reports and saved files

- Reader-friendly HTML and PDF reports are saved on the Desktop.
- The tool opens HTML in the default browser after completion.
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
- Allow SmartScreen or antivirus only when the file source is known.
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

## Support

Zalo: 0978 005 017  
Email: thanhvietit.hopnghia@gmail.com

© 2026 Thanh Viet.
