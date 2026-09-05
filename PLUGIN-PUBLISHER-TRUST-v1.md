# Tin cậy plugin bên thứ ba đã ký / Signed third-party plugin and catalog trust v1

## Giải thích nhanh (vi-VN)

Thông báo chưa có `trusted-plugin-publishers-v1.json` là khóa bảo mật đúng thiết kế, không phải lỗi ứng dụng. Bản chạy chính thức không tự tin cậy chứng thư nằm trong chính plugin và không tự tạo danh sách nhà phát hành thay cho quản trị viên.

Để cài plugin bên thứ ba an toàn:

1. Nhận tệp `*.plugin.json` cùng chữ ký rời `*.plugin.json.p7s` từ nguồn đã kiểm soát.
2. Xác minh SHA-256 của chứng thư nhà phát hành qua một kênh độc lập, không lấy giá trị tin cậy từ chính gói plugin.
3. Quản trị viên hoặc MDM tạo/cập nhật `trusted-plugin-publishers-v1.json` trong thư mục plugin được bảo vệ theo mẫu bên dưới.
4. Chạy lại chức năng cài plugin; Tool vẫn kiểm tra schema, CMS, signer và SHA-256 sau khi sao chép.

Đoạn `v4.6` trong đường dẫn dữ liệu là tên thế hệ lưu trữ tương thích được giữ ổn định qua các bản nâng cấp, không phải số phiên bản của EXE đang chạy. Không hạ ACL, tắt xác minh chữ ký hoặc tự ghim fingerprint chỉ để vượt thông báo.

## Trust model (en-US)

Official builds evaluate third-party declarative plugins only when the plugin JSON has an adjacent detached CMS signature (`.plugin.json.p7s`) and the signing certificate's SHA-256 fingerprint is explicitly trusted by an administrator.

The trust policy is `trusted-plugin-publishers-v1.json` inside the protected plugin directory. The launcher restricts that directory to Administrators and SYSTEM. The application never trusts a certificate merely because it is embedded in a plugin or its signature.

Example policy:

```json
{
  "SchemaVersion": "1.0",
  "Publishers": [
    {
      "PublisherId": "example.vendor",
      "DisplayName": "Example Vendor",
      "CertificateSha256": "64_HEXADECIMAL_CHARACTERS",
      "Enabled": true
    }
  ]
}
```

Deployment rules:

- create/update the policy only through an elevated administrator or MDM deployment;
- obtain the fingerprint through a separate verified channel;
- place the signature beside the plugin before installation;
- publisher not listed, missing/corrupt signature, multiple signers, non-SHA-256 digest, or package hash change all fail closed;
- the embedded ThanhViet built-in plugin remains covered by the signed executable's payload integrity manifest;
- source/development mode may still inspect unsigned local plugins and labels them as source-mode trust. It must not be presented as production trust.

## Signed third-party catalogs

A third-party catalog is a declarative, read-only JSON file named `*.plugin-catalog.json`. Its adjacent detached CMS signature is `*.plugin-catalog.json.p7s`. Reading a catalog never downloads a package, opens a URI, executes code, or installs anything automatically.

Catalog schema `1.0` has exactly these root fields:

```json
{
  "SchemaVersion": "1.0",
  "CatalogId": "example.vendor.stable",
  "PublisherId": "example.vendor",
  "GeneratedAtUtc": "2026-08-24T00:00:00Z",
  "Plugins": [
    {
      "PluginId": "example.vendor.assurance",
      "Version": "1.2.0",
      "PackageUri": "https://downloads.example.com/plugins/example.vendor.assurance.plugin.json",
      "SignatureUri": "https://downloads.example.com/plugins/example.vendor.assurance.plugin.json.p7s",
      "PackageSha256": "64_HEXADECIMAL_CHARACTERS"
    }
  ]
}
```

Trust and validation rules:

- the catalog is limited to 512 KiB and 256 unique PluginIds;
- unknown/missing fields, wrong JSON types, invalid IDs/versions, invalid timestamps, or invalid package hashes reject the catalog;
- catalog CMS must have exactly one signer, SHA-256 as its digest algorithm, and a certificate SHA-256 fingerprint pinned by the administrator policy or the caller;
- package and signature URIs must be stable absolute HTTPS URLs with a DNS host, no credentials, query, fragment, loopback/IP literal, backslash, or encoded path-control segment;
- `SignatureUri` must be exactly the adjacent `PackageUri + ".p7s"` location;
- a catalog is `Warning` at 30 days old, `Stale` at 45 days, and `Future` when generated more than 24 hours ahead of local UTC;
- `Fresh` and `Warning` catalogs may support an explicit install; `Stale`, `Future`, invalid, unsigned, or untrusted catalogs remain inspectable as results but cannot authorize installation;
- `Install-ToolPluginPackageFromCatalog` accepts only local package/signature paths. It re-verifies the catalog, matches the local package SHA-256 and PluginId/Version, and requires the package CMS signature to use the same explicitly pinned certificate that signed the catalog;
- callers must acquire catalog/package files through a separately controlled channel. This module intentionally contains no HTTP client or auto-update path.

Read-only inspection example:

```powershell
$pins = Get-ToolPluginTrustedSignerCertificateSha256
$catalog = Read-ToolPluginCatalog `
  -Path 'C:\Staging\vendor.plugin-catalog.json' `
  -TrustedSignerCertificateSha256 $pins

$catalog | Select-Object Valid, FreshnessStatus, InstallationAllowed, EntryCount
```

An administrator may also pass fingerprints directly to support an isolated deployment workflow. A certificate embedded only in a CMS object is never added to trust automatically.
