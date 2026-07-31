# Entry points Tool-Kiem-Tra v4.3

Nguồn chuẩn là `Tool-ModuleContract.ps1`. Catalog có 25 descriptor, trong đó 22 entry point công khai và ba nguồn kiểm kê nội bộ.

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

## 22 entry point nghiệp vụ

| ModuleId | Script / Operation | AccessMode | NetworkScope | Admin |
| --- | --- | --- | --- | --- |
| `report.all` | `kiem-tra-cau-hinh-ban-quyen.ps1 / All` | ReadOnly | LocalOnly | Không |
| `report.hardware` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Hardware` | ReadOnly | LocalOnly | Không |
| `report.windows` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Windows` | ReadOnly | LocalOnly | Không |
| `report.office` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Office` | ReadOnly | LocalOnly | Không |
| `report.software` | `kiem-tra-cau-hinh-ban-quyen.ps1 / Software` | ReadOnly | LocalOnly | Không |
| `cleanup.scan` | `windows-license-compliance-cleanup.ps1 / Scan` | ReadOnly | LocalOnly | Không |
| `cleanup.repair` | `windows-license-compliance-cleanup.ps1 / RepairScanSources` | SystemChange | LocalOnly | Có |
| `cleanup.remediate` | `windows-license-compliance-cleanup.ps1 / Remediate` | SystemChange | LocalOnly | Có |
| `cleanup.deep` | `windows-license-compliance-cleanup.ps1 / DeepClean` | SystemChange | LocalOnly | Có |
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
- `Internet`: hiện không có descriptor nào.

Module mới phải khai báo `NetworkScope` và được thêm vào verifier trước khi phát hành.
