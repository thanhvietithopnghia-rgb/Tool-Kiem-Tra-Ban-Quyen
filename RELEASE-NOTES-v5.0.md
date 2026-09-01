# Tool Kiểm Tra v5.0

Ngày build kỹ thuật: `2026-09-01`
Ngày phát hành hiện tại: `2026-09-01`
ProductVersion/FileVersion: `5.0.0.0`
Trạng thái: `ManagedSigned`; launcher ghim đúng signer và certificate SHA-256

## Giới thiệu

Tool Kiểm Tra v5.0 hỗ trợ kiểm tra cấu hình máy, trạng thái bản quyền Windows, Microsoft Office và phần mềm khác theo cách thận trọng, minh bạch và ưu tiên an toàn. Tool hoạt động Offline theo mặc định, không tự tải inventory hoặc báo cáo lên Internet và chỉ dùng Online khi người dùng chủ động cho phép.

## Nội dung chính của v5.0

- Ba mức quét Quick, Standard và Deep với ngân sách và phạm vi an toàn.
- Danh sách phần mềm cần xem xét được sắp xếp **Cao → Trung bình → Thấp**.
- Phần mềm trả phí, thuê bao hoặc dùng thử chưa xác minh luôn được nhắc kiểm tra giấy phép, không tự kết luận vi phạm.
- Thành phần hệ thống, runtime, codec, extension nền, trình cài đặt, add-in, gói hỗ trợ và trình gỡ driver chỉ nằm trong kiểm kê/báo cáo, không xuất hiện ở cửa sổ xử lý.
- Catalog tích hợp và Online `1.6.3.0` có 94 nhóm sản phẩm, được ký CMS, kiểm tra schema và chống hạ phiên bản.
- Khắc phục tách riêng Windows, Microsoft Office và phần mềm khác; bắt buộc xem trước, Dry Run, backup, xác nhận và hậu kiểm.
- Báo cáo HTML/PDF/JSON/XML được tạo cục bộ và che định danh phần cứng trong bản chia sẻ mặc định.
- Hỗ trợ giao diện responsive, DPI cao, Light/Dark, timeline, plugin khai báo có chữ ký, CLI headless và quản trị nhiều máy.
- Trung tâm **Việc cần xử lý** gom kết quả theo Cao → Trung bình → Thấp và mở đúng thao tác liên quan.
- Tìm kiếm, lọc và so sánh với lần quét trước cùng chế độ: Mới xuất hiện, Đã hết hoặc Không đổi.
- Trung tâm sao lưu–khôi phục kiểm tra HMAC/SHA-256 trước khi cho phép khôi phục.
- Gói hỗ trợ chỉ nhận báo cáo đã che dữ liệu, tạo bản xem trước và loại thông tin nhạy cảm khỏi log chia sẻ.
- Điều hướng chức năng tách rõ **Trở về** và **Đóng**: Trở về quay đúng bước trước và giữ lựa chọn còn hợp lệ; Đóng kết thúc toàn bộ phiên chức năng rồi trở về màn hình chính.
- Mọi phần mềm đều có thể dùng **Mở / tìm trang chính thức**: mở URL HTTPS đã xác minh trong catalog hoặc tìm kiếm an toàn theo tên và nhà phát hành khi chưa có URL trực tiếp.

## Toàn vẹn và lưu ý khi chạy

- EXE, provenance, catalog và update manifest đều có chữ ký hoặc hash đối chiếu.
- Launcher kiểm tra Authenticode, signer được ghim, BuildId và payload trước khi mở thao tác thay đổi hệ thống.
- Bản hiện tại có Authenticode hợp lệ và timestamp DigiCert nhưng dùng chứng thư tự ký được ghim; Windows vẫn có thể hiện `Unknown publisher` hoặc SmartScreen.
- Không tắt Defender hoặc SmartScreen để ép chạy tệp không xác minh được.
- Người dùng đang giữ EXE v5.0 cũ nên tải lại tệp mới nhất và thay thế thủ công vì ProductVersion/FileVersion vẫn là `5.0.0.0`.

## Giới hạn công khai

- Đây không phải danh tính code-signing public-CA.
- Ứng viên Microsoft Store được chuẩn bị riêng và chưa thay thế bản ManagedSigned hiện tại.
- `Chưa xác minh` không đồng nghĩa phần mềm vi phạm; cần kiểm tra giấy phép, tài khoản hoặc chứng từ chính thức.
