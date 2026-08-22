# Hướng dẫn tham gia và tiếp cận mã nguồn có kiểm soát từ v4.9

Áp dụng cho Tool Kiểm Tra v4.9.0.0, build 2026.08.22 và các phiên bản mới hơn.

## Mô hình phát triển

Tool Kiểm Tra được cung cấp miễn phí và phát triển cùng cộng đồng thông qua báo lỗi, đề xuất, tài liệu, bản dịch, kiểm thử và đóng góp kỹ thuật. Kể từ v4.9, mã nguồn không còn được công khai miễn phí, không được phát hành theo giấy phép mã nguồn mở và được tác giả Thanh Việt quản lý theo cơ chế truy cập có kiểm soát. Bản thực thi chính thức tiếp tục được cung cấp miễn phí tại:

<https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

Tệp thực thi chuẩn của nhánh phiên bản này là `Tool-Kiem-Tra-v4.9.exe`.

Việc kiểm soát truy cập nhằm bảo vệ nguồn gốc và công sức phát triển sau khi tác giả ghi nhận nội dung, giao diện, mô tả và thành quả của Tool bị sao chép gần như nguyên trạng, đổi tên hoặc đổi thương hiệu thành sản phẩm cá nhân mà không xin phép hay ghi nhận tác giả. Tuyên bố này không khẳng định mã nguồn/backend đã bị lấy khi chưa có bằng chứng kỹ thuật xác nhận.

## Tham gia không cần truy cập mã nguồn

Cộng đồng có thể gửi báo lỗi, đề xuất tính năng, tài liệu, bản dịch, kịch bản kiểm thử và mẫu dữ liệu đã loại thông tin nhạy cảm qua kênh chính thức. Việc tiếp nhận đóng góp không tự chuyển quyền sở hữu và không cấp quyền đối với mã nguồn chưa công bố.

## Ai có thể yêu cầu truy cập

Cá nhân hoặc tổ chức có mục đích thiện chí có thể gửi yêu cầu cho một trong các trường hợp:

- học tập hoặc nghiên cứu;
- đánh giá bảo mật và phối hợp tiết lộ có trách nhiệm;
- kiểm định kỹ thuật;
- đề xuất sửa lỗi hoặc đóng góp tính năng;
- rà soát khả năng tích hợp trong phạm vi được tác giả xem xét riêng.

Người muốn tham khảo, học tập hoặc làm việc trực tiếp với mã phải xin ý kiến tác giả trước. Quyền truy cập chỉ có hiệu lực sau khi tác giả chấp thuận **bằng văn bản**, theo đúng mục đích, phạm vi, thời hạn, người được truy cập và điều kiện ghi trong chấp thuận.

## Nội dung nên có trong yêu cầu

Gửi email tới `thanhvietit.hopnghia@gmail.com` và nêu rõ:

1. họ tên, tổ chức và thông tin liên hệ;
2. mục đích nghiên cứu/đánh giá/đóng góp;
3. phạm vi thành phần cần xem;
4. thời gian dự kiến cần truy cập;
5. người sẽ được truy cập và biện pháp bảo vệ dữ liệu nguồn;
6. đầu ra dự kiến, cách công bố kết quả và kế hoạch tiết lộ lỗ hổng nếu có;
7. xác nhận tuân thủ `SOURCE-POLICY-v4.9.md`, `LICENSE-NOTICE.txt` và điều kiện bổ sung trong văn bản chấp thuận.

Tác giả có quyền chấp thuận, giới hạn hoặc từ chối yêu cầu. Việc gửi yêu cầu không tự tạo quyền truy cập.

## Giới hạn mặc định của quyền xem

Trừ khi văn bản chấp thuận ghi rõ khác, quyền truy cập không cho phép:

- sao chép ngoài bản kỹ thuật cần thiết trong môi trường đã được cấp;
- chia sẻ tài khoản, chuyển quyền truy cập hoặc cho người khác xem mã;
- công bố, mirror, tải lên dịch vụ khác hoặc phát tán toàn bộ/một phần mã nguồn;
- sửa đổi, tạo sản phẩm phái sinh hoặc tích hợp vào sản phẩm/dịch vụ khác;
- đóng gói lại, đổi tên, đổi thương hiệu, mạo danh tác giả hoặc xóa thông tin nguồn gốc;
- bán, cho thuê, thu phí, thương mại hóa hoặc dùng để cung cấp dịch vụ cho bên thứ ba;
- công bố mã nguồn nhạy cảm/lỗ hổng trước khi hoàn tất quy trình tiết lộ có trách nhiệm.

Khả năng clone hoặc tạo bản sao cục bộ do nền tảng kỹ thuật cung cấp không tạo thêm quyền pháp lý. Quyền xem không đồng nghĩa quyền sử dụng lại.

## Đóng góp mã nguồn được chấp thuận

Nếu yêu cầu đóng góp được duyệt, tác giả sẽ cung cấp riêng phạm vi nhánh, tiêu chuẩn kiểm thử, cách gửi thay đổi, cách ghi nhận và điều kiện quyền tác giả. Không gửi mã nguồn v4.9 lên kho công khai, issue công khai, paste service hoặc tệp đính kèm ngoài kênh được chấp thuận. Tác giả duy trì quyền xem xét, yêu cầu sửa, chấp nhận hoặc từ chối đóng góp và quyết định bản phát hành chính thức.

Những kiểm soát kỹ thuật quan trọng của v4.9 gồm:

- manifest nguồn gốc và chữ ký fail-closed cho bản chính thức;
- catalog online khai báo, ký số và chống hạ phiên bản;
- khắc phục theo trạng thái với hậu kiểm, thử lại, policy và yêu cầu Repair riêng;
- báo cáo che định danh theo mặc định.

Các cơ chế này giúp phát hiện bản bị sửa và giảm rủi ro xử lý sai; chúng không thể ngăn tuyệt đối sao chép, chụp màn hình hoặc dịch ngược mã chạy trên máy người nhận.

## Phiên bản trước v4.9

Chính sách này chỉ áp dụng cho mã nguồn từ v4.9 trở đi. Phiên bản cũ tiếp tục chịu điều khoản đi kèm tại thời điểm phát hành; không có thay đổi hồi tố đối với quyền đã được cấp hợp lệ. Việc một phiên bản từng có thể xem công khai không tự biến phiên bản đó thành mã nguồn mở nếu không có giấy phép cấp các quyền mã nguồn mở.

## Tài liệu chính sách chuẩn

- [Chính sách phát triển cộng đồng và mã nguồn có kiểm soát](SOURCE-POLICY-v4.9.md)
- [Thông báo bản quyền và điều khoản sử dụng](LICENSE-NOTICE.txt)
- [Trang tải bản mới nhất](https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest)

Nếu nội dung tóm tắt này khác với văn bản chấp thuận riêng hoặc chính sách đầy đủ, văn bản chấp thuận và `SOURCE-POLICY-v4.9.md` được ưu tiên áp dụng.

© 2026 Thanh Việt. Mọi quyền được bảo lưu.
