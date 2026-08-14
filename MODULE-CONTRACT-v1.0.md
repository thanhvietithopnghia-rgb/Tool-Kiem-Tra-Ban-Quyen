# Module Contract schema 1.0 — Tool-Kiem-Tra v4.8

`Tool-ModuleContract.ps1` là nguồn chuẩn. Catalog có 27 descriptor: 24 entry point và ba nguồn inventory nội bộ.

## Descriptor

| Trường | Ý nghĩa |
| --- | --- |
| `ContractSchemaVersion` | `1.0` |
| `ResultSchemaVersion` | `1.0` |
| `ToolVersion` | `4.8` |
| `ModuleId` | ID chữ thường, ổn định |
| `Category`, `DisplayName` | Nhóm và tên hiển thị |
| `ScriptFile`, `Operation`, `TaskKind` | Entry point và mode |
| `AccessMode` | `ReadOnly` hoặc `SystemChange` |
| `NetworkScope` | `LocalOnly`, `Lan` hoặc `Internet` |
| `OfflineCapable` | true khi `NetworkScope=LocalOnly` |
| `RequiresElevation` | cần Administrator |
| `RequiredCapabilities` | capability gate, hỗ trợ toán tử OR bằng `|` |
| `IsEntryPoint` | GUI được phép khởi chạy độc lập |
| `ExitCodeMap` | ánh xạ exit code sang trạng thái |

Hai mô-đun có `NetworkScope=Internet`: `software.catalog.update` yêu cầu consent riêng để tải catalog HTTPS; `application.update.check` chỉ kiểm tra manifest sau khi người dùng cho phép Online. Cả hai dùng host/path allowlist và không gửi inventory/đường dẫn/khóa/token. `license.manager` là `LocalOnly`; chỉ `enterprise.server` và `enterprise.agent` dùng `Lan`.

## Invocation

`New-ToolModuleInvocation` tạo:

- `SchemaVersion`;
- `InvocationId`;
- `CorrelationId`;
- `ModuleId`;
- `ToolVersion`;
- `StartedAtUtc`.

GUI chỉ gọi module đã đăng ký. Trước khi tạo tiến trình con, `Test-ToolModuleAvailability` kiểm tra capability và sự tồn tại của script.

## ModuleResult

`Complete-ToolModuleInvocation` trả:

- `SchemaVersion`, `ModuleId`, `InvocationId`, `CorrelationId`;
- `StartedAtUtc`, `CompletedAtUtc`, `DurationMs`;
- `Status`, `ExitCode`, `Summary`;
- `OutputPaths`, `FindingCount`, `WarningCount`.

`Completed` chỉ xác nhận tiến trình hoàn tất theo contract. Kết luận nghiệp vụ phải lấy từ report envelope; không được suy ra tính hợp pháp hoặc quyền cleanup từ exit code đơn lẻ.

## Capability expression

Mỗi phần tử `RequiredCapabilities` là điều kiện AND. Trong một phần tử, dấu `|` tạo OR:

```text
SupportedOperatingSystem
CimCmdlets|WmiFallback
ScheduledTasksModule|ScheduledTasksFallback
NativeCscript
```

Thiếu capability trả `Unsupported` với `MissingRequirements`; không cố chạy và bắt lỗi muộn.

## Quy tắc SystemChange

Module `SystemChange` chỉ khả dụng khi:

1. payload/integrity hợp lệ;
2. capability đủ;
3. secure launch;
4. quyền Administrator nếu descriptor yêu cầu;
5. offline/network gate cho phép;
6. safety policy và xác nhận người dùng đã thỏa.

Plugin assurance vẫn read-only; thao tác cài plugin là hành động riêng của GUI. Enterprise không nhận mã thực thi tùy ý.

## Danh sách entry point

Danh sách đầy đủ, script/operation, quyền và network scope nằm trong `ENTRY-POINTS-v4.8.md`. Verifier yêu cầu đúng 27 descriptor/24 entry point, ID duy nhất, script tồn tại, schema đúng và `OfflineCapable` khớp `NetworkScope`.

## Quy tắc mở rộng

Module mới phải:

1. có ID không đổi sau khi phát hành;
2. khai báo access/network scope trung thực;
3. không dùng Internet nếu chưa có policy và threat review riêng;
4. có exit-code map;
5. có fixture/verifier;
6. cập nhật entry-point docs và release manifest.
