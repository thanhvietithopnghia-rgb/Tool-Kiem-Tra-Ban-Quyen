# Tool-Kiem-Tra v4.3 — mã nguồn

Release `4.3.0.7 Enterprise`, build `2026.07.31`. Người dùng cuối chạy một tệp `Tool-Kiem-Tra-v4.3.exe`; launcher AnyCPU tự chọn CLR/Windows PowerShell native phù hợp.

## Điểm mới v4.3

- Dashboard schema 2.0: Modern WinForms 1040 × 820, card Windows/Office, tile có mô tả, responsive DPI và dark mode toàn công cụ; Mục 8 có màu nhận diện riêng.
- Mục 6 dùng tên rõ nghĩa “Khắc phục KMS/Activator, đưa về trạng thái gốc” nhưng giữ nguyên luồng an toàn hiện có.
- Offline toàn ứng dụng mặc định; Mục 8 có công tắc mạng riêng fail-closed, bật/tắt lại được mà không ẩn chức năng hoặc xóa cấu hình; không telemetry, không auto-update.
- Đa ngôn ngữ `vi-VN`/`en-US` cho dashboard, menu, Mục 8, trình quản lý cục bộ Windows/Office và report shell; có English user guide.
- Catalog cục bộ cho Windows 11 24H2/25H2/26H1, Office 2024/LTSC 2024 và Microsoft 365 channels.
- Catalog freshness gate 45 ngày và GitHub Actions kiểm tra hàng tuần.
- HTML/PDF hiện đại, CSS tự chứa, CSP, offline safety validation và stylesheet A4.
- Tài liệu kiến trúc, entry point, schema, safety, offline, localization và compatibility tách rõ.

v4.3 chọn nâng cấp WinForms thay vì WPF/WebView2 để giữ tương thích .NET Framework 4, Windows PowerShell 3+ và không phụ thuộc runtime/asset web.

## Thành phần nền

- `Tool-Kiem-Tra-v4.3-OneFile.cs` / `.manifest`: launcher nhúng 39 payload.
- `Giao-Dien.ps1`: dashboard và trung tâm hành động.
- `Tool-UiTheme.ps1`: palette Light/Dark dùng chung.
- `Tool-Localization.ps1`, `Tool-Strings.*.json`: localization schema 1.0.
- `Tool-OfflinePolicy.ps1`: Offline fail-closed schema 1.0.
- `Tool-Compatibility.ps1`, `compatibility-catalog-v1.0.json`: compatibility schema 1.0.
- `Tool-Capabilities.ps1`: capability schema 1.1.
- `Tool-ModuleContract.ps1`: 25 descriptor/22 entry point.
- `Tool-ReportSchema.ps1`: report schema 1.5.
- `Tool-ReportExport.ps1`: export schema 1.2 và HTML/PDF/JSON/XML; giao diện báo cáo dùng chung, ngắt trang an toàn và mở HTML mặc định.
- `Tool-SafetyPolicy.ps1`: safety policy schema 1.0.
- `Tool-PluginEngine.ps1`: plugin JSON khai báo chỉ đọc.
- `Tool-LicenseTimeline.ps1`: timeline DPAPI/HMAC/hash chain.
- `enterprise-license-manager.ps1`: Mục 8 giữ đủ ba chức năng, đồng bộ vi-VN/en-US và có công tắc mạng riêng bật/tắt được.
- `Tool-Enterprise*.ps1`: server/agent/envelope Enterprise; thao tác LAN chỉ chạy khi công tắc mạng Mục 8 đang bật.

## Tài liệu kỹ thuật

- `TECHNICAL-ARCHITECTURE-v4.3.md`
- `ENTRY-POINTS-v4.3.md`
- `MODULE-CONTRACT-v1.0.md`
- `REPORT-SCHEMA-v1.5.md`
- `SAFETY-POLICY-v1.0.md`
- `COMPATIBILITY-MATRIX-v4.3.md`
- `OFFLINE-AND-REPORTING-v4.3.md`
- `LOCALIZATION-v1.0.md`
- `SECURITY-HARDENING-v4.3.md`

## Build chưa ký

Mở Windows PowerShell 64-bit:

```powershell
Set-Location '<thu-muc-ma-nguon>'
.\BUILD.ps1 -OutputDirectory .\dist
```

Build tạo một EXE AnyCPU, tài liệu sidecar, `RELEASE-MANIFEST.json`, thông tin phát hành và `RELEASE-SHA256SUMS.txt`. Verifier chạy trên CLR x64/x86.

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
.\VERIFY-RELEASE.ps1 -SourceDirectory . -DistributionDirectory .\dist
```

Build đã ký:

```powershell
.\VERIFY-AUTHENTICODE.ps1 `
  -FilePath .\dist-signed\Tool-Kiem-Tra-v4.3.exe `
  -RequireTimestamp
```

## Dữ liệu cục bộ

- log: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\logs`
- backup: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\backups`
- plugin: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\plugins`
- timeline: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\timeline`
- enterprise: `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.3\enterprise`
- PDF profile tạm: `%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf`
- user preferences: `%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra`

ProgramData root từ chối reparse point và chỉ Administrators/SYSTEM có quyền ghi. PDF/user preference dùng vùng user hiện tại.

## Phạm vi tương thích

- Windows 7 SP1 trở lên ở lớp runtime cũ; v4.3 tập trung xác minh Windows 11 24H2/25H2/26H1.
- Office 2024/LTSC 2024 và Microsoft 365 Apps Click-to-Run.
- Build mới hơn catalog được đánh dấu cần rà soát, không bị coi là lỗi giả.
- PDF phụ thuộc Edge/Chrome/Word; thiếu engine không ảnh hưởng HTML/JSON/XML.

## Giới hạn

- Offline mode là policy ứng dụng, không phải firewall hệ điều hành.
- Kết luận kỹ thuật không thay hóa đơn/hợp đồng/tư vấn pháp lý.
- EXE chỉ được coi là đã ký khi Authenticode trả `Valid`.
- CFG native không được tuyên bố cho launcher managed IL.
