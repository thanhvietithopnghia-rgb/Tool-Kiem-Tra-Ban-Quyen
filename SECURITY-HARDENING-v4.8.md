# Security hardening baseline — Tool-Kiem-Tra v4.8

> Đây là baseline bảo mật lịch sử của v4.8. Không dùng tên EXE, ToolVersion hoặc lệnh xác minh v4.8 bên dưới cho build v5.0 R6; với bản hiện tại, dùng `Tool-Kiem-Tra-v5.0.exe` và đối chiếu `RELEASE-MANIFEST.json`, `OFFICIAL-PROVENANCE-v1.json` cùng `RELEASE-SHA256SUMS.txt` của release v5.0.0.0.

## Artefact và build

| Thuộc tính | Giá trị |
| --- | --- |
| EXE | `Tool-Kiem-Tra-v4.8.exe` |
| Runtime | .NET Framework 4 / CLR v4 |
| Kiến trúc | AnyCPU, không Prefer 32-bit |
| PowerShell | native x64/x86, `RemoteSigned` |
| UAC | `asInvoker`; elevation on demand for privileged modes/actions |
| PE | HIGH_ENTROPY_VA, ASLR, NX, NO_SEH, TerminalServerAware |
| CFG | không tuyên bố cho managed IL |

## Secure launch

- Launcher lấy PowerShell từ System32 native, không dùng PATH.
- Payload dashboard và log chỉ đọc/kiểm tra nằm trong vùng LocalAppData v4.6 của user hiện tại; mode nâng quyền, backup hệ thống và Enterprise dùng ProgramData v4.6. Log/backup v4.4/v4.5 không còn dùng chung để ghi.
- Payload được nén Deflate riêng từng tệp khi có lợi; tệp không giảm được dung lượng giữ nguyên raw. Đây chỉ là tối ưu đóng gói, không bỏ mô-đun hay giảm phạm vi quét.
- Mỗi payload được đối chiếu SHA-256.
- Root/session từ chối reparse point.
- LocalAppData runtime chỉ cấp quyền user hiện tại/Administrators/SYSTEM; ProgramData nâng quyền chỉ Administrators/SYSTEM.
- Schema version được truyền và đối chiếu fail-closed.
- Tiến trình 32-bit trên Windows 64-bit bị chặn để tránh WOW64 redirection.

## Offline và network

Offline toàn ứng dụng mặc định khi preference thiếu/lỗi. Launcher luôn cho phép mở Enterprise UI để Mục 8 giữ đủ ba chức năng. Server/agent dùng preference mạng riêng của Mục 8, mặc định tắt và độc lập với Offline toàn ứng dụng; UI gate từng thao tác LAN, còn launcher cùng script host/agent kiểm tra lại theo defense in depth. Người dùng có thể tắt lại công tắc mà không xóa cấu hình.

- không telemetry;
- không kiểm tra phiên bản hoặc tải cập nhật khi Offline; không service nền/silent update;
- chỉ tải catalog sau xác nhận riêng hoặc tải EXE khi người dùng chọn **Cập nhật ngay**;
- HTML/PDF không dùng remote asset;
- plugin không có URL hoặc command;
- network opt-in được audit.

Catalog phần mềm dùng đúng hai HTTPS GET tới host/path allowlist, không redirect, timeout và giới hạn 2 MiB; schema được xác minh trước khi ghi cache. GUI, worker và HTTP boundary trong module đều tự nạp/kiểm tra Offline policy, nên lời gọi trực tiếp không thể bypass Offline. Luồng này không có POST/PUT/PATCH và không gửi inventory, đường dẫn, product key, token hoặc bằng chứng cục bộ. Không truyền consent hoặc truyền `false` trả mã `2` trước khi nạp updater hay gọi mạng; wrapper chuyển đúng giá trị caller thay vì gán `true`.

Kho tri thức Trợ lý dùng hai HTTPS GET cố định cho JSON và chữ ký detached CMS. Chữ ký phải dùng SHA-256, đúng một signer RSA và khớp fingerprint SHA-256 của chứng thư nhà phát hành được ghim trong lõi; sau đó JSON còn phải qua giới hạn 2 MiB, UTF-8 nghiêm ngặt, schema, `Scope=Tool-Kiem-Tra`, dải Tool tương thích, kiểm tra nội dung an toàn và chống hạ `KnowledgeVersion`. Cache và chữ ký luôn đi theo cặp, giữ một cặp hợp lệ trước đó để rollback; cache không ký/sai chữ ký bị bỏ qua. Tệp `.p7s` không nhúng vào payload EXE và private key không nằm trong repository.

Trình cập nhật ứng dụng chỉ đọc manifest từ URL GitHub HTTPS cố định sau khi Online đã được cho phép. URL release/download phải thuộc đúng repository/tag; redirect asset chỉ tới host GitHub allowlist. EXE bị giới hạn 100 MiB và phải khớp kích thước/SHA-256, PE `MZ`, cùng signer Authenticode đã ghim nếu manifest yêu cầu. Apply xác minh launcher path/PID/hash, backup bản cũ, thay thế cùng thư mục và rollback nếu bản mới thoát sớm. Manifest không chứa lệnh hoặc script và không có cơ chế chạy nền.

Quy tắc tải online chỉ được dùng sau consent, từ URL HTTPS cố định, và phải qua signer CMS đã ghim, schema cùng chống rollback. Catalog cache đạt các điều kiện đó có thể đóng góp hash/tên activator mới; object raw, forged hoặc thiếu chữ ký không bao giờ tạo bằng chứng quyết định. Dù catalog nào được dùng, chỉ tổ hợp bằng chứng crack `Direct` có exact path/hash gắn đúng ứng dụng mới được phép cách ly. Mọi kho license Adobe/Autodesk/WinRAR được giữ nguyên; File artifact bị kiểm tra lại SHA-256/kích thước ngay trước khi cách ly, còn process/service/task/registry/folder chuyển sang hướng dẫn thủ công cho tới khi có identity revalidation. Quét sâu cũng loại root hệ thống quá rộng, reparse point và phần mở rộng tài liệu khỏi bằng chứng artifact quyết định.

## Dữ liệu

LocalAppData v4.6 (dashboard không nâng quyền):

- payload runtime đã xác minh;
- log và preference theo user.

ProgramData v4.6 (mode nâng quyền/máy):

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
- manifest ToolVersion 4.8; restore vẫn đọc tương thích backup 4.6/4.7;
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
- mọi package dùng chung `Desktop\BaoCao-Tool-Kiem-Tra`, tên tệp có timestamp mili-giây chống ghi đè và chỉ HTML được tự mở;
- HTML dùng liên kết tương đối tới PDF cùng tên và chỉ cho phép anchor HTTPS do renderer tạo để người dùng chủ động mở nguồn chính thức; anchor không tự tải nội dung khi in, còn remote image/CSS/SVG/form và href không tin cậy vẫn bị chặn. Phần mềm hệ thống nằm trong phụ lục, không bị loại khỏi JSON/PDF chi tiết;
- bảng rộng dùng overflow ngang trên màn hình, profile cột theo ngữ nghĩa và quy tắc co riêng khi in, tránh ép mất dữ liệu.

## Authenticode

Build hỗ trợ chứng thư store hoặc PFX và timestamp. Khi dùng `-RequireAuthenticode`:

1. build yêu cầu signing credential;
2. `SIGN-RELEASE.ps1` ký SHA-256;
3. chữ ký phải `Valid`;
4. release verifier kiểm tra;
5. `VERIFY-AUTHENTICODE.ps1 -RequireTimestamp` xác minh timestamp.

Build stable bắt buộc `-RequireAuthenticode`, ghim thumbprint signer vào manifest và từ chối nếu manifest Source/Release không giống hệt từng byte. Build phát triển chưa ký chỉ được tạo với `-AllowUnsignedDevelopmentBuild`, mang kênh `development` và không được phát hành. Một EXE tự giải nén payload PowerShell, chứa từ khóa KMS/activator và trình cập nhật có thể bị engine heuristic cảnh báo. Không coi cảnh báo là false positive chỉ dựa vào tên detection; phải xác minh nguồn GitHub chính thức, SHA-256, Authenticode, kết quả Defender và hành vi thực tế trước khi gửi mẫu cho hãng antivirus. Không hướng dẫn tắt Defender/SmartScreen hoặc thêm exclusion rộng.

## Lệnh kiểm tra

```powershell
.\BUILD.ps1 -OutputDirectory .\dist-development -AllowUnsignedDevelopmentBuild
.\VERIFY-RELEASE.ps1 -SourceDirectory . -DistributionDirectory .\dist
Get-FileHash .\dist\Tool-Kiem-Tra-v4.8.exe -Algorithm SHA256
Get-AuthenticodeSignature .\dist\Tool-Kiem-Tra-v4.8.exe
```

## Giới hạn

- Application Offline policy không thay firewall.
- Managed IL không có CFG/load-config native từ CSC; không gắn GUARD_CF giả.
- UAC theo nhu cầu/ACL/hash không vượt AppLocker, WDAC, SmartScreen hoặc antivirus.
- Chứng chỉ audit offline không bảo đảm trạng thái thu hồi trực tuyến.
- Kết luận license kỹ thuật không thay chứng từ pháp lý.
