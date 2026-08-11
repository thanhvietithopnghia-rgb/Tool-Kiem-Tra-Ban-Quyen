using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Globalization;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Công cụ kiểm tra cấu hình máy và bản quyền phần mềm")]
[assembly: AssemblyDescription("Hỗ trợ người dùng cá nhân và doanh nghiệp - Tác giả phát triển Thanh Việt")]
[assembly: AssemblyCompany("Thanh Việt")]
[assembly: AssemblyProduct("Công cụ kiểm tra cấu hình máy và bản quyền phần mềm")]
[assembly: AssemblyCopyright("Copyright © Thanh Việt 2026")]
[assembly: AssemblyVersion("4.8.0.0")]
[assembly: AssemblyFileVersion("4.8.0.0")]
[assembly: AssemblyInformationalVersion("4.8.0.0")]

namespace ThanhViet.ToolKiemTra
{
    internal static class Program
    {
        private static string RuntimeArchitecture
        {
            get { return Environment.Is64BitProcess ? "x64" : "x86"; }
        }

        private static readonly object LocalizationLock = new object();
        private static readonly Dictionary<string, Dictionary<string, string>> LocalizationCatalogs =
            new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);

        private static readonly string[] PayloadFiles = new string[]
        {
            "00-Tool-Kiem-Tra.ico",
            "approved-kms-servers.txt",
            "HUONG-DAN.txt",
            "USER-GUIDE-en-US.md",
            "LICH-SU-PHIEN-BAN.txt",
            "VERSION-HISTORY-en-US.md",
            "Giao-Dien.ps1",
            "kiem-tra-cau-hinh-ban-quyen.ps1",
            "Tool-Kiem-Tra-icon.svg",
            "Tool-Kiem-Tra.cmd",
            "Tool-Runtime.ps1",
            "Tool-ElevatedBridge.ps1",
            "Tool-DataLifecycle.ps1",
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
            "Tool-Assistant.ps1",
            "tool-assistant-knowledge-v1.1.json",
            "Tool-SoftwareInventory.ps1",
            "software-license-catalog-v1.0.json",
            "software-license-online-update.ps1",
            "Tool-UpdateManager.ps1",
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
            "VERSION-HISTORY-en-US.md",
            "Giao-Dien.ps1",
            "kiem-tra-cau-hinh-ban-quyen.ps1",
            "Tool-Kiem-Tra-icon.svg",
            "Tool-Kiem-Tra.cmd",
            "Tool-Runtime.ps1",
            "Tool-ElevatedBridge.ps1",
            "Tool-DataLifecycle.ps1",
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
            "Tool-Assistant.ps1",
            "tool-assistant-knowledge-v1.1.json",
            "Tool-SoftwareInventory.ps1",
            "software-license-catalog-v1.0.json",
            "software-license-online-update.ps1",
            "Tool-UpdateManager.ps1",
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

            if (Environment.OSVersion.Platform != PlatformID.Win32NT)
            {
                ShowMessage(mode, L("launcher.windowsOnly"), MessageBoxIcon.Warning);
                return 10;
            }
            if (Environment.OSVersion.Version < new Version(6, 1))
            {
                ShowMessage(mode, L("launcher.windowsVersionRequired"), MessageBoxIcon.Warning);
                return 10;
            }
            if (!IsArchitectureSupported())
                return 12;
            if (RequiresAdministrator(mode) && !IsAdministrator())
                return RelaunchElevated(mode);

            bool createdNew;
            using (Mutex singleInstance = new Mutex(true, GetMutexName(mode), out createdNew))
            {
                if (!createdNew)
                {
                    ShowMessage(mode, L("launcher.singleInstance"), MessageBoxIcon.Information);
                    return 2;
                }

                string legacyMutexName;
                if (IsLegacyVersionRunning(out legacyMutexName))
                {
                    ShowMessage(mode, L("launcher.legacyVersionRunning", legacyMutexName), MessageBoxIcon.Warning);
                    return 3;
                }

                if (Environment.OSVersion.Platform != PlatformID.Win32NT)
                {
                    ShowMessage(mode, L("launcher.windowsOnly"), MessageBoxIcon.Warning);
                    return 10;
                }
                if (Environment.OSVersion.Version < new Version(6, 1))
                {
                    ShowMessage(mode, L("launcher.windowsVersionRequired"), MessageBoxIcon.Warning);
                    return 10;
                }
                if (!IsArchitectureSupported())
                    return 12;

                string powershellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "WindowsPowerShell\\v1.0\\powershell.exe");
                if (!File.Exists(powershellPath))
                {
                    ShowMessage(mode, L("launcher.powerShellMissing", powershellPath), MessageBoxIcon.Error);
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
                throw new ArgumentException(L("launcher.invalidArguments"));
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
            throw new ArgumentException(L("launcher.unsupportedArgument", args[0]));
        }

        private static bool RequiresAdministrator(LaunchMode mode)
        {
            return mode != LaunchMode.Gui;
        }

        private static bool IsAdministrator()
        {
            try
            {
                using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
                {
                    WindowsPrincipal principal = new WindowsPrincipal(identity);
                    return principal.IsInRole(WindowsBuiltInRole.Administrator);
                }
            }
            catch { return false; }
        }

        private static string GetLaunchArgument(LaunchMode mode)
        {
            switch (mode)
            {
                case LaunchMode.EnterpriseUi: return "--enterprise-ui";
                case LaunchMode.EnterpriseServer: return "--enterprise-server";
                case LaunchMode.EnterpriseAgent: return "--enterprise-agent";
                case LaunchMode.EnterpriseAgentForce: return "--enterprise-agent-force";
                case LaunchMode.LocalLicenseManager: return "--local-license-manager";
                default: return "--gui";
            }
        }

        private static int RelaunchElevated(LaunchMode mode)
        {
            try
            {
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = Assembly.GetExecutingAssembly().Location;
                startInfo.Arguments = GetLaunchArgument(mode);
                startInfo.UseShellExecute = true;
                startInfo.Verb = "runas";
                using (Process process = Process.Start(startInfo))
                {
                    if (process == null)
                        throw new InvalidOperationException(L("launcher.elevationFailed", "Process.Start returned null."));
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                if (ex.NativeErrorCode == 1223)
                {
                    ShowMessage(mode, L("launcher.elevationCancelled"), MessageBoxIcon.Information);
                    return 1223;
                }
                ShowMessage(mode, L("launcher.elevationFailed", ex.Message), MessageBoxIcon.Error);
                return 5;
            }
            catch (Exception ex)
            {
                ShowMessage(mode, L("launcher.elevationFailed", ex.Message), MessageBoxIcon.Error);
                return 5;
            }
        }

        private static string GetMutexName(LaunchMode mode)
        {
            switch (mode)
            {
                case LaunchMode.EnterpriseServer: return "Global\\ThanhViet.ToolKiemTra.v4.6.ServerLauncher";
                case LaunchMode.EnterpriseAgent:
                case LaunchMode.EnterpriseAgentForce: return "Global\\ThanhViet.ToolKiemTra.v4.6.AgentLauncher";
                case LaunchMode.EnterpriseUi: return "Local\\ThanhViet.ToolKiemTra.v4.6.EnterpriseUi";
                case LaunchMode.LocalLicenseManager: return "Local\\ThanhViet.ToolKiemTra.v4.6.LocalLicenseManager";
                default: return "Local\\ThanhViet.ToolKiemTra.v4.6.Gui";
            }
        }

        private static bool IsLegacyVersionRunning(out string activeMutexName)
        {
            string[] legacyMutexNames = new string[]
            {
                "Global\\ThanhViet.ToolKiemTra.v4.4.ServerLauncher",
                "Global\\ThanhViet.ToolKiemTra.v4.4.AgentLauncher",
                "Local\\ThanhViet.ToolKiemTra.v4.4.EnterpriseUi",
                "Local\\ThanhViet.ToolKiemTra.v4.4.LocalLicenseManager",
                "Local\\ThanhViet.ToolKiemTra.v4.4.Gui",
                "Global\\ThanhViet.ToolKiemTra.v4.4.EnterpriseServer"
            };
            foreach (string name in legacyMutexNames)
            {
                Mutex legacy = null;
                try
                {
                    if (!Mutex.TryOpenExisting(name, out legacy))
                        continue;
                    bool acquired = false;
                    try { acquired = legacy.WaitOne(0, false); }
                    catch (AbandonedMutexException) { acquired = true; }
                    if (acquired)
                    {
                        try { legacy.ReleaseMutex(); } catch (ApplicationException) { }
                        continue;
                    }
                    activeMutexName = name;
                    return true;
                }
                catch (UnauthorizedAccessException)
                {
                    activeMutexName = name;
                    return true;
                }
                finally
                {
                    if (legacy != null) legacy.Dispose();
                }
            }
            activeMutexName = String.Empty;
            return false;
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
            // Every fresh launch fails closed. Online is explicitly enabled only
            // inside the current dashboard session and is never restored silently.
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
                        "v4.6",
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

        private static string GetUiCulture()
        {
            return IsEnglishUi() ? "en-US" : "vi-VN";
        }

        private static string JsonUnescape(string value)
        {
            if (String.IsNullOrEmpty(value) || value.IndexOf('\\') < 0)
                return value ?? String.Empty;

            StringBuilder result = new StringBuilder(value.Length);
            for (int index = 0; index < value.Length; index++)
            {
                char current = value[index];
                if (current != '\\' || index + 1 >= value.Length)
                {
                    result.Append(current);
                    continue;
                }

                char escaped = value[++index];
                switch (escaped)
                {
                    case '"': result.Append('"'); break;
                    case '\\': result.Append('\\'); break;
                    case '/': result.Append('/'); break;
                    case 'b': result.Append('\b'); break;
                    case 'f': result.Append('\f'); break;
                    case 'n': result.Append('\n'); break;
                    case 'r': result.Append('\r'); break;
                    case 't': result.Append('\t'); break;
                    case 'u':
                        if (index + 4 < value.Length)
                        {
                            int codePoint;
                            string hex = value.Substring(index + 1, 4);
                            if (Int32.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out codePoint))
                            {
                                result.Append((char)codePoint);
                                index += 4;
                                break;
                            }
                        }
                        result.Append('u');
                        break;
                    default: result.Append(escaped); break;
                }
            }
            return result.ToString();
        }

        private static Stream OpenPayloadStream(Assembly assembly, int payloadIndex)
        {
            string suffix = payloadIndex.ToString(CultureInfo.InvariantCulture);
            Stream compressed = assembly.GetManifestResourceStream("payload.deflate." + suffix);
            if (compressed != null)
                return new DeflateStream(compressed, CompressionMode.Decompress, false);

            return assembly.GetManifestResourceStream("payload.raw." + suffix);
        }

        private static Dictionary<string, string> LoadLocalizationCatalog(string culture)
        {
            lock (LocalizationLock)
            {
                Dictionary<string, string> cached;
                if (LocalizationCatalogs.TryGetValue(culture, out cached))
                    return cached;

                Dictionary<string, string> catalog = new Dictionary<string, string>(StringComparer.Ordinal);
                string fileName = "Tool-Strings." + culture + ".json";
                int payloadIndex = Array.IndexOf(PayloadFiles, fileName);
                if (payloadIndex >= 0)
                {
                    Assembly assembly = Assembly.GetExecutingAssembly();
                    using (Stream stream = OpenPayloadStream(assembly, payloadIndex))
                    {
                        if (stream != null)
                        {
                            using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(false), true))
                            {
                                string json = reader.ReadToEnd();
                                MatchCollection entries = Regex.Matches(
                                    json,
                                    "\"(?<key>(?:\\\\.|[^\"\\\\])*)\"\\s*:\\s*\"(?<value>(?:\\\\.|[^\"\\\\])*)\"",
                                    RegexOptions.CultureInvariant);
                                foreach (Match entry in entries)
                                    catalog[JsonUnescape(entry.Groups["key"].Value)] = JsonUnescape(entry.Groups["value"].Value);
                            }
                        }
                    }
                }
                LocalizationCatalogs[culture] = catalog;
                return catalog;
            }
        }

        private static string L(string key, params object[] arguments)
        {
            string culture = GetUiCulture();
            string text;
            Dictionary<string, string> catalog = LoadLocalizationCatalog(culture);
            if (!catalog.TryGetValue(key, out text) && !String.Equals(culture, "vi-VN", StringComparison.OrdinalIgnoreCase))
                LoadLocalizationCatalog("vi-VN").TryGetValue(key, out text);
            if (String.IsNullOrEmpty(text))
                text = "[" + key + "]";
            if (arguments == null || arguments.Length == 0)
                return text;
            try
            {
                return String.Format(CultureInfo.GetCultureInfo(culture), text, arguments);
            }
            catch (FormatException)
            {
                return text;
            }
        }

        private static string GetProductCaption()
        {
            return L("launcher.productCaption");
        }

        private static int RunPayload(LaunchMode mode, string powershellPath)
        {
            bool machineScope = mode != LaunchMode.Gui;
            string dataBase = Environment.GetFolderPath(machineScope
                ? Environment.SpecialFolder.CommonApplicationData
                : Environment.SpecialFolder.LocalApplicationData);
            if (String.IsNullOrWhiteSpace(dataBase))
                dataBase = Path.GetTempPath();
            string productRoot = Path.Combine(dataBase, "ThanhViet-Tool-Kiem-Tra");
            string protectedRoot = Path.Combine(productRoot, "v4.6");
            string legacyRoot = Path.Combine(productRoot, "v4.4");
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
                ShowMessage(mode, L("launcher.enterpriseNetworkBlocked"), MessageBoxIcon.Information);
                return 30;
            }

            try
            {
                CreateProtectedDirectory(productRoot, machineScope);
                CreateProtectedDirectory(protectedRoot, machineScope);
                CreateProtectedDirectory(logsDirectory, machineScope);
                CreateProtectedDirectory(pluginsDirectory, machineScope);
                CreateProtectedDirectory(timelineDirectory, machineScope);
                CreateProtectedDirectory(tempDirectory, machineScope);
                Dictionary<string, string> extractedHashes = ExtractPayload(tempDirectory);
                VerifyExtractedPayload(tempDirectory, extractedHashes);
                InitializeProtectedApprovedKmsList(tempDirectory, approvedKmsPath);
                InitializeProtectedBuiltInPlugin(tempDirectory, pluginsDirectory);
                CreateProtectedDirectory(Path.Combine(tempDirectory, "runtime"), machineScope);

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
                startInfo.EnvironmentVariables["TOOL_DATA_ROOT"] = protectedRoot;
                startInfo.EnvironmentVariables["TOOL_LEGACY_DATA_ROOT"] = legacyRoot;
                startInfo.EnvironmentVariables["TOOL_DATA_SCOPE"] = machineScope ? "Machine" : "User";
                startInfo.EnvironmentVariables["TOOL_DATA_SCHEMA_VERSION"] = "2.0";
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
                startInfo.EnvironmentVariables["TOOL_LAUNCHER_PID"] = Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture);
                startInfo.EnvironmentVariables["TOOL_LAUNCH_MODE"] = mode.ToString();
                startInfo.EnvironmentVariables["TOOL_AGENT_FORCE"] = mode == LaunchMode.EnterpriseAgentForce ? "1" : "0";
                startInfo.EnvironmentVariables["TOOL_TOOL_VERSION"] = "4.8.0.0";
                startInfo.EnvironmentVariables["TOOL_UI_CULTURE"] = GetUiCulture();
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
                        throw new InvalidOperationException(L("launcher.powerShellStartFailed"));
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
            catch (System.ComponentModel.Win32Exception ex)
            {
                ShowMessage(mode, L("launcher.powerShellBlocked", ex.Message), MessageBoxIcon.Error);
                return 11;
            }
            catch (Exception ex)
            {
                ShowMessage(mode, L("launcher.toolStartFailed", ex.Message), MessageBoxIcon.Error);
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
                    L("launcher.architectureMismatch"),
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
                string outputPath = Path.Combine(targetDirectory, PayloadFiles[index]);

                using (Stream input = OpenPayloadStream(assembly, index))
                {
                    if (input == null)
                        throw new InvalidDataException(L("launcher.payloadMissing", PayloadFiles[index]));

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
                    throw new InvalidDataException(L("launcher.kmsProtectedReparse"));
                if (existingInfo.Length > 1024 * 1024)
                    throw new InvalidDataException(L("launcher.kmsProtectedTooLarge"));
                return;
            }

            string source = File.Exists(sidecar) ? sidecar : bundled;
            if (!File.Exists(source))
                throw new InvalidDataException(L("launcher.kmsTemplateMissing"));

            FileInfo sourceInfo = new FileInfo(source);
            if ((sourceInfo.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException(L("launcher.kmsTemplateReparse"));
            if (sourceInfo.Length > 1024 * 1024)
                throw new InvalidDataException(L("launcher.kmsTemplateTooLarge"));

            File.Copy(source, destination, false);
        }

        private static void InitializeProtectedBuiltInPlugin(string extractedDirectory, string pluginsDirectory)
        {
            string source = Path.Combine(extractedDirectory, "builtin-windows-office-trust.plugin.json");
            string destination = Path.Combine(pluginsDirectory, "thanhviet.builtin.windows-office-trust.plugin.json");
            if (!File.Exists(source))
                throw new InvalidDataException(L("launcher.pluginMissing"));

            FileInfo sourceInfo = new FileInfo(source);
            if ((sourceInfo.Attributes & FileAttributes.ReparsePoint) != 0 || sourceInfo.Length <= 0 || sourceInfo.Length > 524288)
                throw new InvalidDataException(L("launcher.pluginUnsafe"));

            if (File.Exists(destination))
            {
                FileInfo existingInfo = new FileInfo(destination);
                if ((existingInfo.Attributes & FileAttributes.ReparsePoint) != 0 || existingInfo.Length <= 0 || existingInfo.Length > 524288)
                    throw new InvalidDataException(L("launcher.pluginInstalledUnsafe"));
                return;
            }
            File.Copy(source, destination, false);
        }

        private static void CreateProtectedDirectory(string directory, bool machineScope)
        {
            if (Directory.Exists(directory) &&
                (File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException(L("launcher.protectedDirectoryReparse", directory));

            Directory.CreateDirectory(directory);

            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException(L("launcher.protectedDirectoryReparse", directory));

            SecurityIdentifier administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            SecurityIdentifier system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            SecurityIdentifier currentUser = WindowsIdentity.GetCurrent().User;
            DirectorySecurity security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            security.SetOwner(machineScope ? administrators : currentUser);
            InheritanceFlags inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            security.AddAccessRule(new FileSystemAccessRule(administrators, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(system, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            if (!machineScope && currentUser != null)
                security.AddAccessRule(new FileSystemAccessRule(currentUser, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
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
                throw new InvalidDataException(L("launcher.manifestMissing"));

            HashSet<string> required = new HashSet<string>(RequiredIntegrityFiles, StringComparer.OrdinalIgnoreCase);
            HashSet<string> checkedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string rawLine in File.ReadAllLines(manifestPath))
            {
                string line = rawLine.Trim();
                if (line.Length == 0 || line.StartsWith("#"))
                    continue;

                int separator = line.IndexOfAny(new char[] { ' ', '\t' });
                if (separator != 64)
                    throw new InvalidDataException(L("launcher.manifestLineInvalid"));

                string expected = line.Substring(0, 64).ToUpperInvariant();
                string relativeName = line.Substring(separator).Trim().TrimStart('*');
                if (!Regex.IsMatch(expected, "^[0-9A-F]{64}$"))
                    throw new InvalidDataException(L("launcher.manifestHashInvalid"));
                if (relativeName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || Path.GetFileName(relativeName) != relativeName)
                    throw new InvalidDataException(L("launcher.manifestFileNameUnsafe", relativeName));
                if (!required.Contains(relativeName))
                    throw new InvalidDataException(L("launcher.manifestFileNotAllowed", relativeName));
                if (!checkedFiles.Add(relativeName))
                    throw new InvalidDataException(L("launcher.manifestDuplicate", relativeName));

                string path = Path.Combine(targetDirectory, relativeName);
                string actual;
                if (!File.Exists(path) || !extractedHashes.TryGetValue(relativeName, out actual) ||
                    !String.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException(L("launcher.integrityFailed", relativeName));
            }

            foreach (string requiredFile in required)
            {
                if (!checkedFiles.Contains(requiredFile))
                    throw new InvalidDataException(L("launcher.manifestRequiredMissing", requiredFile));
            }

            if (checkedFiles.Count != required.Count)
                throw new InvalidDataException(L("launcher.manifestCountMismatch"));
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
