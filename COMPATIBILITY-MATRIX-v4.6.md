# Ma trận tương thích v4.6

Mốc rà soát: **2026-08-05 UTC**. Nguồn máy đọc: `compatibility-catalog-v1.0.json`, schema catalog `1.1`, phiên bản `1.1.0.0`.

Catalog Microsoft này tách biệt với `software-license-catalog-v1.0.json` phiên bản `1.3.0.0`. Catalogue phần mềm có 73 quy tắc sản phẩm duy nhất, gồm các nhóm CAD/CAE/BIM, mô phỏng, kết cấu, GIS, EDA, đo lường, rendering và nhiều ứng dụng phổ biến. Các quy tắc bổ sung nhận diện signer/domain/tệp lõi/artifact nhưng không hạ ngưỡng kết luận fail-closed của engine quét sâu; `HashMismatch` đơn lẻ chỉ tạo `IntegrityCompromised`.

- Từ 30 ngày: Dashboard hiện **Catalog Age Warning**.
- Quá 45 ngày: catalog chuyển `Stale`, tác vụ phụ thuộc phiên bản chuyển sang chỉ đọc và build phát hành thất bại.
- Runtime không tự kiểm tra mạng. Việc đối chiếu nguồn Microsoft chỉ chạy trong workflow bảo trì hoặc khi maintainer chủ động gọi verifier.

## Windows

| Release | Build nền | Revision đã biết | Trạng thái catalog |
| --- | ---: | ---: | --- |
| Windows 10 22H2 | 19045 | 7548 | End of support hoặc ESU |
| Windows 11 23H2 | 22631 | 7376 | Còn hỗ trợ tùy edition |
| Windows 11 24H2 | 26100 | 8973 | Supported |
| Windows 11 25H2 | 26200 | 8973 | Supported |
| Windows 11 26H1 | 28000 | 2608 | Supported; phạm vi thiết bị mới |

Nguồn:

- [Windows 10 release information](https://learn.microsoft.com/en-us/windows/release-health/release-information)
- [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)

Logic không khóa cứng revision như điều kiện khởi động:

- thấp hơn catalog → `OlderThanCatalog`;
- bằng catalog → `MatchesCatalog`;
- cao hơn catalog → `AheadOfCatalog` và khóa tác vụ tự động nhạy phiên bản;
- build lớn hơn mọi build đã biết → `FutureReleaseUnverified`;
- build/DisplayVersion chưa phân loại → `ReadOnlyManualReview`.

Nhờ đó Windows mới không bị tuyên bố “không hỗ trợ” giả, nhưng cũng không được xem là đã xác minh khi catalog chưa cập nhật.

## Office Click-to-Run

Catalog dùng `OfficeProductFamilies` để ánh xạ nhóm sản phẩm bằng dữ liệu thay vì hard-code trong thuật toán:

- Office 2021 / LTSC 2021;
- Office 2024 / LTSC 2024;
- Microsoft 365 Apps.

Maintainer có thể bổ sung một nhóm Office tương lai và thuộc tính Product ID mới trong JSON mà không sửa hàm phân loại. Product ID chưa biết được ghi `Office Click-to-Run (unverified product IDs)` và chuyển sang rà soát thủ công.

Nguồn:

- [Office LTSC 2024 overview](https://learn.microsoft.com/en-us/office/ltsc/2024/overview)
- [Product IDs supported by the Office Deployment Tool](https://learn.microsoft.com/en-us/microsoft-365/troubleshoot/installation/product-ids-supported-office-deployment-click-to-run)

Nhận diện family không đồng nghĩa với xác nhận quyền sở hữu giấy phép; trạng thái kích hoạt vẫn phải lấy từ OSPP/Software Protection và đối chiếu hồ sơ cấp phép.

## Microsoft 365 Apps

| Channel | GUID | Mốc catalog |
| --- | --- | --- |
| Current Channel | `492350f6-3a01-4f97-b9c0-c7c6ddf67d60` | `2607` · `16.0.20228.20158` · 2026-08-04 |
| Monthly Enterprise Channel | `55336b82-a18d-4dd6-b5f6-9e5095c314a6` | `2606` · `16.0.20131.20152` · 2026-07-14 |
| Semi-Annual Enterprise Channel | `7ffbc6bf-bc32-4f92-8982-f9dd17fd3114` | `2606` · `16.0.20131.20150` · 2026-07-14 |

Nguồn:

- [Microsoft 365 Apps update history](https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft365-apps-by-date)
- [Overview of update channels](https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels)

Tenant có channel riêng, policy quản trị hoặc GUID chưa biết được ghi `Unknown / managed`; tool không tự kết luận lỗi.

## Tương thích nền

- Runtime: .NET Framework 4/CLR v4, Windows PowerShell 3+.
- Kiến trúc: một EXE AnyCPU; x64 trên Windows 64-bit, x86 trên Windows 32-bit.
- Fallback: CIM→WMI và ScheduledTasks→`schtasks.exe`.
- PDF: Edge, Chrome hoặc Word; không có engine thì vẫn xuất HTML/JSON/XML.

## Quy trình cập nhật catalog

`.github/workflows/compatibility-review.yml` chạy hàng tuần và khi thay đổi catalog:

1. kiểm tra schema, tuổi, nguồn HTTPS và fixture cục bộ;
2. đối chiếu 6 trang Microsoft Learn bằng `VERIFY-MICROSOFT-CATALOG-SOURCES.ps1`;
3. phát hiện revision Windows hoặc channel Microsoft 365 mới;
4. xuất `microsoft-catalog-review.json` làm bằng chứng CI;
5. dừng workflow nếu cần maintainer rà soát.

Workflow **không tự sửa hoặc tự xuất bản catalog**. Khi Microsoft thay đổi dữ liệu, maintainer phải đối chiếu nguồn chính thức, cập nhật JSON/fixture, chạy verifier và thử trên VM đại diện trước khi tuyên bố đã xác minh.

## Mức chứng minh

`Supported` trong catalog chỉ có nghĩa logic nhận diện nằm trong phạm vi kiểm thử. Nó không thay cho chứng nhận Microsoft, không chứng minh mọi edition/policy/driver/tenant và không chứng minh quyền sở hữu giấy phép.
