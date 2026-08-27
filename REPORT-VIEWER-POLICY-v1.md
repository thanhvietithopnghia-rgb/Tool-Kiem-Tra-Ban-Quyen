# Report viewer policy v1

The report is a self-contained, offline-safe HTML document. The compatibility baseline remains Windows 7 SP1 through current Windows 11 releases.

## Default behavior

- Open reports with the operating system's registered HTML browser.
- Validate report HTML with `Test-ToolHtmlOfflineSafe` before PDF conversion or any future embedded rendering.
- Keep PDF export independent from the viewer. The existing Edge, Chrome, and Microsoft Word fallback chain remains authoritative.

## Optional WebView2 direction

WebView2 may be enabled only as an optional viewer on supported Windows 10/11 devices when all of the following are true:

1. the WebView2 Runtime and architecture-matching loader are present;
2. the viewer component is signed and covered by the release integrity manifest;
3. navigation outside the local report is blocked;
4. startup has a bounded timeout and any failure immediately falls back to the default browser;
5. no WebView2 component becomes mandatory for Windows 7.

The v5 feature branch intentionally does not bundle WebView2 native binaries yet. This avoids silently increasing the trusted code surface or breaking the single-file AnyCPU/Windows 7 contract. The report and PDF paths therefore remain fully functional without WebView2.
