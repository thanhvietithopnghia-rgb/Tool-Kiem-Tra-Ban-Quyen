# Lộ trình một nhánh đến v5.0

Nguyên tắc cố định: một sản phẩm, một EXE AnyCPU tự nhận diện, tương thích Windows 7 SP1–Windows 11. Mỗi mốc phải build, kiểm thử, đóng gói và có checksum độc lập.

Trạng thái 06/08/2026: v4.6 đã hoàn thành catalog phần mềm 1.2 cho nhóm kỹ thuật, Dry Run không thay đổi hệ thống, consent online fail-closed, Enterprise status tối giản và DataSchema 2.0 với migration/rollback sang vùng ghi riêng. Catalog Lifecycle 1.1 cho Microsoft vẫn có cảnh báo tuổi 30/45 ngày, phân loại Office điều khiển bằng dữ liệu, build tương lai chỉ đọc, đối chiếu nguồn chính thức hàng tuần và báo cáo CI máy đọc. Ưu tiên v5.0 là mở rộng QA máy thật/VM, quản trị catalog có ký metadata và hoàn thiện pipeline phát hành; chưa được tuyên bố Authenticode tin cậy khi chưa có chứng thư code-signing thật.

## Các mốc

- **v3.7 — Hoàn thành:** capability detection, fallback và JSONL log bảo vệ.
- **v3.8 — Hoàn thành:** module descriptor và ModuleResult.
- **v3.9 — Hoàn thành:** report schema, quick repair, hướng xử lý và giảm false positive.
- **v4.0/R2 — Hoàn thành:** dashboard, action center, restore NoGenTicket và quét nhiều Office SKU.
- **v4.2 — Hoàn thành phần mềm:** HTML/PDF/JSON/XML, plugin khai báo chỉ đọc, certificate audit, timeline có HMAC/hash chain, pipeline Authenticode và enterprise server/agent với outbox offline.
- **v4.3 — Hoàn thành phần mềm:** dashboard schema 2.0, Offline/i18n, compatibility catalog/freshness CI, HTML/PDF offline-safe và tài liệu kỹ thuật.
- **v4.4 — Hoàn thành phần mềm:** lưu language/theme/network default, cảnh báo VM/RDP, lịch sử nội bộ, tiện ích log/báo cáo và tối ưu quét song song.
- **v5.0 ưu tiên 1 — Đang phát triển:** Catalog Lifecycle, nguồn Microsoft chính thức, cảnh báo tuổi, báo cáo thay đổi, chống kết luận sai với Windows/Office tương lai và ma trận QA thực tế.
- **v4.3 signed — Chờ chứng thư:** ký bằng chứng thư tổ chức thật, timestamp và xác minh `Valid`.
- **v4.4 — Detection/forensics mở rộng:** chữ ký activator có mức tin cậy, nguồn bằng chứng và hợp nhất timeline với Windows Event Log.
- **v4.5 — Backup/restore + hardware assurance:** coverage matrix, TPM/Secure Boot/BitLocker recommendation và rollback lab.
- **v4.6 — Health score/plugin catalog:** điểm minh bạch, rule có giải thích và marketplace có ký metadata.
- **v4.7 — Enterprise/Release engineering:** Intune/SCCM/RMM, reproducible build, attestations và vòng đời chứng thư.
- **v4.8 — Pilot:** ma trận VM/máy thật Windows 7 SP1, Windows 10 22H2, Windows 11 release hiện hành và Office 2021/2024/Microsoft 365.
- **v5.0 — Ổn định:** hợp nhất các mốc, audit cuối, tài liệu và gói phát hành công khai.

Không chuyển toàn bộ sang modern .NET/WinUI nếu làm mất Windows 7. Tính năng không có trên hệ điều hành cũ phải dùng capability/fallback hoặc báo “không hỗ trợ”, không làm toàn bộ tool khởi động thất bại.
