# Localization schema 1.0

v4.3 cung cấp hai culture:

- `vi-VN` — mặc định;
- `en-US` — dashboard, menu chính, Mục 8, trình quản lý cục bộ Windows/Office, trạng thái mạng/Offline và phần trình bày báo cáo.

Nguồn chuỗi:

- `Tool-Strings.vi-VN.json`;
- `Tool-Strings.en-US.json`;
- loader `Tool-Localization.ps1`.

## Quy tắc key

Key dùng namespace ổn định:

- `app.*`: shell và command;
- `dashboard.*`: card/status;
- `menu.<n>.*`: tên và mô tả chức năng;
- `status.*`, `progress.*`;
- `enterprise.*`: toàn bộ cửa sổ, tab, trạng thái và xác nhận của Mục 8;
- `localLicense.*`: trình quản lý cục bộ Windows/Office;
- `integrity.*`, `about.*`: bảo vệ thao tác và cửa sổ giới thiệu;
- `report.*`: tiêu đề, metadata và privacy/offline labels.

Catalog phải là JSON object phẳng, UTF-8, tối đa 512 KiB. Giá trị không phải chuỗi hoặc key trống bị từ chối.

## Fallback

1. culture được yêu cầu;
2. `vi-VN`;
3. chính key nếu cả hai catalog đều thiếu.

Nhờ vậy thiếu một bản dịch không làm dashboard dừng chạy và vẫn nhìn thấy key cần bổ sung.

## Lưu lựa chọn

Culture được lưu theo user trong:

`%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\localization-settings.json`

Environment `TOOL_UI_CULTURE` có ưu tiên cao hơn và được truyền sang tiến trình con. Tệp lỗi không được thực thi và không ảnh hưởng integrity payload.

## Thêm ngôn ngữ

1. sao chép catalog chuẩn thành `Tool-Strings.<culture>.json`;
2. dịch đủ toàn bộ key, giữ placeholder `{0}`, `{1}`;
3. thêm culture vào `ToolLocalizationSupportedCultures`;
4. thêm lựa chọn UI;
5. thêm payload/integrity/build manifest;
6. mở rộng `VERIFY-OFFLINE-I18N.ps1`;
7. kiểm tra layout ở 100%, 150% và 200% DPI.

## Phạm vi v4.3.0.8

Dashboard/menu chính, cửa sổ Mục 8, trình quản lý cục bộ Windows/Office, các xác nhận/trạng thái/lỗi của Mục 8 và report shell dùng catalog đồng bộ. Verifier yêu cầu catalog vi-VN/en-US có cùng tập key và chạy smoke test Mục 8 ở cả Light/Dark, mạng bật/tắt.

Các báo cáo kỹ thuật và dữ liệu nghiệp vụ có thể giữ nguyên tên trường/lệnh Windows do đó là tên API hoặc output gốc của hệ điều hành; phần điều khiển và thông báo dành cho người dùng vẫn theo culture đã chọn.
