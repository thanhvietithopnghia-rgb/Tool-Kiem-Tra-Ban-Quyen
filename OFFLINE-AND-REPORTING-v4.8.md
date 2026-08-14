# Offline mode, Trợ lý Tool và báo cáo v4.8

## Chính sách mặc định

v4.8 luôn khởi động **Offline** ở mỗi tiến trình mới. Lựa chọn Online chỉ có hiệu lực trong phiên hiện tại; đóng rồi mở lại ứng dụng sẽ trở về Offline, không phụ thuộc thiết lập của phiên trước.

Trạng thái được hiển thị trên dashboard. Chuyển sang “Cho phép mạng” cần xác nhận rõ ràng và được ghi audit.

## Những gì bị chặn

Trong Offline mode, tool chặn:

- Internet;
- LAN;
- loopback/network listener;
- tiến trình Enterprise server/agent khi công tắc mạng riêng của Mục 8 đang tắt;
- mở URL hỗ trợ/release;
- mọi telemetry, kiểm tra phiên bản và tải cập nhật ứng dụng.

Khi người dùng chủ động cho phép Online, ba luồng Internet mới có thể chạy: `software.catalog.update` tải catalog sau xác nhận riêng; `application.update.check` chỉ đọc manifest phiên bản GitHub; Trợ lý Tool chỉ tải JSON tri thức và chữ ký CMS rời từ hai URL GitHub cố định. Cả ba fail-closed khi Offline và không tải inventory, đường dẫn, khóa, token, báo cáo hay nội dung trò chuyện lên mạng. Enterprise UI là `LocalOnly`; server và agent khai báo `NetworkScope=Lan` và cần công tắc mạng riêng của Mục 8.

## Những gì vẫn hoạt động

- kiểm kê phần cứng, Windows, Office và phần mềm;
- quét sâu cục bộ có giới hạn cho từng ứng dụng bằng nhiều EXE/DLL, chữ ký, hash xấu đã biết và dấu vết hệ thống tương quan;
- nhận diện Windows 11/Office bằng catalog cục bộ;
- đối chiếu phần mềm bằng catalog đi kèm hoặc bản cache online đã xác minh;
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

## Kết nối online để đối chiếu phần mềm

- Không tự chạy và không phụ thuộc công tắc LAN của Mục 8.
- Mỗi lần chạy đều hiển thị nội dung sẽ tải, dữ liệu không gửi đi và yêu cầu xác nhận Yes/No; mặc định là No.
- Chỉ chấp nhận HTTPS, host `raw.githubusercontent.com`, phương thức GET, không redirect và tối đa 2 MiB.
- Catalog tải về phải qua kiểm tra schema/quy tắc trước khi ghi cache. Nếu tải lỗi, người dùng có thể tiếp tục quét bằng catalog cục bộ/cache hợp lệ.
- Catalog cache khác catalog tích hợp không được tạo bằng chứng hash/tên activator mang tính quyết định; không có kết nối mạng nào được dùng để tải inventory lên hoặc hỏi trạng thái giấy phép tài khoản.

## Kiểm tra và cài phiên bản mới

- Chỉ kiểm tra manifest khi Online đã được người dùng cho phép trong phiên hiện tại. Lần mở tiếp theo trở lại Offline; chuyển về Offline hủy kiểm tra đang chờ và không tải gì.
- Khi có bản mới, Tool chỉ hiển thị **Cập nhật ngay**, **Để sau**, **Bỏ qua lần này**. Không lựa chọn nào được tự giả định.
- **Để sau** hỏi lại sau tác vụ kế tiếp hoặc khoảng 2 giờ. **Bỏ qua lần này** chỉ áp dụng cho phiên ứng dụng hiện tại; lần mở sau vẫn Offline cho tới khi người dùng chủ động bật Online.
- Chỉ **Cập nhật ngay** tải EXE từ asset GitHub HTTPS đúng repository/tag. Tệp phải khớp kích thước, SHA-256 và signer Authenticode nếu manifest yêu cầu trước khi thay thế.
- Bản EXE cũ được backup; nếu bản mới thoát trong lúc kiểm tra khởi động, updater khôi phục và mở lại bản cũ.
- Không có dịch vụ nền, telemetry, silent update hoặc gửi dữ liệu máy. Manifest `update-manifest-v1.json` chỉ chứa phiên bản, mô tả, URL, kích thước, SHA-256 và chính sách chữ ký.

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

Từ export schema 1.4, HTML và PDF dùng cùng dữ liệu nhưng khác mức trình bày. HTML là tổng quan, giữ cấu hình chính, kết luận, cảnh báo, ứng dụng chính và nút mở đúng PDF. PDF là bản chi tiết có toàn bộ bảng/bằng chứng cùng phụ lục phần mềm hệ thống; bảng rộng được tách, nội dung dài mở đầy đủ khi in và ngắt trang A4 an toàn. Mọi lượt xuất dùng chung `Desktop\BaoCao-Tool-Kiem-Tra`, không tạo thư mục con; tên tệp có timestamp mili-giây và sau khi hoàn tất chỉ HTML tổng quan được mở.

Kho Trợ lý schema `1.1`, knowledge `1.3.1` tách dữ liệu tăng thêm khỏi EXE. Cache chỉ được nhận khi JSON khớp chữ ký CMS SHA-256 của chứng thư nhà phát hành đã ghim, đúng `Scope=Tool-Kiem-Tra`, kích thước tối đa 2 MiB và tương thích theo `ToolVersionMin`/`ToolVersionMax`; phiên bản bằng hoặc thấp hơn không thay cache hiện có. Bản cache hợp lệ trước được giữ làm dự phòng, còn cache hỏng/sai chữ ký bị bỏ qua để dùng bản nhúng. Mỗi máy kết hợp tri thức chuẩn với HDSD, ngữ cảnh lượt trước và báo cáo cục bộ của chính máy; hàng rào phạm vi chạy trước định tuyến nên ngay cả từ khóa điểm cao cũng không mở chủ đề ngoài Tool.

HTML cân năm thẻ kết quả nhanh trên màn hình rộng và đặt Mức xác minh/Hướng xử lý trong các ô con riêng. Chân PDF được chia thành hai hàng để giữ đủ tên công cụ và thông tin tác giả/hỗ trợ trên khổ A4.

## PDF

Tool thử lần lượt:

1. Microsoft Edge headless;
2. Google Chrome headless;
3. Microsoft Word automation.

Edge/Chrome nhận cờ tắt background networking, sync, domain reliability và metrics; DNS resolver được map về `0.0.0.0`. Profile tạm nằm dưới `%LOCALAPPDATA%\Temp\ThanhViet-Tool-Kiem-Tra\pdf`, chỉ user hiện tại/SYSTEM truy cập và được dọn bằng retry có giới hạn.

Nếu không có engine, tool báo rõ lỗi PDF nhưng vẫn giữ HTML/JSON/XML và SHA-256 manifest.

## Gói báo cáo

Mỗi package có:

- HTML tổng quan kèm hướng dẫn mở bản đầy đủ;
- PDF chi tiết nếu engine khả dụng;
- JSON theo report schema 1.5;
- XML kiểu hóa;
- `*-SHA256SUMS.txt`.

Tên thư mục package gồm loại báo cáo và timestamp. Các artefact của một lượt xuất không bị rải trực tiếp trên Desktop và PDF/JSON/XML không tự mở.

Tất cả định dạng dùng cùng dữ liệu nguồn. Consumer phải xác minh SHA-256 và schema trước khi nhập.

## Quyền riêng tư

- Không thu thập mật khẩu.
- Không ghi product key đầy đủ vào báo cáo/log.
- Chế độ redact che tên máy, user, profile path, địa chỉ mạng và KMS host.
- Không tự upload hoặc gửi report.
- **Kết nối online** không gửi danh sách phần mềm, tên máy, đường dẫn, product key, token hoặc bằng chứng cục bộ.
- Export chỉ ghi vào thư mục người dùng chọn.

## Phạm vi bảo đảm Offline

Offline mode bảo đảm code của Tool-Kiem-Tra không chủ động tạo kết nối mạng. Nó không thay firewall và không thể kiểm soát một dịch vụ Windows, Office, antivirus hoặc PDF engine đã chạy độc lập ngoài tiến trình tool. Với môi trường yêu cầu cách ly tuyệt đối, vẫn nên ngắt adapter mạng hoặc áp policy firewall/WDAC của tổ chức.
