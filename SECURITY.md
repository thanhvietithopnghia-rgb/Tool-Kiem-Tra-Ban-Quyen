# Chính sách bảo mật

## Báo cáo lỗ hổng

Không đăng công khai lỗ hổng chưa được khắc phục, khóa ký, mã ghép nối, bí mật Enterprise, dữ liệu máy khách hoặc mẫu khai thác chứa dữ liệu thật.

Ưu tiên gửi báo cáo bằng **Private vulnerability reporting / Security Advisory** của kho mã nguồn chính thức. Nếu kênh đó chưa được bật, hãy liên hệ riêng với đơn vị đã cung cấp bản cài và yêu cầu một kênh mã hóa; không đính kèm bí mật trong tin nhắn đầu tiên.

Báo cáo hữu ích nên có:

- phiên bản, bản dựng và SHA-256 của tệp;
- Windows/PowerShell đã thử;
- bước tái hiện tối thiểu và tác động;
- bằng chứng đã loại bỏ product key, token, tên máy, IP và dữ liệu cá nhân;
- đề xuất thời hạn công bố phối hợp.

Mục tiêu phản hồi ban đầu là 5 ngày làm việc. Đây là mục tiêu vận hành, không phải cam kết pháp lý. Dự án hiện chưa công bố chương trình thưởng tiền; chỉ gọi là bug bounty khi phạm vi, điều kiện và ngân sách đã được công bố chính thức.

## Phạm vi được khuyến khích

- xác thực chữ ký, chống rollback catalog và fail-closed;
- launcher, ranh giới tiến trình, đường dẫn/reparse point và cập nhật;
- parser catalog/plugin khai báo, schema báo cáo và chống CSV formula injection;
- Enterprise pairing, DPAPI, envelope HMAC, phân quyền, rate limit và giới hạn LAN/VPN;
- rò rỉ product key, token, tên máy, IP hoặc đường dẫn nội bộ;
- sai khác hành vi giữa Windows 10 22H2 và các bản Windows 11 được hỗ trợ.

Không thử trên hệ thống không thuộc quyền kiểm soát của bạn, không gây gián đoạn, không quét Internet và không thu thập dữ liệu thật quá mức cần thiết.

## Bản dựng và chữ ký

Chỉ xem bản dựng là chính thức khi chữ ký Authenticode hợp lệ, chuỗi chứng thư được Windows tin cậy, dấu thời gian hợp lệ và SHA-256 khớp kênh phát hành chính thức. Xem `CODE-SIGNING-POLICY-v1.md`.

## Dữ liệu Enterprise

Mặc định xuất fleet đã ẩn định danh/IP/partial key, không chứa full product key và chống công thức CSV. Chỉ dùng tùy chọn xuất dữ liệu nhạy cảm trong môi trường quản trị được kiểm soát. Không mở cổng Enterprise trực tiếp ra Internet; giới hạn firewall vào CIDR LAN/VPN đã phê duyệt.
