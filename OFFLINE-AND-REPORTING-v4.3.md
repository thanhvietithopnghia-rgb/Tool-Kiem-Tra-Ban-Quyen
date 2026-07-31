# Offline mode và báo cáo v4.3

## Chính sách mặc định

v4.3 khởi động **Offline** nếu:

- chưa có thiết lập;
- tệp thiết lập không đọc được hoặc sai định dạng;
- launcher không nhận giá trị `TOOL_OFFLINE_MODE` hợp lệ.

Trạng thái được hiển thị trên dashboard. Chuyển sang “Cho phép mạng” cần xác nhận rõ ràng và được ghi audit.

## Những gì bị chặn

Trong Offline mode, tool chặn:

- Internet;
- LAN;
- loopback/network listener;
- tiến trình Enterprise server/agent khi công tắc mạng riêng của Mục 8 đang tắt;
- mở URL hỗ trợ/release;
- mọi telemetry và kiểm tra cập nhật tự động.

Không có module nào cần Internet. Enterprise UI là `LocalOnly`; server và agent khai báo `NetworkScope=Lan` và cần công tắc mạng riêng của Mục 8.

## Những gì vẫn hoạt động

- kiểm kê phần cứng, Windows, Office và phần mềm;
- nhận diện Windows 11/Office bằng catalog cục bộ;
- quét tuân thủ, deep scan, forensics;
- backup/restore và xử lý đã xác nhận;
- OEM inspect/apply đã xác nhận;
- quản lý giấy phép cục bộ;
- mở Mục 8 và xem đủ ba chức năng khi công tắc mạng riêng đang tắt;
- certificate/plugin/timeline audit;
- xuất HTML/PDF/JSON/XML.

## Công tắc mạng riêng của Mục 8

Mục 8 dùng preference riêng, mặc định `Allowed=false`, độc lập với nút Offline toàn ứng dụng:

- **Online** bật các thao tác LAN của server/agent sau xác nhận;
- nút đổi thành **Offline** ngay sau khi bật;
- chọn lại sẽ lưu `Allowed=false`, yêu cầu dừng server/agent do cửa sổ hiện tại khởi động và giữ nguyên cấu hình;
- ba chức năng Quản lý cục bộ, Máy chủ và Máy trạm không bị ẩn hoặc xóa ở bất kỳ trạng thái nào.

## HTML

HTML được tạo tự chứa:

- UTF-8;
- CSS nhúng, không CDN/web font;
- không script, iframe hoặc stylesheet từ xa;
- CSP `default-src 'none'`;
- ảnh chỉ cho phép `data:`;
- responsive screen layout, dark preview và print A4;
- bảng có header lặp khi in, hạn chế tách dòng/card giữa trang.

`Test-ToolHtmlOfflineSafe` từ chối HTML có `http(s)`, protocol-relative URL, remote `src`/`href`, `@import`, script hoặc iframe trước khi PDF/package được coi là hợp lệ.

Từ export schema 1.2, mọi báo cáo dành cho người đọc dùng chung giao diện chuyên nghiệp và ngắt trang an toàn. HTML/PDF được lưu trực tiếp trên Desktop; HTML luôn được mở bằng trình duyệt mặc định sau khi hoàn tất.

## PDF

Tool thử lần lượt:

1. Microsoft Edge headless;
2. Google Chrome headless;
3. Microsoft Word automation.

Edge/Chrome nhận cờ tắt background networking, sync, domain reliability và metrics; DNS resolver được map về `0.0.0.0`. Profile tạm nằm dưới `%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf`, chỉ user hiện tại/SYSTEM truy cập và được dọn bằng retry có giới hạn.

Nếu không có engine, tool báo rõ lỗi PDF nhưng vẫn giữ HTML/JSON/XML và SHA-256 manifest.

## Gói báo cáo

Mỗi package có:

- HTML trình bày;
- PDF nếu engine khả dụng;
- JSON theo report schema 1.5;
- XML kiểu hóa;
- `*-SHA256SUMS.txt`.

Tất cả định dạng dùng cùng dữ liệu nguồn. Consumer phải xác minh SHA-256 và schema trước khi nhập.

## Quyền riêng tư

- Không thu thập mật khẩu.
- Không ghi product key đầy đủ vào báo cáo/log.
- Chế độ redact che tên máy, user, profile path, địa chỉ mạng và KMS host.
- Không tự upload hoặc gửi report.
- Export chỉ ghi vào thư mục người dùng chọn.

## Phạm vi bảo đảm Offline

Offline mode bảo đảm code của Tool-Kiem-Tra không chủ động tạo kết nối mạng. Nó không thay firewall và không thể kiểm soát một dịch vụ Windows, Office, antivirus hoặc PDF engine đã chạy độc lập ngoài tiến trình tool. Với môi trường yêu cầu cách ly tuyệt đối, vẫn nên ngắt adapter mạng hoặc áp policy firewall/WDAC của tổ chức.
