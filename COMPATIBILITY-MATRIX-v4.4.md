# Ma trận tương thích v4.4

Mốc rà soát: **2026-07-30 UTC**. Nguồn máy đọc: `compatibility-catalog-v1.0.json`. Catalog có thời hạn rà soát tối đa 45 ngày; quá hạn thì `VERIFY-COMPATIBILITY.ps1` và build phát hành thất bại.

## Windows 11

| Release | Build nền | Revision đã biết khi rà soát | Trạng thái trong tool |
| --- | ---: | ---: | --- |
| Windows 11 24H2 | 26100 | 8875 | Nhận diện và so sánh revision |
| Windows 11 25H2 | 26200 | 8875 | Nhận diện và so sánh revision |
| Windows 11 26H1 | 28000 | 2525 | Nhận diện và so sánh revision |

Nguồn: [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information).

Logic không khóa cứng revision như một điều kiện chạy:

- thấp hơn catalog → `OlderThanCatalog`;
- bằng catalog → `MatchesCatalog`;
- cao hơn catalog → `AheadOfCatalog`;
- build Windows 11 chưa có trong catalog → `ManualReview`.

Do đó máy đã cập nhật mới hơn không bị báo “không hỗ trợ” giả; nó được đánh dấu cần rà soát.

## Office 2024 / LTSC 2024

v4.4 nhận diện các ProductReleaseId Retail/Volume của:

- Microsoft 365 Apps và Office 2024 ProPlus/Standard;
- Project 2024;
- Visio 2024;
- Access, Excel, Word, PowerPoint, Outlook 2024;
- Skype for Business 2024 Volume.

Nguồn:

- [Office LTSC 2024 overview](https://learn.microsoft.com/en-us/office/ltsc/2024/overview)
- [Product IDs supported by the Office Deployment Tool](https://learn.microsoft.com/en-us/microsoft-365/troubleshoot/installation/product-ids-supported-office-deployment-click-to-run)

Tool đọc cả registry view 64-bit và WOW6432Node. Nhận diện family không đồng nghĩa với xác nhận giấy phép hợp pháp; trạng thái kích hoạt vẫn đến từ OSPP/Software Protection.

## Microsoft 365 Apps

| Channel | GUID | Mốc catalog ngày 2026-07-14 |
| --- | --- | --- |
| Current Channel | `492350f6-3a01-4f97-b9c0-c7c6ddf67d60` | `16.0.20131.20154` |
| Monthly Enterprise Channel | `55336b82-a18d-4dd6-b5f6-9e5095c314a6` | `16.0.20131.20152` |
| Semi-Annual Enterprise Channel | `7ffbc6bf-bc32-4f92-8982-f9dd17fd3114` | `16.0.20131.20150` |

Nguồn:

- [Microsoft 365 Apps update history](https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft365-apps-by-date)
- [Overview of update channels](https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels)

Tenant có channel riêng, policy quản trị hoặc GUID chưa biết được ghi `Unknown / managed`, không tự kết luận lỗi.

## Tương thích nền

- Runtime: .NET Framework 4/CLR v4, Windows PowerShell 3+.
- Kiến trúc: một EXE AnyCPU; x64 trên Windows 64-bit, x86 trên Windows 32-bit.
- Fallback: CIM→WMI và ScheduledTasks→`schtasks.exe`.
- PDF: Edge, Chrome hoặc Word; không có engine thì vẫn xuất HTML/JSON/XML.

## Kiểm tra liên tục

`.github/workflows/compatibility-review.yml` chạy hàng tuần và khi thay đổi catalog:

1. parse toàn bộ catalog;
2. chạy fixture 24H2/25H2/build tương lai;
3. kiểm tra Office 2024, Microsoft 365 và channel GUID;
4. kiểm tra tuổi catalog;
5. kiểm tra các URL nguồn Microsoft còn truy cập được.

Workflow không tự sửa số build. Khi Microsoft cập nhật release/channel, maintainer phải:

1. đối chiếu nguồn chính thức;
2. cập nhật JSON và `ReviewedAtUtc`;
3. thêm/sửa fixture;
4. chạy verifier;
5. thử trên VM/máy thật đại diện trước khi tuyên bố đã xác minh.

## Mức chứng minh

`Supported` trong catalog nghĩa là logic nhận diện và các đường code tương ứng đã được đưa vào phạm vi kiểm thử. Nó không thay cho chứng nhận Microsoft và không chứng minh mọi tổ hợp edition, policy, driver hoặc tenant.
