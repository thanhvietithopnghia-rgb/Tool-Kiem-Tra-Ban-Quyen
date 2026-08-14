# Tool Kiểm Tra v4.8 – Nhanh hơn, dễ dùng hơn, an toàn hơn

**Trang giới thiệu chính thức:** <https://thanhvietithopnghia-rgb.github.io/Tool-Kiem-Tra-Ban-Quyen/>

v4.8 tập trung vào ba điều người dùng dễ nhận thấy: thao tác rõ hơn, quét nhanh hơn và khắc phục an toàn hơn. Tool vẫn kiểm tra cấu hình, Windows, Office và phần mềm; mặc định Offline và chỉ thay đổi hệ thống sau khi người dùng chọn, xác nhận và tạo backup.

Bản cập nhật dùng Catalog Lifecycle 1.1 để nhận diện Windows 10 22H2, Windows 11 23H2/24H2/25H2/26H1; Office 2021/2024, Microsoft 365 Apps và phần mềm khác từ nhiều nguồn cài đặt. Catalog cảnh báo tuổi 30/45 ngày; phiên bản Microsoft chưa biết chuyển sang chỉ đọc và yêu cầu rà soát thay vì bị kết luận sai. Giao diện Dashboard 2.0 hỗ trợ Sáng/Tối, tự tối ưu theo DPI và chỉ kết nối online khi người dùng đồng ý.

Offline vẫn là mặc định: công cụ không kết nối mạng khi chưa được cho phép và không tải lên danh sách phần mềm, đường dẫn, khóa hoặc token. Khi Online đã được người dùng bật, Tool mới kiểm tra phiên bản mới; không tự tải hoặc cài nếu chưa chọn **Cập nhật ngay**. Báo cáo HTML/PDF được tăng cường bảo vệ, đồng thời tính toàn vẹn của dữ liệu được xác minh bằng SHA-256 và HMAC.

Khả năng quản lý tập trung qua mạng LAN cũng được nâng cấp với cơ chế mã hóa AES-256-CBC, giúp quản trị viên kiểm kê và theo dõi tình trạng bản quyền an toàn, nhanh chóng và hiệu quả hơn.

Phiên bản hiện tại: **v4.8.0 — FileVersion 4.8.0.0 — Build 2026.08.13**

Tác giả và phát triển: **Thanh Việt**

## Điểm chính

- **Dễ dùng:** giao diện Sáng/Tối, Việt/Anh và tự co giãn theo DPI; đã sửa nút **Bản đã che thông tin** bị cắt chữ hoặc mờ khi rê chuột.
- **Nhanh hơn:** tối ưu quét và kiểm kê nhưng giữ nguyên phạm vi kiểm tra; catalogue hiện có 76 quy tắc nhận diện phần mềm.
- **Báo cáo rõ hơn:** HTML dùng để xem nhanh, PDF chứa chi tiết; người dùng có thể che dữ liệu nhạy cảm trước khi chia sẻ.
- **Khắc phục an toàn:** có Dry Run, backup, chọn từng mục, UAC khi cần và kiểm tra lại kết quả; Tool không tự gỡ ứng dụng.
- **Kết luận thận trọng:** tệp bị sửa không tự đồng nghĩa phần mềm không chính hãng; kết quả chưa đủ bằng chứng được ghi rõ là chưa xác minh.
- **Trợ lý hiểu toàn phạm vi Tool:** trả lời mọi câu hỏi liên quan theo kho tri thức, HDSD nhúng và báo cáo hiện có — từ phiên bản/tác giả/tóm tắt đến mục đích, cách dùng, lỗi và trạng thái của mọi chức năng. Kho tri thức mới được lưu ngoài EXE, chỉ đồng bộ sau khi người dùng bật Online, phải có chữ ký nhà phát hành hợp lệ và không thể hạ phiên bản; câu hỏi, báo cáo và dữ liệu máy không được tải lên. Trợ lý giữ ngữ cảnh câu hỏi tiếp theo và khóa nội dung ngoài phạm vi Tool.
- **Offline mặc định:** không telemetry, không cập nhật ngầm và không gửi dữ liệu máy lên mạng khi chưa được phép.
- **Một tệp EXE:** tự chạy đúng x64/x86; có chữ ký Authenticode tự ký miễn phí để phát hiện tệp bị sửa, nhưng vẫn có thể bị SmartScreen cảnh báo trên máy lạ.

## Mười chức năng

1. **Kiểm tra toàn bộ** — tổng hợp cấu hình, Windows, Office, phần mềm và đánh giá chung.
2. **Cấu hình phần cứng** — CPU, RAM, bo mạch, BIOS/UEFI, ổ đĩa, đồ họa, mạng và thiết bị.
3. **Bản quyền Windows** — trạng thái kích hoạt, edition, kênh cấp phép, PartialProductKey và KMS nếu có.
4. **Bản quyền Microsoft Office** — Office 2021/2024/LTSC, Microsoft 365 Apps, Click-to-Run, SKU và OSPP.
5. **Phần mềm & dấu hiệu can thiệp** — kiểm kê mọi nguồn cài đặt được hỗ trợ và quét sâu có giới hạn cho từng ứng dụng, gồm nhiều tệp thực thi/DLL, chữ ký số, hash, artifact, hosts, firewall, IFEO, tự động chạy, dịch vụ, tác vụ và bằng chứng kỹ thuật kích hoạt bị can thiệp.
6. **Khắc phục KMS/Activator** — chế độ Online, Dry Run và thực hiện thật đều có ba ô tích **Windows, Office, Phần mềm khác**; có thể chọn một hoặc nhiều phạm vi và chỉ quét/xử lý đúng mục đã chọn. Mọi mục Không chính hãng/Nghi vấn đều chọn thủ công được; tự động chỉ chạy kế hoạch an toàn đã khóa phạm vi, còn gỡ/cài lại chính thức luôn cần xác nhận riêng và backup có kiểm chứng.
7. **Khôi phục key OEM** — kiểm tra key firmware và chỉ áp dụng khi người dùng xác nhận edition phù hợp.
8. **Quản lý giấy phép hợp lệ** — quản lý Windows/Office cục bộ hoặc máy chủ/máy trạm trong LAN được cho phép.
9. **Kiểm tra chuyên sâu** — quét sâu và điều tra forensics dành cho quản trị viên.
10. **Trung tâm báo cáo bảo đảm** — chứng chỉ, plugin, timeline, HDSD HTML/PDF và tài liệu phiên bản/cập nhật.

## Bắt đầu nhanh

1. Tải gói phát hành chính thức và đối chiếu SHA-256.
2. Giải nén toàn bộ gói vào một thư mục cố định; không chạy EXE trực tiếp bên trong ZIP.
3. Chạy `Tool-Kiem-Tra-v4.8.exe`. Dashboard không cần UAC; chỉ chấp nhận UAC khi tên tác vụ cho biết đang khắc phục, cập nhật hoặc quản trị hệ thống.
4. Tool luôn mở ở **Offline**. Chỉ chuyển sang **Online** trong phiên hiện tại khi cập nhật/đồng bộ thực sự cần Internet/LAN.
5. Chọn chức năng 01–10 trên màn hình chính.
6. Khi tác vụ hoàn tất, đọc bản HTML được mở tự động; toàn bộ tệp liên quan nằm cạnh nhau trong `Desktop\BaoCao-Tool-Kiem-Tra`.

Hướng dẫn sử dụng v4.8.0 dành cho người trực tiếp chạy EXE nằm trong `HUONG-DAN.txt` và được mở nhanh bằng:

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

Mỗi lần xuất tạo một nhóm tệp có cùng tên gốc và timestamp mili-giây ngay trong `Desktop\BaoCao-Tool-Kiem-Tra`, không tạo thư mục con. HTML tổng quan là tệp duy nhất được tự mở và có nút mở đúng PDF; PDF giữ đầy đủ bảng/bằng chứng và phụ lục hệ thống, còn JSON/XML và `SHA256SUMS` nằm cạnh đó để lưu trữ/đối chiếu.

Công cụ không thu thập mật khẩu hoặc xuất product key đầy đủ. Hãy chọn báo cáo đã che trước khi chia sẻ ra ngoài nhóm quản trị có trách nhiệm.

## Mô hình vận hành, công nghệ và ngôn ngữ

Tool dùng mô hình **local-first, offline-first**: một EXE cung cấp 10 chức năng trên máy đang quản trị. Kiểm tra mặc định chỉ đọc; thay đổi hệ thống phải qua quyền Administrator, xem trước, lựa chọn cụ thể, xác nhận và backup. Không có dịch vụ đám mây bắt buộc, telemetry, tự kiểm tra cập nhật hoặc tự gửi báo cáo.

- **Launcher:** C#/.NET Framework 4, AnyCPU, kiểm tra SHA-256 của payload và chọn Windows PowerShell native.
- **Giao diện và nghiệp vụ:** Windows PowerShell 3+/WinForms; theo dõi tiến trình con và cho phép dừng tác vụ đang chạy.
- **Hợp đồng dữ liệu:** JSON cho catalog, localization, plugin và kết quả mô-đun.
- **Vòng đời dữ liệu:** dashboard dùng vùng người dùng `%LOCALAPPDATA%\ThanhViet-Tool-Kiem-Tra\v4.6`; chế độ nâng quyền/doanh nghiệp dùng `%ProgramData%`; DataSchema 2.0, staging/đối chiếu SHA-256 và rollback được giữ nguyên.
- **Báo cáo:** HTML/CSS tự chứa, JSON, XML và SHA-256.
- **PDF:** tạo cục bộ bằng Microsoft Edge, Google Chrome hoặc Microsoft Word; không dùng dịch vụ chuyển đổi trực tuyến.
- **Plugin:** quy tắc JSON khai báo chỉ đọc; không nạp DLL hoặc thực thi mã plugin tùy ý.
- **Timeline:** DPAPI LocalMachine, HMAC-SHA256 và chuỗi hash.
- **Mạng doanh nghiệp tùy chọn:** Trung tâm quản lý giấy phép có công tắc Online/Offline riêng; HTTP trong LAN với phong bì ứng dụng AES-256-CBC + HMAC-SHA256, nonce, timestamp và kiểm soát replay.

Mã nguồn PowerShell là nguồn sự thật cho logic nghiệp vụ. Launcher C# chỉ đóng gói, xác minh và khởi chạy đúng môi trường.

## Lịch sử phát triển chính

Lịch sử công khai chuyển trực tiếp từ `v4.6` lên `v4.8`; các thay đổi trung gian đã kiểm định được hợp nhất vào v4.8 và không tách thành phiên bản công khai riêng.

- **v1.0–v1.3:** hình thành giao diện Windows, kiểm tra cấu hình/bản quyền, tiến độ tác vụ, key OEM và quét chuyên sâu có UAC nhưng vẫn chỉ đọc.
- **v2.4–v2.9:** tối ưu bố cục, quản lý key/edition hợp lệ, điều tra 7/12 nhóm, chấm điểm rủi ro, bộ bằng chứng HTML/JSON/CSV/SHA-256 và hậu kiểm.
- **v3.0–v3.5:** khắc phục chọn lọc, backup/restore, manifest, DPAPI/HMAC, kiểm tra toàn vẹn, nhật ký trực tiếp và chính sách fail-closed.
- **v3.6–v3.9:** một EXE AnyCPU, build deterministic, PE hardening, capability schema, JSONL logging, module contract và report schema có verifier x64/x86.
- **v4.0–v4.8:** dashboard hiện đại, giao diện Light mặc định, Trung tâm bảo đảm, Trợ lý Tool, catalogue mở rộng, plugin/timeline, quản lý máy chủ–máy trạm trong LAN, quét song song và báo cáo HTML/PDF thống nhất.

Chi tiết từng mốc từ `v1.0` đến `v4.8`, gồm nâng cấp, công nghệ và ngôn ngữ, nằm trong [`LICH-SU-PHIEN-BAN.txt`](LICH-SU-PHIEN-BAN.txt).

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
Get-FileHash .\Tool-Kiem-Tra-v4.8.exe -Algorithm SHA256
Get-AuthenticodeSignature .\Tool-Kiem-Tra-v4.8.exe | Format-List Status,StatusMessage,SignerCertificate
```

Đối chiếu hash với manifest trong gói phát hành. EXE chỉ được công bố là đã ký khi trạng thái Authenticode thực tế là `Valid`; nếu chưa có chứng thư ký mã, tài liệu phát hành phải ghi rõ `NotSigned`.

## Tài liệu

- `HUONG-DAN.txt` — hướng dẫn người dùng v4.8: điểm mới, cách chạy EXE và toàn bộ chức năng.
- `USER-GUIDE-en-US.md` — complete evergreen English end-user guide.
- `LICH-SU-PHIEN-BAN.txt` — lịch sử phiên bản tiếng Việt.
- `VERSION-HISTORY-en-US.md` — English version history.
- `README-MA-NGUON.md` — cách build, kiểm thử và đóng gói.
- `TECHNICAL-ARCHITECTURE-v4.8.md` — kiến trúc kỹ thuật.
- `SAFETY-POLICY-v1.0.md` — ranh giới an toàn.

## Tải chính thức và hỗ trợ

Kho dự án: <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen>

Các bản phát hành (bản mới nhất hiển thị ở đầu): <https://github.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/releases>

Chỉ tải từ kho chính thức và đối chiếu SHA-256 trước khi dùng. Bản v4.8 có chữ ký Authenticode tự ký miễn phí; chữ ký này giúp phát hiện tệp bị sửa nhưng không được Windows tin cậy công khai, nên SmartScreen/antivirus vẫn có thể cảnh báo. Không tắt phần mềm bảo vệ; hãy quét lại và gửi mẫu false-positive cho hãng bảo mật nếu nguồn cùng hash đã được xác minh.

- Zalo: `0978 005 017`
- Email: `thanhvietit.hopnghia@gmail.com`

© 2026 Thanh Việt. Không xóa thông tin tác giả, mạo danh, đóng gói lại hoặc phân phối dưới tên khác khi chưa có chấp thuận bằng văn bản.
