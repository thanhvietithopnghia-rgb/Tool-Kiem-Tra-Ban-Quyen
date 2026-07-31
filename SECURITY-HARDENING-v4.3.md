# Security hardening baseline — Tool-Kiem-Tra v4.3

## Artefact và build

| Thuộc tính | Giá trị |
| --- | --- |
| EXE | `Tool-Kiem-Tra-v4.3.exe` |
| Runtime | .NET Framework 4 / CLR v4 |
| Kiến trúc | AnyCPU, không Prefer 32-bit |
| PowerShell | native x64/x86, `RemoteSigned` |
| UAC | `requireAdministrator` |
| PE | HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, TerminalServerAware |
| CFG | không tuyên bố cho managed IL |

## Secure launch

- Launcher lấy PowerShell từ System32 native, không dùng PATH.
- Payload nhúng được ghi vào session ProgramData v4.3.
- Mỗi payload được đối chiếu SHA-256.
- Root/session từ chối reparse point.
- ACL chỉ Administrators/SYSTEM.
- Schema version được truyền và đối chiếu fail-closed.
- Tiến trình 32-bit trên Windows 64-bit bị chặn để tránh WOW64 redirection.

## Offline và network

Offline toàn ứng dụng mặc định khi preference thiếu/lỗi. Launcher luôn cho phép mở Enterprise UI để Mục 8 giữ đủ ba chức năng. Server/agent dùng preference mạng riêng của Mục 8, mặc định tắt và độc lập với Offline toàn ứng dụng; UI gate từng thao tác LAN, còn launcher cùng script host/agent kiểm tra lại theo defense in depth. Người dùng có thể tắt lại công tắc mà không xóa cấu hình.

- không telemetry;
- không auto-update;
- không tải script/binary/rule;
- HTML/PDF không dùng remote asset;
- plugin không có URL hoặc command;
- network opt-in được audit.

## Dữ liệu

ProgramData v4.3:

- log JSONL;
- backup hash/HMAC/DPAPI;
- plugin JSON;
- timeline DPAPI/HMAC/hash chain;
- enterprise secret/config/queue/report.

Full product key bị loại khỏi log/report/timeline. Enterprise key chỉ nằm trong envelope mã hóa và audit chỉ lưu last-5.

## Backup/restore

- root cố định, canonical path check;
- ACL/reparse validation;
- machine binding;
- SHA-256 + HMAC;
- DPAPI LocalMachine;
- manifest ToolVersion 4.3;
- restore từ chối dữ liệu sai schema/hash/máy/root.

## Plugin threat model

Allowed:

- đọc Registry allowlist;
- kiểm tra file/version/Authenticode allowlist;
- đọc service state/start mode.

Denied:

- arbitrary PowerShell/code/command;
- network;
- external schema fields;
- path ngoài allowlist/reparse;
- cài vào thư mục không có protected ACL.

## Enterprise threat model

- LAN-only và Offline opt-in.
- Pairing code/admin verifier.
- AES-256-CBC + HMAC-SHA256 envelope.
- replay/age validation.
- client opt-in cho remote license changes.
- DPAPI LocalMachine cho secret/queue.
- endpoint cố định; không arbitrary execution.

HTTP transport không tự cung cấp TLS; bảo mật nội dung dựa trên envelope. Môi trường doanh nghiệp nên giới hạn firewall/VLAN và cân nhắc TLS/reverse proxy trong roadmap.

## Report hardening

- report envelope schema 1.5;
- HTML CSP `default-src 'none'`;
- no script/iframe/remote CSS/font/image;
- PDF browser flags tắt background networking/DNS;
- profile browser nằm ở LocalAppData, ACL user/SYSTEM và được dọn;
- SHA-256 manifest cho package.

## Authenticode

Build hỗ trợ chứng thư store hoặc PFX và timestamp. Khi dùng `-RequireAuthenticode`:

1. build yêu cầu signing credential;
2. `SIGN-RELEASE.ps1` ký SHA-256;
3. chữ ký phải `Valid`;
4. release verifier kiểm tra;
5. `VERIFY-AUTHENTICODE.ps1 -RequireTimestamp` xác minh timestamp.

Build phát triển chưa ký vẫn có thể tạo để test, nhưng không được mô tả là release đã ký.

## Lệnh kiểm tra

```powershell
.\BUILD.ps1 -OutputDirectory .\dist
.\VERIFY-RELEASE.ps1 -SourceDirectory . -DistributionDirectory .\dist
Get-FileHash .\dist\Tool-Kiem-Tra-v4.3.exe -Algorithm SHA256
Get-AuthenticodeSignature .\dist\Tool-Kiem-Tra-v4.3.exe
```

## Giới hạn

- Application Offline policy không thay firewall.
- Managed IL không có CFG/load-config native từ CSC; không gắn GUARD_CF giả.
- UAC/ACL/hash không vượt AppLocker, WDAC, SmartScreen hoặc antivirus.
- Chứng chỉ audit offline không bảo đảm trạng thái thu hồi trực tuyến.
- Kết luận license kỹ thuật không thay chứng từ pháp lý.
