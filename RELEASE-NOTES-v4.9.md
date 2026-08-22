# Tool Kiểm Tra v4.9.0.0

Build: **2026.08.22**

## Điểm mới

- Xác minh bản chính thức bằng Authenticode, chứng thư ghim và manifest provenance ký CMS.
- Khóa tự cập nhật và thao tác thay đổi hệ thống khi bản dựng bị sửa hoặc chưa xác minh.
- Mở rộng catalog ký số lên tối thiểu 92 nhóm sản phẩm với schema khai báo giới hạn và chống hạ phiên bản.
- Tách định danh khắc phục Windows, Office và phần mềm bên thứ ba; hỗ trợ trạng thái thử lại và hậu kiểm bắt buộc.
- Che serial, UUID, Processor ID và Asset Tag theo mặc định; chỉ giữ đầy đủ khi người dùng chọn báo cáo nội bộ.
- Giữ mặc định Offline, không telemetry và chỉ kiểm tra cập nhật sau khi người dùng bật Online.
- Yêu cầu UAC cho lượt quét toàn máy; tự kiểm tra `Winmgmt`/`sppsvc`, thử CIM rồi WMI và báo riêng lỗi nguồn dữ liệu thay vì kết luận nhầm là chưa kích hoạt.
- Mở rộng kiểm kê Registry, AppX/MSIX, shortcut mọi hồ sơ người dùng, Scoop, Chocolatey, Steam và ứng dụng portable trong các vùng giới hạn.
- Gom bản ghi trùng có cùng danh tính/vị trí; gắn updater, language pack, plugin và thành phần phụ vào nhóm sản phẩm chính, giữ chúng ở chế độ chỉ đọc.
- Báo cáo ghi số bản ghi thô, số dòng đã gom, nguồn phát hiện và phạm vi đọc toàn máy; không cam kết nhận diện 100% mọi phần mềm.

## Phát hành

- Tool chính thức tiếp tục miễn phí cho cộng đồng.
- Từ v4.9, dự án phát triển cùng cộng đồng với mã nguồn có kiểm soát. Người muốn tham khảo, học tập, nghiên cứu, đánh giá bảo mật hoặc đóng góp mã phải xin ý kiến và nhận chấp thuận bằng văn bản của tác giả; quyền xem không tự cấp quyền sao chép, phân phối, sửa đổi, đóng gói lại, thương mại hóa, dùng làm dữ liệu huấn luyện hoặc đổi thương hiệu.
- Các phiên bản cũ đã công khai tiếp tục theo điều khoản đi kèm tại thời điểm phát hành.

## An toàn

- Không tự kích hoạt Windows, Office hoặc phần mềm bên thứ ba.
- Không tự xóa policy tổ chức, không tự gỡ ứng dụng và không tự đặt lại kho bản quyền của hãng.
- Khắc phục thật vẫn yêu cầu xem trước, xác nhận, backup và kiểm tra lại sau xử lý.
