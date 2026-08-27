# Safety Policy schema 1.0

Nguồn thực thi lõi là `Tool-SafetyPolicy.ps1`; các hợp đồng Enterprise, export, MDM và release còn được thực thi tại module/script tương ứng và verifier governance. Mọi quy tắc dưới đây là fail-closed; verifier phải thất bại nếu mã nghiệp vụ làm yếu quy tắc.

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

### Fleet export và CLI

- Fleet export mặc định `RedactSensitive=true`: thay ClientId/ComputerName bằng tham chiếu ổn định, che địa chỉ và last-5, bỏ danh sách địa chỉ mạng; không bao giờ xuất product key đầy đủ hoặc internal source path.
- Bỏ redaction chỉ được thực hiện bằng lựa chọn quản trị explicit trong môi trường kiểm soát. Dù vậy full key, password, pairing code và secret vẫn không được đưa vào output.
- Client filter, giới hạn tuổi và ngưỡng stale phải được ghi trong metadata để consumer biết phạm vi. Timestamp thiếu/sai được coi là stale, không được coi là current.
- CSV phải chống formula injection; HTML phải self-contained/offline-safe. Nếu format PDF được yêu cầu nhưng không tạo được file thì tác vụ phải thất bại, không trả `Success=true` giả.
- Publish dùng staging cục bộ và checksum; từ chối destination qua reparse point. Artifact dở dang không được chuyển thành thư mục export hoàn tất.
- CLI headless chỉ cho phép các action đã khai báo, trả JSON có `Success` và exit code phù hợp; lỗi không được đổi thành kết quả thành công. `ServerStatus` không trả dữ liệu nhạy cảm và `ClientSnapshot` không chứa full key.
- Chỉ fleet payload đã redact là ứng viên chia sẻ, sau khi người quản trị đọc lại. CLI stdout/control result có thể chứa path hoặc lỗi môi trường; bản không redact và stdout không phải public-safe theo mặc định.

### Intune/MDM

- Install/Repair production phải xác minh SHA-256 của source manifest từ kênh tin cậy; bypass nguồn chỉ dành cho thử nghiệm cô lập và phải explicit.
- Chỉ payload chương trình trong allowlist được cài. Source, target, staging và payload không được đi qua reparse point; mỗi file cài được ghi SHA-256 trong deployment manifest schema 1.0.
- Deployment package không mang pairing code, client/server secret, report hoặc network policy; cài đặt không tự mở port hay bật listener.
- Install/Repair phải hậu kiểm trạng thái. Detect được phép đối chiếu desired source manifest hash để bản cũ tự nhất quán vẫn bị đánh dấu cần nâng cấp.
- Uninstall chỉ xóa payload do manifest quản lý khi hash vẫn khớp; file đã bị quản trị viên sửa phải được giữ lại và báo trong `PreservedModifiedFiles`. Secret không bị xóa vì script này không cài hoặc quản lý secret.
- Deployment manifest/trạng thái có thể chứa path và trust metadata; chỉ dùng trong control plane MDM nội bộ, không công bố nguyên trạng như artifact public-safe.

### Bằng chứng VM public-safe

- Workflow công khai chỉ ghi tuple tên verifier/exit code/status; raw stdout/stderr không được đưa vào job log, record hoặc artifact của workflow này. Nếu tổ chức giữ raw output để điều tra, nó phải nằm ngoài public workflow và trong kho được bảo vệ riêng.
- Tóm tắt công khai chỉ giữ field allowlist: platform, danh tính/build Windows, PowerShell, commit, thời gian và tên/exit code/status của verifier; không mang `OutputTail`, raw stdout/stderr, path runner hay trường tùy ý.
- Ba platform phải khớp policy OS, chạy đủ danh sách verifier bắt buộc và cùng source commit. Thiếu platform, sai OS, khác commit hoặc test lỗi không được đổi thành `Passed`.
- Workflow/schema không tự chứng minh release đã đạt. Chỉ artifact của đúng release candidate mới là bằng chứng; `Missing` luôn khác `Passed`.

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
- Build stable bắt buộc `-RequireAuthenticode`; signer Authenticode của executable phải `Valid` và khớp signer được update manifest khai báo.
- Detached CMS của update manifest dùng trust anchor nội dung được client ghim riêng; không suy diễn signer CMS từ signer Authenticode. Rollover phải theo bản cập nhật bắc cầu, không thay đồng thời hai pin hoặc tắt xác minh.
- Build chưa ký chỉ được tạo bằng `-AllowUnsignedDevelopmentBuild`; manifest mang kênh `development`, `ReleaseStatus=DevelopmentUnsigned`, nhãn development và không đủ điều kiện phát hành.
- Release không được mô tả là đã ký nếu chưa có chứng thư thật và timestamp hợp lệ.
- Không tuyên bố CFG native cho launcher managed IL.
