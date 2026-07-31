# Kiến trúc kỹ thuật Tool-Kiem-Tra v4.3

Tài liệu này mô tả kiến trúc phát hành `4.3.0.8`, dashboard schema `2.0` và các ranh giới an toàn của bản một tệp. Mã nguồn PowerShell tương ứng là nguồn sự thật; tài liệu không thay thế verifier.

## Mục tiêu kiến trúc

- Một EXE AnyCPU tự chọn Windows PowerShell native x64/x86.
- Hoạt động cục bộ hoàn toàn khi Offline đang bật; không telemetry và không kiểm tra cập nhật ngầm.
- Dashboard WinForms hiện đại nhưng vẫn giữ .NET Framework 4/Windows PowerShell 3+.
- Mọi chức năng chạy qua module contract, capability gate và structured log.
- Báo cáo HTML/PDF/JSON/XML dùng chung report envelope, không tải asset từ Internet.
- Dữ liệu có thể thay đổi hệ thống nằm trong vùng ProgramData có ACL Administrators/SYSTEM.

## Sơ đồ thành phần

```text
Tool-Kiem-Tra-v4.3.exe
  ├─ kiểm tra OS/kiến trúc, UAC, mutex và offline preference
  ├─ giải nén 39 payload vào session được bảo vệ
  ├─ đối chiếu TOOL-SHA256SUMS.txt
  └─ chạy Windows PowerShell native với schema/environment cố định
       ├─ Giao-Dien.ps1                    dashboard schema 2.0
       ├─ Tool-Capabilities.ps1            capability schema 1.1
       │   └─ Tool-Compatibility.ps1       catalog schema 1.0
       ├─ Tool-Localization.ps1            localization schema 1.0
       ├─ Tool-OfflinePolicy.ps1           offline policy schema 1.0
       ├─ Tool-ModuleContract.ps1          contract/result schema 1.0
       ├─ Tool-ReportSchema.ps1            report schema 1.5
       │   └─ Tool-ReportExport.ps1        export schema 1.2
       ├─ Tool-SafetyPolicy.ps1            safety schema 1.0
       └─ các entry point nghiệp vụ
```

## Lớp launcher

`Tool-Kiem-Tra-v4.3-OneFile.cs`:

1. yêu cầu Administrator qua application manifest;
2. từ chối Windows cũ hơn Windows 7 SP1;
3. dùng `Environment.SpecialFolder.System` để lấy PowerShell native, không tìm `powershell.exe` qua `PATH`;
4. tạo vùng `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3`;
5. từ chối reparse point và ACL ngoài Administrators/SYSTEM;
6. giải nén payload, tính SHA-256 và so với manifest nhúng;
7. truyền phiên bản schema, correlation ID, đường dẫn log/plugin/timeline và trạng thái Offline qua environment;
8. dọn session tạm sau khi tiến trình con kết thúc.

Launcher có sáu mode được công bố trong `ENTRY-POINTS-v4.3.md`. `--enterprise-ui` luôn được phép mở để Mục 8 giữ đủ ba chức năng. Các tiến trình mạng `--enterprise-server`, `--enterprise-agent` và `--enterprise-agent-force` chỉ chạy khi công tắc mạng riêng của Mục 8 đang bật.

## Dashboard và UI

v4.3 chọn **Modern WinForms** thay vì WPF/WebView2 để không kéo thêm runtime hoặc tài nguyên web:

- font Segoe UI, dashboard card, tile hai dòng, hover state và bo góc;
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
- catalog cục bộ `compatibility-catalog-v1.0.json`.

Build mới hơn catalog được trả về `AheadOfCatalog`/`ManualReview`, không tự nhận là đã xác minh. Catalog quá `MaximumReviewAgeDays` làm verifier thất bại.

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

`NetworkScope=LocalOnly` là offline-capable. `license.manager` chỉ mở giao diện chứa đủ ba chức năng nên là `LocalOnly`; `enterprise.server` và `enterprise.agent` khai báo `Lan`. Không mô-đun nào khai báo Internet.

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
| Session trong ProgramData v4.3 | payload đã xác minh | Administrators/SYSTEM |
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
| Compatibility catalog | `1.0` |
| Localization | `1.0` |
| Offline policy | `1.0` |
| Module contract / result | `1.0` / `1.0` |
| Report envelope | `1.5` |
| Report export | `1.1` |
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
- PE flags và release manifest;
- Authenticode khi `-RequireAuthenticode` được bật.

Workflow `.github/workflows/compatibility-review.yml` chạy hàng tuần để phát hiện catalog quá hạn và nguồn Microsoft không truy cập được.

## Giới hạn

- Catalog chứng minh logic nhận diện và mốc đã rà soát; chứng nhận đầy đủ vẫn cần test trên VM/máy thật cho từng release.
- Offline mode không thể ngăn một dịch vụ Windows hoặc ứng dụng Office độc lập tự kết nối mạng; nó bảo đảm code của tool không chủ động dùng mạng.
- Kết luận kỹ thuật không thay thế chứng từ hoặc tư vấn pháp lý về bản quyền.
- Bản build không được coi là đã ký nếu `Get-AuthenticodeSignature` không trả `Valid`.
