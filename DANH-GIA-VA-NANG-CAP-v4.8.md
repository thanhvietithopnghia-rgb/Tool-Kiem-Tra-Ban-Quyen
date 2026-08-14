# Đánh giá và nâng cấp đến v4.8

## Kết quả

v4.8 giữ nguyên các nhóm nâng cấp trước và bổ sung:

- sao chép toàn bộ log và mở thư mục báo cáo;
- lưu ngôn ngữ, theme và Offline/Online mặc định;
- cảnh báo máy ảo/Remote Desktop;
- lịch sử phiên bản trong Tool;
- quét nhiều Office/nhiều nguồn tệp song song có giới hạn.
- quét sâu phổ quát từng ứng dụng bằng nhiều EXE/DLL, Authenticode, hash và dấu vết hệ thống tương quan, có phân phối ngân sách công bằng và metadata độ phủ.
- catalogue phần mềm 1.3.2.0 với 76 quy tắc; gộp nhiều nguồn phát hiện, tách phần mềm hệ thống, tách mô hình giấy phép khỏi bằng chứng can thiệp và không suy diễn `HashMismatch` thành giấy phép không chính hãng;
- Trợ lý schema 1.1 / knowledge 1.3.1 với 63 nhóm và 481 từ khóa/cách hỏi; dữ liệu tăng thêm nằm ngoài EXE, dùng JSON + chữ ký CMS SHA-256, ghim chứng thư, chống hạ phiên bản, cache dự phòng theo người dùng và khóa phạm vi Tool;
- báo cáo dùng một thư mục chung, PDF tách bảng rộng và mở phụ lục phần mềm hệ thống; Máy chủ/Máy trạm có tự dò/chẩn đoán LAN và hàng đợi gửi lại;
- Dry Run lập kế hoạch target/action/backup/restorability mà không thay đổi hệ thống, sau đó yêu cầu chọn và xác nhận lại nếu thực hiện thật;
- data lifecycle schema 2.0 với vùng ghi v4.6 riêng, migration staging đã xác minh SHA-256, commit/rollback và dữ liệu cũ chỉ đọc;
- status Enterprise công khai tối giản và consent catalog online fail-closed khi thiếu/false.

Nền tảng v4.3 đã hoàn thành sáu nhóm nâng cấp:

1. **UI hiện đại hơn:** Modern WinForms dashboard schema 2.0, card/tile hai dòng, Segoe UI, bo góc, hover, DPI responsive và dark mode toàn công cụ.
2. **Tài liệu kỹ thuật:** kiến trúc, module contract, entry point, report schema, safety policy, offline/reporting, localization và compatibility matrix.
3. **Windows/Office và vòng đời catalog:** catalog 1.1 nhận diện Windows 10 22H2, Windows 11 23H2/24H2/25H2/26H1, Office 2021/2024 và Microsoft 365; có cảnh báo tuổi, nguồn Microsoft chính thức và chế độ chỉ đọc cho phiên bản tương lai.
4. **Kiểm tra liên tục:** freshness gate 45 ngày, fixture và workflow hàng tuần dựa trên nguồn Microsoft chính thức.
5. **Offline hoàn toàn ở cấp ứng dụng:** mặc định fail-closed, không telemetry/auto-update; Mục 8 có công tắc mạng riêng mặc định tắt và bật/tắt lại được, trong khi ba chức năng luôn sẵn có.
6. **Báo cáo và đa ngôn ngữ:** HTML/PDF tự chứa, print A4, JSON/XML/SHA-256; `vi-VN`/`en-US` cho dashboard/report shell và English guide.

## Lựa chọn UI

Không chuyển sang WPF/WebView2 trong v4.3. Modern WinForms được chọn để:

- giữ một EXE nhỏ và không cần WebView2 runtime;
- giữ .NET Framework 4/Windows PowerShell 3+;
- không đưa browser/web asset vào trust boundary;
- giảm rủi ro hồi quy ở các cửa sổ nghiệp vụ hiện có.

Đây là nâng cấp thực tế của UI chứ không chỉ đổi màu: cấu trúc thông tin, dashboard card, tile mô tả, control trạng thái Offline/language và layout responsive đều thay đổi.

## Mức hoàn thành

| Hạng mục | Trạng thái | Bằng chứng |
| --- | --- | --- |
| Dashboard/dark mode | Hoàn thành | `VERIFY-DASHBOARD.ps1` |
| Compatibility logic/catalog | Hoàn thành ở mức code + fixture | `VERIFY-COMPATIBILITY.ps1` |
| VM/máy thật mọi SKU | Cần ma trận QA bên ngoài repo | `COMPATIBILITY-MATRIX-v4.8.md` |
| Offline policy | Hoàn thành ở cấp ứng dụng | `VERIFY-OFFLINE-I18N.ps1` |
| HTML/PDF offline-safe | Hoàn thành | export schema 1.4, HTML tổng quan / PDF chi tiết và ngắt trang an toàn |
| Quét sâu phần mềm phổ quát | Hoàn thành ở mức code + fixture + quét tích hợp máy thật | `VERIFY-SAFETY-REGRESSIONS.ps1` và metadata deep scan |
| Catalogue phần mềm 1.3.2.0 | Hoàn thành ở mức JSON/regex/fixture | 76 quy tắc duy nhất, gộp trùng, phân loại hệ thống và chặn xử lý tự động từ mức `Low` |
| Dry Run không thay đổi | Hoàn thành ở mức code + AST/plan fixture | `VERIFY-SAFETY-REGRESSIONS.ps1` |
| Data schema/migration/rollback | Hoàn thành ở mức code + fixture idempotent/rollback | `VERIFY-DATA-LIFECYCLE.ps1` |
| Enterprise status tối giản | Hoàn thành ở mức AST/security fixture | `VERIFY-ENTERPRISE.ps1` |
| vi-VN/en-US shell | Hoàn thành | hai catalog JSON |
| Dịch toàn bộ thông báo legacy | Chuyển dần | `LOCALIZATION-v1.0.md` |
| Authenticode chính thức | Phụ thuộc chứng thư thật | `-RequireAuthenticode` |

## Rủi ro còn lại

- Catalog sẽ cũ nếu workflow bị tắt hoặc maintainer không review nguồn chính thức.
- “Fully offline” không thay firewall hệ điều hành.
- Microsoft có thể thêm channel/ProductReleaseId mới; tool sẽ đánh dấu unknown thay vì tự suy diễn.
- Một số dialog chẩn đoán chuyên sâu vẫn tiếng Việt trong release này.
- Quét cục bộ không thể chứng minh quyền sở hữu tài khoản/hóa đơn cho mọi hãng; ứng dụng thiếu bằng chứng hoặc thiếu độ phủ vẫn phải là `Unverified`.
- Chữ ký không thể được tuyên bố `Valid` khi build không có chứng thư code-signing thật.

## Hướng phát triển hợp lý

- chuyển nốt chuỗi nghiệp vụ safety-critical sang catalog có review;
- thêm VM matrix tự động cho Win10 22H2, Win11 23H2/24H2/25H2/26H1, Office 2021/2024/M365;
- tăng kiểm tra TPM/Secure Boot/BitLocker;
- đưa read-only/audit-only thành policy mặc định riêng;
- thiết kế catalog plugin công khai có ký metadata;
- chỉ cân nhắc WPF/WebView2 khi chấp nhận nâng runtime và thay đổi support baseline.
