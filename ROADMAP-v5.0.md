# Lộ trình Tool Kiểm Tra v5.0

Trạng thái cập nhật ngày 28/08/2026: các hạng mục dưới đây đang được tích hợp trên nhánh tính năng `feature/v5.0-trust-enterprise`. Có mã nguồn hoặc workflow không đồng nghĩa đã có bằng chứng phát hành. ManagedSigned Preview R6 đã được phát hành có kiểm soát nhưng chưa phải Public Stable; mọi build không ký của nhánh vẫn phải mang `ReleaseStatus=DevelopmentUnsigned` và nhãn development.

## Đã tích hợp trên nhánh tính năng

- **Code signing và nguồn gốc:** đường build stable yêu cầu signer Authenticode trong certificate store/HSM, EKU Code Signing, chuỗi Windows tin cậy, RFC 3161 timestamp, worktree sạch và provenance được ràng buộc với snapshot release. Signer Authenticode của EXE được tách khỏi signer CMS nội dung update đang được client ghim; việc đổi signer cần bản cập nhật bắc cầu theo [chính sách code-signing](CODE-SIGNING-POLICY-v1.md).
- **Catalog và plugin:** catalog phần mềm có trạng thái Fresh/Warning/Stale/Future/Invalid/Unavailable; dữ liệu quá cũ, sai hoặc có ngày tương lai chỉ còn giá trị nhận diện và không được dùng làm bằng chứng quyết định. Plugin và catalog plugin bên thứ ba dùng detached CMS SHA-256 với fingerprint chứng thư do quản trị viên ghim; catalog không tự tải mạng hoặc chạy mã.
- **Hiệu năng và phạm vi:** Quick/Standard/Deep, chế độ máy yếu và include/exclude hiện chỉ điều khiển traversal read-only khi tạo báo cáo/kiểm kê. Chúng không thay đổi cleanup, license deep-scan, forensics hoặc assurance. Root bị giới hạn ở thư mục cục bộ rõ ràng và chặn UNC/junction/symlink. Cả Standard và Deep vẫn có ngân sách depth/result/timeout; traversal chạm giới hạn phải ghi độ phủ chưa hoàn tất, không được suy diễn `CoverageComplete=true` chỉ từ tên profile.
- **Giao diện:** theme hệ thống được áp dụng lúc khởi động và có override ghi nhớ; PerMonitorV2 có fallback PerMonitor/System cho Windows cũ, các hộp thoại dùng DPI scaling. Việc tự đổi theme khi Windows thay đổi trong lúc ứng dụng đang chạy chưa nằm trong phạm vi hiện tại.
- **Báo cáo:** HTML vẫn self-contained/offline-safe trước khi mở. WebView2 được hoãn, chưa có runtime loader/control và không phải dependency. Trình duyệt mặc định cùng chuỗi xuất PDF Edge/Chrome/Word tiếp tục là fallback để ứng dụng vẫn khởi động trên Windows 7; khả năng tạo PDF còn phụ thuộc engine có trên máy và yêu cầu PDF phải thất bại rõ ràng nếu không tạo được tệp.
- **Doanh nghiệp:** xuất fleet hàng loạt JSON/CSV/HTML/PDF, mặc định che dữ liệu nhạy cảm, lọc client/freshness và chống CSV formula injection; có CLI headless cùng script Install/Detect/Repair/Uninstall idempotent cho Intune/MDM hoặc quản trị trung tâm.
- **Minh bạch và review:** có security policy, audit scope, quy trình disclosure/review có kiểm soát, chính sách code-signing và tài liệu kết quả kiểm thử. Schema/catalog/safety policy và verifier là phạm vi ưu tiên cho review; khóa ký, bí mật Enterprise, dữ liệu khách hàng và logic khắc phục nhạy cảm không được công khai.
- **Ma trận VM:** workflow và bộ tổng hợp public-safe đã được khai báo cho Windows 10 22H2, Windows 11 nhánh trước và nhánh hiện hành. Chúng kiểm tra DisplayVersion/build/UBR, commit và danh sách verifier bắt buộc; tóm tắt không mang raw output. Đây mới là hạ tầng tạo bằng chứng, không phải bằng chứng một release candidate đã đạt.

## Trạng thái bằng chứng hiện tại

- ManagedSigned Preview R6 có evidence `Passed=1`, `Failed=0`, `Missing=2`: Windows 11 current/25H2 đạt 11 verifier; Windows 10 22H2 và Windows 11 previous/24H2 còn thiếu. Evidence chỉ áp dụng cho commit R6 đã ghi, không tự động áp dụng cho commit phát triển mới.
- Chưa có hậu kiểm stable bằng chứng thư CA-issued và timestamp thật. Build development, kể cả khi verifier cục bộ đạt, không đủ điều kiện đưa lên kênh production.
- Chưa có kiểm thử WebView2 vì tính năng này được hoãn. Fallback Windows 7, chuyển màn hình/DPI, accessibility và đổi theme khi đang chạy vẫn cần kiểm thử máy thật phù hợp.
- Scan profile chỉ cam kết cho luồng tạo báo cáo/kiểm kê read-only; tài liệu và UI không được mô tả nó là profile quét toàn ứng dụng.

## Cổng còn phải hoàn tất ngoài mã nguồn

1. Mua/cấp chứng thư code-signing tổ chức thật (ưu tiên EV khi phù hợp), đặt private key trong HSM/token/dịch vụ ký và cấu hình quyền release tối thiểu.
2. Chốt source snapshot commit, chỉ cho phép metadata release được kiểm soát thay đổi sau snapshot, rồi ký provenance/update manifest; build trên môi trường sạch và hậu kiểm chữ ký/timestamp trên máy sạch.
3. Cấu hình environment `client-vm-validation`, ba self-hosted runner được cô lập và biến `ENABLE_CLIENT_VM_MATRIX`; chạy ma trận trên đúng release candidate và công bố artifact tóm tắt.
4. Tổ chức security review độc lập hoặc chương trình disclosure/bug-bounty có phạm vi, kênh riêng và ngân sách rõ ràng. Không gọi là bug bounty trước khi các điều kiện này được công bố.
5. Chạy accessibility/DPI thủ công, kiểm thử máy thật và kiểm thử nâng cấp/rollback trước khi gắn nhãn stable.

Build Public Stable nay có cổng fail-closed bổ sung: bắt buộc nạp JSON ma trận VM đủ 3/3 Passed, ba kết quả VM thô có hash/kích thước kiểm chứng được và attestation security review độc lập gắn đúng source snapshot commit. Thiếu bằng chứng, raw evidence bị sửa hoặc generator không khớp snapshot thì `BUILD.ps1 -RequireAuthenticode` phải dừng.

EV giúp xác minh nhà phát hành và bảo vệ khóa tốt hơn nhưng không bảo đảm SmartScreen hết cảnh báo ngay. Uy tín còn phụ thuộc lịch sử phát hành sạch, publisher ổn định, kênh tải đáng tin cậy và tỷ lệ false positive thấp.
