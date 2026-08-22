# Tool Kiểm Tra v4.9 — xác minh nguồn gốc, cập nhật nhận diện, khắc phục có hậu kiểm

**Phiên bản hiện tại:** v4.9.0.0 · Build 2026.08.22
**Tác giả và phát triển:** Thanh Việt
**Trang tải luôn trỏ tới bản mới nhất:** <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

Tool Kiểm Tra là ứng dụng Windows miễn phí cho cộng đồng, hỗ trợ kiểm kê cấu hình máy, kiểm tra trạng thái Windows/Office/phần mềm, rà soát dấu hiệu KMS/activator/can thiệp và tạo báo cáo. Tool hoạt động Offline theo mặc định, không có telemetry và chỉ dùng mạng sau khi người dùng chủ động bật Online.

v4.9 tăng khả năng chứng minh bản chính thức, mở rộng catalog nhận diện có ký số, sửa luồng khắc phục để chỉ báo thành công sau hậu kiểm và bảo vệ dữ liệu định danh trong báo cáo. Công cụ cung cấp bằng chứng kỹ thuật hỗ trợ quản trị; không thay thế hóa đơn, hợp đồng, tài khoản hãng hoặc tư vấn pháp lý và không thể cam kết nhận diện/làm sạch 100% mọi sản phẩm hay biến thể.

## Tải và bắt đầu

1. Mở [trang tải bản mới nhất](https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest).
2. Tải `Tool-Kiem-Tra-v4.9.exe` cùng tệp checksum/chứng minh nguồn gốc đi kèm.
3. Đối chiếu SHA-256 và chữ ký trước khi chạy. Không tắt Defender hoặc SmartScreen để ép chạy tệp không xác minh được.
4. Giữ Offline nếu chỉ kiểm tra máy cục bộ. Chỉ bật Online khi muốn cập nhật Tool/catalog hoặc dùng chức năng LAN được cho phép.
5. Chỉ chấp nhận UAC khi tên tác vụ đúng với thao tác khắc phục, cập nhật hoặc quản trị mà bạn vừa chọn.

```powershell
Get-FileHash .\Tool-Kiem-Tra-v4.9.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v4.9.exe |
  Format-List Status,StatusMessage,SignerCertificate
```

## Điểm mới trong v4.9

- **Nguồn gốc và chống giả mạo:** launcher kiểm tra chữ ký, chứng thư ghim, metadata, Build ID và manifest nguồn gốc. Bản bị sửa hoặc không xác minh được được cảnh báo rõ và fail-closed đối với cập nhật cùng thao tác thay đổi hệ thống.
- **Catalog online an toàn:** catalog khai báo có chữ ký CMS, giới hạn trường/quy tắc được phép, chống hạ phiên bản và giữ cache dự phòng. Chỉ tải sau khi người dùng bật Online; inventory, đường dẫn, key và báo cáo không được tải lên.
- **Nhận diện mở rộng nhưng thận trọng:** đối chiếu Product ID, publisher, chữ ký, đường dẫn, service, task, Registry và trạng thái cấp phép. `Chưa xác minh` không tự biến thành kết luận crack và không đủ điều kiện tự động làm sạch.
- **Kiểm kê toàn máy rõ nguồn:** bổ sung AppX/MSIX, Winget, shortcut mọi hồ sơ người dùng, Scoop, Chocolatey, Steam, đăng ký cấp phép Autodesk chỉ-đọc và vùng portable giới hạn; phân biệt bản cài đã xác nhận với portable/tệp còn sót, gom bản ghi trùng theo họ sản phẩm và công bố phạm vi đọc có/không có quyền quản trị.
- **Quét toàn vẹn thích ứng:** khi hosts, firewall hoặc dịch vụ hãng có dấu hiệu bất thường, Tool tăng phạm vi kiểm tra Authenticode trong đúng thư mục sản phẩm. Đường dẫn cụ thể nhất được ưu tiên để bằng chứng Acrobat không lan sang Lightroom/Premiere.
- **Đọc cấp phép có chẩn đoán:** lượt quét Windows/Office/Phần mềm/Toàn bộ yêu cầu UAC, kiểm tra dịch vụ cần thiết, thử CIM rồi WMI và phân biệt `không đọc được dữ liệu` với `chưa kích hoạt`.
- **Khắc phục có hậu kiểm:** từng mục có định danh và trạng thái riêng. Tool chỉ báo `VerifiedClean` khi hậu kiểm chứng minh dấu vết đã hết và trạng thái cấp phép phù hợp; lỗi có thể thử lại, còn policy hoặc bản cài cần sửa chữa được báo riêng thay vì báo thành công giả.
- **Quyền riêng tư mặc định:** báo cáo dòng lệnh và bản chia sẻ mặc định che serial, UUID, Processor ID và Asset Tag. Chỉ lựa chọn nội bộ đầy đủ mới giữ định danh.
- **Giữ nguyên nguyên tắc an toàn:** xem trước, chọn từng mục, xác nhận, backup và hậu kiểm; không tự gỡ phần mềm chỉ vì tên hoặc một dấu vết yếu.

## Mười chức năng chính

1. Kiểm tra toàn bộ.
2. Cấu hình phần cứng, TPM, Secure Boot và BitLocker.
3. Bản quyền Windows.
4. Bản quyền Microsoft Office.
5. Phần mềm và dấu hiệu can thiệp.
6. Khắc phục KMS/Activator có Dry Run, backup và hậu kiểm.
7. Khôi phục key OEM khi edition phù hợp.
8. Quản lý giấy phép hợp lệ cục bộ hoặc trong LAN được cho phép.
9. Kiểm tra chuyên sâu dành cho quản trị viên.
10. Trung tâm báo cáo bảo đảm, timeline, plugin và tài liệu.

## Cách hiểu kết quả khắc phục

- `Pending` / `Running`: đang chờ hoặc đang xử lý.
- `VerifiedClean`: hậu kiểm đã xác nhận điều kiện làm sạch của quy tắc; không đồng nghĩa đã có giấy phép hợp lệ.
- `ApprovedInternalKMS`: KMS tổ chức đã được người quản trị xác nhận và được giữ nguyên.
- `RetryableFailure`: lần xử lý chưa đạt; có thể sửa nguyên nhân và thử lại.
- `BlockedByPolicy`: chính sách quản trị đang áp dụng; Tool không âm thầm xóa policy của tổ chức.
- `NeedsOfficeRepair`: edition/tệp/trạng thái Office cần Repair, cấu hình lại hoặc cài từ nguồn chính thức.

Nếu catalog chưa đủ bằng chứng, Tool giữ trạng thái `Chưa xác minh`. Nếu bản cài Volume, file đã bị thay đổi hoặc policy tái áp dụng cấu hình, Tool có thể yêu cầu Repair/cài lại thay vì cố xử lý nguy hiểm.

## Báo cáo và quyền riêng tư

Báo cáo HTML/PDF/JSON/XML được tạo cục bộ. Bản chia sẻ mặc định che định danh phần cứng; bản `FullInternal` chỉ dùng trong phạm vi quản trị có trách nhiệm. Tool không xuất product key đầy đủ, mật khẩu hoặc dữ liệu đăng nhập. Trước khi gửi báo cáo ra ngoài, vẫn cần đọc lại nội dung và giới hạn người nhận.

## Phát triển cộng đồng và mã nguồn có kiểm soát từ v4.9

Bản thực thi chính thức của Tool tiếp tục **miễn phí cho cộng đồng** cho các mục đích hợp pháp theo điều khoản đi kèm. Dự án tiếp nhận báo lỗi, đề xuất, tài liệu, bản dịch, kiểm thử và đóng góp kỹ thuật của cộng đồng. Kể từ v4.9, mã nguồn không còn được công khai miễn phí, không được phát hành theo giấy phép mã nguồn mở và được quản lý theo cơ chế truy cập có kiểm soát.

Thay đổi này được đưa ra sau khi tác giả ghi nhận nội dung, giao diện, mô tả và thành quả phát triển của Tool bị sao chép gần như nguyên trạng, đổi tên/đổi thương hiệu thành sản phẩm cá nhân mà không xin phép hoặc ghi nhận tác giả. Nội dung này **không khẳng định mã nguồn hoặc backend đã bị lấy** khi chưa có bằng chứng kỹ thuật xác nhận.

Người muốn tham khảo, học tập, nghiên cứu, đánh giá bảo mật hoặc đóng góp mã phải xin ý kiến và nhận chấp thuận bằng văn bản của tác giả trước khi truy cập. Quyền xem không tự cấp quyền sao chép, chia sẻ, sửa đổi, tạo sản phẩm phái sinh, đóng gói, thương mại hóa, dùng làm dữ liệu huấn luyện, đổi thương hiệu hoặc xóa ghi nhận tác giả. Chính sách áp dụng cho mã nguồn từ v4.9 trở đi và không thay đổi hồi tố điều khoản của các phiên bản cũ.

Đọc [Chính sách phát triển cộng đồng và mã nguồn có kiểm soát](SOURCE-POLICY-v4.9.md), [Thông báo bản quyền và điều khoản sử dụng](LICENSE-NOTICE.txt) và [Hướng dẫn tiếp cận mã nguồn](README-MA-NGUON.md).

## Tài liệu

- [Hướng dẫn sử dụng tiếng Việt](HUONG-DAN.txt)
- [English user guide](USER-GUIDE-en-US.md)
- [Lịch sử phiên bản](LICH-SU-PHIEN-BAN.txt)
- [English version history](VERSION-HISTORY-en-US.md)
- [Release notes v4.9](RELEASE-NOTES-v4.9.md)
- [Chính sách an toàn](SAFETY-POLICY-v1.0.md)

## Nguồn chính thức và hỗ trợ

- Kho phát hành: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen>
- Bản mới nhất: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>
- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

Chỉ chia sẻ đường dẫn tải chính thức; không đăng lại, đóng gói, thu phí, đổi thương hiệu hoặc tuyên bố Tool là sản phẩm của người khác khi chưa có chấp thuận bằng văn bản.

© 2026 Thanh Việt. Mọi quyền được bảo lưu.
