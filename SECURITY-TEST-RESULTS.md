# Kết quả kiểm thử bảo mật và tương thích

Trạng thái: tài liệu sống cho nhánh phát triển v5. Không dùng tài liệu này để tuyên bố một bản phát hành đã được chứng nhận.

## Cổng tự động trong kho mã

- `VERIFY-ENTERPRISE.ps1`: protocol, DPAPI/envelope, pairing, report schema, UI smoke và giới hạn endpoint;
- `VERIFY-ENTERPRISE-GOVERNANCE.ps1`: redaction mặc định, freshness/filter, CSV formula protection, export staging và script MDM/CLI;
- `VERIFY-SAFETY-REGRESSIONS.ps1`: catalog ký số, quyết định fail-closed và broker UAC qua launcher đã biên dịch; fixture xác nhận payload gốc bị sửa sẽ bị chặn trước tiến trình quản trị;
- `VERIFY-AUTHENTICODE.ps1`: Authenticode, EKU, signer/timestamp theo tham số release;
- `.github/workflows/client-vm-matrix.yml`: Windows 10 22H2, Windows 11 nhánh trước và Windows 11 nhánh hiện hành trên runner tự quản được bảo vệ; workflow ghi lại DisplayVersion/build/UBR thực tế.

## Cách đọc kết quả VM

Workflow tạo `client-vm-summary.json`, `client-vm-summary.md` và ba tệp `*.vm-result.json` thô. Summary ghi commit, Windows build, PowerShell, trạng thái từng verifier, test/platform manifest, hash generator, SHA-256 và kích thước từng kết quả VM. `Missing` không phải là `Passed`. Workflow lịch chỉ chạy khi biến kho `ENABLE_CLIENT_VM_MATRIX=true`; chạy thủ công phải bật input và có thể yêu cầu phê duyệt environment `client-vm-validation`.

## Bằng chứng của ManagedSigned Preview R6

Bản R6 đã công bố kèm `Tool-Kiem-Tra-v5.0-R6-Test-Evidence.zip`. Tóm tắt bên dưới được đọc từ `client-vm-summary.json` trong gói evidence, không suy diễn từ việc workflow tồn tại. Bằng chứng gắn với commit metadata release `1ed0e46069a5d04522552031263d6ceaa184f354`; source snapshot của provenance là `7fe893963206fa7c1ec01d9e1ee129b33fd154b4`.

| Commit/artifact | Win10 22H2 | Win11 previous | Win11 current | Ngày UTC |
|---|---|---|---|---|
| `1ed0e460...` / R6 Test Evidence | Missing | Missing | Passed — Windows 11 25H2, build 26200.9168, 11 verifier | 28/08/2026 |

Tổng trạng thái R6: `Passed=1`, `Failed=0`, `Missing=2`, `Status=IncompleteOrFailed`. Kết quả này ghi nhận một môi trường đã hồi quy thành công, nhưng chưa đủ cho Public Stable. Mọi commit phát triển sau R6 phải tạo evidence mới; không được tái sử dụng kết quả R6 cho source snapshot khác.

Giới hạn: VM tự động không chứng minh không có lỗ hổng; nó chỉ cho bằng chứng hồi quy trên cấu hình đã nêu. Kiểm thử máy thật, accessibility, driver/vendor khác biệt và review thủ công vẫn cần thiết.

## Cổng Public Stable

`BUILD.ps1 -RequireAuthenticode` bắt buộc nhận cả `ClientVmSummaryPath` và `IndependentSecurityReviewPath`. Ba tệp VM thô phải nằm cạnh summary; verifier tính lại SHA-256/kích thước, kiểm tra OS/test trong dữ liệu thô và buộc hash generator khớp source snapshot hiện tại. Cổng từ chối build nếu ma trận không đủ 3/3 Passed, commit không khớp provenance, raw evidence bị sửa, hoặc security review độc lập còn finding Critical/High mở. Tệp attestation mẫu mang trạng thái `NotReviewed` và không thể vượt cổng.
