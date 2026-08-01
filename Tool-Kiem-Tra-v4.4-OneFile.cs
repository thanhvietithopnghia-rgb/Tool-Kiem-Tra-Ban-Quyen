using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Tool kiểm tra cấu hình máy và bản quyền")]
[assembly: AssemblyDescription("Bản một file - Phát triển bởi Thanh Việt")]
[assembly: AssemblyCompany("Thanh Việt")]
[assembly: AssemblyProduct("Tool kiểm tra cấu hình máy và bản quyền")]
[assembly: AssemblyCopyright("Copyright © Thanh Việt 2026")]
[assembly: AssemblyVersion("4.4.0.0")]
[assembly: AssemblyFileVersion("4.4.0.0")]
[assembly: AssemblyInformationalVersion("4.4.0.0")]

namespace ThanhViet.ToolKiemTra
{
    internal static class Program
    {
        private const string ProductCaption = "Tool kiểm tra cấu hình máy và bản quyền v4.4.0.0 Enterprise";

        private static string RuntimeArchitecture
        {
            get { return Environment.Is64BitProcess ? "x64" : "x86"; }
        }

        private static readonly string[] PayloadFiles = new string[]
        {
            "00-Tool-Kiem-Tra.ico",
            "approved-kms-servers.txt",
            "HUONG-DAN.txt",
            "USER-GUIDE-en-US.md",
            "LICH-SU-PHIEN-BAN.txt",
            "Giao-Dien.ps1",
            "kiem-tra-cau-hinh-ban-quyen.ps1",
            "Tool-Kiem-Tra-icon.svg",
            "Tool-Kiem-Tra.cmd",
            "Tool-Runtime.ps1",
            "Tool-Compatibility.ps1",
            "compatibility-catalog-v1.0.json",
            "Tool-Capabilities.ps1",
            "Tool-ScanOptimization.ps1",
            "Tool-Logging.ps1",
            "Tool-ModuleContract.ps1",
            "Tool-UiTheme.ps1",
            "Tool-Localization.ps1",
            "Tool-Strings.vi-VN.json",
            "Tool-Strings.en-US.json",
            "Tool-OfflinePolicy.ps1",
            "Tool-ReportSchema.ps1",
            "Tool-ReportExport.ps1",
            "Tool-PluginEngine.ps1",
            "Tool-LicenseTimeline.ps1",
            "Tool-SafetyPolicy.ps1",
            "Tool-Enterprise.ps1",
            "Tool-EnterpriseHost.ps1",
            "Tool-EnterpriseAgent.ps1",
            "enterprise-license-manager.ps1",
            "TOOL-SHA256SUMS.txt",
            "windows-license-backup.ps1",
            "windows-license-compliance-cleanup.ps1",
            "windows-license-restore.ps1",
            "windows-license-deep-scan.ps1",
            "windows-license-forensics.ps1",
            "windows-oem-license-assistant.ps1",
            "windows-office-license-manager.ps1",
            "windows-license-assurance.ps1",
            "builtin-windows-office-trust.plugin.json"
        };

        private static readonly string[] RequiredIntegrityFiles = new string[]
        {
            "00-Tool-Kiem-Tra.ico",
            "HUONG-DAN.txt",
            "USER-GUIDE-en-US.md",
            "LICH-SU-PHIEN-BAN.txt",
            "Giao-Dien.ps1",
            "kiem-tra-cau-hinh-ban-quyen.ps1",
            "Tool-Kiem-Tra-icon.svg",
            "Tool-Kiem-Tra.cmd",
            "Tool-Runtime.ps1",
            "Tool-Compatibility.ps1",
            "compatibility-catalog-v1.0.json",
            "Tool-Capabilities.ps1",
            "Tool-ScanOptimization.ps1",
            "Tool-Logging.ps1",
            "Tool-ModuleContract.ps1",
            "Tool-UiTheme.ps1",
            "Tool-Localization.ps1",
            "Tool-Strings.vi-VN.json",
            "Tool-Strings.en-US.json",
            "Tool-OfflinePolicy.ps1",
            "Tool-ReportSchema.ps1",
            "Tool-ReportExport.ps1",
            "Tool-PluginEngine.ps1",
            "Tool-LicenseTimeline.ps1",
            "Tool-SafetyPolicy.ps1",
            "Tool-Enterprise.ps1",
            "Tool-EnterpriseHost.ps1",
            "Tool-EnterpriseAgent.ps1",
            "enterprise-license-manager.ps1",
            "windows-license-backup.ps1",
            "windows-license-compliance-cleanup.ps1",
            "windows-license-restore.ps1",
            "windows-license-deep-scan.ps1",
            "windows-license-forensics.ps1",
            "windows-oem-license-assistant.ps1",
            "windows-office-license-manager.ps1",
            "windows-license-assurance.ps1",
            "builtin-windows-office-trust.plugin.json"
        };

        private enum LaunchMode
        {
            Gui,
            EnterpriseUi,
            EnterpriseServer,
            EnterpriseAgent,
            EnterpriseAgentForce,
            LocalLicenseManager
        }

        [STAThread]
        private static int Main(string[] args)
        {
            LaunchMode mode;
            try { mode = ParseLaunchMode(args); }
            catch (ArgumentException ex)
            {
                MessageBox.Show(ex.Message, GetProductCaption(), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 64;
            }

            bool createdNew;
            using (Mutex singleInstance = new Mutex(true, GetMutexName(mode), out createdNew))
            {
                if (!createdNew)
                {
                    ShowMessage(mode, UiText(
                        "Chức năng này đang chạy. Hãy chờ tiến trình hiện tại hoàn tất.",
                        "This function is already running. Wait for the current process to finish."), MessageBoxIcon.Information);
                    return 2;
                }

                if (Environment.OSVersion.Platform != PlatformID.Win32NT)
                {
                    ShowMessage(mode, UiText(
                        "Bản EXE này chỉ hỗ trợ Windows.",
                        "This executable supports Windows only."), MessageBoxIcon.Warning);
                    return 10;
                }
                if (Environment.OSVersion.Version < new Version(6, 1))
                {
                    ShowMessage(mode,
                        UiText(
                            "Bản EXE này cần Windows 7 SP1 hoặc mới hơn.\r\n\r\n" +
                            "Windows XP/Vista không còn đủ thành phần hệ thống để chạy an toàn.",
                            "This executable requires Windows 7 SP1 or later.\r\n\r\n" +
                            "Windows XP/Vista no longer provides the system components required for safe operation."),
                        MessageBoxIcon.Warning);
                    return 10;
                }
                if (!IsArchitectureSupported())
                    return 12;

                string powershellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell\\v1.0\\powershell.exe");
                if (!File.Exists(powershellPath))
                {
                    ShowMessage(mode,
                        UiText(
                            "Không tìm thấy Windows PowerShell native tại:\r\n" + powershellPath +
                            "\r\n\r\nTool không dùng powershell.exe từ PATH vì có thể sai kiến trúc hoặc không đáng tin cậy.",
                            "Native Windows PowerShell was not found at:\r\n" + powershellPath +
                            "\r\n\r\nThe tool does not use powershell.exe from PATH because it may have the wrong architecture or be untrusted."),
                        MessageBoxIcon.Error);
                    return 13;
                }
                return RunPayload(mode, powershellPath);
            }
        }

        private static LaunchMode ParseLaunchMode(string[] args)
        {
            if (args == null || args.Length == 0 || String.Equals(args[0], "--gui", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.Gui;
            if (args.Length != 1)
                throw new ArgumentException(UiText("Tham số khởi động không hợp lệ.", "Invalid startup arguments."));
            if (String.Equals(args[0], "--enterprise-ui", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.EnterpriseUi;
            if (String.Equals(args[0], "--enterprise-server", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.EnterpriseServer;
            if (String.Equals(args[0], "--enterprise-agent", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.EnterpriseAgent;
            if (String.Equals(args[0], "--enterprise-agent-force", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.EnterpriseAgentForce;
            if (String.Equals(args[0], "--local-license-manager", StringComparison.OrdinalIgnoreCase))
                return LaunchMode.LocalLicenseManager;
            throw new ArgumentException(UiText("Tham số không được hỗ trợ: ", "Unsupported argument: ") + args[0]);
        }

        private static string GetMutexName(LaunchMode mode)
        {
            switch (mode)
            {
                case LaunchMode.EnterpriseServer: return "Global\\ThanhViet.ToolKiemTra.v4.4.ServerLauncher";
                case LaunchMode.EnterpriseAgent:
                case LaunchMode.EnterpriseAgentForce: return "Global\\ThanhViet.ToolKiemTra.v4.4.AgentLauncher";
                case LaunchMode.EnterpriseUi: return "Local\\ThanhViet.ToolKiemTra.v4.4.EnterpriseUi";
                case LaunchMode.LocalLicenseManager: return "Local\\ThanhViet.ToolKiemTra.v4.4.LocalLicenseManager";
                default: return "Local\\ThanhViet.ToolKiemTra.v4.4.Gui";
            }
        }

        private static bool IsInteractiveMode(LaunchMode mode)
        {
            return mode == LaunchMode.Gui || mode == LaunchMode.EnterpriseUi || mode == LaunchMode.LocalLicenseManager;
        }

        private static void ShowMessage(LaunchMode mode, string message, MessageBoxIcon icon)
        {
            if (IsInteractiveMode(mode))
                MessageBox.Show(message, GetProductCaption(), MessageBoxButtons.OK, icon);
            else
                Console.Error.WriteLine(message);
        }

        private static string GetScriptName(LaunchMode mode)
        {
            switch (mode)
            {
                case LaunchMode.EnterpriseUi: return "enterprise-license-manager.ps1";
                case LaunchMode.EnterpriseServer: return "Tool-EnterpriseHost.ps1";
                case LaunchMode.EnterpriseAgent:
                case LaunchMode.EnterpriseAgentForce: return "Tool-EnterpriseAgent.ps1";
                case LaunchMode.LocalLicenseManager: return "windows-office-license-manager.ps1";
                default: return "Giao-Dien.ps1";
            }
        }

        private static string ResolveOfflineMode()
        {
            string inherited = Environment.GetEnvironmentVariable("TOOL_OFFLINE_MODE");
            if (String.Equals(inherited, "1", StringComparison.Ordinal)) return "1";
            if (String.Equals(inherited, "0", StringComparison.Ordinal)) return "0";

            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!String.IsNullOrWhiteSpace(localAppData))
                {
                    string settingsPath = Path.Combine(localAppData, "ThanhViet-Tool-Kiem-Tra", "offline-settings.json");
                    if (File.Exists(settingsPath))
                    {
                        FileInfo info = new FileInfo(settingsPath);
                        if ((info.Attributes & FileAttributes.ReparsePoint) == 0 && info.Length > 2 && info.Length <= 65536)
                        {
                            string json = File.ReadAllText(settingsPath);
                            Match match = Regex.Match(json, "\"OfflineMode\"\\s*:\\s*(true|false)", RegexOptions.IgnoreCase);
                            if (match.Success)
                                return String.Equals(match.Groups[1].Value, "false", StringComparison.OrdinalIgnoreCase) ? "0" : "1";
                        }
                    }
                }
            }
            catch
            {
                // Fail closed: unreadable or malformed settings keep the tool offline.
            }
            return "1";
        }

        private static string ResolveEnterpriseNetworkAllowed()
        {
            string inherited = Environment.GetEnvironmentVariable("TOOL_ENTERPRISE_NETWORK_ALLOWED");
            if (String.Equals(inherited, "1", StringComparison.Ordinal)) return "1";
            if (String.Equals(inherited, "0", StringComparison.Ordinal)) return "0";

            try
            {
                string commonData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                if (!String.IsNullOrWhiteSpace(commonData))
                {
                    string settingsPath = Path.Combine(
                        commonData,
                        "ThanhViet-Tool-Kiem-Tra",
                        "v4.4",
                        "enterprise-network-settings.json");
                    if (File.Exists(settingsPath))
                    {
                        FileInfo info = new FileInfo(settingsPath);
                        if ((info.Attributes & FileAttributes.ReparsePoint) == 0 && info.Length > 2 && info.Length <= 65536)
                        {
                            string json = File.ReadAllText(settingsPath);
                            Match match = Regex.Match(json, "\"Allowed\"\\s*:\\s*(true|false)", RegexOptions.IgnoreCase);
                            if (match.Success)
                                return String.Equals(match.Groups[1].Value, "true", StringComparison.OrdinalIgnoreCase) ? "1" : "0";
                        }
                    }
                }
            }
            catch
            {
                // Fail closed: Section 8 networking remains blocked.
            }
            return "0";
        }

        private static bool IsEnglishUi()
        {
            string culture = Environment.GetEnvironmentVariable("TOOL_UI_CULTURE");
            if (!String.IsNullOrWhiteSpace(culture))
                return culture.StartsWith("en", StringComparison.OrdinalIgnoreCase);

            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!String.IsNullOrWhiteSpace(localAppData))
                {
                    string settingsPath = Path.Combine(
                        localAppData,
                        "ThanhViet-Tool-Kiem-Tra",
                        "localization-settings.json");
                    if (File.Exists(settingsPath))
                    {
                        FileInfo info = new FileInfo(settingsPath);
                        if ((info.Attributes & FileAttributes.ReparsePoint) == 0 && info.Length > 2 && info.Length <= 65536)
                        {
                            string json = File.ReadAllText(settingsPath);
                            Match match = Regex.Match(json, "\"Culture\"\\s*:\\s*\"([^\"]+)\"", RegexOptions.IgnoreCase);
                            if (match.Success)
                                return match.Groups[1].Value.StartsWith("en", StringComparison.OrdinalIgnoreCase);
                        }
                    }
                }
            }
            catch
            {
                // Fall back to Vietnamese if the user preference cannot be read safely.
            }
            return false;
        }

        private static string UiText(string vietnamese, string english)
        {
            return IsEnglishUi() ? english : vietnamese;
        }

        private static string GetProductCaption()
        {
            return UiText(ProductCaption, "Configuration & License Assurance Tool v4.4.0.0 Enterprise");
        }

        private static int RunPayload(LaunchMode mode, string powershellPath)
        {
            string commonData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            string productRoot = Path.Combine(commonData, "ThanhViet-Tool-Kiem-Tra");
            string protectedRoot = Path.Combine(productRoot, "v4.4");
            string approvedKmsPath = Path.Combine(protectedRoot, "approved-kms-servers.txt");
            string logsDirectory = Path.Combine(protectedRoot, "logs");
            string pluginsDirectory = Path.Combine(protectedRoot, "plugins");
            string timelineDirectory = Path.Combine(protectedRoot, "timeline");
            string enterpriseDirectory = Path.Combine(protectedRoot, "enterprise");
            string logPath = Path.Combine(logsDirectory, DateTime.UtcNow.ToString("yyyyMMdd") + ".jsonl");
            string timelinePath = Path.Combine(timelineDirectory, "license-timeline.jsonl");
            string timelineKeyPath = Path.Combine(timelineDirectory, "timeline-hmac.key");
            string correlationId = Guid.NewGuid().ToString("N");
            string tempDirectory = Path.Combine(protectedRoot, "session-" + Guid.NewGuid().ToString("N"));
            string offlineMode = ResolveOfflineMode();
            string enterpriseNetworkAllowed = ResolveEnterpriseNetworkAllowed();

            if (enterpriseNetworkAllowed != "1" &&
                (mode == LaunchMode.EnterpriseServer || mode == LaunchMode.EnterpriseAgent ||
                 mode == LaunchMode.EnterpriseAgentForce))
            {
                string blockedMessage = IsEnglishUi()
                    ? "The server/workstation network process is blocked because Section 8 network access is disabled.\r\n\r\nOpen Section 8 and select “Allow network for Section 8” before running this process."
                    : "Tiến trình mạng máy chủ/máy trạm bị chặn vì Mục 8 đang Offline.\r\n\r\nHãy mở Mục 8 và chọn “Online” trước khi chạy tiến trình này.";
                ShowMessage(mode, blockedMessage, MessageBoxIcon.Information);
                return 30;
            }

            try
            {
                CreateProtectedDirectory(productRoot);
                CreateProtectedDirectory(protectedRoot);
                CreateProtectedDirectory(logsDirectory);
                CreateProtectedDirectory(pluginsDirectory);
                CreateProtectedDirectory(timelineDirectory);
                CreateProtectedDirectory(tempDirectory);
                Dictionary<string, string> extractedHashes = ExtractPayload(tempDirectory);
                VerifyExtractedPayload(tempDirectory, extractedHashes);
                InitializeProtectedApprovedKmsList(tempDirectory, approvedKmsPath);
                InitializeProtectedBuiltInPlugin(tempDirectory, pluginsDirectory);
                CreateProtectedDirectory(Path.Combine(tempDirectory, "runtime"));

                string scriptPath = Path.Combine(tempDirectory, GetScriptName(mode));
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = powershellPath;
                string sta = IsInteractiveMode(mode) ? "-STA " : "";
                string agentModeArguments = mode == LaunchMode.EnterpriseAgentForce ? " -Force" : "";
                startInfo.Arguments = "-NoProfile -ExecutionPolicy RemoteSigned " + sta +
                    "-WindowStyle Hidden -File \"" + scriptPath + "\"" + agentModeArguments;
                startInfo.WorkingDirectory = tempDirectory;
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.WindowStyle = ProcessWindowStyle.Hidden;
                startInfo.EnvironmentVariables["TOOL_APPROVED_KMS_FILE"] = approvedKmsPath;
                startInfo.EnvironmentVariables["TOOL_SECURE_RUNTIME_DIR"] = Path.Combine(tempDirectory, "runtime");
                startInfo.EnvironmentVariables["TOOL_SECURE_LAUNCH"] = "1";
                startInfo.EnvironmentVariables["TOOL_BUILD_ARCHITECTURE"] = "AnyCPU";
                startInfo.EnvironmentVariables["TOOL_EXPECTED_PROCESS_ARCHITECTURE"] = RuntimeArchitecture;
                startInfo.EnvironmentVariables["TOOL_POWERSHELL_PATH"] = powershellPath;
                startInfo.EnvironmentVariables["TOOL_LOG_PATH"] = logPath;
                startInfo.EnvironmentVariables["TOOL_PLUGIN_DIR"] = pluginsDirectory;
                startInfo.EnvironmentVariables["TOOL_TIMELINE_PATH"] = timelinePath;
                startInfo.EnvironmentVariables["TOOL_TIMELINE_KEY_PATH"] = timelineKeyPath;
                startInfo.EnvironmentVariables["TOOL_ENTERPRISE_ROOT"] = enterpriseDirectory;
                startInfo.EnvironmentVariables["TOOL_LAUNCHER_PATH"] = Assembly.GetExecutingAssembly().Location;
                startInfo.EnvironmentVariables["TOOL_LAUNCH_MODE"] = mode.ToString();
                startInfo.EnvironmentVariables["TOOL_AGENT_FORCE"] = mode == LaunchMode.EnterpriseAgentForce ? "1" : "0";
                startInfo.EnvironmentVariables["TOOL_TOOL_VERSION"] = "4.4";
                startInfo.EnvironmentVariables["TOOL_CORRELATION_ID"] = correlationId;
                startInfo.EnvironmentVariables["TOOL_CAPABILITY_SCHEMA"] = "1.1";
                startInfo.EnvironmentVariables["TOOL_MODULE_CONTRACT_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_REPORT_SCHEMA"] = "1.5";
                startInfo.EnvironmentVariables["TOOL_SAFETY_POLICY_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_DASHBOARD_SCHEMA"] = "2.0";
                startInfo.EnvironmentVariables["TOOL_ENTERPRISE_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_COMPATIBILITY_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_LOCALIZATION_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_OFFLINE_POLICY_SCHEMA"] = "1.0";
                startInfo.EnvironmentVariables["TOOL_OFFLINE_MODE"] = offlineMode;
                startInfo.EnvironmentVariables["TOOL_ENTERPRISE_NETWORK_ALLOWED"] = enterpriseNetworkAllowed;

                using (Process process = Process.Start(startInfo))
                {
                    if (process == null)
                        throw new InvalidOperationException(UiText(
                            "Không thể khởi động Windows PowerShell.",
                            "Windows PowerShell could not be started."));
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                ShowMessage(mode,
                    UiText(
                        "Windows đã chặn hoặc không thể khởi động PowerShell.\r\n\r\n" +
                        "Tool không né UAC, AppLocker, WDAC hoặc phần mềm bảo mật. Hãy nhờ quản trị viên cho phép tệp nếu đây là máy cơ quan.\r\n\r\n",
                        "Windows blocked PowerShell or PowerShell could not be started.\r\n\r\n" +
                        "The tool does not bypass UAC, AppLocker, WDAC, or security software. On a managed device, ask an administrator to allow this file.\r\n\r\n") +
                    ex.Message,
                    MessageBoxIcon.Error);
                return 11;
            }
            catch (Exception ex)
            {
                ShowMessage(mode, UiText(
                    "Không thể khởi động Tool v4.4.\r\n\r\n",
                    "Tool v4.4 could not be started.\r\n\r\n") + ex.Message, MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                DeleteTemporaryDirectory(tempDirectory);
            }
        }

        private static bool IsArchitectureSupported()
        {
            // AnyCPU không đặt 32BITREQUIRED/32BITPREFERRED: CLR tự chọn x64 trên
            // Windows 64-bit và x86 trên Windows 32-bit. Vẫn fail-closed nếu tiến
            // trình bị ép thành 32-bit trên một hệ điều hành 64-bit.
            if (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess)
            {
                MessageBox.Show(
                    UiText(
                        "Tool phát hiện tiến trình 32-bit trên Windows 64-bit và đã dừng để tránh WOW64 chuyển hướng Registry/System32.\r\n\r\n" +
                        "Hãy chạy trực tiếp Tool-Kiem-Tra-v4.4.exe; bản AnyCPU sẽ tự dùng tiến trình 64-bit.",
                        "The tool detected a 32-bit process on 64-bit Windows and stopped to avoid WOW64 Registry/System32 redirection.\r\n\r\n" +
                        "Run Tool-Kiem-Tra-v4.4.exe directly; the AnyCPU build will use a 64-bit process automatically."),
                    GetProductCaption(),
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return false;
            }
            return true;
        }

        private static Dictionary<string, string> ExtractPayload(string targetDirectory)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            Dictionary<string, string> hashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (int index = 0; index < PayloadFiles.Length; index++)
            {
                string resourceName = "payload." + index.ToString();
                string outputPath = Path.Combine(targetDirectory, PayloadFiles[index]);

                using (Stream input = assembly.GetManifestResourceStream(resourceName))
                {
                    if (input == null)
                        throw new InvalidDataException("Thiếu thành phần đóng gói: " + PayloadFiles[index]);

                    using (FileStream output = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    using (SHA256 algorithm = SHA256.Create())
                    {
                        byte[] buffer = new byte[81920];
                        int bytesRead;
                        while ((bytesRead = input.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            output.Write(buffer, 0, bytesRead);
                            algorithm.TransformBlock(buffer, 0, bytesRead, buffer, 0);
                        }
                        algorithm.TransformFinalBlock(new byte[0], 0, 0);
                        hashes[PayloadFiles[index]] = BitConverter.ToString(algorithm.Hash).Replace("-", "");
                    }
                }
            }
            return hashes;
        }

        private static void InitializeProtectedApprovedKmsList(string extractedDirectory, string destination)
        {
            string sidecar = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "approved-kms-servers.txt");
            string bundled = Path.Combine(extractedDirectory, "approved-kms-servers.txt");

            if (File.Exists(destination))
            {
                FileInfo existingInfo = new FileInfo(destination);
                if ((existingInfo.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidDataException("Tệp cấu hình KMS bảo vệ không được là symlink/reparse point.");
                if (existingInfo.Length > 1024 * 1024)
                    throw new InvalidDataException("Tệp cấu hình KMS bảo vệ vượt quá giới hạn 1 MB.");
                return;
            }

            string source = File.Exists(sidecar) ? sidecar : bundled;
            if (!File.Exists(source))
                throw new InvalidDataException("Thiếu tệp mẫu approved-kms-servers.txt.");

            FileInfo sourceInfo = new FileInfo(source);
            if ((sourceInfo.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Tệp mẫu approved-kms-servers.txt không được là symlink/reparse point.");
            if (sourceInfo.Length > 1024 * 1024)
                throw new InvalidDataException("Tệp approved-kms-servers.txt vượt quá giới hạn 1 MB.");

            File.Copy(source, destination, false);
        }

        private static void InitializeProtectedBuiltInPlugin(string extractedDirectory, string pluginsDirectory)
        {
            string source = Path.Combine(extractedDirectory, "builtin-windows-office-trust.plugin.json");
            string destination = Path.Combine(pluginsDirectory, "thanhviet.builtin.windows-office-trust.plugin.json");
            if (!File.Exists(source))
                throw new InvalidDataException("Thiếu plugin quy tắc tích hợp.");

            FileInfo sourceInfo = new FileInfo(source);
            if ((sourceInfo.Attributes & FileAttributes.ReparsePoint) != 0 || sourceInfo.Length <= 0 || sourceInfo.Length > 524288)
                throw new InvalidDataException("Plugin tích hợp không an toàn hoặc vượt giới hạn.");

            if (File.Exists(destination))
            {
                FileInfo existingInfo = new FileInfo(destination);
                if ((existingInfo.Attributes & FileAttributes.ReparsePoint) != 0 || existingInfo.Length <= 0 || existingInfo.Length > 524288)
                    throw new InvalidDataException("Plugin tích hợp đã cài không an toàn hoặc vượt giới hạn.");
                return;
            }
            File.Copy(source, destination, false);
        }

        private static void CreateProtectedDirectory(string directory)
        {
            if (Directory.Exists(directory) &&
                (File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Từ chối thư mục bảo vệ là junction/symlink: " + directory);

            Directory.CreateDirectory(directory);

            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Từ chối thư mục bảo vệ là junction/symlink: " + directory);

            SecurityIdentifier administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            SecurityIdentifier system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            DirectorySecurity security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.SetOwner(administrators);
            InheritanceFlags inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            security.AddAccessRule(new FileSystemAccessRule(administrators, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            Directory.SetAccessControl(directory, security);
        }

        private static string GetSha256(string path)
        {
            using (FileStream stream = File.OpenRead(path))
            using (SHA256 algorithm = SHA256.Create())
                return BitConverter.ToString(algorithm.ComputeHash(stream)).Replace("-", "");
        }

        private static void VerifyExtractedPayload(string targetDirectory, Dictionary<string, string> extractedHashes)
        {
            string manifestPath = Path.Combine(targetDirectory, "TOOL-SHA256SUMS.txt");
            if (!File.Exists(manifestPath))
                throw new InvalidDataException("Thiếu manifest SHA-256 của bộ tool.");

            HashSet<string> required = new HashSet<string>(RequiredIntegrityFiles, StringComparer.OrdinalIgnoreCase);
            HashSet<string> checkedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string rawLine in File.ReadAllLines(manifestPath))
            {
                string line = rawLine.Trim();
                if (line.Length == 0 || line.StartsWith("#"))
                    continue;

                int separator = line.IndexOfAny(new char[] { ' ', '\t' });
                if (separator != 64)
                    throw new InvalidDataException("Manifest SHA-256 có dòng không hợp lệ.");

                string expected = line.Substring(0, 64).ToUpperInvariant();
                string relativeName = line.Substring(separator).Trim().TrimStart('*');
                if (!Regex.IsMatch(expected, "^[0-9A-F]{64}$"))
                    throw new InvalidDataException("Manifest SHA-256 chứa mã băm sai định dạng.");
                if (relativeName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || Path.GetFileName(relativeName) != relativeName)
                    throw new InvalidDataException("Manifest chứa tên tệp không an toàn: " + relativeName);
                if (!required.Contains(relativeName))
                    throw new InvalidDataException("Manifest chứa tệp ngoài danh sách cho phép: " + relativeName);
                if (!checkedFiles.Add(relativeName))
                    throw new InvalidDataException("Manifest chứa tệp lặp: " + relativeName);

                string path = Path.Combine(targetDirectory, relativeName);
                string actual;
                if (!File.Exists(path) || !extractedHashes.TryGetValue(relativeName, out actual) ||
                    !String.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("Kiểm tra toàn vẹn thất bại: " + relativeName);
            }

            foreach (string requiredFile in required)
            {
                if (!checkedFiles.Contains(requiredFile))
                    throw new InvalidDataException("Manifest SHA-256 thiếu thành phần bắt buộc: " + requiredFile);
            }

            if (checkedFiles.Count != required.Count)
                throw new InvalidDataException("Manifest SHA-256 không khớp danh sách thành phần bắt buộc.");
        }

        private static void DeleteTemporaryDirectory(string directory)
        {
            for (int attempt = 0; attempt < 8; attempt++)
            {
                try
                {
                    if (Directory.Exists(directory))
                        Directory.Delete(directory, true);
                    return;
                }
                catch
                {
                    Thread.Sleep(350);
                }
            }
        }
    }
}
