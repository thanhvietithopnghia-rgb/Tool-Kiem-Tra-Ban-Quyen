# Tool Kiểm Tra v5.0.0.0 — Bản cập nhật R10

Build date: 2026-08-26
Published revision: 2026-08-31 (R10 catalog and Online update)

## Cập nhật R10

- Giữ nguyên ProductVersion/FileVersion `5.0.0.0` và tag `v5.0.0.0`.
- Đồng bộ catalog tích hợp và catalog Online lên `1.6.1.0`, gồm 93 nhóm sản phẩm.
- Bổ sung nhận diện driver máy in Canon LBP/CAPT.
- Catalog Online thấp hơn catalog đang dùng không còn làm tác vụ cập nhật thất bại: Tool giữ bản mới hơn, không hạ cấp và tiếp tục quét.
- Bản phát hành dùng trạng thái `ManagedSigned`, không còn bị khóa như build thử nghiệm `DevelopmentUnsigned`.
- Online vẫn cần người dùng cho phép, chỉ tải catalog/chữ ký từ URL HTTPS trong allowlist và không tải inventory, khóa bản quyền hoặc báo cáo lên mạng.
- Người đang dùng R9 hoặc bản cũ hơn cần tải lại EXE vì các revision cùng mang số phiên bản `5.0.0.0`.

## Cập nhật R9

- Cho phép chọn phần mềm trả phí, thuê bao, dùng thử, nghi ngờ hoặc chưa rõ để tiếp tục xử lý.
- Không còn khóa ô chọn chỉ vì Tool nhận diện phần mềm là trả phí hoặc chưa chắc chắn.
- Mục có dấu vết cụ thể chỉ xử lý đúng dấu vết đã phát hiện và vẫn yêu cầu xác nhận.
- Mục chưa có dấu vết cụ thể chỉ đưa ra bước kiểm tra, sửa hoặc cài lại từ nguồn chính thức; không tự ý xóa dữ liệu.
- Sửa cách gộp phần mềm trùng nhau và giảm trường hợp nhận diện sai do dữ liệu quét chung.
- Người đang dùng R8 cần tải lại EXE vì R8 và R9 cùng mang số phiên bản `5.0.0.0`.

## R8 portability hotfix

- Fixes `Authenticode=0x800B0109` on a new PC that does not already trust the self-signed certificate.
- Accepts only `CERT_E_UNTRUSTEDROOT` for the exact self-signed publisher pinned by both SHA-1 and SHA-256.
- A changed executable still returns `TRUST_E_BAD_DIGEST`/`HashMismatch`; a different signer, certificate, or trust error remains blocked.
- Keeps the RFC 3161 timestamp, signed provenance, embedded-payload hash checks, protected UAC bridge, and system-change fail-closed controls.
- Shows the child-process exit code when PowerShell or a required component prevents the interface from opening, instead of closing without a useful diagnostic.
- R7 users must download and replace the EXE manually because R7 and R8 share file version `5.0.0.0` and the ManagedSigned channel keeps public self-update disabled.
- Windows Defender SmartScreen may still require the user to review an `Unknown publisher` warning because no public-CA certificate is used.

Store preparation note (2026-08-29): a separate `StoreSubmission` candidate is under development and is not released. Its inner EXE is unsigned before Partner Center, trust is bound to the exact Store origin/package identity, and every elevated module is re-dispatched by the compiled launcher into an Administrator-only, hash-verified payload directory. Store certification, three-VM evidence, and independent review remain open gates.

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
- Unsigned development builds remain a separate mode and keep self-update plus every system-changing action blocked.

## Public Stable Gates Still Required

- Acquire and protect a CA-issued code-signing certificate through an HSM, token, or managed signing service.
- Keep RFC3161 signing on the verified DigiCert HTTP endpoint while the local HTTPS route remains blocked.
- Complete the Windows 10/11 client VM matrix and independent security review evidence.
- Commit the final source snapshot, update and sign provenance, then run the complete Stable build and verifier chain.

Do not represent a `ManagedSigned` artifact as public-CA Stable.
