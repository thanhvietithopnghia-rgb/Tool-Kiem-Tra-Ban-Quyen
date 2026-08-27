# Report Schema 1.5 — Tool-Kiem-Tra v5.0

`Tool-ReportSchema.ps1` là nguồn chuẩn. JSON và XML dùng chung một envelope; mọi báo cáo phải qua `Test-ToolReportEnvelope`.

## Trường chung

- `SchemaVersion`: `1.5`
- `ReportSchemaVersion`: `1.5`
- `ReportKind`: một trong chín loại bên dưới
- `ToolVersion`: phiên bản Tool tạo báo cáo, hiện tại `5.0.0.0`
- `ToolName`
- `CreatedAt`: ISO 8601
- `ComputerName` hoặc `AN_DANH` khi redact
- `ModuleResult`: module result schema 1.0
- `Export`: format, privacy mode và output path

Tool có thể bổ sung các object `Capabilities`, `Compatibility`, `Localization` và `Offline`; consumer phải bỏ qua extension field không biết nhưng vẫn từ chối sai trường bắt buộc/schema.

## Chín ReportKind

| ReportKind | Trường nghiệp vụ tối thiểu |
| --- | --- |
| `InventoryAndLicense` | `ToolName`, `CreatedAt`, `Mode` |
| `CleanupCompliance` | `ReadyForOfficialActivation`, `ScanWarningCount`, `HandlingGuidance` |
| `LicenseForensics` | `Overall`, `RiskScore`, `HighCount`, `ReviewCount` |
| `DeepScanDecision` | `AccessDenied`, `Overall`, `HighCount`, `ReviewCount`, `ReportPath` |
| `ScanSourceRepair` | `RepairAttempted`, `RecheckPassed`, `StartupTypeChanged`, `RollbackApplied`, before/after state |
| `CertificateAudit` | `CreatedAt`, `Overall`, signature counts, `Targets` |
| `PluginEvaluation` | `CreatedAt`, plugin/rule/finding counts |
| `LicenseTimeline` | `CreatedAt`, `ChainValid`, event/change counts |
| `EnterpriseInventory` | `CreatedAt`, client/device/network/license/privacy fields |

## JSON

- UTF-8.
- Giữ kiểu boolean/number/array/object.
- Không xuất full product key.
- Redact trước khi serialize.
- Không chấp nhận `ReportKind` ngoài allowlist.

## XML

- UTF-8, root `ToolReport`.
- Không DTD/external entity.
- Thuộc tính `type`: `object`, `array`, `string`, `boolean`, `number`, `null`.
- Item trong mảng dùng element `Item`.

## HTML/PDF export schema 1.4

HTML là presentation, không phải nguồn dữ liệu machine-readable:

- CSP `default-src 'none'`;
- CSS nhúng, không JavaScript/iframe/remote asset;
- responsive screen + dark preview;
- A4 print CSS;
- offline safety validation trước package/PDF.

HTML là bản tổng quan không có bảng dài: chỉ giữ cấu hình chính, kết luận, cảnh báo, hướng xử lý và hướng dẫn mở PDF. PDF được tạo từ một presentation chi tiết riêng theo Edge→Chrome, giữ toàn bộ bảng và bằng chứng. Mỗi lượt trình duyệt đọc HTML và ghi PDF trung gian trong profile tạm đã khóa ACL; chỉ tiến trình Tool mới chép PDF hợp lệ về thư mục báo cáo. Cách này giữ đúng CSS khi Tool chạy nâng quyền hoặc đích thuộc hồ sơ người dùng khác, đồng thời cho phép Chrome tiếp quản nếu Edge lỗi. Word chỉ còn là fallback cho presentation cơ bản không mang theme PDF; báo cáo chi tiết `v4.8-classic-a4` sẽ fail closed để không tạo tài liệu sai bố cục. Không có engine phù hợp thì PDF có thể vắng mặt nhưng JSON/XML/HTML vẫn hợp lệ và HTML thông báo rõ trạng thái này.

Ở màn hình rộng, HTML cân năm thẻ kết quả nhanh trên một hàng; màn hình hẹp tự giảm số cột. Mỗi kết luận có hai ô con riêng cho Mức xác minh và Hướng xử lý. Chân presentation chi tiết dùng hai hàng cố định (tên công cụ, sau đó thông tin tác giả/hỗ trợ) để PDF không ép hoặc cắt chữ.

Schema 1.4 dùng ngắt trang A4 an toàn cho PDF và metadata `HtmlPresentation=Summary`, `PdfPresentation=Detailed`. Presentation PDF chi tiết mang chủ đề `v4.8-classic-a4`, khóa giao diện A4 sáng, khung xanh, năm thẻ trạng thái và mật độ bảng của v4.8 trong khi vẫn giữ toàn bộ dữ liệu v4.9. Các nhóm thẻ kết quả mang lớp đếm cột `cards-count-N`; vì vậy năm thẻ Windows, Office, dấu hiệu, rà soát và Online/Offline giữ trên cùng một hàng khi in PDF, còn màn hình hẹp vẫn tự co. Từ v4.8, mọi package ghi trực tiếp vào thư mục chung `Desktop\BaoCao-Tool-Kiem-Tra`, không tạo thư mục con theo lượt; các tệp cùng lượt dùng chung tên gốc có timestamp mili-giây. Khi hoàn tất, Tool mở HTML tổng quan và người dùng chọn nút trong HTML để mở đúng PDF đầy đủ.

## Artifact quản trị v5 ngoài envelope ReportKind

Các artifact dưới đây có hợp đồng riêng và **không** được gắn giả một trong chín `ReportKind` của schema 1.5. Consumer phải chọn parser theo loại artifact, không dựa vào phần mở rộng hoặc parse HTML thay JSON.

### Fleet export schema 1.0

`Export-ToolEnterpriseFleetReport` tạo một thư mục staging rồi chỉ publish cả thư mục khi các output được yêu cầu đã thành công. JSON fleet có các trường chính:

- `SchemaVersion`, `ToolVersion`, `CreatedAtUtc`, `ClientCount`;
- `Selection`: số client nguồn/được chọn/bị loại, giới hạn tuổi và số ID lọc;
- `Freshness`: ngưỡng stale cùng số client current/stale; timestamp thiếu hoặc sai được tính là stale;
- `Privacy`: `RedactSensitive`, danh sách trường đã che, `FullProductKeysIncluded=false`, `InternalSourcePathsIncluded=false` và `CsvFormulaProtection=true`;
- `Formats` và `Clients`; mỗi client chỉ chứa định danh/địa chỉ đã áp chính sách privacy, thời gian/freshness, trạng thái/kênh Windows và Office, last-5 khi được phép, cùng cờ cho phép thay đổi license từ xa.

Các format hỗ trợ là JSON, CSV, HTML và PDF. Redaction là mặc định; xuất dữ liệu nhạy cảm cần lựa chọn quản trị rõ ràng nhưng vẫn không bao gồm product key đầy đủ. CSV trung hòa ô có thể bị spreadsheet hiểu là công thức. HTML phải qua kiểm tra offline-safe. Nếu PDF nằm trong danh sách format mà converter không tạo được tệp, toàn bộ yêu cầu phải báo lỗi thay vì trả thành công giả. Manifest `*-SHA256SUMS.txt` chỉ liệt kê artifact đã được publish thành công.

Chỉ fleet file có `Privacy.RedactSensitive=true` mới được thiết kế làm ứng viên chia sẻ ra ngoài, và vẫn phải được người quản trị đọc lại trước khi gửi. Bản không redact là artifact nội bộ. Object kết quả của hàm/CLI có thể chứa đường dẫn cục bộ nên không tự động là public-safe chỉ vì fleet payload đã redact.

### CLI headless

`Tool-EnterpriseCli.ps1` ghi đúng một object JSON nén ra stdout. Thành công dùng `Success=true`, `Action` và trường kết quả tương ứng; lỗi dùng `Success=false`, `Action`, `Error` và exit code khác 0. Action được phép là `FleetExport`, `ServerStatus`, `ClientSnapshot`. `FleetExport` mặc định redact và chỉ bỏ redact khi quản trị viên truyền lựa chọn sensitive; `ServerStatus` không trả dữ liệu nhạy cảm; `ClientSnapshot` ghi file cục bộ và khai báo `FullProductKeysIncluded=false`. CLI không biến output presentation thành nguồn dữ liệu chuẩn thay cho JSON.

Stdout CLI là control-plane output dành cho automation, không phải public report: nó có thể chứa output path hoặc thông báo lỗi môi trường. Consumer phải dùng file fleet đã redact khi cần chia sẻ và không công bố nguyên stdout theo mặc định.

### Intune/MDM deployment manifest schema 1.0

`Manage-ToolEnterpriseDeployment.ps1` quản lý một allowlist payload chương trình qua `Install`, `Detect`, `Repair`, `Uninstall`. Manifest cài đặt gồm `SchemaVersion`, `InstalledAtUtc`, danh sách `Files` với SHA-256, `ContainsSecrets=false`, `NetworkConfigurationManaged=false`, `SourceTrustMode` và `SourceManifestSha256`. Production Install/Repair phải ghim SHA-256 của source manifest tin cậy; Detect có thể so desired manifest hash để bản cũ không được báo compliant chỉ vì tự nhất quán. Đây là manifest triển khai, không phải report envelope và không chứa pairing code, secret, report hoặc network policy.

Deployment manifest và JSON trạng thái có thể chứa target path/source trust metadata; chúng dành cho MDM nội bộ, không được phân loại là public-safe artifact. Log đưa ra ngoài phải redact path và error chi tiết theo chính sách của tổ chức.

### VM public-safe summary schema 1.0

`New-ClientVmTestSummary.ps1` chỉ chấp nhận các platform và verifier trong allowlist, cùng commit 40 ký tự hex và danh tính OS khớp policy. JSON tổng hợp gồm `SchemaVersion`, `GeneratedAtUtc`, số platform/result Passed/Failed/Missing, `Status`, `SourceCommit` và `Results`. Mỗi row công khai chỉ giữ platform, trạng thái, caption/build/UBR/DisplayVersion Windows, giá trị expected, `OsIdentityVerified`, phiên bản PowerShell, commit, thời gian UTC và tên/exit code/trạng thái verifier.

Tóm tắt public-safe không mang `OutputTail`, raw stdout/stderr, đường dẫn runner hoặc trường tùy ý từ input. `Missing` và sai danh tính OS làm summary không đạt; kết quả từ các platform khác commit bị từ chối. Schema chỉ mô tả định dạng bằng chứng: trạng thái thực tế vẫn phải đọc từ [SECURITY-TEST-RESULTS.md](SECURITY-TEST-RESULTS.md), hiện chưa được suy diễn từ việc workflow tồn tại.

## Integrity package của report envelope 1.5

Với package thuộc một trong chín `ReportKind`, `*-SHA256SUMS.txt` liệt kê mọi artefact tạo thành công, trừ chính manifest. Fleet export dùng hợp đồng/manifest riêng đã mô tả ở trên. Consumer của report envelope 1.5:

1. xác minh SHA-256;
2. kiểm tra `SchemaVersion`, `ReportSchemaVersion`, `ReportKind`, `ToolVersion`;
3. kiểm tra dữ liệu bắt buộc theo kind;
4. không parse HTML thay JSON/XML;
5. xử lý Offline/compatibility status như metadata, không như chứng cứ pháp lý.
