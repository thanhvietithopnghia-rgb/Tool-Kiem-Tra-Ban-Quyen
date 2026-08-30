# Chính sách code signing v1

## Mục tiêu

Bản stable phải được ký Authenticode bằng chứng thư code-signing do CA công cộng tin cậy, có EKU Code Signing, dấu thời gian RFC 3161 và hậu kiểm trên máy sạch. Khóa riêng không nằm trong kho mã, gói build, log hoặc artifact CI.

Kênh `ManagedSigned` dùng chứng thư tự ký đã ghim và vẫn bắt buộc chữ ký Authenticode nguyên vẹn, RFC 3161 timestamp, đúng SHA-1/SHA-256 của signer, provenance CMS của source snapshot và worktree sạch. Trên máy đã được quản trị viên phân phối trust anchor, Windows xác minh chuỗi theo cách thông thường. Với ngoại lệ portable được công bố rõ, launcher chỉ chấp nhận thêm đúng lỗi `CERT_E_UNTRUSTEDROOT` sau khi signer tự ký khớp cả hai pin; `TRUST_E_BAD_DIGEST`, sai signer, sai SHA-256 chứng thư và mọi lỗi khác vẫn bị khóa. Windows/SmartScreen vẫn có thể báo `Unknown publisher` trên máy mới; kênh này không được mô tả là public-CA và không dùng cơ chế tự cập nhật public.

Kênh `StoreSubmission` là ngoại lệ đóng gói có chủ đích: EXE bên trong chưa ký Authenticode trước khi tải lên, còn gói cuối do Microsoft Store ký sau chứng nhận. Launcher chỉ mở thao tác thay đổi hệ thống khi Windows gắn đúng package family `ThanhVit.ToolKimTraBnQuyn_9tjmpwr25h78w`, đúng phiên bản/kiến trúc, báo `PackageOrigin_Store` và provenance CMS của source snapshot hợp lệ. Mỗi yêu cầu UAC phải quay lại launcher đã biên dịch để xác minh trust lần nữa, giải nén payload vào vùng chỉ Administrator/SYSTEM được ghi, kiểm lại hash cây payload gốc và áp allowlist tham số riêng theo `ModuleId` trước khi chạy script. EXE bị sao chép ra ngoài package, gói sideload DeveloperSigned/LineOfBusiness, script bị thay sau lần kiểm đầu hoặc module chỉ-đọc mang cờ thay đổi hệ thống đều phải fail-closed; kênh này không dùng public self-update.

Ưu tiên EV khi ngân sách và quy trình vận hành cho phép vì xác minh danh tính/giữ khóa chặt hơn. Tuy nhiên **EV không bảo đảm SmartScreen hết cảnh báo ngay lập tức**. Uy tín còn phụ thuộc lịch sử phát hành sạch, tên publisher ổn định, kênh tải đáng tin cậy, mức phổ biến và việc không đổi chứng thư tùy tiện.

## Hai vai trò tin cậy độc lập

Pipeline stable cấu hình hai chứng thư độc lập; chúng có thể thuộc cùng một tổ chức nhưng không được dùng một thumbprint như thể hai trust domain là một:

1. **Signer Authenticode của EXE/PE:** chứng minh publisher của executable. Chứng thư phải có EKU Code Signing, chuỗi Windows tin cậy và timestamp RFC 3161 hợp lệ. Update manifest khai báo thumbprint signer được phép cho executable, và verifier phải đối chiếu khai báo đó với chữ ký thật trên tệp.
2. **Signer CMS nội dung update:** ký detached CMS cho update manifest/checksum. Đây là trust anchor nội dung mà client ghim để quyết định manifest nào được quyền khai báo hash artifact và signer Authenticode. Chứng thư này không mặc nhiên là signer của EXE và không được thay bằng tham số Authenticode chỉ vì cùng một đợt phát hành.

Tách hai vai trò giúp thay chứng thư Authenticode mà không phải đồng thời thay trust anchor nội dung. Private key, quyền ký, audit log và quy trình thu hồi của từng vai trò phải được quản lý riêng. Bản build phát triển không ký chỉ mang trạng thái `DevelopmentUnsigned`; nó không phải bằng chứng cho pipeline stable và không được đưa lên kênh production.

## Quy tắc phát hành

1. Dev/test không ký phải mang trạng thái `DevelopmentUnsigned`; artifact không được đưa lên kênh stable.
2. Public Stable phải có trạng thái WinVerifyTrust thành công; không chấp nhận self-signed hoặc untrusted root như bản chính thức.
3. `ManagedSigned` chấp nhận signer tự ký khi Windows đã tin cậy đúng trust anchor; ngoại lệ portable chỉ chấp nhận thêm `CERT_E_UNTRUSTEDROOT` khi signer tự ký khớp đồng thời SHA-1 và SHA-256 đã ghim. Chữ ký/timestamp/provenance phải hợp lệ và manifest phải ghi `PinnedSelfSignedPortable`.
4. `StoreSubmission` chỉ chấp nhận EXE có Store marker riêng, exact package identity đã ghim, provenance CMS hợp lệ và release manifest `MicrosoftStorePackageIdentity`; Partner Center chịu trách nhiệm ký gói cuối.
5. Ký mọi PE/launcher được phát hành trực tiếp và timestamp trong cùng pipeline được bảo vệ; ngoại lệ duy nhất là EXE nằm trong `StoreSubmission` được Store ký ở cấp package.
6. Hậu kiểm publisher, EKU, thumbprint/SHA-256 chứng thư Authenticode, timestamp và hash artifact trên máy sạch không có chứng thư dev; với Store phải hậu kiểm package identity sau cài đặt.
7. Manifest/checksum phải được tạo sau khi ký executable; update manifest sau đó phải được ký detached CMS bằng đúng signer nội dung đã ghim. Store không phát hành public update manifest và giữ self-update tắt.
8. Build/release phải nhận signer Authenticode và signer CMS nội dung bằng hai cấu hình rõ ràng; không suy diễn một thumbprint cho cả hai vai trò.
9. Không công bố build stable chỉ dựa trên việc các verifier tĩnh đạt; còn cần chứng thư thật hoặc chữ ký Store cuối, provenance của đúng commit, worktree sạch và hậu kiểm artifact cuối.

## Chuyển đổi chứng thư

Rollover signer Authenticode phải giữ đường nâng cấp cho client đã cài. Khi signer cũ là chứng thư đã được Windows tin cậy trên client, trước khi phát hành executable dùng signer mới cần một **bản cập nhật bắc cầu** vẫn được ký Authenticode bằng signer cũ và có update manifest do signer CMS cũ đang được client ghim ký. Bản bắc cầu cập nhật logic/pin để client có thể chấp nhận signer Authenticode mới khi signer đó được một manifest CMS hợp lệ ủy quyền.

Signer Authenticode legacy hiện được ghim trong source là chứng thư tự ký; trên máy sạch không tin cậy chứng thư này, nó không thể tạo một bản bắc cầu đạt cổng stable CA-issued. Pipeline stable không được hạ cổng để hợp thức hóa signer cũ. Client không thể xác minh bản bắc cầu phải nâng cấp thủ công bằng gói CA-signed từ kênh chính thức sau khi đối chiếu publisher/SHA-256. Chỉ các máy đã tin cậy signer legacy theo chính sách quản trị mới có thể dùng bản bắc cầu; artifact đó phải mang nhãn transitional, không được gọi là stable CA-signed.

Sau khi bản bắc cầu đã được phân phối và theo dõi đủ, manifest vẫn do trust anchor CMS được chấp nhận ký mới được khai báo executable mang signer Authenticode mới. Rollover signer CMS là một quy trình riêng: phải có giai đoạn chồng lấn hoặc gói cập nhật trust được signer CMS cũ ủy quyền. Không đổi đồng thời cả hai trust anchor, không tắt xác minh và không giả định client cũ tự hiểu pin mới. Kế hoạch phải có rollback, thời hạn hỗ trợ signer cũ và hướng xử lý máy bỏ lỡ bản bắc cầu.

## Bảo vệ khóa

- ưu tiên token phần cứng/HSM hoặc dịch vụ ký có xác thực mạnh;
- chỉ job release được bảo vệ mới có quyền ký;
- không xuất private key nếu nhà cung cấp hỗ trợ ký từ xa;
- tách người phê duyệt release và người quản trị khóa khi có thể;
- theo dõi audit log, giới hạn số lần ký và cảnh báo ký ngoài cửa sổ release.

## Sự cố và thu hồi

Khi nghi ngờ lộ khóa: dừng phát hành, vô hiệu hóa job ký, liên hệ CA để thu hồi, bảo toàn audit log, phát hành chỉ dẫn xác minh hash và chuyển sang chứng thư mới qua quy trình rollover. Không xóa lịch sử để che sự cố.

## SmartScreen

Không hứa “không còn cảnh báo”. Cách giảm cảnh báo hợp lệ là chữ ký công cộng ổn định, artifact không đổi sau ký, HTTPS/kênh chính thức, ít false positive, lịch sử phiên bản sạch và hướng dẫn người dùng kiểm tra Publisher/SHA-256. Không khuyến khích người dùng tắt SmartScreen.
