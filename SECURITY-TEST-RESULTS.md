# Kết quả kiểm thử bảo mật và tương thích

Trạng thái: tài liệu sống cho nhánh phát triển v5. Không dùng tài liệu này để tuyên bố một bản phát hành đã được chứng nhận.

## Cổng tự động trong kho mã

- `VERIFY-ENTERPRISE.ps1`: protocol, DPAPI/envelope, pairing, report schema, UI smoke và giới hạn endpoint;
- `VERIFY-ENTERPRISE-GOVERNANCE.ps1`: redaction mặc định, freshness/filter, CSV formula protection, export staging và script MDM/CLI;
- `VERIFY-SAFETY-REGRESSIONS.ps1`: catalog ký số và quyết định fail-closed;
- `VERIFY-AUTHENTICODE.ps1`: Authenticode, EKU, signer/timestamp theo tham số release;
- `.github/workflows/client-vm-matrix.yml`: Windows 10 22H2, Windows 11 nhánh trước và Windows 11 nhánh hiện hành trên runner tự quản được bảo vệ; workflow ghi lại DisplayVersion/build/UBR thực tế.

## Cách đọc kết quả VM

Workflow tạo `client-vm-summary.json` và `client-vm-summary.md`, gồm commit, Windows build, PowerShell, trạng thái từng verifier và thời gian UTC. `Missing` không phải là `Passed`. Workflow lịch chỉ chạy khi biến kho `ENABLE_CLIENT_VM_MATRIX=true`; chạy thủ công phải bật input và có thể yêu cầu phê duyệt environment `client-vm-validation`.

## Kết quả hiện tại

Preview R6 có gói bằng chứng public-safe `Tool-Kiem-Tra-v5.0-R6-Test-Evidence.zip` đính kèm tại release `v5.0.0.0`. Tóm tắt được tạo từ metadata release commit `1ed0e46069a5d04522552031263d6ceaa184f354`; raw output và dữ liệu nhạy cảm không được đưa vào gói công khai.

| Commit/artifact | Win10 22H2 | Win11 previous | Win11 current | Ngày UTC |
|---|---|---|---|---|
| Preview R6 — `1ed0e46` | Missing | Missing | Passed (25H2, build 26200.9168) | 2026-08-28 |

Tổng hợp hiện tại: `Passed=1`, `Failed=0`, `Missing=2`, vì vậy trạng thái ma trận vẫn là `IncompleteOrFailed`. `Missing` nghĩa là chưa có runner/bằng chứng đúng nền tảng, không phải một lượt kiểm thử đã chạy và thất bại.

Giới hạn: VM tự động không chứng minh không có lỗ hổng; nó chỉ cho bằng chứng hồi quy trên cấu hình đã nêu. Kiểm thử máy thật, accessibility, driver/vendor khác biệt và review thủ công vẫn cần thiết.
