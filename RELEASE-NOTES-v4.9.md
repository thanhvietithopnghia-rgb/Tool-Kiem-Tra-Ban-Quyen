# Tool Kiểm Tra v4.9.0.0

## Bản bảo trì nhận diện ngày 22/08/2026

- Phân biệt rõ cài đặt đã xác nhận, đăng ký đơn nguồn, ứng dụng portable và bộ tệp còn sót; AutoCAD chỉ tìm thấy từ cây tệp không còn bị trình bày như một bản cài chính thức.
- Tích hợp Winget làm nguồn đối chiếu cục bộ và adapter chỉ-đọc cho đăng ký Autodesk khi dịch vụ hãng có sẵn.
- Gộp Registry, MSIX, Winget, shortcut và Distiller vào đúng họ Adobe Acrobat; ưu tiên đường dẫn tệp chạy chính thay vì uninstaller dùng chung.
- Khi phát hiện hosts/firewall hoặc dịch vụ hãng bất thường, tự mở rộng kiểm tra Authenticode cho toàn bộ tệp PE trong đúng thư mục sản phẩm. Kiểm thử thực tế đã phát hiện 9 tệp Acrobat `HashMismatch` mà cơ chế giới hạn cũ bỏ sót.
- Bằng chứng dùng đường dẫn cụ thể nhất nên không còn lan từ Acrobat sang Lightroom/Premiere; nguồn lặp lại không được đếm như bằng chứng độc lập.
- Catalog `1.6.0.0` bổ sung tệp lõi và signer Adobe/Autodesk, vẫn là dữ liệu khai báo ký số, không chứa lệnh và không tải dữ liệu máy lên Internet.
- Tách tuyệt đối **Quét/Báo cáo** khỏi **Khắc phục**: các chế độ báo cáo chỉ đọc; mọi thay đổi hệ thống phải đi qua xem trước, chọn mục, backup và xác nhận.
- Khắc phục Windows/Office theo đúng Activation ID hoặc 5 ký tự cuối của khóa được chọn, bảo toàn Retail/OEM/MAK/Subscription hợp lệ cùng tồn tại; không còn chạy thao tác rộng sau khi gỡ khóa đích.
- Bổ sung gỡ cài đặt hoàn chỉnh thủ công cho ứng dụng bên thứ ba được chọn rõ ràng, chỉ chấp nhận danh tính MSI hoặc AppX gắn với nguồn; hậu kiểm yêu cầu ứng dụng và dấu vết thuộc đúng mục đã chọn không còn tồn tại.
- Làm sạch Activator kiểm tra lại PID, đường dẫn tiến trình/dịch vụ, hành động tác vụ và giá trị Startup/IFEO ngay trước khi xóa; chỉ xóa đúng giá trị hoặc tệp đã xác minh.
- Cập nhật điều khoản từ v4.9 và rút gọn lịch sử v4.8/v4.9 theo thay đổi cốt lõi; bỏ mốc v4.8.0.1 khỏi lịch sử hiển thị.

- Khôi phục giao diện PDF chi tiết theo phong cách v4.8: khổ A4 sáng, khung xanh, năm thẻ trạng thái, bảng gọn hơn và phụ lục đồng nhất xanh–trắng. Chủ đề `v4.8-classic-a4` chỉ áp dụng cho PDF, không làm thay đổi dữ liệu, quyền riêng tư hoặc cơ chế kiểm tra của v4.9.
- Sửa trường hợp Tool chạy nâng quyền hoặc ghi báo cáo sang hồ sơ người dùng khác khiến Edge không truy cập được tệp nguồn và âm thầm rơi xuống Microsoft Word, làm mất bố cục v4.8. HTML/PDF trung gian nay nằm trong profile tạm đã khóa ACL; Tool thử lần lượt Edge rồi Chrome, chờ tệp PDF có header/EOF và dung lượng ổn định, sau đó tiến trình cha mới chép PDF hợp lệ về thư mục báo cáo. Nếu cả hai trình duyệt lỗi, presentation mang theme v4.8 sẽ báo PDF chưa tạo và giữ HTML/JSON/XML thay vì sinh một PDF Word sai giao diện.

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
- Kể từ v4.9, mã nguồn không còn được công khai miễn phí, không được phát hành theo giấy phép mã nguồn mở và được quản lý theo cơ chế có kiểm soát. Người muốn tham khảo, học tập, nghiên cứu, đánh giá bảo mật hoặc đóng góp mã phải nhận chấp thuận trước bằng văn bản của tác giả; quyền xem không tự cấp quyền sao chép, trích xuất, sửa đổi, dịch ngược, phân phối, đóng gói lại, thương mại hóa, dùng làm dữ liệu huấn luyện hoặc đổi thương hiệu.
- Các phiên bản cũ đã công khai tiếp tục theo điều khoản đi kèm tại thời điểm phát hành.

## An toàn

- Không tự kích hoạt Windows, Office hoặc phần mềm bên thứ ba.
- Không tự xóa policy tổ chức, không tự gỡ ứng dụng ngoài mục người dùng chủ động chọn và không tự đặt lại kho bản quyền của hãng.
- Khắc phục thật vẫn yêu cầu xem trước, xác nhận, backup và kiểm tra lại sau xử lý.
