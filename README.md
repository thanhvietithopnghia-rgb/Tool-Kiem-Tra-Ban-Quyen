# Tool Kiểm Tra v5.0 — Bản nâng cấp và cải tiến tiếp nối từ v4.9

**Phiên bản hiện tại:** Tool Kiểm Tra v5.0 · ProductVersion/FileVersion `5.0.0.0` · cập nhật ngày 31/08/2026
**Tác giả và phát triển:** Thanh Việt
**Trang v5 ManagedSigned:** <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v5.0.0.0>
**Stable công khai mới nhất:** <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>

> **Nguyên tắc cập nhật:** Bài giới thiệu này chỉ thay đổi khi dự án công bố một phiên bản chính thức mới. Các bản vá, cập nhật kỹ thuật và bản dựng nội bộ trong cùng phiên bản không thay đổi tiêu đề, tên phiên bản hoặc nội dung giới thiệu; chi tiết bảo trì được ghi trong release notes của phiên bản hiện hành.

Tiếp nối nền tảng của v4.9, Tool Kiểm Tra v5.0 được nâng cấp để kiểm tra nhanh hơn, nhận diện chính xác hơn và sử dụng thuận tiện hơn. Phiên bản mới có ba mức kiểm tra từ cơ bản đến chuyên sâu, tách riêng Windows, Microsoft Office và các phần mềm khác, đồng thời cải thiện giao diện để hiển thị tốt trên nhiều kích thước màn hình.

Quy trình khắc phục cũng an toàn và rõ ràng hơn: người dùng được xem trước nội dung, sao lưu, xác nhận trước khi thực hiện và kiểm tra lại kết quả sau xử lý. v5.0 còn bổ sung báo cáo dễ theo dõi hơn và hỗ trợ quản lý nhiều máy. Tool vẫn hoạt động **Offline theo mặc định, không tự động gửi dữ liệu ra Internet** và chỉ kết nối mạng khi người dùng chủ động cho phép.

Trong v5.0, danh sách phần mềm được sắp xếp theo đúng thứ tự **Cao → Trung bình → Thấp**; phần mềm trả phí/thuê bao/dùng thử chưa xác minh luôn được nhắc kiểm tra giấy phép. Thành phần hệ thống, runtime, codec, extension nền, trình cài đặt, add-in, gói hỗ trợ và trình gỡ driver chỉ nằm trong kiểm kê/báo cáo, không xuất hiện trong danh sách xử lý.

Catalog tích hợp và Online hiện là `1.6.3.0` với 94 nhóm sản phẩm. Tool dùng chứng thư tự ký được launcher ghim, nên Windows vẫn có thể hiện `Unknown publisher` hoặc SmartScreen.

## Tải và bắt đầu

1. Mở [trang v5.0.0.0 ManagedSigned](https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/tag/v5.0.0.0) hoặc [Stable công khai mới nhất](https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest).
2. Nếu đang dùng một tệp v5.0 cũ, hãy tải EXE v5.0 mới nhất và thay tệp cũ vì ProductVersion/FileVersion vẫn là `5.0.0.0`.
3. Đối chiếu SHA-256 và chữ ký trước khi chạy. Không tắt Defender hoặc SmartScreen để ép chạy tệp không xác minh được.
4. Giữ Offline nếu chỉ kiểm tra máy cục bộ. Chỉ bật Online khi muốn cập nhật Tool/catalog hoặc dùng chức năng LAN được cho phép.
5. Chỉ chấp nhận UAC khi tên tác vụ đúng với thao tác khắc phục, cập nhật hoặc quản trị mà bạn vừa chọn.

```powershell
Get-FileHash .\Tool-Kiem-Tra-v5.0.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v5.0.exe |
  Format-List Status,StatusMessage,SignerCertificate
```

## Điểm mới trong v5.0

- **Khởi động nhanh hơn:** dùng hồ sơ hệ thống đọc nhanh từ Registry và đưa các bước xác minh catalog, dựng menu, kiểm tra toàn vẹn sang sau lần vẽ đầu tiên; nút thao tác chỉ được bật khi kiểm tra an toàn hoàn tất.
- **Phát hành fail-closed:** Stable bắt buộc chứng thư code-signing CA-issued/HSM, chuỗi tin cậy Windows, RFC3161 timestamp, source commit sạch và provenance CMS đúng commit.
- **Catalog và plugin có biên tin cậy:** catalog phân loại Fresh/Warning/Stale/Future/Invalid; plugin bên thứ ba chỉ nhận metadata khai báo đã ký từ fingerprint nhà phát hành được quản trị viên ghim.
- **Quét theo mục tiêu:** Quick/Standard/Deep dùng ngân sách rõ ràng và giới hạn include/exclude/root an toàn.
- **Trải nghiệm và quản trị:** theme theo hệ thống, dark/light override, PerMonitorV2 DPI, fleet export có redaction/chống CSV injection, CLI headless và script Intune/MDM.
- **Khắc phục theo phạm vi rõ ràng:** mục Khắc phục tách thành Windows, Microsoft Office và phần mềm khác; phạm vi được khóa xuyên suốt quét, Dry Run, backup, xác nhận và hậu kiểm.
- **Trạng thái phát hành minh bạch:** bản ManagedSigned tự ký được ghim đúng chứng thư; Windows vẫn có thể cảnh báo `Unknown publisher`, và đây không phải danh tính public-CA.

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
6. Khắc phục KMS/Activator có Dry Run, backup và hậu kiểm; mục Khắc phục có năm chức năng riêng gồm Windows, Microsoft Office, phần mềm khác, Khôi phục key OEM và Quản lý giấy phép hợp lệ. Ba chức năng đầu mở thẳng đúng màn hình, không qua menu chung.
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
- [Release notes v5.0](RELEASE-NOTES-v5.0.md)
- [Release notes v4.9](RELEASE-NOTES-v4.9.md)
- [Chính sách an toàn](SAFETY-POLICY-v1.0.md)
- [Report schema và artifact quản trị](REPORT-SCHEMA-v1.5.md)
- [Chính sách trình xem báo cáo/fallback](REPORT-VIEWER-POLICY-v1.md)
- [Chính sách báo cáo bảo mật](SECURITY.md)
- [Phạm vi audit và quy trình review](AUDIT-SCOPE-v1.md)
- [Chính sách code-signing](CODE-SIGNING-POLICY-v1.md)
- [Lộ trình/tiến độ nhánh v5.0](ROADMAP-v5.0.md)
- [Kết quả kiểm thử bảo mật và tương thích](SECURITY-TEST-RESULTS.md)

## Nguồn chính thức và hỗ trợ

- Kho phát hành: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen>
- Bản mới nhất: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases/latest>
- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

Chỉ chia sẻ đường dẫn tải chính thức; không đăng lại, đóng gói, thu phí, đổi thương hiệu hoặc tuyên bố Tool là sản phẩm của người khác khi chưa có chấp thuận bằng văn bản.

© 2026 Thanh Việt. Mọi quyền được bảo lưu.
