# Kiến trúc kỹ thuật Tool-Kiem-Tra v4.8

Tài liệu này mô tả kiến trúc phát hành `4.8.0.1`, dashboard schema `2.0` và các ranh giới an toàn của bản một tệp. Mã nguồn PowerShell tương ứng là nguồn sự thật; tài liệu không thay thế verifier.

## Mục tiêu kiến trúc

- Một EXE AnyCPU tự chọn Windows PowerShell native x64/x86.
- Hoạt động cục bộ hoàn toàn khi Offline đang bật; không telemetry, service nền hoặc cập nhật im lặng. Kiểm tra phiên bản chỉ chạy khi Online đã được người dùng cho phép.
- Dashboard WinForms hiện đại nhưng vẫn giữ .NET Framework 4/Windows PowerShell 3+.
- Mọi chức năng chạy qua module contract, capability gate và structured log.
- Báo cáo HTML/PDF/JSON/XML dùng chung report envelope, không tải asset từ Internet.
- Dashboard/log chỉ đọc dùng LocalAppData của đúng user; dữ liệu có thể thay đổi hệ thống nằm trong ProgramData có ACL Administrators/SYSTEM.

## Sơ đồ thành phần

```text
Tool-Kiem-Tra-v4.8.exe
  ├─ kiểm tra OS/kiến trúc, chọn quyền chạy theo mode, mutex và Offline mặc định
  ├─ giải nén 49 payload vào session được bảo vệ
  ├─ đối chiếu TOOL-SHA256SUMS.txt
  └─ chạy Windows PowerShell native với schema/environment cố định
       ├─ Giao-Dien.ps1                    dashboard schema 2.0
       ├─ Tool-ElevatedBridge.ps1          cầu nối UAC khóa module/script/runtime và allowlist TOOL_*
       ├─ Tool-DataLifecycle.ps1           data schema 2.0 + migration transaction
       ├─ Tool-Capabilities.ps1            capability schema 1.1
       │   └─ Tool-Compatibility.ps1       catalog schema 1.0
       ├─ Tool-Localization.ps1            localization schema 1.0
       ├─ Tool-OfflinePolicy.ps1           offline policy schema 1.0
       ├─ Tool-Assistant.ps1               hỏi đáp cục bộ schema 1.1, phạm vi Tool + cache có chữ ký
       │   ├─ tool-assistant-knowledge-v1.1.json (Tool min/max + knowledge 1.3.1)
       │   └─ cache người dùng JSON + CMS .p7s (ngoài EXE, chống hạ phiên bản)
       ├─ Tool-UpdateManager.ps1           update manifest schema 1.0 + verified swap/rollback
       ├─ Tool-SoftwareInventory.ps1       inventory/deep scan schema 1.0
       │   ├─ software-license-catalog-v1.0.json      catalog 1.4
       │   └─ software-license-catalog-v1.0.json.p7s  detached CMS signature
       ├─ Tool-ModuleContract.ps1          contract/result schema 1.0
       ├─ Tool-ReportSchema.ps1            report schema 1.5
       │   └─ Tool-ReportExport.ps1        export schema 1.4 (HTML summary / detailed PDF)
       ├─ Tool-SafetyPolicy.ps1            safety schema 1.0
       └─ các entry point nghiệp vụ
```

## Lớp launcher

`Tool-Kiem-Tra-v4.8-OneFile.cs`:

1. chạy `asInvoker` cho dashboard; mode không-GUI cần quyền cao tự relaunch bằng `runas` và GUI chỉ nâng quyền cho từng hành động cần thiết;
2. từ chối Windows cũ hơn Windows 7 SP1;
3. dùng `Environment.SpecialFolder.System` để lấy PowerShell native, không tìm `powershell.exe` qua `PATH`;
4. dùng `%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6` cho dashboard và `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6` cho mode nâng quyền; vùng v4.4/v4.5 chỉ là nguồn migration hoặc tham chiếu log/backup đọc;
5. từ chối reparse point; ACL LocalAppData chỉ cho user hiện tại/Administrators/SYSTEM, ACL ProgramData chỉ cho Administrators/SYSTEM;
6. giải nén payload, tính SHA-256 và so với manifest nhúng;
7. truyền phiên bản schema, correlation ID, đường dẫn log/plugin/timeline và trạng thái Offline qua environment;
8. dọn session tạm sau khi tiến trình con kết thúc.

Launcher có sáu mode được công bố trong `ENTRY-POINTS-v4.8.md`. `--enterprise-ui` luôn được phép mở để Mục 8 giữ đủ ba chức năng. Các tiến trình mạng `--enterprise-server`, `--enterprise-agent` và `--enterprise-agent-force` chỉ chạy khi công tắc mạng riêng của Mục 8 đang bật.

## Vòng đời dữ liệu v4.8 trên storage generation v4.6

`Tool-DataLifecycle.ps1` tạo `data-state.json` với `DataSchemaVersion=2.0`, `ProducerVersion=4.8.0.1`, storage generation và kết quả migration. Launcher tiếp tục dùng vùng dữ liệu tương thích v4.6/v4.4 cùng schema qua environment; dashboard fail-closed khi schema không khớp.

Migration chỉ chạy khi chưa có state:

1. giữ global migration mutex và từ chối root/reparse point không an toàn;
2. sao chép cấu hình KMS, network preference, plugin, timeline và Enterprise sang staging GUID trong root v4.6;
3. đối chiếu danh sách tệp, kích thước và SHA-256 với nguồn;
4. commit từng mục, ưu tiên cấu hình KMS cũ của người dùng nhưng không ghi đè plugin tích hợp mới;
5. nếu commit lỗi, khôi phục tệp bị ghi đè, xóa đúng tệp/thư mục mới và không tạo state hoàn tất;
6. giữ nguyên toàn bộ vùng cũ; `logs`/`backups` cũ chỉ được công bố dưới `LegacyReadOnlyRoots`.

Launcher v4.8 kiểm tra mutex launcher v4.4/v4.5 trước migration. Enterprise agent/audit tiếp tục dùng mutex của storage generation v4.6. Các chuỗi `v4.4` còn lại trong timeline/Enterprise là nhãn mật mã tương thích, không phải đường dẫn ghi.

## Cập nhật ứng dụng v4.6.1–v4.8.0

`Tool-UpdateManager.ps1` có ba mode: `Library` cho verifier cục bộ, `Check` chỉ đọc manifest và `Apply` tải/cài bản đã xác nhận. Hai mode thực thi fail-closed nếu thiếu `-ConsentGranted` hoặc `TOOL_OFFLINE_MODE` khác `0`.

- Manifest chỉ được lấy từ URL HTTPS cố định của repository; release/download URL phải thuộc đúng repository/tag phiên bản và EXE asset.
- Tệp tải qua tối đa bốn redirect chỉ tới host tài sản GitHub allowlist, bị giới hạn dung lượng, và phải khớp chính xác `DownloadSize`/`DownloadSha256`; Authenticode được bắt buộc khi manifest khai báo signer đã ghim.
- GUI chỉ hỏi khi rảnh, có ba lựa chọn. `Later` giữ state trong phiên và hỏi lại sau tác vụ kế tiếp hoặc hai giờ; `DismissForSession` chỉ bỏ qua đến lần mở sau.
- `Apply` xác minh launcher path/PID/hash từ secure environment, chờ launcher cũ thoát, backup EXE, thay thế cùng thư mục, khởi động bản mới và rollback nếu bản mới thoát sớm.
- Không có scheduler/service/background downloader. Mọi kiểm tra và tải đều dừng khi người dùng chuyển về Offline.

## Dashboard và UI

v4.3 chọn **Modern WinForms** thay vì WPF/WebView2 để không kéo thêm runtime hoặc tài nguyên web:

- font Segoe UI cỡ gọn, bề mặt trung tính, ít bold/màu nhấn, dashboard card, tile hai dòng, khoảng đệm icon, hover state và bo góc;
- biểu tượng Windows/Office/bảo mật/tác vụ được vẽ vector bằng `System.Drawing` ngay trong tiến trình, không phụ thuộc asset mạng;
- layout hai cột tự co theo DPI/WorkingArea, có AutoScroll cho màn hình thấp;
- dark mode dùng palette chung trong `Tool-UiTheme.ps1` và được truyền sang cửa sổ con;
- thẻ trạng thái Windows release, Office family/channel, chế độ chạy và integrity;
- chọn `vi-VN`/`en-US` trực tiếp, lưu theo người dùng và truyền sang Mục 8 cùng trình quản lý cục bộ;
- nút Offline/Online toàn ứng dụng luôn hiện rõ trạng thái hiện tại và tooltip mô tả trạng thái đích;
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

Catalogue phần mềm `1.4.0.0` có 77 quy tắc duy nhất và chữ ký CMS tách rời, bổ sung IObit Driver Booster, WIRIS MathType, PDF editor thương mại và IDM, đồng thời bao phủ phần mềm kỹ thuật và nhiều ứng dụng văn phòng, phát triển, cơ sở dữ liệu, media, mạng và bảo mật. Record Registry/Appx/shortcut được gộp theo identity tương thích; thành phần hệ thống được gắn `IsSystemComponent`. Mô hình giấy phép và bằng chứng can thiệp được đánh giá độc lập; quy tắc chỉ tăng độ chính xác nhận diện/signature/domain/artifact, còn scoring fail-closed vẫn áp dụng như mọi phần mềm khác và mức `Low` không tạo hành động xóa.

## Dry Run khắc phục

`Get-DryRunRemediationPlan` biến đúng các candidate đã chọn thành danh sách máy đọc được: target, action code, yêu cầu Administrator, backup dự kiến, `Restorable` và `ChangesSystem`. Nhánh Dry Run nằm trước `Checkpoint-Computer`, `Invoke-DeepCleanupV35` và `Invoke-Remediation`; nó chỉ quét lại, ghi decision/report và trả `NoSystemChangesApplied=true`. Nút **Execute for real** mở lại danh sách với ID gợi ý và bắt buộc xác nhận lần nữa.

## Offline policy

`Tool-OfflinePolicy.ps1` fail-closed:

- mỗi tiến trình mới luôn bắt đầu Offline; Online chỉ có hiệu lực trong phiên hiện tại;
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

`NetworkScope=LocalOnly` là offline-capable. `license.manager` chỉ mở giao diện chứa đủ ba chức năng nên là `LocalOnly`; `enterprise.server` và `enterprise.agent` khai báo `Lan`. `software.catalog.update` khai báo `Internet`; trình cập nhật ứng dụng và đồng bộ tri thức Trợ lý cũng đi qua Offline gate riêng, chỉ dùng HTTPS GET tới host/path allowlist và không thay đổi mặc định Offline của lần mở sau. Đồng bộ Trợ lý tải đúng hai byte-stream cố định (JSON và `.p7s`), giới hạn lần lượt 2 MiB/64 KiB, không redirect, xác minh detached CMS SHA-256 bằng fingerprint SHA-256 của chứng thư RSA đã ghim, rồi mới kiểm tra schema/phạm vi/phiên bản và cài cache có rollback. Không có POST, telemetry hoặc mô hình tự huấn luyện từ Internet.

## Báo cáo

Luồng báo cáo:

```text
module data
  → New-ToolReportEnvelope (schema 1.5)
  → schema validation
  → HTML + JSON + XML
  → offline HTML safety validation
  → HTML tổng quan được ghi làm tệp mở mặc định
  → PDF từ presentation HTML chi tiết riêng (Edge → Chrome → Word)
  → SHA-256 manifest
```

HTML có CSP `default-src 'none'`, CSS nhúng, layout responsive, dark-mode preview và stylesheet A4. Bảng dùng profile độ rộng theo ngữ nghĩa; bảng đánh giá rộng tách thành tổng quan/bằng chứng tối đa sáu cột, `<details>` tự mở khi in, header lặp và hàng tránh bị cắt. Mọi lần xuất đặt HTML/PDF/JSON/XML/SHA-256 trực tiếp trong một `Desktop\BaoCao-Tool-Kiem-Tra`, dùng timestamp mili-giây; HTML liên kết tương đối tới PDF và là tệp duy nhất tự mở. Edge/Chrome chạy với background networking tắt và host resolver map về `0.0.0.0`. Nếu không có PDF engine, các định dạng còn lại vẫn hợp lệ.

## Dữ liệu và ranh giới tin cậy

| Vùng | Dữ liệu | Quyền ghi |
| --- | --- | --- |
| Session dashboard trong LocalAppData v4.6 | payload đã xác minh | user hiện tại/Administrators/SYSTEM |
| `logs` dashboard | JSONL theo ngày | user hiện tại/Administrators/SYSTEM |
| Session/log mode nâng quyền trong ProgramData v4.6 | payload đã xác minh + JSONL | Administrators/SYSTEM |
| `backups` | backup + hash/HMAC/DPAPI | Administrators/SYSTEM |
| `plugins` | plugin JSON khai báo | Administrators/SYSTEM |
| `timeline` | JSONL + HMAC/hash chain | Administrators/SYSTEM |
| `enterprise` | config, secret DPAPI, queue, report | Administrators/SYSTEM |
| `%LOCALAPPDATA%\Temp\...\pdf` | profile browser tạm | người dùng hiện tại/SYSTEM |
| `Desktop\BaoCao-Tool-Kiem-Tra` | package report theo từng lượt | người dùng hiện tại |

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
| Software inventory / catalog | `1.0` / `1.4` |
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
- Authenticode bắt buộc cho build stable; build chưa ký chỉ được phép ở kênh `development` có cờ xác nhận riêng.

Workflow `.github/workflows/compatibility-review.yml` chạy hàng tuần, dùng `VERIFY-MICROSOFT-CATALOG-SOURCES.ps1` để phát hiện catalog quá hạn, revision/release/channel mới và xuất `microsoft-catalog-review.json`. Workflow chỉ tạo bằng chứng/khóa gate; không tự sửa hay tự xuất bản catalog.

## Giới hạn

- Catalog chứng minh logic nhận diện và mốc đã rà soát; chứng nhận đầy đủ vẫn cần test trên VM/máy thật cho từng release.
- Offline mode không thể ngăn một dịch vụ Windows hoặc ứng dụng Office độc lập tự kết nối mạng; nó bảo đảm code của tool không chủ động dùng mạng.
- Kết luận kỹ thuật không thay thế chứng từ hoặc tư vấn pháp lý về bản quyền.
- Bản build không được coi là đã ký nếu `Get-AuthenticodeSignature` không trả `Valid`.
