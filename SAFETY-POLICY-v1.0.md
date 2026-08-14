# Safety Policy schema 1.0

Nguồn thực thi: `Tool-SafetyPolicy.ps1`. Mọi quy tắc dưới đây là fail-closed; verifier phải thất bại nếu mã nghiệp vụ làm yếu quy tắc.

## Nguyên tắc

- Kiểm tra trước, thay đổi sau.
- Không coi dấu hiệu kỹ thuật là bằng chứng pháp lý.
- Không xóa hoặc sửa khi nguồn quét quan trọng lỗi.
- Không thay StartupType trong Quick Repair.
- Không tạo ticket/kích hoạt giả.
- Không chạy mã tùy ý từ plugin hoặc mạng.
- Không ghi full product key vào log/report/timeline.
- Offline là mặc định.

## Quy tắc cleanup

Danh sách xử lý mặc định không chọn. `cleanup.remediate`/`cleanup.deep` chỉ chạy khi:

1. secure launch và integrity hợp lệ;
2. có Administrator;
3. scan không có lỗi nguồn quan trọng;
4. người dùng chọn từng mục;
5. đã hiển thị tác động;
6. đã tạo backup hoặc người dùng xử lý rõ lỗi backup;
7. người dùng xác nhận cuối.

`NoGenTicket=true`: không tạo, cài hoặc sử dụng genuine ticket giả.

`AllowStartupTypeChange=false` cho Quick Repair: chỉ có thể khởi động tạm dịch vụ cần thiết, không đổi cấu hình start mode. Nếu hậu kiểm lỗi, rollback được áp dụng theo dữ liệu trước đó.

## Backup và restore

- Root cố định `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\backups`.
- Từ chối path ra ngoài root hoặc qua reparse point.
- Manifest schema 2.0, ToolVersion 4.3.
- SHA-256 cho nội dung; HMAC/DPAPI LocalMachine cho dữ liệu ràng buộc máy.
- Restore kiểm tra ACL, machine binding và hash trước mọi thay đổi.

## OEM và license manager

- Inspect là read-only.
- Apply/cài key/kích hoạt cần xác nhận và Administrator.
- Chỉ dùng API/công cụ Microsoft cục bộ (`SoftwareLicensingService`, `slmgr.vbs`, `OSPP.VBS`).
- Không tải key, script hoặc binary từ Internet.

## Plugin

Plugin chỉ là JSON khai báo với rule allowlist `RegistryValue`, `File`, `Service`.

- `ArbitraryCodeAllowed=false`;
- không PowerShell/script/command;
- không URL/network;
- từ chối property ngoài schema;
- chỉ cài vào vùng plugin có ACL bảo vệ.

## Enterprise

Mục 8 luôn mở và hiển thị đủ ba chức năng. Listener server, agent và các thao tác LAN bị chặn theo mặc định cho tới khi người dùng chủ động bật công tắc mạng riêng của Mục 8. Công tắc này độc lập với Offline toàn ứng dụng và có thể tắt lại; khi tắt, các tiến trình server/agent do cửa sổ khởi động được yêu cầu dừng nhưng cấu hình không bị xóa. Khi được cho phép:

- enroll cần pairing code;
- payload có AES-256-CBC và HMAC-SHA256;
- chống replay/giới hạn tuổi envelope;
- remote license changes mặc định tắt tại client;
- không nhận arbitrary command;
- secret bảo vệ bằng DPAPI LocalMachine;
- báo cáo/audit chỉ ghi last-5.

## Log và timeline

Log JSONL:

- một event/một dòng;
- giới hạn kích thước bản ghi;
- làm phẳng newline;
- correlation/module invocation ID;
- không secret/full key.

Timeline dùng DPAPI LocalMachine, HMAC-SHA256 và hash chain. Chuỗi hỏng bị từ chối nối thêm cho đến khi quản trị viên xử lý.

## Network policy

| Scope | Offline |
| --- | --- |
| Local file/Registry/CIM/WMI/process | Cho phép |
| Loopback | Chặn |
| LAN | Chặn |
| Internet | Chặn |

Cho phép mạng là opt-in từ dashboard, không phải trạng thái tự động.

## Release policy

- Không dùng `ExecutionPolicy Bypass`; tiến trình con dùng `RemoteSigned`.
- Build stable bắt buộc `-RequireAuthenticode`, ghim thumbprint trong manifest và thất bại nếu chữ ký không `Valid`.
- Build chưa ký chỉ được tạo bằng `-AllowUnsignedDevelopmentBuild`; manifest mang kênh `development` và không đủ điều kiện phát hành.
- Release không được mô tả là đã ký nếu chưa có chứng thư thật và timestamp hợp lệ.
- Không tuyên bố CFG native cho launcher managed IL.
