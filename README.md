# Tool Kiểm Tra Cấu Hình & Bảo Đảm Bản Quyền Windows/Office

Tool Kiểm Tra là bộ công cụ quản trị cục bộ dành cho Windows và Microsoft Office. Công cụ giúp kiểm kê cấu hình, đọc trạng thái cấp phép, rà soát dấu hiệu can thiệp, thực hiện khắc phục có kiểm soát và xuất hồ sơ HTML/PDF có thể kiểm chứng.

Phiên bản hiện tại: **v4.3.0.7 Enterprise — Build 2026.07.31**

Tác giả và phát triển: **Thanh Việt**

## Điểm chính

- Một tệp EXE AnyCPU, tự chạy đúng kiến trúc x64 hoặc x86.
- Giao diện WinForms sáng/tối, tiếng Việt/English và tự co giãn theo DPI.
- Mười chức năng được đánh số rõ ràng từ 01 đến 10.
- Kiểm tra mặc định chỉ đọc; thao tác thay đổi hệ thống yêu cầu quyền quản trị, xem trước, lựa chọn, xác nhận và backup.
- Báo cáo HTML/PDF dùng cùng giao diện chuyên nghiệp, lưu trên Desktop và tự mở bản HTML bằng trình duyệt.
- JSON/XML và manifest SHA-256 phục vụ tích hợp, lưu trữ và đối chiếu.
- Không telemetry, không tự kiểm tra cập nhật và không dùng mô hình AI trực tuyến khi chạy.

## Mười chức năng

1. **Kiểm tra toàn bộ** — tổng hợp cấu hình, Windows, Office, phần mềm và đánh giá chung.
2. **Cấu hình phần cứng** — CPU, RAM, bo mạch, BIOS/UEFI, ổ đĩa, đồ họa, mạng và thiết bị.
3. **Bản quyền Windows** — trạng thái kích hoạt, edition, kênh cấp phép, PartialProductKey và KMS nếu có.
4. **Bản quyền Microsoft Office** — Office 2024/LTSC, Microsoft 365 Apps, Click-to-Run, SKU và OSPP.
5. **Phần mềm & dấu hiệu can thiệp** — giữ giao diện/báo cáo truyền thống, đồng thời bổ sung chữ ký số, nguồn cài, tự động chạy, dịch vụ, tác vụ, phiên bản song song và lý do cần rà soát.
6. **Khắc phục KMS/Activator** — quét chỉ đọc, backup có kiểm chứng, lựa chọn từng mục, xác nhận, hậu kiểm và khôi phục.
7. **Khôi phục key OEM** — kiểm tra key firmware và chỉ áp dụng khi người dùng xác nhận edition phù hợp.
8. **Quản lý giấy phép hợp lệ** — quản lý Windows/Office cục bộ hoặc máy chủ/máy trạm trong LAN được cho phép.
9. **Kiểm tra chuyên sâu** — quét sâu và điều tra forensics dành cho quản trị viên.
10. **Trung tâm báo cáo bảo đảm** — chứng chỉ, plugin, timeline, HDSD HTML/PDF và tài liệu phiên bản/cập nhật.

## Bắt đầu nhanh

1. Tải gói phát hành chính thức và đối chiếu SHA-256.
2. Giải nén toàn bộ gói vào một thư mục cố định; không chạy EXE trực tiếp bên trong ZIP.
3. Chạy `Tool-Kiem-Tra-v4.3.exe` và chấp nhận UAC.
4. Chọn ngôn ngữ, giao diện sáng/tối và chế độ mạng phù hợp.
5. Chọn chức năng 01–10 trên màn hình chính.
6. Khi tác vụ hoàn tất, đọc bản HTML được mở tự động; bản HTML và PDF nằm trên Desktop.

HDSD đầy đủ nằm trong `HUONG-DAN.txt` và được mở nhanh bằng:

- nút **Mở hướng dẫn** trong cửa sổ Giới thiệu; hoặc
- **Chức năng 10 → 6. Mở hướng dẫn sử dụng chi tiết bằng HTML/PDF**.

Lần đầu, Tool tạo HTML/PDF và manifest SHA-256. Những lần sau, nếu nguồn HDSD không đổi, Tool dùng bản cache theo phiên bản/ngôn ngữ và mở HTML ngay.

## Báo cáo và quyền riêng tư

Các báo cáo dành cho người đọc dùng chung một bố cục:

- banner tiêu đề và thông tin máy/thời điểm;
- thẻ tổng quan;
- mục lục;
- các phần nội dung, bảng và ghi chú;
- font Segoe UI, màu sắc và quy tắc ngắt trang đồng bộ cho HTML/PDF.
- PDF không chèn URL, ngày giờ hoặc header/footer mặc định của trình duyệt.

Tệp được lưu trực tiếp trên Desktop. HTML là tệp được mở mặc định; PDF được tạo để lưu/in. Với hồ sơ kỹ thuật, nên giữ HTML, PDF, JSON/XML và `SHA256SUMS` cùng nhau.

Công cụ không thu thập mật khẩu hoặc xuất product key đầy đủ. Hãy chọn báo cáo đã che trước khi chia sẻ ra ngoài nhóm quản trị có trách nhiệm.

## Mô hình triển khai và mã nguồn

- **Launcher:** C#/.NET Framework 4, AnyCPU, kiểm tra payload và chọn Windows PowerShell native.
- **Giao diện và nghiệp vụ:** Windows PowerShell/WinForms.
- **Hợp đồng dữ liệu:** JSON cho catalog, localization, plugin và kết quả mô-đun.
- **Báo cáo:** HTML/CSS tự chứa, JSON, XML và SHA-256.
- **PDF:** tạo cục bộ bằng Microsoft Edge, Google Chrome hoặc Microsoft Word; không dùng dịch vụ chuyển đổi trực tuyến.
- **Plugin:** quy tắc JSON khai báo chỉ đọc; không nạp DLL hoặc thực thi mã plugin tùy ý.
- **Timeline:** DPAPI LocalMachine, HMAC-SHA256 và chuỗi hash.
- **Mạng doanh nghiệp tùy chọn:** HTTP trong LAN với phong bì ứng dụng AES-256-CBC + HMAC-SHA256, nonce, timestamp và kiểm soát replay.

Mã nguồn PowerShell là nguồn sự thật cho logic nghiệp vụ. Launcher C# chỉ đóng gói, xác minh và khởi chạy đúng môi trường.

## An toàn khi dùng chức năng 06, 07 và 08

- Chỉ xử lý máy thuộc quyền quản trị hợp lệ.
- Đóng ứng dụng Office trước khi thay đổi giấy phép Office.
- Không chọn mục nếu chưa xác minh rõ nguồn gốc.
- Không bỏ qua bước backup, manifest, HMAC hoặc SHA-256.
- Chuẩn bị key/tài khoản bản quyền hợp lệ trước khi gỡ key hoặc trạng thái KMS cũ.
- Kết quả kỹ thuật không thay thế hóa đơn, hợp đồng hoặc xác nhận quyền sử dụng từ Microsoft.

## Xác minh bản phát hành

Trong PowerShell:

```powershell
Get-FileHash .\Tool-Kiem-Tra-v4.3.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v4.3.exe | Format-List Status,StatusMessage,SignerCertificate
```

Đối chiếu hash với manifest trong gói phát hành. EXE chỉ được công bố là đã ký khi trạng thái Authenticode thực tế là `Valid`; nếu chưa có chứng thư ký mã, tài liệu phát hành phải ghi rõ `NotSigned`.

## Tài liệu

- `HUONG-DAN.txt` — hướng dẫn chi tiết theo từng chức năng.
- `USER-GUIDE-en-US.md` — English user guide.
- `LICH-SU-PHIEN-BAN.txt` — giới thiệu phiên bản, nội dung thay đổi và mô hình/công nghệ.
- `README-MA-NGUON.md` — cách build, kiểm thử và đóng gói.
- `TECHNICAL-ARCHITECTURE-v4.3.md` — kiến trúc kỹ thuật.
- `SAFETY-POLICY-v1.0.md` — ranh giới an toàn.

## Tải chính thức và hỗ trợ

Kho dự án: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen>

Chỉ tải từ kho chính thức, đối chiếu phiên bản và SHA-256 trước khi dùng.

- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

© 2026 Thanh Việt. Không xóa thông tin tác giả, mạo danh, đóng gói lại hoặc phân phối dưới tên khác khi chưa có chấp thuận bằng văn bản.
