# Kiến trúc kỹ thuật Tool-Kiem-Tra v4.6

Tài liệu này mô tả kiến trúc phát hành `4.6.0.0`, dashboard schema `2.0` và các ranh giới an toàn của bản một tệp. Mã nguồn PowerShell tương ứng là nguồn sự thật; tài liệu không thay thế verifier.

## Mục tiêu kiến trúc

- Một EXE AnyCPU tự chọn Windows PowerShell native x64/x86.
- Hoạt động cục bộ hoàn toàn khi Offline đang bật; không telemetry và không kiểm tra cập nhật ngầm.
- Dashboard WinForms hiện đại nhưng vẫn giữ .NET Framework 4/Windows PowerShell 3+.
- Mọi chức năng chạy qua module contract, capability gate và structured log.
- Báo cáo HTML/PDF/JSON/XML dùng chung report envelope, không tải asset từ Internet.
- Dữ liệu có thể thay đổi hệ thống nằm trong vùng ProgramData có ACL Administrators/SYSTEM.

## Sơ đồ thành phần

```text
Tool-Kiem-Tra-v4.6.exe
  ├─ kiểm tra OS/kiến trúc, UAC, mutex và offline preference
  ├─ giải nén 45 payload vào session được bảo vệ
  ├─ đối chiếu TOOL-SHA256SUMS.txt
  └─ chạy Windows PowerShell native với schema/environment cố định
       ├─ Giao-Dien.ps1                    dashboard schema 2.0
       ├─ Tool-DataLifecycle.ps1           data schema 2.0 + migration transaction
       ├─ Tool-Capabilities.ps1            capability schema 1.1
       │   └─ Tool-Compatibility.ps1       catalog schema 1.0
       ├─ Tool-Localization.ps1            localization schema 1.0
       ├─ Tool-OfflinePolicy.ps1           offline policy schema 1.0
       ├─ Tool-SoftwareInventory.ps1       inventory/deep scan schema 1.0
       │   └─ software-license-catalog-v1.0.json  catalog 1.2
       ├─ Tool-ModuleContract.ps1          contract/result schema 1.0
       ├─ Tool-ReportSchema.ps1            report schema 1.5
       │   └─ Tool-ReportExport.ps1        export schema 1.2
       ├─ Tool-SafetyPolicy.ps1            safety schema 1.0
       └─ các entry point nghiệp vụ
```

## Lớp launcher

`Tool-Kiem-Tra-v4.6-OneFile.cs`:

1. yêu cầu Administrator qua application manifest;
2. từ chối Windows cũ hơn Windows 7 SP1;
3. dùng `Environment.SpecialFolder.System` để lấy PowerShell native, không tìm `powershell.exe` qua `PATH`;
4. dùng vùng ghi `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6`; vùng v4.4/v4.5 chỉ là nguồn migration hoặc tham chiếu log/backup đọc;
5. từ chối reparse point và ACL ngoài Administrators/SYSTEM;
6. giải nén payload, tính SHA-256 và so với manifest nhúng;
7. truyền phiên bản schema, correlation ID, đường dẫn log/plugin/timeline và trạng thái Offline qua environment;
8. dọn session tạm sau khi tiến trình con kết thúc.

Launcher có sáu mode được công bố trong `ENTRY-POINTS-v4.6.md`. `--enterprise-ui` luôn được phép mở để Mục 8 giữ đủ ba chức năng. Các tiến trình mạng `--enterprise-server`, `--enterprise-agent` và `--enterprise-agent-force` chỉ chạy khi công tắc mạng riêng của Mục 8 đang bật.

## Vòng đời dữ liệu v4.6

`Tool-DataLifecycle.ps1` tạo `data-state.json` với `DataSchemaVersion=2.0`, `ProducerVersion=4.6.0.0`, storage generation và kết quả migration. Launcher truyền vùng v4.6/v4.4 cùng schema qua environment; dashboard fail-closed khi schema không khớp.

Migration chỉ chạy khi chưa có state:

1. giữ global migration mutex và từ chối root/reparse point không an toàn;
2. sao chép cấu hình KMS, network preference, plugin, timeline và Enterprise sang staging GUID trong root v4.6;
3. đối chiếu danh sách tệp, kích thước và SHA-256 với nguồn;
4. commit từng mục, ưu tiên cấu hình KMS cũ của người dùng nhưng không ghi đè plugin tích hợp mới;
5. nếu commit lỗi, khôi phục tệp bị ghi đè, xóa đúng tệp/thư mục mới và không tạo state hoàn tất;
6. giữ nguyên toàn bộ vùng cũ; `logs`/`backups` cũ chỉ được công bố dưới `LegacyReadOnlyRoots`.

Launcher v4.6 kiểm tra mutex launcher v4.4/v4.5 trước migration. Enterprise agent/audit dùng mutex v4.6 riêng. Các chuỗi `v4.4` còn lại trong timeline/Enterprise là nhãn mật mã tương thích, không phải đường dẫn ghi.

## Dashboard và UI

v4.3 chọn **Modern WinForms** thay vì WPF/WebView2 để không kéo thêm runtime hoặc tài nguyên web:

- font Segoe UI, dashboard card, tile hai dòng, hover state và bo góc;
- biểu tượng Windows/Office/bảo mật/tác vụ được vẽ vector bằng `System.Drawing` ngay trong tiến trình, không phụ thuộc asset mạng;
- layout hai cột tự co theo DPI/WorkingArea, có AutoScroll cho màn hình thấp;
- dark mode dùng palette chung trong `Tool-UiTheme.ps1` và được truyền sang cửa sổ con;
- thẻ trạng thái Windows release, Office family/channel, chế độ chạy và integrity;
- chọn `vi-VN`/`en-US` trực tiếp, lưu theo người dùng và truyền sang Mục 8 cùng trình quản lý cục bộ;
- nút Offline toàn ứng dụng luôn hiện rõ trạng thái;
- Mục 8 có công tắc mạng riêng bật/tắt được, fail-closed và không ẩn ba chức năng.

Không có WebView, JavaScript, CDN, web font hoặc ảnh từ xa trong dashboard.

## Capability và compatibility

`Tool-Capabilities.ps1` không suy diễn hỗ trợ chỉ từ số phiên bản OS. Nó kết hợp:

- kiến trúc OS/tiến trình;
- CIM hoặc WMI fallback;
- ScheduledTasks module hoặc `schtasks.exe` fallback;
- đường dẫn native tới `cscript.exe`, `sfc.exe`, `reg.exe` và các công cụ hệ thống;
- `CurrentBuild`, `UBR`, `DisplayVersion`;
- Office Click-to-Run `ProductReleaseIds`, channel GUID và `ClientVersionToReport`;
- catalog cục bộ `compatibility-catalog-v1.0.json` schema 1.1 với nhóm Office điều khiển bằng dữ liệu.

Build/revision mới hơn catalog được trả về `AheadOfCatalog`/`FutureReleaseUnverified` và `ReadOnlyManualReview`, không tự nhận là đã xác minh. Dashboard cảnh báo từ `ReviewWarningAgeDays`; quá `MaximumReviewAgeDays` thì tác vụ nhạy phiên bản chuyển sang chỉ đọc và verifier phát hành thất bại.

## Quét sâu phần mềm phổ quát

`Tool-SoftwareInventory.ps1` dùng cùng một pipeline cho mọi hãng và chỉ bổ sung quy tắc đặc hiệu khi catalog có dữ liệu:

1. tạo tối đa hai root an toàn, riêng cho ứng dụng; loại ổ đĩa gốc, `Windows`, `Program Files`, `ProgramData`, profile/AppData gốc và reparse point;
2. duyệt breadth-first có giới hạn thời gian, độ sâu, entry và số tệp; cache snapshot theo root để các bản ghi trùng ứng dụng không quét lại;
3. ưu tiên executable/DLL quan trọng, tệp cấp phép, artifact và EXE tầng nông; phân phối ngân sách Authenticode có trọng số cao hơn cho phần mềm trả phí/dùng thử/có dấu vết nhưng vẫn dự trù lượt cho nhóm chưa biết và miễn phí;
4. chỉ tính SHA-256 khi catalog cung cấp hash xấu, cache theo đường dẫn/kích thước/mtime và chỉ cho hash từ catalog tích hợp hoặc bản cache giống byte-for-byte tạo bằng chứng quyết định;
5. tương quan IFEO, outbound firewall block, dịch vụ cấp phép Disabled, autorun, task/service/process/folder và hosts với đúng application ID hoặc phạm vi hãng thực;
6. gom bằng chứng theo `Conclusive`, `Strong`, `Moderate`, `Weak` và nhóm độc lập. `NonGenuine` cần bằng chứng quyết định hoặc ít nhất hai nhóm mạnh độc lập; một dấu hiệu không đủ chỉ là `Suspicious`.

Metadata báo cáo ghi Administrator, Complete, số ứng dụng/root/tệp, chữ ký/hash, timeout, giới hạn và cảnh báo truy cập. Không có bằng chứng hoặc độ phủ chưa hoàn tất luôn giữ `Unverified`; pipeline không xác minh quyền sở hữu pháp lý từ tài khoản/hóa đơn của nhà sản xuất.

Catalog phần mềm `1.2.0.0` có 45 quy tắc, trong đó 16 quy tắc có `Category` cho CAD/CAE/BIM, mô phỏng, kết cấu, GIS, EDA, đo lường và rendering. Quy tắc mới chỉ tăng độ chính xác nhận diện/signature/domain/artifact; scoring fail-closed vẫn áp dụng như mọi phần mềm khác.

## Dry Run khắc phục

`Get-DryRunRemediationPlan` biến đúng các candidate đã chọn thành danh sách máy đọc được: target, action code, yêu cầu Administrator, backup dự kiến, `Restorable` và `ChangesSystem`. Nhánh Dry Run nằm trước `Checkpoint-Computer`, `Invoke-DeepCleanupV35` và `Invoke-Remediation`; nó chỉ quét lại, ghi decision/report và trả `NoSystemChangesApplied=true`. Nút **Execute for real** mở lại danh sách với ID gợi ý và bắt buộc xác nhận lần nữa.

## Offline policy

`Tool-OfflinePolicy.ps1` fail-closed:

- không có preference hoặc preference lỗi → Offline;
- chặn scope `Internet`, `Lan` và `Loopback`;
- Enterprise UI vẫn khởi động và luôn hiển thị đủ Quản lý cục bộ, Máy chủ, Máy trạm;
- trạng thái mạng riêng của Mục 8 mặc định tắt và được lưu độc lập với Offline toàn ứng dụng;
- server/agent và từng thao tác LAN bị chặn cho tới khi người dùng bật công tắc Mục 8;
- người dùng có thể tắt lại công tắc; server/agent do cửa sổ khởi động được yêu cầu dừng nhưng cấu hình không bị xóa;
- liên kết web trong dashboard không được mở;
- không telemetry, không tự kiểm tra bản mới;
- báo cáo chỉ dùng dữ liệu và asset cục bộ.

Việc tắt Offline toàn ứng dụng hoặc bật mạng riêng cho Mục 8 đều là lựa chọn chủ động. Hai trạng thái không tự thay đổi lẫn nhau. Đây là policy của ứng dụng, không phải firewall cấp hệ điều hành.

## Module contract

Mỗi descriptor gồm:

- định danh: `ModuleId`, `Category`, `DisplayName`;
- entry point: `ScriptFile`, `Operation`, `TaskKind`, `IsEntryPoint`;
- quyền: `AccessMode`, `RequiresElevation`;
- mạng: `NetworkScope`, `OfflineCapable`;
- điều kiện: `RequiredCapabilities`;
- ánh xạ `ExitCodeMap`.

`NetworkScope=LocalOnly` là offline-capable. `license.manager` chỉ mở giao diện chứa đủ ba chức năng nên là `LocalOnly`; `enterprise.server` và `enterprise.agent` khai báo `Lan`. Chỉ `software.catalog.update` khai báo `Internet`; nó cần consent riêng, chỉ dùng HTTPS GET tới host allowlist và không thay đổi preference Offline.

## Báo cáo

Luồng báo cáo:

```text
module data
  → New-ToolReportEnvelope (schema 1.5)
  → schema validation
  → HTML + JSON + XML
  → offline HTML safety validation
  → PDF từ chính HTML (Edge → Chrome → Word)
  → SHA-256 manifest
```

HTML có CSP `default-src 'none'`, CSS nhúng, layout responsive, dark-mode preview và stylesheet A4. HTML/PDF dành cho người đọc được lưu trực tiếp trên Desktop và HTML là định dạng tự mở mặc định. CSS in cho phép ngắt trang an toàn trong section, giữ tiêu đề bảng và tránh cắt hàng. Edge/Chrome được chạy với background networking bị tắt và host resolver map về `0.0.0.0`. Nếu không có PDF engine, các định dạng còn lại vẫn hợp lệ.

## Dữ liệu và ranh giới tin cậy

| Vùng | Dữ liệu | Quyền ghi |
| --- | --- | --- |
| Session trong ProgramData v4.6 | payload đã xác minh | Administrators/SYSTEM |
| `logs` | JSONL theo ngày | Administrators/SYSTEM |
| `backups` | backup + hash/HMAC/DPAPI | Administrators/SYSTEM |
| `plugins` | plugin JSON khai báo | Administrators/SYSTEM |
| `timeline` | JSONL + HMAC/hash chain | Administrators/SYSTEM |
| `enterprise` | config, secret DPAPI, queue, report | Administrators/SYSTEM |
| `%LOCALAPPDATA%\Temp\...\pdf` | profile browser tạm | người dùng hiện tại/SYSTEM |

Product key đầy đủ không được ghi vào log, timeline hoặc báo cáo. Enterprise chỉ mang key trong envelope mã hóa; audit chỉ giữ last-5.

## Bảng schema

| Thành phần | Schema |
| --- | --- |
| Dashboard | `2.0` |
| Capability | `1.1` |
| Compatibility module / catalog | `1.0` / `1.1` |
| Localization | `1.0` |
| Offline policy | `1.0` |
| Data lifecycle / writable data | `1.0` / `2.0` |
| Software inventory / catalog | `1.0` / `1.2` |
| Module contract / result | `1.0` / `1.0` |
| Report envelope | `1.5` |
| Report export | `1.2` |
| Safety policy | `1.0` |
| Plugin | `1.0` |
| Timeline | `1.0` |
| Enterprise protocol | `1.0` |

Launcher và dashboard so khớp schema qua environment. Lệch schema trong secure launch là lỗi fail-closed.

## Release gates

`BUILD.ps1` chạy:

- PowerShell parser cho toàn bộ script;
- kiểm tra payload trên CLR x64 và x86;
- module contract/report/safety/dashboard;
- compatibility freshness và fixtures Windows/Office;
- offline/i18n/offline-safe HTML/PDF;
- plugin/timeline/enterprise;
- data lifecycle migration/idempotency/rollback;
- PE flags và release manifest;
- Authenticode khi `-RequireAuthenticode` được bật.

Workflow `.github/workflows/compatibility-review.yml` chạy hàng tuần, dùng `VERIFY-MICROSOFT-CATALOG-SOURCES.ps1` để phát hiện catalog quá hạn, revision/release/channel mới và xuất `microsoft-catalog-review.json`. Workflow chỉ tạo bằng chứng/khóa gate; không tự sửa hay tự xuất bản catalog.

## Giới hạn

- Catalog chứng minh logic nhận diện và mốc đã rà soát; chứng nhận đầy đủ vẫn cần test trên VM/máy thật cho từng release.
- Offline mode không thể ngăn một dịch vụ Windows hoặc ứng dụng Office độc lập tự kết nối mạng; nó bảo đảm code của tool không chủ động dùng mạng.
- Kết luận kỹ thuật không thay thế chứng từ hoặc tư vấn pháp lý về bản quyền.
- Bản build không được coi là đã ký nếu `Get-AuthenticodeSignature` không trả `Valid`.
