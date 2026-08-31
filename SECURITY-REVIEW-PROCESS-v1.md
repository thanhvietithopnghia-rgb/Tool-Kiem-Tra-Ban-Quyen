# Quy trình security review có kiểm soát v1

## 1. Tiếp nhận và phân loại

- ghi nhận qua kênh riêng trong `SECURITY.md`;
- xác nhận phiên bản, hash và quyền sở hữu môi trường thử;
- xóa/che product key, token, tên máy, IP và dữ liệu cá nhân;
- phân loại tác động đến confidentiality, integrity, availability và khả năng phục hồi.

## 2. Cô lập và tái hiện

- dùng VM/fixture tổng hợp, không dùng máy khách thật;
- đóng băng commit và lưu hash của artifact;
- không chạy proof-of-concept phá hoại trên hệ thống sản xuất;
- giữ log tối thiểu, có thời hạn xóa.

## 3. Khắc phục

- ưu tiên fail-closed cho chữ ký/catalog/plugin và thao tác thay đổi hệ thống;
- thêm verifier hồi quy cho đường khai thác;
- review độc lập phần vá và tác động tương thích Windows 7–11;
- thay/thu hồi secret nếu có khả năng đã lộ; không đưa secret vào issue/commit.

## 4. Phát hành phối hợp

- ký Authenticode và timestamp theo `CODE-SIGNING-POLICY-v1.md`;
- chạy verifier nguồn, verifier Enterprise và ma trận VM được bảo vệ;
- công bố mức độ, phiên bản đã sửa, biện pháp giảm thiểu và giới hạn;
- ghi nhận người báo cáo nếu họ đồng ý.

### Attestation bắt buộc cho Public Stable

- reviewer độc lập phát hành báo cáo cuối và SHA-256 của báo cáo;
- attestation JSON phải theo `SECURITY-REVIEW-ATTESTATION-TEMPLATE-v1.json`, gắn đúng release version và source snapshot commit;
- `ReviewStatus=Passed` chỉ được dùng khi không còn finding Critical/High mở;
- phạm vi tối thiểu gồm threat model, privilege boundary, remediation/rollback, catalog/plugin trust, update/transport và tampering/downgrade;
- maintainer không tự điền danh tính reviewer để thay thế một review độc lập;
- `VERIFY-STABLE-READINESS.ps1` kiểm tra attestation và VM summary trước build Public Stable.

## 5. Đóng và học lại

- xác nhận bản vá trên môi trường ban đầu;
- cập nhật safety policy/schema nếu cần;
- lưu bản tóm tắt không chứa bí mật;
- đặt ngày xem lại nếu phụ thuộc catalog, chứng thư hoặc Windows lifecycle.

Không cam kết bounty trước khi chương trình riêng được phê duyệt và công bố. Review trả phí, NDA và quyền truy cập mã riêng phải được phê duyệt theo từng đợt.
