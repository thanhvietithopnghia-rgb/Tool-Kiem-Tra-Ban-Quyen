# Lộ trình Tool Kiểm Tra v5.0

Trạng thái ngày 28/08/2026: Preview R6 đã được build theo trạng thái `ManagedSigned` trên nhánh tính năng `feature/v5.0-trust-enterprise`. Có mã nguồn, workflow hoặc chữ ký quản trị không đồng nghĩa đã đạt public-CA Stable; mọi build không ký vẫn phải mang `ReleaseStatus=DevelopmentUnsigned` và nhãn development, không được mô tả là production.

## Đã tích hợp trên nhánh tính năng

- **Code signing và nguồn gốc:** đường build stable yêu cầu signer Authenticode trong certificate store/HSM, EKU Code Signing, chuỗi Windows tin cậy, RFC 3161 timestamp, worktree sạch và provenance được ràng buộc với snapshot release. Signer Authenticode của EXE được tách khỏi signer CMS nội dung update đang được client ghim; việc đổi signer cần bản cập nhật bắc cầu theo [chính sách code-signing](CODE-SIGNING-POLICY-v1.md).
- **Catalog và plugin:** catalog phần mềm có trạng thái Fresh/Warning/Stale/Future/Invalid/Unavailable; dữ liệu quá cũ, sai hoặc có ngày tương lai chỉ còn giá trị nhận diện và không được dùng làm bằng chứng quyết định. Plugin và catalog plugin bên thứ ba dùng detached CMS SHA-256 với fingerprint chứng thư do quản trị viên ghim; catalog không tự tải mạng hoặc chạy mã.
- **Hiệu năng và phạm vi:** Quick/Standard/Deep, chế độ máy yếu và include/exclude hiện chỉ điều khiển traversal read-only khi tạo báo cáo/kiểm kê. Chúng không thay đổi cleanup, license deep-scan, forensics hoặc assurance. Root bị giới hạn ở thư mục cục bộ rõ ràng và chặn UNC/junction/symlink. Cả Standard và Deep vẫn có ngân sách depth/result/timeout; traversal chạm giới hạn phải ghi độ phủ chưa hoàn tất, không được suy diễn `CoverageComplete=true` chỉ từ tên profile.
- **Giao diện:** theme hệ thống được áp dụng lúc khởi động và có override ghi nhớ; PerMonitorV2 có fallback PerMonitor/System cho Windows cũ, các hộp thoại dùng DPI scaling. Việc tự đổi theme khi Windows thay đổi trong lúc ứng dụng đang chạy chưa nằm trong phạm vi hiện tại.
- **Báo cáo:** HTML vẫn self-contained/offline-safe trước khi mở. WebView2 được hoãn, chưa có runtime loader/control và không phải dependency. Trình duyệt mặc định cùng chuỗi xuất PDF Edge/Chrome/Word tiếp tục là fallback để ứng dụng vẫn khởi động trên Windows 7; khả năng tạo PDF còn phụ thuộc engine có trên máy và yêu cầu PDF phải thất bại rõ ràng nếu không tạo được tệp.
- **Doanh nghiệp:** xuất fleet hàng loạt JSON/CSV/HTML/PDF, mặc định che dữ liệu nhạy cảm, lọc client/freshness và chống CSV formula injection; có CLI headless cùng script Install/Detect/Repair/Uninstall idempotent cho Intune/MDM hoặc quản trị trung tâm.
- **Minh bạch và review:** có security policy, audit scope, quy trình disclosure/review có kiểm soát, chính sách code-signing và tài liệu kết quả kiểm thử. Schema/catalog/safety policy và verifier là phạm vi ưu tiên cho review; khóa ký, bí mật Enterprise, dữ liệu khách hàng và logic khắc phục nhạy cảm không được công khai.
- **Ma trận VM:** workflow và bộ tổng hợp public-safe đã được khai báo cho Windows 10 22H2, Windows 11 nhánh trước và nhánh hiện hành. Chúng kiểm tra DisplayVersion/build/UBR, commit và danh sách verifier bắt buộc; tóm tắt không mang raw output. Preview R6 đã ghi nhận một runner Windows 11 25H2 đạt, nhưng hai nền tảng còn lại vẫn thiếu bằng chứng.

## Trạng thái bằng chứng hiện tại

- [Kết quả kiểm thử bảo mật và tương thích](SECURITY-TEST-RESULTS.md) ghi `Passed=1`, `Failed=0`, `Missing=2`: Windows 11 current/25H2 đã đạt trên build 26200.9168; Windows 10 22H2 và Windows 11 previous/24H2 vẫn thiếu runner/bằng chứng.
- Chưa có hậu kiểm Stable bằng chứng thư code-signing CA-issued. Preview R6 dùng ManagedSigned + RFC 3161 timestamp cho môi trường đã phân phối chứng thư quản trị, không đủ điều kiện đưa lên public-CA Stable.
- Chưa có kiểm thử WebView2 vì tính năng này được hoãn. Fallback Windows 7, chuyển màn hình/DPI, accessibility và đổi theme khi đang chạy vẫn cần kiểm thử máy thật phù hợp.
- Scan profile chỉ cam kết cho luồng tạo báo cáo/kiểm kê read-only; tài liệu và UI không được mô tả nó là profile quét toàn ứng dụng.

## Cổng còn phải hoàn tất ngoài mã nguồn

1. Mua/cấp chứng thư code-signing tổ chức thật (ưu tiên EV khi phù hợp), đặt private key trong HSM/token/dịch vụ ký và cấu hình quyền release tối thiểu.
2. Chốt source snapshot commit, chỉ cho phép metadata release được kiểm soát thay đổi sau snapshot, rồi ký provenance/update manifest; build trên môi trường sạch và hậu kiểm chữ ký/timestamp trên máy sạch.
3. Hoàn tất hai runner còn thiếu trong environment `client-vm-validation` cho Windows 10 22H2 và Windows 11 previous/24H2; chạy lại ma trận trên đúng release candidate và công bố artifact tóm tắt.
4. Tổ chức security review độc lập hoặc chương trình disclosure/bug-bounty có phạm vi, kênh riêng và ngân sách rõ ràng. Không gọi là bug bounty trước khi các điều kiện này được công bố.
5. Chạy accessibility/DPI thủ công, kiểm thử máy thật và kiểm thử nâng cấp/rollback trước khi gắn nhãn stable.

EV giúp xác minh nhà phát hành và bảo vệ khóa tốt hơn nhưng không bảo đảm SmartScreen hết cảnh báo ngay. Uy tín còn phụ thuộc lịch sử phát hành sạch, publisher ổn định, kênh tải đáng tin cậy và tỷ lệ false positive thấp.
