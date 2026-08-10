# Report Schema 1.5 — Tool-Kiem-Tra v4.8

`Tool-ReportSchema.ps1` là nguồn chuẩn. JSON và XML dùng chung một envelope; mọi báo cáo phải qua `Test-ToolReportEnvelope`.

## Trường chung

- `SchemaVersion`: `1.5`
- `ReportSchemaVersion`: `1.5`
- `ReportKind`: một trong chín loại bên dưới
- `ToolVersion`: phiên bản Tool tạo báo cáo, hiện tại `4.8.0.0`
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

HTML là bản tổng quan không có bảng dài: chỉ giữ cấu hình chính, kết luận, cảnh báo, hướng xử lý và hướng dẫn mở PDF. PDF được tạo từ một presentation chi tiết riêng theo Edge→Chrome→Word, giữ toàn bộ bảng và bằng chứng. Không có engine thì PDF có thể vắng mặt nhưng JSON/XML/HTML vẫn hợp lệ và HTML thông báo rõ trạng thái này.

Ở màn hình rộng, HTML cân năm thẻ kết quả nhanh trên một hàng; màn hình hẹp tự giảm số cột. Mỗi kết luận có hai ô con riêng cho Mức xác minh và Hướng xử lý. Chân presentation chi tiết dùng hai hàng cố định (tên công cụ, sau đó thông tin tác giả/hỗ trợ) để PDF không ép hoặc cắt chữ.

Schema 1.4 dùng ngắt trang A4 an toàn cho PDF và metadata `HtmlPresentation=Summary`, `PdfPresentation=Detailed`. Các nhóm thẻ kết quả mang lớp đếm cột `cards-count-N`; vì vậy năm thẻ Windows, Office, dấu hiệu, rà soát và Online/Offline giữ trên cùng một hàng khi in PDF, còn màn hình hẹp vẫn tự co. Từ v4.8, mọi package ghi trực tiếp vào thư mục chung `Desktop\BaoCao-Tool-Kiem-Tra`, không tạo thư mục con theo lượt; các tệp cùng lượt dùng chung tên gốc có timestamp mili-giây. Khi hoàn tất, Tool mở HTML tổng quan và người dùng chọn nút trong HTML để mở đúng PDF đầy đủ.

## Integrity package

`*-SHA256SUMS.txt` liệt kê mọi artefact tạo thành công, trừ chính manifest. Consumer:

1. xác minh SHA-256;
2. kiểm tra `SchemaVersion`, `ReportSchemaVersion`, `ReportKind`, `ToolVersion`;
3. kiểm tra dữ liệu bắt buộc theo kind;
4. không parse HTML thay JSON/XML;
5. xử lý Offline/compatibility status như metadata, không như chứng cứ pháp lý.
