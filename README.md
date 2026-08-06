# Công cụ kiểm tra cấu hình máy và bản quyền phần mềm v4.6

Phiên bản v4.6 hỗ trợ người dùng cá nhân và doanh nghiệp, tập trung vào giao diện dễ đọc, kiểm kê toàn bộ phần mềm phát hiện được, đối chiếu bằng chứng bản quyền và bảo mật dữ liệu.

Bản cập nhật dùng Catalog Lifecycle 1.1 để nhận diện Windows 10 22H2, Windows 11 23H2/24H2/25H2/26H1; Office 2021/2024, Microsoft 365 Apps và phần mềm khác từ nhiều nguồn cài đặt. Catalog cảnh báo tuổi 30/45 ngày; phiên bản Microsoft chưa biết chuyển sang chỉ đọc và yêu cầu rà soát thay vì bị kết luận sai. Giao diện Dashboard 2.0 hỗ trợ Sáng/Tối, tự tối ưu theo DPI và chỉ kết nối online khi người dùng đồng ý.

Offline vẫn là mặc định: công cụ không tự kết nối mạng và không tải lên danh sách phần mềm, đường dẫn, khóa hoặc token. Báo cáo HTML/PDF được tăng cường bảo vệ, đồng thời tính toàn vẹn của dữ liệu được xác minh bằng SHA-256 và HMAC.

Khả năng quản lý tập trung qua mạng LAN cũng được nâng cấp với cơ chế mã hóa AES-256-CBC, giúp quản trị viên kiểm kê và theo dõi tình trạng bản quyền an toàn, nhanh chóng và hiệu quả hơn.

Phiên bản hiện tại: **v4.6 — FileVersion 4.6.0.0 — Build 2026.08.06**

Tác giả và phát triển: **Thanh Việt**

## Điểm chính

- Một tệp EXE AnyCPU, tự chạy đúng kiến trúc x64 hoặc x86.
- Giao diện WinForms ghi nhớ chế độ sáng/tối, tiếng Việt/English và tự co giãn theo DPI mà không cần cuộn cửa sổ chính.
- Ghi nhớ ngôn ngữ, theme và trạng thái Offline/Online mặc định theo tài khoản người dùng.
- Cảnh báo khi chạy trong máy ảo hoặc Remote Desktop mà không khóa chức năng.
- Có nút **Sao chép toàn bộ log**, **Mở thư mục báo cáo** và lịch sử phiên bản hiển thị ngay trong Tool.
- Quét nhiều bản Office và nhiều nguồn tệp song song có giới hạn để tăng tốc trên máy nhiều ổ đĩa.
- Quét sâu phổ quát từng phần mềm phát hiện được: phân bổ ngân sách chữ ký có trọng số nhưng vẫn giữ độ phủ cho mọi nhóm, kiểm tra nhiều EXE/DLL, hash xấu đã biết, artifact, hosts, firewall, IFEO, dịch vụ và autorun; mọi giới hạn và độ phủ đều được ghi vào báo cáo.
- Catalog phần mềm `1.2.0.0` có 45 quy tắc, gồm 16 nhóm phần mềm kỹ thuật CAD/CAE/BIM, mô phỏng, kết cấu, GIS, EDA, đo lường và rendering.
- **Dry Run** cho khắc phục: lập kế hoạch chi tiết và báo cáo nhưng không tạo restore point/backup, không dừng, xóa hoặc sửa hệ thống; thực hiện thật phải chọn và xác nhận lại.
- DataSchema `2.0` dùng vùng ghi v4.6 riêng; migration từ v4.4/v4.5 được staging, kiểm tra SHA-256, commit có rollback và không xóa dữ liệu cũ.
- Mười chức năng được đánh số rõ ràng từ 01 đến 10.
- Khu vực hoạt động để trống khi khởi động; khi có tác vụ mới hiển thị tiến độ, thời gian, nhật ký và nút **Dừng**.
- Hai trạng thái mạng ngắn gọn **Offline/Online**; Tool luôn khởi động Offline và chỉ dùng mạng sau khi người dùng chủ động bật.
- Kiểm tra mặc định chỉ đọc; thao tác thay đổi hệ thống yêu cầu quyền quản trị, xem trước, lựa chọn, xác nhận và backup.
- Báo cáo HTML/PDF dùng cùng giao diện chuyên nghiệp, lưu trên Desktop và tự mở bản HTML bằng trình duyệt.
- JSON/XML và manifest SHA-256 phục vụ tích hợp, lưu trữ và đối chiếu.
- Không telemetry, không tự kiểm tra cập nhật và không dùng mô hình AI trực tuyến khi chạy.

## Mười chức năng

1. **Kiểm tra toàn bộ** — tổng hợp cấu hình, Windows, Office, phần mềm và đánh giá chung.
2. **Cấu hình phần cứng** — CPU, RAM, bo mạch, BIOS/UEFI, ổ đĩa, đồ họa, mạng và thiết bị.
3. **Bản quyền Windows** — trạng thái kích hoạt, edition, kênh cấp phép, PartialProductKey và KMS nếu có.
4. **Bản quyền Microsoft Office** — Office 2021/2024/LTSC, Microsoft 365 Apps, Click-to-Run, SKU và OSPP.
5. **Phần mềm & dấu hiệu can thiệp** — kiểm kê mọi nguồn cài đặt được hỗ trợ và quét sâu có giới hạn cho từng ứng dụng, gồm nhiều tệp thực thi/DLL, chữ ký số, hash, artifact, hosts, firewall, IFEO, tự động chạy, dịch vụ, tác vụ và bằng chứng kỹ thuật kích hoạt bị can thiệp.
6. **Khắc phục KMS/Activator** — chọn Quét toàn bộ, Windows & Office hoặc Phần mềm khác; có Dry Run không thay đổi hệ thống và luồng thực yêu cầu chọn/xác nhận lại. Mọi mục Không chính hãng/Nghi vấn đều chọn thủ công được; tự động chỉ chạy kế hoạch an toàn đã khóa phạm vi, còn gỡ/cài lại chính thức luôn cần xác nhận riêng và backup có kiểm chứng.
7. **Khôi phục key OEM** — kiểm tra key firmware và chỉ áp dụng khi người dùng xác nhận edition phù hợp.
8. **Quản lý giấy phép hợp lệ** — quản lý Windows/Office cục bộ hoặc máy chủ/máy trạm trong LAN được cho phép.
9. **Kiểm tra chuyên sâu** — quét sâu và điều tra forensics dành cho quản trị viên.
10. **Trung tâm báo cáo bảo đảm** — chứng chỉ, plugin, timeline, HDSD HTML/PDF và tài liệu phiên bản/cập nhật.

## Bắt đầu nhanh

1. Tải gói phát hành chính thức và đối chiếu SHA-256.
2. Giải nén toàn bộ gói vào một thư mục cố định; không chạy EXE trực tiếp bên trong ZIP.
3. Chạy `Tool-Kiem-Tra-v4.6.exe` và chấp nhận UAC.
4. Tool khôi phục theme và Offline/Online đã lưu. Chỉ chuyển sang **Online** khi chức năng đang dùng thực sự cần Internet/LAN.
5. Chọn chức năng 01–10 trên màn hình chính.
6. Khi tác vụ hoàn tất, đọc bản HTML được mở tự động; bản HTML và PDF nằm trên Desktop.

Hướng dẫn sử dụng v4.6 dành cho người trực tiếp chạy EXE nằm trong `HUONG-DAN.txt` và được mở nhanh bằng:

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

## Mô hình vận hành, công nghệ và ngôn ngữ

Tool dùng mô hình **local-first, offline-first**: một EXE cung cấp 10 chức năng trên máy đang quản trị. Kiểm tra mặc định chỉ đọc; thay đổi hệ thống phải qua quyền Administrator, xem trước, lựa chọn cụ thể, xác nhận và backup. Không có dịch vụ đám mây bắt buộc, telemetry, tự kiểm tra cập nhật hoặc tự gửi báo cáo.

- **Launcher:** C#/.NET Framework 4, AnyCPU, kiểm tra SHA-256 của payload và chọn Windows PowerShell native.
- **Giao diện và nghiệp vụ:** Windows PowerShell 3+/WinForms; theo dõi tiến trình con và cho phép dừng tác vụ đang chạy.
- **Hợp đồng dữ liệu:** JSON cho catalog, localization, plugin và kết quả mô-đun.
- **Vòng đời dữ liệu:** DataSchema 2.0, `ProducerVersion`, mutex migration, staging/đối chiếu SHA-256/rollback và vùng ghi `%ProgramData%\ThanhViet-Tool-Kiem-Tra\v4.6`.
- **Báo cáo:** HTML/CSS tự chứa, JSON, XML và SHA-256.
- **PDF:** tạo cục bộ bằng Microsoft Edge, Google Chrome hoặc Microsoft Word; không dùng dịch vụ chuyển đổi trực tuyến.
- **Plugin:** quy tắc JSON khai báo chỉ đọc; không nạp DLL hoặc thực thi mã plugin tùy ý.
- **Timeline:** DPAPI LocalMachine, HMAC-SHA256 và chuỗi hash.
- **Mạng doanh nghiệp tùy chọn:** Trung tâm quản lý giấy phép có công tắc Online/Offline riêng; HTTP trong LAN với phong bì ứng dụng AES-256-CBC + HMAC-SHA256, nonce, timestamp và kiểm soát replay.

Mã nguồn PowerShell là nguồn sự thật cho logic nghiệp vụ. Launcher C# chỉ đóng gói, xác minh và khởi chạy đúng môi trường.

## Lịch sử phát triển chính

Lịch sử trên GitHub dùng số phiên bản phát hành như `v4.6`; các số vá nội bộ được gộp khi không thay đổi hợp đồng công khai.

- **v1.0–v1.3:** hình thành giao diện Windows, kiểm tra cấu hình/bản quyền, tiến độ tác vụ, key OEM và quét chuyên sâu có UAC nhưng vẫn chỉ đọc.
- **v2.4–v2.9:** tối ưu bố cục, quản lý key/edition hợp lệ, điều tra 7/12 nhóm, chấm điểm rủi ro, bộ bằng chứng HTML/JSON/CSV/SHA-256 và hậu kiểm.
- **v3.0–v3.5:** khắc phục chọn lọc, backup/restore, manifest, DPAPI/HMAC, kiểm tra toàn vẹn, nhật ký trực tiếp và chính sách fail-closed.
- **v3.6–v3.9:** một EXE AnyCPU, build deterministic, PE hardening, capability schema, JSONL logging, module contract và report schema có verifier x64/x86.
- **v4.0–v4.6:** dashboard hiện đại, giao diện Light mặc định, Trung tâm bảo đảm, plugin/timeline, quản lý máy chủ–máy trạm trong LAN, cảnh báo môi trường, quét song song và báo cáo HTML/PDF thống nhất.

Chi tiết từng mốc từ `v1.0` đến `v4.6`, gồm nâng cấp, công nghệ và ngôn ngữ, nằm trong [`LICH-SU-PHIEN-BAN.txt`](LICH-SU-PHIEN-BAN.txt).

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
Get-FileHash .\Tool-Kiem-Tra-v4.6.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v4.6.exe | Format-List Status,StatusMessage,SignerCertificate
```

Đối chiếu hash với manifest trong gói phát hành. EXE chỉ được công bố là đã ký khi trạng thái Authenticode thực tế là `Valid`; nếu chưa có chứng thư ký mã, tài liệu phát hành phải ghi rõ `NotSigned`.

## Tài liệu

- `HUONG-DAN.txt` — hướng dẫn người dùng v4.6: điểm mới, cách chạy EXE và toàn bộ chức năng.
- `USER-GUIDE-en-US.md` — complete English v4.6 end-user guide.
- `LICH-SU-PHIEN-BAN.txt` — lịch sử phiên bản tiếng Việt.
- `VERSION-HISTORY-en-US.md` — English version history.
- `README-MA-NGUON.md` — cách build, kiểm thử và đóng gói.
- `TECHNICAL-ARCHITECTURE-v4.6.md` — kiến trúc kỹ thuật.
- `SAFETY-POLICY-v1.0.md` — ranh giới an toàn.

## Tải chính thức và hỗ trợ

Kho dự án: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen>

Chỉ tải từ kho chính thức, đối chiếu phiên bản và SHA-256 trước khi dùng.

- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

© 2026 Thanh Việt. Không xóa thông tin tác giả, mạo danh, đóng gói lại hoặc phân phối dưới tên khác khi chưa có chấp thuận bằng văn bản.
