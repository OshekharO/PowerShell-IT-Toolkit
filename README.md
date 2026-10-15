# SysAdmin Toolkit

> **Tagline:** Diagnose. Repair. Keep Windows Running.

A comprehensive, all-in-one diagnostic, repair, and maintenance PowerShell toolkit engineered for technical support professionals, sysadmins, and IT technicians. Collects system specs, inspects hardware, evaluates disk health, analyzes event logs, diagnoses network issues, inspects security/encryption/TPM settings, audits startup items & user accounts, performs Windows repairs, and generates consolidated reports.

![SysAdmin Toolkit Interactive Menu](image.png)

---

## 🛠️ Key Features

- **System Information:** Collects OS build, architecture, computer model, serial number, uptime, and registered user info.
- **Hardware Information:** Detailed specifications for CPU (cores, clock speed), RAM (slots, capacity, speed), Motherboard, and GPU (resolution, driver version).
- **Disk Health & Storage:** Logical volume space usage and physical disk SMART health status.
- **Network Diagnostics:** IP configuration, active network adapters, ICMP ping tests, DNS server checks, routing table, ARP cache, and listening ports.
- **Event Logs:** Queries recent Critical and Error entries across System, Application, and Security logs.
- **Services & Processes:** Identifies stopped automatic services and highlights top CPU and Memory consuming processes.
- **Installed Software:** Generates a full inventory of installed software and exports to CSV.
- **Windows Repair:** Executes `DISM /Online /Cleanup-Image /RestoreHealth` and System File Checker (`sfc /scannow`).
- **CHKDSK Scan:** Read-only health check for disk integrity on the C: volume.
- **Firewall Status:** Status of Domain, Private, and Public firewall profiles along with enabled inbound rules summary.
- **Windows Update History:** Displays installed hotfixes and update records sorted by installation date.
- **Security Diagnostics:** Inspects Windows Defender status & real-time protection, BitLocker volume encryption, and TPM health.
- **Startup & Accounts Info:** Audits startup applications (Registry & CIM), local user accounts, and members of the local Administrators group.
- **Battery Report:** Generates an HTML battery health and capacity report via `powercfg /batteryreport`.
- **Full Diagnostic Mode:** Runs all diagnostic functions sequentially and creates a timestamped report directory.
- **Quick Maintenance Utilities:** Quick actions to Flush DNS, Release & Renew IP, Reset Winsock & IP, Clear Temporary Files, Purge Print Queue & Restart Spooler, and Restart Windows Update Services.
- **Open Report Folder:** Fast 1-click access to all generated reports.
- **Task Scheduler Integration:** Automated daily diagnostic task setup via Task Scheduler.

---

## 🚀 Getting Started

### Prerequisites
- **Operating System:** Windows 10, Windows 11, or Windows Server 2016+
- **PowerShell Version:** Windows PowerShell 5.1 or PowerShell 7+
- **Privileges:** Administrator privileges required for full functionality (DISM, SFC, Event Logs, Firewall, BitLocker, Defender, TPM).

### Usage Instructions

1. **Open PowerShell as Administrator**
   Right-click PowerShell or Windows Terminal and select **Run as Administrator**.

2. **Unblock Downloaded File (if blocked by Windows):**
   When scripts are downloaded from the internet, Windows marks them as blocked (untrusted). Unblock the script before running:
   ```powershell
   Unblock-File .\SysAdmin_Toolkit.ps1
   ```

3. **Set Execution Policy / Bypass Execution Restrictions:**
   If running unsigned scripts is blocked on your system, temporarily set the execution policy for your current session:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```

4. **Run the Script:**
   ```powershell
   .\SysAdmin_Toolkit.ps1
   ```
   *Alternatively, run directly with execution policy bypass:*
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\SysAdmin_Toolkit.ps1
   ```

---

## 📁 Output Reports

Each session creates a timestamped folder on the current user's Desktop:
`Desktop\IT_Toolkit_Report_YYYY-MM-DD_HH-mm-ss\`

It contains:
- `Technician_Log.txt` - Complete log of all actions executed during the session.
- `SystemInfo.txt` & `ComputerInfo.txt` & `OperatingSystem.txt` - Operating system and system architecture details.
- `HardwareInfo.txt` - CPU, RAM layout, GPU, and motherboard specs.
- `DiskHealth.txt` - Drive space and SMART status.
- `InstalledSoftware.csv` - Full inventory of installed programs.
- `NetworkDiagnostics.txt` - Adapter details, ping results, DNS, routes, and listening ports.
- `EventLogs_RecentErrors.txt` - Critical/Error logs from Application, System, and Security.
- `Services.txt` & `TopProcesses.txt` - Service states and top resource-consuming processes.
- `FirewallStatus.txt` - Active firewall profiles and enabled inbound rules.
- `WindowsUpdateHistory.txt` - Installed hotfixes and update records.
- `SecurityDiagnostics.txt` - Windows Defender, BitLocker encryption, and TPM status.
- `StartupAndAccountInfo.txt` - Local accounts, local admin group members, and startup applications.
- `WindowsRepair.txt` - Logs from DISM and SFC scans.
- `BatteryReport.html` - Comprehensive laptop battery analytics.

---

## 🤖 Automating with Task Scheduler

You can schedule the script to run daily at 8:00 AM automatically:
1. Launch `SysAdmin_Toolkit.ps1`.
2. Select **[17] Schedule Daily Task**.
3. The script will register `SysAdmin_Toolkit_Daily_Diagnostics` in Task Scheduler using `-AutoRun`.

---

## 📄 License
Released under the MIT License. Designed for IT Professionals and Technical Support teams.
