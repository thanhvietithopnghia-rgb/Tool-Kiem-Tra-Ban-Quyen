# Entry points Tool-Kiem-Tra v4.8

Nguồn chuẩn là `Tool-ModuleContract.ps1`. Catalog có 27 descriptor, trong đó 24 entry point công khai và ba nguồn kiểm kê nội bộ.

## Launcher modes

| Tham số EXE | Script | Mục đích | Offline |
| --- | --- | --- | --- |
| không có hoặc `--gui` | `Giao-Dien.ps1` | Dashboard chính | Có |
| `--local-license-manager` | `windows-office-license-manager.ps1` | Quản lý Windows/Office cục bộ | Có |
| `--enterprise-ui` | `enterprise-license-manager.ps1` | Mục 8: Quản lý cục bộ + Máy chủ + Máy trạm | Có; có công tắc mạng riêng |
| `--enterprise-server` | `Tool-EnterpriseHost.ps1` | Listener máy chủ | Cần bật mạng Mục 8 |
| `--enterprise-agent` | `Tool-EnterpriseAgent.ps1` | Agent theo lịch | Cần bật mạng Mục 8 |
| `--enterprise-agent-force` | `Tool-EnterpriseAgent.ps1 -Force` | Agent chạy cưỡng bức một lượt | Cần bật mạng Mục 8 |

Người dùng phát hành nên chạy EXE. Chạy script trực tiếp chỉ dành cho phát triển/kiểm thử và không có toàn bộ bảo đảm secure-launch.

Từ v4.6.2, manifest EXE là `asInvoker`: `--gui` mở dashboard bằng quyền hiện tại. Các mode không-GUI trong bảng trên tự yêu cầu UAC khi cần; từ dashboard, hành động `Admin=Có`, cập nhật ứng dụng và Trung tâm doanh nghiệp được mở lại bằng `RunAs`. Hủy UAC không làm đóng dashboard hoặc vô hiệu hóa các chức năng chỉ đọc.

## 24 entry point nghiệp vụ

| ModuleId | Script / Operation | AccessMode | NetworkScope | Admin |
| --- | --- | --- | --- | --- |
| `report.all` | `kiem-tra-cau-hinh-ban-quyen.ps1 / All` | ReadOnly | LocalOnly | Không |
| `report.hardware` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Hardware` | ReadOnly | LocalOnly | Không |
| `report.windows` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Windows` | ReadOnly | LocalOnly | Không |
| `report.office` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Office` | ReadOnly | LocalOnly | Không |
| `report.software` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Software` | ReadOnly | LocalOnly | Không |
| `software.catalog.update` | `software-license-online-update.ps1 / Update` | ReadOnly | Internet | Không |
| `application.update.check` | `Tool-UpdateManager.ps1 / Check` | ReadOnly | Internet | Không |
| `cleanup.scan` | `windows-license-compliance-cleanup.ps1 / Scan` | ReadOnly | LocalOnly | Có |
| `cleanup.repair` | `windows-license-compliance-cleanup.ps1 / RepairScanSources` | SystemChange | LocalOnly | Có |
| `cleanup.remediate` | `windows-license-compliance-cleanup.ps1 / Remediate` | SystemChange | LocalOnly | Có |
| `cleanup.deep` | `windows-license-compliance-cleanup.ps1 / DeepClean` (có `-DryRun`) | SystemChange | LocalOnly | Có |
| `backup.create` | `windows-license-backup.ps1 / Create` | SystemChange | LocalOnly | Có |
| `restore.apply` | `windows-license-restore.ps1 / Apply` | SystemChange | LocalOnly | Có |
| `oem.inspect` | `windows-oem-license-assistant.ps1 / Inspect` | ReadOnly | LocalOnly | Không |
| `oem.apply` | `windows-oem-license-assistant.ps1 / Apply` | SystemChange | LocalOnly | Có |
| `license.deep-scan` | `windows-license-deep-scan.ps1 / Scan` | ReadOnly | LocalOnly | Có |
| `forensics.scan` | `windows-license-forensics.ps1 / Scan` | ReadOnly | LocalOnly | Có |
| `license.manager.local` | `windows-office-license-manager.ps1 / Open` | SystemChange | LocalOnly | Có |
| `license.manager` | `enterprise-license-manager.ps1 / Open` | SystemChange | LocalOnly | Có |
| `enterprise.server` | `Tool-EnterpriseHost.ps1 / Serve` | SystemChange | Lan | Có |
| `enterprise.agent` | `Tool-EnterpriseAgent.ps1 / Run` | SystemChange | Lan | Có |
| `assurance.certificates` | `windows-license-assurance.ps1 / CertificateAudit` | ReadOnly | LocalOnly | Không |
| `assurance.plugins` | `windows-license-assurance.ps1 / PluginAudit` | ReadOnly | LocalOnly | Không |
| `assurance.timeline` | `windows-license-assurance.ps1 / TimelineExport` | ReadOnly | LocalOnly | Không |

`SystemChange` không có nghĩa là tự động thay đổi. Nó yêu cầu secure launch, quyền phù hợp và xác nhận theo safety policy.

Với `cleanup.deep -DryRun`, descriptor vẫn giữ `SystemChange` để áp dụng cùng capability/integrity gate và có đủ quyền đọc bằng chứng, nhưng runtime không gọi hành động thay đổi. Kết quả bắt buộc có `SimulationOnly=true`, `NoSystemChangesApplied=true` và danh sách `PlannedActions`; chuyển sang chạy thật luôn tạo invocation mới sau bước chọn/xác nhận lại.

## Ba descriptor nội bộ

| ModuleId | Nguồn |
| --- | --- |
| `inventory.registry` | Registry inventory trong deep scan |
| `inventory.service` | Service inventory qua CIM/WMI |
| `inventory.task` | Scheduled Task inventory qua module/fallback |

Ba descriptor này có `IsEntryPoint=false`; GUI không được khởi chạy chúng độc lập.

## Invocation contract

GUI tạo `InvocationId`, `CorrelationId`, `ModuleId` và `StartedAtUtc`, sau đó capability gate kiểm tra:

- `SupportedOperatingSystem`;
- `CimCmdlets|WmiFallback`;
- `ScheduledTasksModule|ScheduledTasksFallback`;
- `NativeCscript`;
- script entry point tồn tại.

Kết quả chuẩn gồm `Status`, `ExitCode`, `DurationMs`, `Summary`, `OutputPaths`, `FindingCount` và `WarningCount`. Exit code phải được ánh xạ qua `ExitCodeMap`; consumer không được tự coi exit code khác 0 là bằng chứng vi phạm bản quyền.

## Quy tắc mạng

- `LocalOnly`: chạy được trong Offline mode.
- `Lan`: chỉ chạy sau khi người dùng bật công tắc mạng riêng của Mục 8; có thể tắt lại mà không xóa cấu hình.
- `Internet`: `software.catalog.update` chỉ chạy sau xác nhận riêng để tải catalog HTTPS. `application.update.check` chỉ chạy khi người dùng đã cho phép Online; nó chỉ lấy manifest phiên bản. Thiếu consent hoặc đang Offline trả mã `2` trước mọi thao tác mạng. Không mô-đun nào tải inventory, đường dẫn, khóa hoặc token lên mạng.

Module mới phải khai báo `NetworkScope` và được thêm vào verifier trước khi phát hành.
