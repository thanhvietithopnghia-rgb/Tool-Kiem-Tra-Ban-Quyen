# Công cụ kiểm tra cấu hình máy và bản quyền phần mềm v4.6 — mã nguồn

Release `4.6.0.0`, build `2026.08.06`. Người dùng cuối chạy một tệp `Tool-Kiem-Tra-v4.6.exe`; launcher AnyCPU tự chọn CLR/Windows PowerShell native phù hợp.

## Điểm mới v4.6

- Dashboard schema 2.0: Modern WinForms 1040 × 820, card Windows/Office, tile có mô tả, responsive DPI và dark mode toàn công cụ; Trung tâm quản lý giấy phép có màu nhận diện riêng.
- Kiểm kê toàn bộ phần mềm từ Uninstall Registry, AppX/MSIX, Start Menu, Desktop và các vị trí cài đặt/portable có giới hạn; phân loại theo mô hình cấp phép và bằng chứng kỹ thuật, không mặc định “không có bằng chứng” là chính hãng.
- Quét sâu phổ quát cho từng ứng dụng bằng nhiều EXE/DLL, Authenticode, hash xấu đã biết và dấu vết hệ thống tương quan; ngân sách chữ ký được phân bổ có trọng số cho nhóm trả phí/dùng thử/có dấu vết nhưng vẫn giữ lượt cho nhóm khác, còn trạng thái độ phủ/timeout được xuất máy đọc được.
- Nút **Kết nối online** xin phép trước khi tải danh mục HTTPS cố định để đối chiếu tên/phiên bản/nhà phát hành; không tải lên inventory, đường dẫn, khóa hay token và không thay đổi chế độ Offline mặc định.
- Chức năng **Khắc phục KMS/Activator** tách Quét toàn bộ, Windows & Office và Phần mềm khác; mọi mục NonGenuine/Suspicious đều chọn thủ công được. Tự động chỉ dùng kế hoạch đã khóa phạm vi (adapter Adobe/Autodesk, artifact/hosts chính xác hoặc Repair MSI hợp lệ); gỡ/cài lại chính thức luôn yêu cầu chọn thủ công, xác nhận và backup HMAC trước thay đổi.
- Quét Office/SFC/CIM có timeout, tiến trình dài có heartbeat/cảnh báo, và báo cáo HTML/PDF chỉ được dựng theo yêu cầu để tránh khóa giao diện.
- Offline toàn ứng dụng mặc định; Trung tâm quản lý giấy phép có công tắc mạng riêng fail-closed, bật/tắt lại được mà không ẩn chức năng hoặc xóa cấu hình; không telemetry, không auto-update.
- Đa ngôn ngữ `vi-VN`/`en-US` cho dashboard, menu, trung tâm doanh nghiệp, trình quản lý cục bộ Windows/Office và report shell; có English user guide.
- Catalog Lifecycle 1.1 cho Windows 10 22H2, Windows 11 23H2/24H2/25H2/26H1, Office 2021/2024 và Microsoft 365 channels; có cảnh báo tuổi 30/45 ngày và chế độ chỉ đọc cho phiên bản tương lai chưa xác minh.
- Catalog freshness gate 45 ngày và GitHub Actions kiểm tra hàng tuần.
- Catalog phần mềm `1.2.0.0`: 45 quy tắc, gồm 16 nhóm kỹ thuật CAD/CAE/BIM, mô phỏng, kết cấu, GIS, EDA, đo lường và rendering.
- Dry Run cho khắc phục lập danh sách mục tiêu/hành động/backup/restorability mà không gọi lệnh thay đổi; thực hiện thật luôn chọn và xác nhận lại.
- Data lifecycle schema 2.0 tách vùng ghi v4.6, migrate một lần qua staging đã kiểm tra SHA-256, commit có rollback và giữ v4.4/v4.5 nguyên vẹn.
- HTML/PDF hiện đại, CSS tự chứa, CSP, offline safety validation và stylesheet A4.
- Tài liệu kiến trúc, entry point, schema, safety, offline, localization và compatibility tách rõ.

v4.3 chọn nâng cấp WinForms thay vì WPF/WebView2 để giữ tương thích .NET Framework 4, Windows PowerShell 3+ và không phụ thuộc runtime/asset web.

## Thành phần nền

- `Tool-Kiem-Tra-v4.6-OneFile.cs` / `.manifest`: launcher nhúng payload phát hành.
- `Tool-ScanOptimization.ps1`: quét Office/tệp song song có giới hạn và giữ nguyên nguồn quét.
- `Giao-Dien.ps1`: dashboard và trung tâm hành động.
- `Tool-UiTheme.ps1`: palette Light/Dark dùng chung.
- `Tool-Localization.ps1`, `Tool-Strings.*.json`: localization schema 1.0.
- `Tool-OfflinePolicy.ps1`: Offline fail-closed schema 1.0.
- `Tool-SoftwareInventory.ps1`, `software-license-catalog-v1.0.json`: inventory schema 1.0, catalog 1.2 và bộ quét sâu/chấm điểm bằng chứng dùng chung cho mọi hãng.
- `Tool-DataLifecycle.ps1`: DataSchema 2.0, `ProducerVersion`, staging/verify/commit/rollback và chính sách chỉ đọc dữ liệu log/backup cũ.
- `Tool-Compatibility.ps1`, `compatibility-catalog-v1.0.json`: module compatibility schema 1.0, catalog schema 1.1 điều khiển bằng dữ liệu.
- `VERIFY-MICROSOFT-CATALOG-SOURCES.ps1`: đối chiếu nguồn Microsoft chính thức và tạo báo cáo CI máy đọc, không tự sửa catalog.
- `Tool-Capabilities.ps1`: capability schema 1.1.
- `Tool-ModuleContract.ps1`: 26 descriptor/23 entry point, gồm trình cập nhật danh mục online chỉ chạy sau khi người dùng đồng ý.
- `Tool-ReportSchema.ps1`: report schema 1.5.
- `Tool-ReportExport.ps1`: export schema 1.2 và HTML/PDF/JSON/XML; giao diện báo cáo dùng chung, ngắt trang an toàn và mở HTML mặc định.
- `Tool-SafetyPolicy.ps1`: safety policy schema 1.0.
- `Tool-PluginEngine.ps1`: plugin JSON khai báo chỉ đọc.
- `Tool-LicenseTimeline.ps1`: timeline DPAPI/HMAC/hash chain.
- `enterprise-license-manager.ps1`: Trung tâm doanh nghiệp giữ đủ ba chức năng, đồng bộ vi-VN/en-US và có công tắc mạng riêng bật/tắt được.
- `Tool-Enterprise*.ps1`: server/agent/envelope Enterprise; thao tác LAN chỉ chạy khi công tắc mạng doanh nghiệp đang bật.

## Tài liệu kỹ thuật

- `TECHNICAL-ARCHITECTURE-v4.6.md`
- `ENTRY-POINTS-v4.6.md`
- `MODULE-CONTRACT-v1.0.md`
- `REPORT-SCHEMA-v1.5.md`
- `SAFETY-POLICY-v1.0.md`
- `COMPATIBILITY-MATRIX-v4.6.md`
- `OFFLINE-AND-REPORTING-v4.6.md`
- `LOCALIZATION-v1.0.md`
- `SECURITY-HARDENING-v4.6.md`

## Build chưa ký

Mở Windows PowerShell 64-bit:

```powershell
Set-Location '<thu-muc-ma-nguon>'
.\BUILD.ps1 -OutputDirectory .\dist
```

Build tạo một EXE AnyCPU, tài liệu sidecar, `RELEASE-MANIFEST.json`, thông tin phát hành và `RELEASE-SHA256SUMS.txt`. Mỗi payload được chọn tự động giữa Deflate và raw theo kích thước thực tế; verifier giải nén rồi đối chiếu byte/SHA-256 trên cả CLR x64/x86.

## Build đã ký

Chứng thư trong Windows certificate store:

```powershell
.\BUILD.ps1 -OutputDirectory .\dist-signed `
  -SigningCertificateThumbprint '<THUMBPRINT>' `
  -SigningCertificateStore LocalMachine `
  -TimestampServer 'http://timestamp.digicert.com' `
  -RequireAuthenticode
```

PFX:

```powershell
$password = Read-Host 'Mật khẩu PFX' -AsSecureString
.\BUILD.ps1 -OutputDirectory .\dist-signed `
  -SigningPfxPath 'C:\secure\codesign.pfx' `
  -SigningPfxPassword $password `
  -TimestampServer 'http://timestamp.digicert.com' `
  -RequireAuthenticode
```

Không đưa PFX/private key/mật khẩu vào repo. `-RequireAuthenticode` làm build thất bại nếu chữ ký không `Valid`.

## Verifier

```powershell
.\VERIFY-DASHBOARD.ps1 -SourceDirectory .
.\VERIFY-COMPATIBILITY.ps1 -SourceDirectory .
.\VERIFY-OFFLINE-I18N.ps1 -SourceDirectory .
.\VERIFY-MODULE-CONTRACT.ps1 -SourceDirectory . -ExpectedArchitecture x64
.\VERIFY-REPORT-SCHEMA.ps1 -SourceDirectory .
.\VERIFY-SAFETY-REGRESSIONS.ps1 -SourceDirectory .
.\VERIFY-EXTENSIONS.ps1 -SourceDirectory .
.\VERIFY-ENTERPRISE.ps1 -SourceDirectory .
.\VERIFY-DATA-LIFECYCLE.ps1 -SourceDirectory .
.\VERIFY-RELEASE.ps1 -SourceDirectory . -DistributionDirectory .\dist
```

Build đã ký:

```powershell
.\VERIFY-AUTHENTICODE.ps1 `
  -FilePath .\dist-signed\Tool-Kiem-Tra-v4.6.exe `
  -RequireTimestamp
```

## Dữ liệu cục bộ

- log: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\logs`
- backup: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\backups`
- plugin: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\plugins`
- timeline: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\timeline`
- enterprise: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6\enterprise`
- log/backup cũ v4.4/v4.5: chỉ được tham chiếu đọc; không ghi chung với v4.6.
- PDF profile tạm: `%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf`
- user preferences: `%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra`

ProgramData root từ chối reparse point và chỉ Administrators/SYSTEM có quyền ghi. `data-state.json` ghi DataSchema/ProducerVersion và kết quả migration; lỗi migration rollback, không tạo trạng thái hoàn tất một phần. PDF/user preference dùng vùng user hiện tại.

## Phạm vi tương thích

- Windows 7 SP1 trở lên ở lớp runtime cũ; catalog hiện theo dõi Windows 10 22H2 và Windows 11 23H2/24H2/25H2/26H1.
- Office 2021/LTSC 2021, Office 2024/LTSC 2024 và Microsoft 365 Apps Click-to-Run.
- Build/Product ID mới hơn catalog được đánh dấu `ReadOnlyManualReview`, không bị coi là lỗi giả hoặc tự động khắc phục.
- PDF phụ thuộc Edge/Chrome/Word; thiếu engine không ảnh hưởng HTML/JSON/XML.

## Giới hạn

- Offline mode là policy ứng dụng, không phải firewall hệ điều hành.
- Kết luận kỹ thuật không thay hóa đơn/hợp đồng/tư vấn pháp lý.
- EXE chỉ được coi là đã ký khi Authenticode trả `Valid`.
- CFG native không được tuyên bố cho launcher managed IL.
