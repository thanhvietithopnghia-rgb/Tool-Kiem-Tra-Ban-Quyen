# Audit scope v1

Tài liệu này xác định phần có thể cung cấp cho kiểm toán độc lập mà không phải công khai bí mật phát hành hoặc logic khắc phục nhạy cảm.

## Bề mặt có thể kiểm toán

- schema catalog, catalog mẫu và quy tắc freshness/anti-rollback;
- schema báo cáo, quy tắc redaction, xuất JSON/CSV/HTML/PDF và manifest SHA-256;
- safety policy, quyết định fail-closed và các verifier hồi quy;
- plugin khai báo: schema, giới hạn dữ liệu, chữ ký và trust policy;
- Enterprise protocol metadata, envelope, pairing, rate limit, ACL, vòng đời dữ liệu và CLI headless;
- script build/verify chữ ký không chứa khóa;
- workflow và tóm tắt ma trận VM.

## Phần chỉ xem trong review có kiểm soát

- launcher/bản dựng đầy đủ chưa phát hành;
- logic khắc phục có thể làm thay đổi trạng thái Windows hoặc giấy phép;
- cấu hình hạ tầng phát hành, runner tự quản và danh sách quản trị;
- phát hiện chưa được vá.

Reviewer chỉ nhận quyền tối thiểu, theo thời hạn, trên snapshot có SHA-256/commit cố định. Mọi dữ liệu khách hàng phải được thay bằng fixture tổng hợp.

## Ngoài phạm vi công khai

- private key, PFX password, token timestamp, CI secret, recovery key;
- pairing code, DPAPI blob, HMAC/master secret và client secret;
- báo cáo thật, product key, tên máy, IP, tài khoản người dùng;
- credential hoặc cấu hình truy cập runner/MDM.

## Bằng chứng tối thiểu của một đợt audit

1. commit/SHA-256 được xem xét;
2. phạm vi và giả định;
3. hệ điều hành/công cụ kiểm thử;
4. phát hiện kèm mức độ, trạng thái khắc phục và kiểm thử hồi quy;
5. phần đã che hoặc không thể kiểm tra;
6. ngày hiệu lực và ngày cần đánh giá lại.

Kết quả tóm tắt có thể công bố sau khi xử lý phát hiện nghiêm trọng. Bản đầy đủ chỉ chia sẻ theo nguyên tắc need-to-know.
