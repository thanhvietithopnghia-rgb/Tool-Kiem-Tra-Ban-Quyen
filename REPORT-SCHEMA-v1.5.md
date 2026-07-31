# Report Schema 1.5 — Tool-Kiem-Tra v4.3

`Tool-ReportSchema.ps1` là nguồn chuẩn. JSON và XML dùng chung một envelope; mọi báo cáo phải qua `Test-ToolReportEnvelope`.

## Trường chung

- `SchemaVersion`: `1.5`
- `ReportSchemaVersion`: `1.5`
- `ReportKind`: một trong chín loại bên dưới
- `ToolVersion`: `4.3`
- `ToolName`
- `CreatedAt`: ISO 8601
- `ComputerName` hoặc `AN_DANH` khi redact
- `ModuleResult`: module result schema 1.0
- `Export`: format, privacy mode và output path

v4.3 có thể bổ sung các object `Capabilities`, `Compatibility`, `Localization` và `Offline`; consumer phải bỏ qua extension field không biết nhưng vẫn từ chối sai trường bắt buộc/schema.

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

## HTML/PDF export schema 1.2

HTML là presentation, không phải nguồn dữ liệu machine-readable:

- CSP `default-src 'none'`;
- CSS nhúng, không JavaScript/iframe/remote asset;
- responsive screen + dark preview;
- A4 print CSS;
- offline safety validation trước package/PDF.

PDF được tạo từ HTML theo Edge→Chrome→Word. Không có engine thì PDF có thể vắng mặt nhưng JSON/XML/HTML vẫn hợp lệ.

Schema 1.2 dùng ngắt trang A4 an toàn để không cắt hàng hoặc nội dung dài. HTML/PDF dành cho người đọc được lưu trực tiếp trên Desktop. Khi hoàn tất, Tool mở HTML trong trình duyệt mặc định; PDF vẫn được tạo và lưu cạnh HTML khi có engine phù hợp.

## Integrity package

`*-SHA256SUMS.txt` liệt kê mọi artefact tạo thành công, trừ chính manifest. Consumer:

1. xác minh SHA-256;
2. kiểm tra `SchemaVersion`, `ReportSchemaVersion`, `ReportKind`, `ToolVersion`;
3. kiểm tra dữ liệu bắt buộc theo kind;
4. không parse HTML thay JSON/XML;
5. xử lý Offline/compatibility status như metadata, không như chứng cứ pháp lý.
