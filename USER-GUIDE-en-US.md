# Configuration & License Assurance Tool User Guide

Developed by Thanh Viet
Applies to the v4.4 Enterprise line

This document explains how to use each function. Version-by-version changes are kept in the separate Versions & updates document.

## Scope and operating principles

- The tool inventories computers, evaluates Windows and Office, reviews installed software, detects KMS/activator indicators, and supports controlled backup and remediation.
- Functions 01–05, the inspection phase of 07, 09, and the reporting operations in 10 are read-only.
- A system-changing action requires Administrator rights, a preview, explicit selection, backup, and confirmation.
- The tool does not provide product keys, perform unauthorized activation, use public KMS services, or make an automatic legal licensing verdict.
- Full product keys, passwords, and sign-in data are not written to reports.
- Results are technical evidence for administrators. Entitlement must still be verified against Microsoft accounts, invoices, agreements, or volume-license records.

## Before you start

1. Download the official package from the project Releases page.
2. Extract the release to a fixed folder.
3. Do not rename, delete, or mix payload files from different versions.
4. Close Word, Excel, Outlook, and other Office applications before changing Office licensing.
5. Prepare a valid key or licensed account before using Function 06 or 08.
6. Run Tool-Kiem-Tra-v4.4.exe and approve UAC.
7. Select Vietnamese or English and the Light or Dark theme.
8. Keep Offline mode enabled for local work. Allow Function 8 networking only when LAN management is required.

If the EXE has no valid Authenticode signature, Windows reports NotSigned. Verify its SHA-256 against the checksum published with the exact release.

## Reading the dashboard

- The four top cards summarize Windows, Office, execution mode, and package integrity.
- The ten numbered tiles open the main functions.
- The status line reports start, completion, warnings, or failure.
- Recent activity shows timestamps, the current step, and the final outcome.
- The animated green bar means work is in progress; it is not a fabricated percentage.
- Human-readable HTML and PDF reports are saved directly to the Desktop.
- HTML opens in the default browser. JSON, XML, and CSV remain available for integration and verification.

## Function 01 – Full inspection

Use it when:

- Inventorying a new computer.
- Preparing a handover, upgrade, or license purchase.
- You need one consolidated report.

Steps:

1. Select 01 Full inspection.
2. Choose the privacy option shown by the tool. Use redacted output before sharing outside the responsible administration team.
3. Wait while hardware, Windows, Office, software, and relevant indicators are collected.
4. In the opened HTML, review the summary cards and then use the table of contents.
5. Keep HTML, PDF, JSON, XML, and SHA256SUMS together when archiving evidence.

Do not treat Completed as a legal license verdict. Read the assessment and verify entitlement records.

## Function 02 – Hardware configuration

Use it for device inventory, upgrade planning, and IT asset records.

Steps:

1. Select 02 Hardware configuration.
2. Choose whether identifying data should be redacted.
3. Wait for CPU, RAM, motherboard, BIOS/UEFI, disks, partitions, graphics, monitors, audio, networking, USB devices, and printers.
4. Review System compatibility if a data source is unsupported or unreadable.

Disk and memory numbers may differ from vendor labels because of unit conversion. TPM, Secure Boot, or BitLocker availability depends on Windows edition and firmware.

## Function 03 – Windows licensing

Use it to inspect activation state, edition, OEM/Retail/MAK/KMS channel, partial key, and KMS overrides.

Steps:

1. Select 03 Windows licensing.
2. Wait for SoftwareLicensingProduct, SoftwareLicensingService, and edition data.
3. Review activation state, channel, PartialProductKey, and any KMS server.
4. Compare the result with invoices, accounts, or agreements.

Licensed means Windows reports activation at scan time. Notification or Unlicensed does not by itself prove tampering. Volume_KMS is appropriate only inside an organization with an authorized KMS service.

## Function 04 – Microsoft Office licensing

Use it to inspect Office 2024, LTSC 2024, Microsoft 365 Apps, and other detected Office SKUs.

Steps:

1. Close all Office applications.
2. Select 04 Microsoft Office licensing.
3. The tool locates OSPP.VBS and runs /dstatusall for supported installations.
4. Review every SKU, activation state, last five key characters, channel, and KMS override.
5. For Microsoft 365, sign in with the licensed account in Office and verify entitlement there.

A computer can contain several Office SKUs. Do not rely on one combined status.

## Function 05 – Software and tampering indicators

Purpose:

- List installed software.
- Review autoruns, services, scheduled tasks, and activator/KMS/crack indicators.
- Add third-party software analysis without replacing the legacy report contract.

Steps:

1. Select 05 Software & tampering indicators.
2. Wait while 32-bit, 64-bit, and current-user installation areas are read.
3. Review the legacy installed-software, assessment, Startup, service, and task tables.
4. Review the appended third-party inspection.
5. For Review items, examine the reason, signature, publisher, source, path, and parallel versions.
6. Compare findings with the organization’s approved software inventory and entitlement records.

The function does not launch, uninstall, or delete discovered software. A suspicious name is only a signal, not an automatic violation verdict.

## Function 06 – KMS/Activator remediation

This function can change the system. Prepare valid licensing, close Office, and review every item.

The Function 06 menu provides:

1. Backup before action.
2. Inspect and remediate.
3. Restore from a verified backup.
4. Automatic safe cleanup for official-activation readiness.

Backup:

1. Select Backup before action.
2. A protected ProgramData backup is created.
3. Manifest, HMAC, and SHA-256 protect the backup.
4. Review the HTML report.
5. Do not move individual files out of the backup.

Inspect and remediate:

1. Select Inspect and remediate.
2. The first scan is read-only.
3. If WMI/CIM, licensing services, or Scheduled Tasks are unavailable, remediation is locked and Quick repair scan sources is offered.
4. Review each service, task, file, folder, Registry, Defender, or license candidate.
5. Every checkbox starts cleared.
6. Select only verified items.
7. Read the separate product-key warning; removing a selected key may not be automatically reversible.
8. Confirm the complete selection.
9. The tool creates a verified backup/quarantine before changing anything.
10. Only selected rows are processed.
11. A post-check opens the Result Center.

Result Center actions include processing remaining items, confirming an authorized internal KMS, rescanning, opening valid-license management, restoring backup, and opening the report.

Restore:

1. Select Restore.
2. Choose a backup_pre_cleanup or quarantine directory containing RESTORE-MANIFEST.json.
3. Location, ACL, manifest, HMAC, and hashes are verified.
4. Moved or modified backup data is rejected.
5. Review the restore report and rescan.

Automatic safe cleanup:

1. Select Automatic safe cleanup.
2. The tool performs a read-only scan and proposes only licensing Registry configuration covered by the restore allowlist, currently KMS overrides and the NoGenTicket policy.
3. Review the complete preview. Product keys, services, tasks, processes, files/folders, Defender exclusions, and Event Log history are never selected automatically.
4. Confirm to create an HMAC-protected backup, approve UAC, and process the proposed entries.
5. The tool runs a post-check and reports official-activation readiness only when no blocker remains.
6. Findings outside the automatic scope remain unchanged and can be reviewed manually.

The tool protects valid OEM/Retail/MAK licenses and approved internal KMS servers. It does not erase Event Logs or PowerShell history.

## Function 07 – Firmware OEM key

Purpose:

- Inspect the manufacturer’s OA3 OEM key in BIOS/UEFI.
- Apply it only after explicit confirmation.

Steps:

1. Select 07 Firmware OEM key.
2. Review the firmware, current edition, and activation report.
3. The full key is not displayed.
4. If a key exists, choose No for inspection only or Yes after confirming that the edition is compatible.
5. Review the HTML/PDF result.

The tool does not run /upk or /cpky before trying the OEM key. Windows rejects an incompatible edition/key pair.

## Function 08 – Valid license management

Function 08 always shows local management, server, and workstation modes.

Local management:

1. Open Local Windows/Office management.
2. Choose the intended Windows or Office task.
3. Enter only an official key supplied by Microsoft, an OEM, or an authorized organization.
4. Review confirmation before changepk.exe, DISM, slmgr.vbs, or OSPP.VBS is called.
5. For Microsoft 365, prefer licensed account sign-in.

Function 8 network switch:

- Networking is blocked by default.
- Select Allow networking for Function 8 only when LAN server/agent workflows are needed.
- Select Disable networking for Function 8 when finished.
- Disabling networking does not delete configuration, reports, or pairing data.

Server:

1. Enter a server name, an administrator code of at least eight characters, and a port; 49420 is the default.
2. Create server configuration.
3. Generate a temporary pairing code and transfer it through a protected internal channel.
4. Grant URL ACL and Firewall only on approved Domain/Private networks.
5. Leave CIDR empty for local detection or provide a specific CIDR/IP.
6. Quick scan discovers candidates; ping does not pair a device.

Workstation:

1. Enter the pairing code.
2. Auto-discover the server when the LAN has one server, or enter an IP/name.
3. Test the connection and pair.
4. Enable remote license-changing tasks only when organization policy permits.
5. Optionally schedule the agent; remove the schedule when the device leaves management.

Fleet export creates JSON, CSV, HTML, PDF, and SHA-256 on the Desktop without full product keys or pairing secrets.

## Function 09 – Advanced inspection

Two read-only modes are available:

- A – Seven-group deep inspection.
- B – Twelve-group forensics and risk scoring.

Steps:

1. Select 09 Advanced inspection.
2. Choose A for licensing, KMS, activator, key, folder, task, and Registry/hosts checks.
3. Choose B for additional signatures, SPP logs, Office, Defender/Firewall, Secure Boot, TPM, BitLocker, and previous-scan comparison.
4. Select redacted reporting before external sharing.
5. Review the conclusion and evidence.

Mode A creates HTML/PDF and a manifest. Mode B also creates JSON, CSV, and an evidence directory. The 0–100 risk score is a review priority, not a legal verdict.

## Function 10 – Assurance Center

Function 10 contains seven items:

1. Inspect Windows/Office digital certificates.
2. Evaluate plugins and extension rules.
3. Verify and export the license-change timeline.
4. Install a read-only JSON plugin.
5. Open the protected plugin directory.
6. Open the detailed HTML/PDF user guide.
7. Open version introduction and update history.

Certificate reports review Authenticode and local certificate chains. Plugin rules are declarative and cannot execute scripts, DLLs, commands, or URLs. Timeline export verifies DPAPI, HMAC-SHA256, and the hash chain.

The guide and version history:

- Open HTML immediately.
- Create and retain a PDF beside HTML on the Desktop.
- Use a stable version/language filename.
- Reuse a verified cache on later opens, avoiding duplicate exports.
- Keep user instructions separate from chronological release notes.

## Reports and storage

- Human-readable HTML and PDF are saved directly to the Desktop.
- HTML is the format opened after completion.
- JSON, XML, and CSV are for structured integration.
- SHA256SUMS detects later changes.
- Forensic evidence and protected backup data can remain in controlled subdirectories while presentation HTML/PDF stays on the Desktop.
- Reports contain embedded CSS and no remote fonts, scripts, or assets.
- PDF uses an installed Edge, Chrome, or Word engine. HTML remains complete when no PDF engine is available.

## Verify a downloaded file

Open PowerShell in the release folder:

```powershell
Get-FileHash .\Tool-Kiem-Tra-v4.4.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v4.4.exe
```

Compare the complete SHA-256 against the value published with the same release.

## Troubleshooting

Tool does not open:

1. Extract the package instead of running inside ZIP.
2. Keep all files from one version.
3. Verify PowerShell 3.0 or later.
4. Verify SHA-256.
5. Review AppLocker, WDAC, SmartScreen, and antivirus policy.

Layout is clipped or shows scrollbars:

1. Close old tool windows.
2. Run one matching version only.
3. Use the Windows-recommended display scaling.
4. Reopen the tool so layout is recalculated after DPI.
5. A low display may use vertical scrolling; horizontal scrolling should not be required.

PDF was not created:

1. Use the opened HTML.
2. Check Edge, Chrome, or Word.
3. Use Print and Microsoft Print to PDF if appropriate.
4. Do not upload sensitive reports to unknown conversion sites.

Function 06 reports insufficient scan data:

1. Use Quick repair scan sources.
2. Restart Windows if the source remains unavailable.
3. Run DISM /Online /Cleanup-Image /RestoreHealth.
4. Run sfc /scannow.
5. Restart and rescan.

Function 08 cannot find the server:

1. Allow Function 8 networking.
2. Verify two-way routing.
3. Verify the configured TCP port and Firewall.
4. Enter the server address across VLANs or when several servers exist.
5. Do not expose the port on Public profiles without approved policy.

## Final safety rules

- Scan first and select later.
- Do not select an unverified item.
- Do not bypass backup or integrity warnings.
- Do not use untrusted keys or KMS services.
- Review reports before sharing them.
- Do not treat one keyword or a risk score as proof of a violation.
- Keep checksums, reports, and purchase records together.
- Obtain legal entitlement confirmation from Microsoft or an authorized licensing provider when required.

## Official project and support

Project and releases:

https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen

Support:

- Zalo: 0978 005 017
- Email: thanhvietit.hopnghia@gmail.com
