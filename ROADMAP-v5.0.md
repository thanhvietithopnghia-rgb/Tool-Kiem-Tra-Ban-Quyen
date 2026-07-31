# Lộ trình một nhánh đến v5.0

Nguyên tắc cố định: một sản phẩm, một EXE AnyCPU tự nhận diện, tương thích Windows 7 SP1–Windows 11. Mỗi mốc phải build, kiểm thử, đóng gói và có checksum độc lập.

Trạng thái 30/07/2026: v4.3 Enterprise đã hoàn thành Modern WinForms dashboard, Offline mặc định, localization nền, compatibility catalog Windows/Office và report export offline-safe. Pipeline ký vẫn chưa được tuyên bố Authenticode tin cậy khi chưa có chứng thư code-signing thật.

## Các mốc

- **v3.7 — Hoàn thành:** capability detection, fallback và JSONL log bảo vệ.
- **v3.8 — Hoàn thành:** module descriptor và ModuleResult.
- **v3.9 — Hoàn thành:** report schema, quick repair, hướng xử lý và giảm false positive.
- **v4.0/R2 — Hoàn thành:** dashboard, action center, restore NoGenTicket và quét nhiều Office SKU.
- **v4.2 — Hoàn thành phần mềm:** HTML/PDF/JSON/XML, plugin khai báo chỉ đọc, certificate audit, timeline có HMAC/hash chain, pipeline Authenticode và enterprise server/agent với outbox offline.
- **v4.3 — Hoàn thành phần mềm:** dashboard schema 2.0, Offline/i18n, compatibility catalog/freshness CI, HTML/PDF offline-safe và tài liệu kỹ thuật.
- **v4.3 signed — Chờ chứng thư:** ký bằng chứng thư tổ chức thật, timestamp và xác minh `Valid`.
- **v4.4 — Detection/forensics mở rộng:** chữ ký activator có mức tin cậy, nguồn bằng chứng và hợp nhất timeline với Windows Event Log.
- **v4.5 — Backup/restore + hardware assurance:** coverage matrix, TPM/Secure Boot/BitLocker recommendation và rollback lab.
- **v4.6 — Health score/plugin catalog:** điểm minh bạch, rule có giải thích và marketplace có ký metadata.
- **v4.7 — Enterprise/Release engineering:** Intune/SCCM/RMM, reproducible build, attestations và vòng đời chứng thư.
- **v4.8 — Pilot:** ma trận VM/máy thật Windows 11 release hiện hành và Office 2024/Microsoft 365.
- **v5.0 — Ổn định:** hợp nhất các mốc, audit cuối, tài liệu và gói phát hành công khai.

Không chuyển toàn bộ sang modern .NET/WinUI nếu làm mất Windows 7. Tính năng không có trên hệ điều hành cũ phải dùng capability/fallback hoặc báo “không hỗ trợ”, không làm toàn bộ tool khởi động thất bại.
