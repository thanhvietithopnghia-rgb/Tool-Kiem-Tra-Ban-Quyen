# Security hardening baseline — Tool-Kiem-Tra v4.6

## Artefact và build

| Thuộc tính | Giá trị |
| --- | --- |
| EXE | `Tool-Kiem-Tra-v4.6.exe` |
| Runtime | .NET Framework 4 / CLR v4 |
| Kiến trúc | AnyCPU, không Prefer 32-bit |
| PowerShell | native x64/x86, `RemoteSigned` |
| UAC | `requireAdministrator` |
| PE | HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, TerminalServerAware |
| CFG | không tuyên bố cho managed IL |

## Secure launch

- Launcher lấy PowerShell từ System32 native, không dùng PATH.
- Payload nhúng và dữ liệu ghi nằm trong vùng ProgramData v4.6 riêng; log/backup v4.4/v4.5 không còn dùng chung để ghi.
- Payload được nén Deflate riêng từng tệp khi có lợi; tệp không giảm được dung lượng giữ nguyên raw. Đây chỉ là tối ưu đóng gói, không bỏ mô-đun hay giảm phạm vi quét.
- Mỗi payload được đối chiếu SHA-256.
- Root/session từ chối reparse point.
- ACL chỉ Administrators/SYSTEM.
- Schema version được truyền và đối chiếu fail-closed.
- Tiến trình 32-bit trên Windows 64-bit bị chặn để tránh WOW64 redirection.

## Offline và network

Offline toàn ứng dụng mặc định khi preference thiếu/lỗi. Launcher luôn cho phép mở Enterprise UI để Mục 8 giữ đủ ba chức năng. Server/agent dùng preference mạng riêng của Mục 8, mặc định tắt và độc lập với Offline toàn ứng dụng; UI gate từng thao tác LAN, còn launcher cùng script host/agent kiểm tra lại theo defense in depth. Người dùng có thể tắt lại công tắc mà không xóa cấu hình.

- không telemetry;
- không auto-update;
- không tải script/binary; chỉ tải catalog đối chiếu JSON sau khi người dùng bấm **Kết nối online** và xác nhận;
- HTML/PDF không dùng remote asset;
- plugin không có URL hoặc command;
- network opt-in được audit.

Catalog phần mềm dùng HTTPS GET, host allowlist, không redirect, timeout và giới hạn 2 MiB; schema được xác minh trước khi ghi cache. Luồng này không có POST/PUT/PATCH và không gửi inventory, đường dẫn, product key, token hoặc bằng chứng cục bộ. Không truyền consent hoặc truyền `false` trả mã `2` trước khi nạp updater hay gọi mạng; wrapper chuyển đúng giá trị caller thay vì gán `true`.

Quy tắc tải online chỉ được dùng để mở rộng nhận diện và tạo bằng chứng không quyết định. Hash/tên activator từ cache online chỉ có thể tự tạo kết luận `NonGenuine` khi SHA-256 của toàn catalog giống byte-for-byte catalog tích hợp đã phát hành; catalog khác biệt phải được review, đưa vào bản dựng và đi qua verifier trước. Quét sâu cũng loại root hệ thống quá rộng, reparse point và phần mở rộng tài liệu khỏi bằng chứng artifact quyết định.

## Dữ liệu

ProgramData v4.6 (vùng ghi hiện hành):

- log JSONL;
- backup hash/HMAC/DPAPI;
- plugin JSON;
- timeline DPAPI/HMAC/hash chain;
- enterprise secret/config/queue/report.

Full product key bị loại khỏi log/report/timeline. Enterprise key chỉ nằm trong envelope mã hóa và audit chỉ lưu last-5.

`data-state.json` ghi DataSchema 2.0 và ProducerVersion. Migration từ v4.4/v4.5 dùng staging GUID, đối chiếu danh sách/kích thước/SHA-256 rồi commit; lỗi commit khôi phục tệp bị ghi đè, xóa đúng mục mới và không ghi trạng thái hoàn tất. Dữ liệu cũ không bị sửa/xóa; log và backup cũ chỉ được tham chiếu đọc. Launcher kiểm tra mutex cũ trước migration, còn agent/audit dùng mutex v4.6 riêng.

## Backup/restore

- root cố định, canonical path check;
- ACL/reparse validation;
- machine binding;
- SHA-256 + HMAC;
- DPAPI LocalMachine;
- manifest ToolVersion 4.6;
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
- `GET /tool/v1/status` không xác thực chỉ trả `Accepted`, `ProtocolVersion`, `ToolVersion`; không trả Server ID/tên máy, IP, bind address, CIDR hoặc số client và vẫn chịu rate limit.

HTTP transport không tự cung cấp TLS; bảo mật nội dung dựa trên envelope. Môi trường doanh nghiệp nên giới hạn firewall/VLAN và cân nhắc TLS/reverse proxy trong roadmap.

## Dry Run threat model

- lập kế hoạch từ candidate đã chọn nhưng không gọi restore point, backup, service/process, Registry, file, MSI hoặc lệnh mạng;
- report đặt `SimulationOnly=true` và `NoSystemChangesApplied=true`;
- mỗi dòng công bố target, action, backup/restorability và yêu cầu quyền;
- chuyển sang thực hiện thật luôn mở lại chọn mục/xác nhận, không tái sử dụng kế hoạch như một lệnh tự động.

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
Get-FileHash .\dist\Tool-Kiem-Tra-v4.6.exe -Algorithm SHA256
Get-AuthenticodeSignature .\dist\Tool-Kiem-Tra-v4.6.exe
```

## Giới hạn

- Application Offline policy không thay firewall.
- Managed IL không có CFG/load-config native từ CSC; không gắn GUARD_CF giả.
- UAC/ACL/hash không vượt AppLocker, WDAC, SmartScreen hoặc antivirus.
- Chứng chỉ audit offline không bảo đảm trạng thái thu hồi trực tuyến.
- Kết luận license kỹ thuật không thay chứng từ pháp lý.
