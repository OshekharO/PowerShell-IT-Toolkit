# ==============================================================================
# SYSADMIN TOOLKIT - FULL IT TECHNICIAN TOOLKIT
# Tagline: Diagnose. Repair. Keep Windows Running.
# Version: 1.1.0
# Description: All-in-one diagnostic, repair, and maintenance toolkit for Windows systems.
#              Collects system info, hardware details, scans disks, gathers logs,
#              performs Windows repairs, audits drivers, SMB shares, and more.
# ==============================================================================

# Ensure script runs as Administrator; attempt auto-elevation if interactive
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Warning "WARNING: SysAdmin Toolkit is running without Administrator privileges."
    Write-Warning "Many diagnostic and repair features (DISM, SFC, Firewall, EventLogs) require Administrator access."
    Write-Host "Attempting to elevate execution to Administrator..." -ForegroundColor Yellow
    try {
        $ScriptPath = $MyInvocation.MyCommand.Definition
        if ($ScriptPath) {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
            Exit
        }
    } catch {
        Write-Error "Failed to elevate. Please re-run PowerShell as Administrator."
    }
}

$ErrorActionPreference = "Continue"

# Setup Output Folder and Logging
$Date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$Desktop = [Environment]::GetFolderPath("Desktop")
if (-not $Desktop -or -not (Test-Path $Desktop)) {
    $Desktop = "$env:USERPROFILE\Desktop"
}
$WorkDir = Join-Path $Desktop "IT_Toolkit_Report_$Date"

if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

$Log = Join-Path $WorkDir "Technician_Log.txt"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$Timestamp] [$Level] $Message"
    $Line | Tee-Object -FilePath $Log -Append
}

Write-Log "SysAdmin Toolkit initialized. Output directory: $WorkDir"


# ==============================================================================
# SECTION 1: CORE DIAGNOSTIC FUNCTIONS
# ==============================================================================

function Get-SystemInformation {
    Write-Host "`n[+] Collecting System Information..." -ForegroundColor Cyan
    Write-Log "Starting System Information collection..."

    $SysInfoPath = Join-Path $WorkDir "SystemInfo.txt"
    $CompInfoPath = Join-Path $WorkDir "ComputerInfo.txt"
    $OSInfoPath = Join-Path $WorkDir "OperatingSystem.txt"

    try {
        # Standard Windows systeminfo output
        systeminfo | Out-File -FilePath $SysInfoPath -Encoding utf8

        # Detailed WMI/CIM Computer System Info
        Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory, PrimaryOwnerName, Domain, Workgroup | Format-List | Out-File -FilePath $CompInfoPath -Encoding utf8

        # Detailed WMI/CIM Operating System Info
        Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime, RegisteredUser, InstallDate | Format-List | Out-File -FilePath $OSInfoPath -Encoding utf8

        Write-Host " [OK] System information successfully saved to $WorkDir" -ForegroundColor Green
        Write-Log "System Information collected successfully."
    } catch {
        Write-Host " [!] Error collecting System Information: $_" -ForegroundColor Red
        Write-Log "Error collecting System Information: $_" "ERROR"
    }
}

function Get-HardwareInformation {
    Write-Host "`n[+] Collecting Hardware Information..." -ForegroundColor Cyan
    Write-Log "Starting Hardware Information collection..."

    $HwInfoPath = Join-Path $WorkDir "HardwareInfo.txt"

    try {
        $HwReport = @()
        $HwReport += "=========================================="
        $HwReport += "           HARDWARE INFORMATION           "
        $HwReport += "=========================================="
        $HwReport += ""

        # CPU Details
        $CPUs = Get-CimInstance Win32_Processor
        $HwReport += "--- PROCESSOR (CPU) ---"
        foreach ($cpu in $CPUs) {
            $HwReport += "Name: $($cpu.Name)"
            $HwReport += "Cores: $($cpu.NumberOfCores) | Logical Processors: $($cpu.NumberOfLogicalProcessors)"
            $HwReport += "Max Clock Speed: $($cpu.MaxClockSpeed) MHz"
            $HwReport += "Socket: $($cpu.SocketDesignation)"
            $HwReport += ""
        }

        # RAM Details
        $RAMs = Get-CimInstance Win32_PhysicalMemory
        $HwReport += "--- PHYSICAL MEMORY (RAM) ---"
        $TotalRAMGB = [math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 2)
        $HwReport += "Total Installed RAM: $TotalRAMGB GB"
        foreach ($ram in $RAMs) {
            $CapacityGB = [math]::Round(($ram.Capacity / 1GB), 2)
            $HwReport += "Slot: $($ram.DeviceLocator) | Capacity: $CapacityGB GB | Speed: $($ram.Speed) MHz | Manufacturer: $($ram.Manufacturer)"
        }
        $HwReport += ""

        # Motherboard Details
        $MB = Get-CimInstance Win32_BaseBoard
        $HwReport += "--- MOTHERBOARD ---"
        $HwReport += "Manufacturer: $($MB.Manufacturer)"
        $HwReport += "Product: $($MB.Product)"
        $HwReport += "SerialNumber: $($MB.SerialNumber)"
        $HwReport += ""

        # GPU / Display Adapters
        $GPUs = Get-CimInstance Win32_VideoController
        $HwReport += "--- GRAPHICS CARD (GPU) ---"
        foreach ($gpu in $GPUs) {
            $HwReport += "Name: $($gpu.Name)"
            $HwReport += "Driver Version: $($gpu.DriverVersion)"
            $HwReport += "Video Processor: $($gpu.VideoProcessor)"
            $HwReport += "Resolution: $($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution) @ $($gpu.CurrentRefreshRate) Hz"
            $HwReport += ""
        }

        $HwReport | Out-File -FilePath $HwInfoPath -Encoding utf8
        Write-Host " [OK] Hardware information saved to $HwInfoPath" -ForegroundColor Green
        Write-Log "Hardware Information collected successfully."
    } catch {
        Write-Host " [!] Error collecting Hardware Information: $_" -ForegroundColor Red
        Write-Log "Error collecting Hardware Information: $_" "ERROR"
    }
}

function Get-DiskHealth {
    Write-Host "`n[+] Checking Disk Health & Storage..." -ForegroundColor Cyan
    Write-Log "Starting Disk Health & Storage check..."

    $DiskInfoPath = Join-Path $WorkDir "DiskHealth.txt"

    try {
        $DiskReport = @()
        $DiskReport += "=========================================="
        $DiskReport += "         DISK HEALTH & STORAGE            "
        $DiskReport += "=========================================="
        $DiskReport += ""

        # Logical Drives / Volumes
        $DiskReport += "--- LOGICAL VOLUMES ---"
        $Volumes = Get-CimInstance Win32_LogicalDisk
        foreach ($vol in $Volumes) {
            $SizeGB = [math]::Round(($vol.Size / 1GB), 2)
            $FreeGB = [math]::Round(($vol.FreeSpace / 1GB), 2)
            $PercentFree = if ($vol.Size -gt 0) { [math]::Round(($vol.FreeSpace / $vol.Size) * 100, 1) } else { 0 }
            $DiskReport += "Drive $($vol.DeviceID) [$($vol.VolumeName)] - FileSystem: $($vol.FileSystem)"
            $DiskReport += "  Size: $SizeGB GB | Free Space: $FreeGB GB ($PercentFree% Free)"
            $DiskReport += ""
        }

        # Physical Disk & SMART Health Status
        $DiskReport += "--- PHYSICAL DISKS & SMART HEALTH ---"
        try {
            $PhysicalDisks = Get-PhysicalDisk
            foreach ($pd in $PhysicalDisks) {
                $SizeGB = [math]::Round(($pd.Size / 1GB), 2)
                $DiskReport += "Disk $($pd.DeviceId): $($pd.FriendlyName) ($SizeGB GB)"
                $DiskReport += "  MediaType: $($pd.MediaType) | BusType: $($pd.BusType)"
                $DiskReport += "  Operational Status: $($pd.OperationalStatus) | Health Status: $($pd.HealthStatus)"
                $DiskReport += ""
            }
        } catch {
            # Fallback to WMI DiskDrive if Get-PhysicalDisk fails
            $WmiDisks = Get-CimInstance Win32_DiskDrive
            foreach ($d in $WmiDisks) {
                $SizeGB = [math]::Round(($d.Size / 1GB), 2)
                $DiskReport += "Disk $($d.Index): $($d.Model) ($SizeGB GB) - Status: $($d.Status)"
            }
        }

        $DiskReport | Out-File -FilePath $DiskInfoPath -Encoding utf8
        Write-Host " [OK] Disk health & storage report saved to $DiskInfoPath" -ForegroundColor Green
        Write-Log "Disk health & storage report saved successfully."
    } catch {
        Write-Host " [!] Error checking Disk Health: $_" -ForegroundColor Red
        Write-Log "Error checking Disk Health: $_" "ERROR"
    }
}

function Get-InstalledSoftware {
    Write-Host "`n[+] Collecting Installed Software List..." -ForegroundColor Cyan
    Write-Log "Starting Installed Software collection..."

    $CsvPath = Join-Path $WorkDir "InstalledSoftware.csv"
    $TxtPath = Join-Path $WorkDir "InstalledSoftware.txt"

    try {
        $SoftwareList = @()

        # Registry uninstall keys (64-bit and 32-bit)
        $RegPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach ($path in $RegPaths) {
            if (Test-Path $path) {
                $SoftwareList += Get-ItemProperty $path |
                    Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } |
                    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString
            }
        }

        # Sort and filter unique software entries
        $UniqueSoftware = $SoftwareList | Sort-Object DisplayName -Unique

        $UniqueSoftware | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding utf8
        $UniqueSoftware | Format-Table -AutoSize | Out-File -FilePath $TxtPath -Encoding utf8

        Write-Host " [OK] Installed software list saved to CSV and TXT in $WorkDir" -ForegroundColor Green
        Write-Log "Installed Software list collected successfully ($($UniqueSoftware.Count) programs found)."
    } catch {
        Write-Host " [!] Error collecting Installed Software: $_" -ForegroundColor Red
        Write-Log "Error collecting Installed Software: $_" "ERROR"
    }
}

function Get-DriverDiagnostics {
    Write-Host "`n[+] Checking Device Drivers & PnP Hardware Health..." -ForegroundColor Cyan
    Write-Log "Starting Device Driver & PnP Hardware Health audit..."

    $DriverPath = Join-Path $WorkDir "DriverDiagnostics.txt"

    try {
        $DriverReport = @()
        $DriverReport += "=========================================="
        $DriverReport += "     DEVICE DRIVER & PNP HEALTH AUDIT     "
        $DriverReport += "=========================================="
        $DriverReport += ""

        # Query PnP Entities with errors or issues
        $ProblemDevices = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -ne "OK" }

        if ($ProblemDevices) {
            $DriverReport += "--- DEVICES WITH DRIVER ERRORS OR ISSUES ---"
            foreach ($dev in $ProblemDevices) {
                $DriverReport += "Device Name   : $($dev.Name)"
                $DriverReport += "Device ID     : $($dev.DeviceID)"
                $DriverReport += "Error Code    : $($dev.ConfigManagerErrorCode)"
                $DriverReport += "Status        : $($dev.Status)"
                $DriverReport += "PNP Class     : $($dev.PNPClass)"
                $DriverReport += "Manufacturer  : $($dev.Manufacturer)"
                $DriverReport += "------------------------------------------"
            }
        } else {
            $DriverReport += " [OK] All Plug and Play devices are functioning normally (No ConfigManager errors detected)."
        }
        $DriverReport += ""

        # Summary of installed driver packages/signed state sample
        $DriverReport += "--- DRIVER SUMMARY & PROBLEM SUMMARY ---"
        $TotalPnP = (Get-CimInstance Win32_PnPEntity).Count
        $DriverReport += "Total PnP Devices Enumerated: $TotalPnP"
        $DriverReport += "Problem Devices Found      : $($ProblemDevices.Count)"

        $DriverReport | Out-File -FilePath $DriverPath -Encoding utf8
        Write-Host " [OK] Driver diagnostics report saved to $DriverPath" -ForegroundColor Green
        Write-Log "Driver diagnostics completed successfully."
    } catch {
        Write-Host " [!] Error checking Device Drivers: $_" -ForegroundColor Red
        Write-Log "Error checking Device Drivers: $_" "ERROR"
    }
}

# ==============================================================================
# SECTION 2: NETWORK, LOGGING, AND MONITORING FUNCTIONS
# ==============================================================================

function Get-NetworkDiagnostics {
    Write-Host "`n[+] Running Network Diagnostics..." -ForegroundColor Cyan
    Write-Log "Starting Network Diagnostics..."

    $NetPath = Join-Path $WorkDir "NetworkDiagnostics.txt"

    try {
        $NetReport = @()
        $NetReport += "=========================================="
        $NetReport += "           NETWORK DIAGNOSTICS            "
        $NetReport += "=========================================="
        $NetReport += ""

        # IP Configuration
        $NetReport += "--- IP CONFIGURATION ---"
        $Adapters = Get-NetAdapter -ErrorAction SilentlyContinue
        if ($Adapters) {
            foreach ($adapter in $Adapters) {
                $IPs = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressFamily -eq 'IPv4' }
                $NetReport += "Adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
                $NetReport += "  Status: $($adapter.Status) | Speed: $($adapter.LinkSpeed) | MAC: $($adapter.MacAddress)"
                foreach ($ip in $IPs) {
                    $NetReport += "  IPv4 Address: $($ip.IPAddress)/$($ip.PrefixLength)"
                }
                $NetReport += ""
            }
        } else {
            $NetReport += (ipconfig /all | Out-String)
        }

        # DNS Server Configuration
        $NetReport += "--- DNS SERVERS ---"
        $DNS = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
        foreach ($d in $DNS) {
            if ($d.ServerAddresses) {
                $NetReport += "Interface $($d.InterfaceAlias): $($d.ServerAddresses -join ', ')"
            }
        }
        $NetReport += ""

        # Ping Connectivity Test
        $NetReport += "--- PING CONNECTIVITY TEST ---"
        $TestTargets = @("1.1.1.1", "8.8.8.8", "google.com")
        foreach ($target in $TestTargets) {
            $PingResult = Test-Connection -ComputerName $target -Count 2 -Quiet -ErrorAction SilentlyContinue
            $Status = if ($PingResult) { "SUCCESS" } else { "FAILED" }
            $NetReport += "Ping $target : $Status"
        }
        $NetReport += ""

        # Active Routing Table
        $NetReport += "--- ROUTING TABLE ---"
        $NetReport += (Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias | Format-Table -AutoSize | Out-String)

        # ARP Table
        $NetReport += "--- ARP TABLE ---"
        $NetReport += (Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias | Format-Table -AutoSize | Out-String)

        # Listening Ports
        $NetReport += "--- LISTENING PORTS (TCP/UDP) ---"
        $NetReport += (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize | Out-String)

        $NetReport | Out-File -FilePath $NetPath -Encoding utf8
        Write-Host " [OK] Network diagnostics saved to $NetPath" -ForegroundColor Green
        Write-Log "Network Diagnostics completed successfully."
    } catch {
        Write-Host " [!] Error running Network Diagnostics: $_" -ForegroundColor Red
        Write-Log "Error running Network Diagnostics: $_" "ERROR"
    }
}

function Get-NetworkExtendedInfo {
    Write-Host "`n[+] Checking Public IP & Hosts File Security..." -ForegroundColor Cyan
    Write-Log "Starting Extended Network & Hosts File inspection..."

    $NetExtPath = Join-Path $WorkDir "NetworkExtended.txt"

    try {
        $Report = @()
        $Report += "=========================================="
        $Report += "   EXTENDED NETWORK & HOSTS FILE CHECK    "
        $Report += "=========================================="
        $Report += ""

        # Public IP Detection
        $Report += "--- EXTERNAL / PUBLIC IP ADDRESS ---"
        try {
            $PublicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5 -ErrorAction Stop).ip
            $Report += "Public IP Address: $PublicIp"
        } catch {
            try {
                $PublicIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 5 -ErrorAction Stop).Trim()
                $Report += "Public IP Address: $PublicIp"
            } catch {
                $Report += "Public IP Address: Unable to retrieve (Offline or blocked)"
            }
        }
        $Report += ""

        # Hosts File Audit
        $Report += "--- HOSTS FILE AUDIT ---"
        $HostsFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (Test-Path $HostsFilePath) {
            $HostsContent = Get-Content -Path $HostsFilePath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
            if ($HostsContent) {
                $Report += "Custom / Non-Comment Hosts Entries Found:"
                foreach ($line in $HostsContent) {
                    $Report += "  $line"
                }
            } else {
                $Report += " [OK] Hosts file contains only default comments (No custom redirects)."
            }
        } else {
            $Report += " [!] Hosts file not found at $HostsFilePath"
        }
        $Report += ""

        # WAN DNS Resolution & Latency
        $Report += "--- WAN DOMAIN RESOLUTION & LATENCY ---"
        $Targets = @("microsoft.com", "cloudflare.com")
        foreach ($t in $Targets) {
            try {
                $IPs = [System.Net.Dns]::GetHostAddresses($t) | ForEach-Object { $_.IPAddressToString }
                $Report += "Domain: $t -> IPs: $($IPs -join ', ')"
            } catch {
                $Report += "Domain: $t -> Resolution Failed"
            }
        }

        $Report | Out-File -FilePath $NetExtPath -Encoding utf8
        Write-Host " [OK] Extended network info saved to $NetExtPath" -ForegroundColor Green
        Write-Log "Extended network info collected successfully."
    } catch {
        Write-Host " [!] Error gathering Extended Network Info: $_" -ForegroundColor Red
        Write-Log "Error gathering Extended Network Info: $_" "ERROR"
    }
}

function Get-EventLogs {
    Write-Host "`n[+] Gathering Recent Windows Event Logs..." -ForegroundColor Cyan
    Write-Log "Starting Event Logs gathering..."

    $LogPath = Join-Path $WorkDir "EventLogs_RecentErrors.txt"

    try {
        $EventReport = @()
        $EventReport += "=========================================="
        $EventReport += "      RECENT EVENT LOGS (CRITICAL/ERROR)  "
        $EventReport += "=========================================="
        $EventReport += ""

        $LogNames = @("System", "Application", "Security")
        foreach ($logName in $LogNames) {
            $EventReport += "--- RECENT ERRORS IN $logName LOG ---"
            try {
                $Events = Get-WinEvent -FilterHashtable @{LogName=$logName; Level=1,2} -MaxEvents 25 -ErrorAction SilentlyContinue
                if ($Events) {
                    foreach ($e in $Events) {
                        $EventReport += "[$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))] [ID: $($e.Id)] [Source: $($e.ProviderName)]"
                        $EventReport += "  Message: $($e.Message -replace "`r`n", " ")"
                        $EventReport += ""
                    }
                } else {
                    $EventReport += "No recent Critical/Error logs found."
                    $EventReport += ""
                }
            } catch {
                $EventReport += "Unable to query $logName log or no entries matching filter."
                $EventReport += ""
            }
        }

        $EventReport | Out-File -FilePath $LogPath -Encoding utf8
        Write-Host " [OK] Event logs summary saved to $LogPath" -ForegroundColor Green
        Write-Log "Event Logs gathered successfully."
    } catch {
        Write-Host " [!] Error gathering Event Logs: $_" -ForegroundColor Red
        Write-Log "Error gathering Event Logs: $_" "ERROR"
    }
}

function Get-ServicesAndProcesses {
    Write-Host "`n[+] Gathering Services & Processes Information..." -ForegroundColor Cyan
    Write-Log "Starting Services & Processes collection..."

    $SvcPath = Join-Path $WorkDir "Services.txt"
    $ProcPath = Join-Path $WorkDir "TopProcesses.txt"

    try {
        # Stopped Auto-start Services & Critical Services
        $SvcReport = @()
        $SvcReport += "--- STOPPED AUTOMATIC SERVICES ---"
        $StoppedAuto = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' }
        foreach ($s in $StoppedAuto) {
            $SvcReport += "Service: $($s.Name) ($($s.DisplayName)) | State: $($s.State)"
        }
        $SvcReport += ""
        $SvcReport += "--- ALL SERVICES SUMMARY ---"
        $SvcReport += (Get-Service | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize | Out-String)
        $SvcReport | Out-File -FilePath $SvcPath -Encoding utf8

        # Top Processes by CPU and Memory
        $ProcReport = @()
        $ProcReport += "--- TOP 15 PROCESSES BY MEMORY USAGE (WORKING SET) ---"
        $ProcReport += (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Id, ProcessName, @{Name="WorkingSet(MB)";Expression={[math]::Round($_.WorkingSet64/1MB, 2)}}, CPU | Format-Table -AutoSize | Out-String)
        $ProcReport += ""
        $ProcReport += "--- TOP 15 PROCESSES BY CPU TIME ---"
        $ProcReport += (Get-Process | Where-Object { $_.CPU -ne $null } | Sort-Object CPU -Descending | Select-Object -First 15 Id, ProcessName, @{Name="CPU(s)";Expression={[math]::Round($_.CPU, 2)}}, @{Name="WorkingSet(MB)";Expression={[math]::Round($_.WorkingSet64/1MB, 2)}} | Format-Table -AutoSize | Out-String)
        $ProcReport | Out-File -FilePath $ProcPath -Encoding utf8

        Write-Host " [OK] Services & Top Processes saved to $WorkDir" -ForegroundColor Green
        Write-Log "Services & Processes collected successfully."
    } catch {
        Write-Host " [!] Error gathering Services & Processes: $_" -ForegroundColor Red
        Write-Log "Error gathering Services & Processes: $_" "ERROR"
    }
}

function Get-FirewallStatus {
    Write-Host "`n[+] Checking Windows Firewall Status..." -ForegroundColor Cyan
    Write-Log "Starting Firewall Status check..."

    $FwPath = Join-Path $WorkDir "FirewallStatus.txt"

    try {
        $FwReport = @()
        $FwReport += "=========================================="
        $FwReport += "         WINDOWS FIREWALL STATUS          "
        $FwReport += "=========================================="
        $FwReport += ""

        # Profile Status
        $Profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        if ($Profiles) {
            foreach ($p in $Profiles) {
                $FwReport += "Profile: $($p.Name)"
                $FwReport += "  Enabled: $($p.Enabled)"
                $FwReport += "  DefaultInboundAction: $($p.DefaultInboundAction)"
                $FwReport += "  DefaultOutboundAction: $($p.DefaultOutboundAction)"
                $FwReport += ""
            }
        } else {
            $FwReport += (netsh advfirewall show allprofiles | Out-String)
        }

        # Enabled Inbound Firewall Rules Summary
        $FwReport += "--- ENABLED INBOUND RULES SUMMARY ---"
        $EnabledRules = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Action, Profile
        $FwReport += ($EnabledRules | Format-Table -AutoSize | Out-String)

        $FwReport | Out-File -FilePath $FwPath -Encoding utf8
        Write-Host " [OK] Firewall status report saved to $FwPath" -ForegroundColor Green
        Write-Log "Firewall Status checked successfully."
    } catch {
        Write-Host " [!] Error checking Firewall Status: $_" -ForegroundColor Red
        Write-Log "Error checking Firewall Status: $_" "ERROR"
    }
}

function Get-WindowsUpdateHistory {
    Write-Host "`n[+] Gathering Windows Update History..." -ForegroundColor Cyan
    Write-Log "Starting Windows Update History collection..."

    $WuPath = Join-Path $WorkDir "WindowsUpdateHistory.txt"

    try {
        $WuReport = @()
        $WuReport += "=========================================="
        $WuReport += "        WINDOWS UPDATE HISTORY            "
        $WuReport += "=========================================="
        $WuReport += ""

        # Installed Hotfixes via WMI / Get-HotFix
        $Hotfixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
        if ($Hotfixes) {
            foreach ($hf in $Hotfixes) {
                $WuReport += "KB Article: $($hf.HotFixID) | Description: $($hf.Description) | InstalledOn: $($hf.InstalledOn) | InstalledBy: $($hf.InstalledBy)"
            }
        } else {
            $WuReport += "No hotfix records returned by Get-HotFix."
        }

        $WuReport | Out-File -FilePath $WuPath -Encoding utf8
        Write-Host " [OK] Windows update history saved to $WuPath" -ForegroundColor Green
        Write-Log "Windows Update History collected successfully."
    } catch {
        Write-Host " [!] Error gathering Windows Update History: $_" -ForegroundColor Red
        Write-Log "Error gathering Windows Update History: $_" "ERROR"
    }
}

function Get-SecurityDiagnostics {
    Write-Host "`n[+] Checking Security Diagnostics (Defender, BitLocker, TPM)..." -ForegroundColor Cyan
    Write-Log "Starting Security Diagnostics check..."

    $SecPath = Join-Path $WorkDir "SecurityDiagnostics.txt"

    try {
        $SecReport = @()
        $SecReport += "=========================================="
        $SecReport += "           SECURITY DIAGNOSTICS           "
        $SecReport += "=========================================="
        $SecReport += ""

        # Windows Defender Status
        $SecReport += "--- WINDOWS DEFENDER STATUS ---"
        try {
            $MpStatus = Get-MpComputerStatus -ErrorAction Stop
            $SecReport += "Antivirus Enabled: $($MpStatus.AntivirusEnabled)"
            $SecReport += "Real Time Protection Enabled: $($MpStatus.RealTimeProtectionEnabled)"
            $SecReport += "Antivirus Signature Age (Days): $($MpStatus.AntivirusSignatureAge)"
            $SecReport += "Antivirus Signature Version: $($MpStatus.AVSignatureVersion)"
            $SecReport += "Quick Scan Age (Days): $($MpStatus.QuickScanAge)"
            $SecReport += "Full Scan Age (Days): $($MpStatus.FullScanAge)"
        } catch {
            $SecReport += "Unable to query Get-MpComputerStatus or third-party AV active."
        }
        $SecReport += ""

        # BitLocker Drive Encryption
        $SecReport += "--- BITLOCKER ENCRYPTION STATUS ---"
        try {
            $BitLockerVols = Get-BitLockerVolume -ErrorAction Stop
            foreach ($vol in $BitLockerVols) {
                $SecReport += "Mount Point: $($vol.MountPoint) | Protection Status: $($vol.ProtectionStatus) | Encryption Percentage: $($vol.EncryptionPercentage)%"
                $SecReport += "  Volume Type: $($vol.VolumeType) | Encryption Method: $($vol.EncryptionMethod)"
            }
        } catch {
            $SecReport += "BitLocker status unavailable or command not supported on this OS edition."
        }
        $SecReport += ""

        # TPM (Trusted Platform Module) Status
        $SecReport += "--- TPM HEALTH STATUS ---"
        try {
            $Tpm = Get-Tpm -ErrorAction Stop
            $SecReport += "TPM Present: $($Tpm.TpmPresent)"
            $SecReport += "TPM Ready: $($Tpm.TpmReady)"
            $SecReport += "TPM Enabled: $($Tpm.TpmEnabled)"
            $SecReport += "TPM Activated: $($Tpm.TpmActivated)"
            $SecReport += "Manufacturer Id: $($Tpm.ManufacturerId)"
        } catch {
            $SecReport += "TPM information unavailable or not detected."
        }

        $SecReport | Out-File -FilePath $SecPath -Encoding utf8
        Write-Host " [OK] Security diagnostics report saved to $SecPath" -ForegroundColor Green
        Write-Log "Security Diagnostics checked successfully."
    } catch {
        Write-Host " [!] Error checking Security Diagnostics: $_" -ForegroundColor Red
        Write-Log "Error checking Security Diagnostics: $_" "ERROR"
    }
}

function Get-SmbDiagnostics {
    Write-Host "`n[+] Auditing SMB Network Shares & Security Protocol..." -ForegroundColor Cyan
    Write-Log "Starting SMB Diagnostics audit..."

    $SmbPath = Join-Path $WorkDir "SmbDiagnostics.txt"

    try {
        $SmbReport = @()
        $SmbReport += "=========================================="
        $SmbReport += "    SMB SHARES & PROTOCOL SECURITY AUDIT  "
        $SmbReport += "=========================================="
        $SmbReport += ""

        # Active Network Shares
        $SmbReport += "--- ACTIVE NETWORK SHARES ---"
        try {
            $Shares = Get-SmbShare -ErrorAction SilentlyContinue
            if ($Shares) {
                foreach ($share in $Shares) {
                    $SmbReport += "Name: $($share.Name) | Path: $($share.Path) | Description: $($share.Description) | ScopeName: $($share.ScopeName)"
                }
            } else {
                $WmiShares = Get-CimInstance Win32_Share
                foreach ($ws in $WmiShares) {
                    $SmbReport += "Name: $($ws.Name) | Path: $($ws.Path) | Description: $($ws.Description)"
                }
            }
        } catch {
            $SmbReport += "Unable to query SMB shares."
        }
        $SmbReport += ""

        # Active SMB Sessions
        $SmbReport += "--- ACTIVE SMB SESSIONS ---"
        try {
            $Sessions = Get-SmbSession -ErrorAction SilentlyContinue
            if ($Sessions) {
                foreach ($sess in $Sessions) {
                    $SmbReport += "ClientIP: $($sess.ClientComputerName) | User: $($sess.ClientUserName) | NumOpens: $($sess.NumOpens)"
                }
            } else {
                $SmbReport += "No active inbound SMB sessions."
            }
        } catch {
            $SmbReport += "Unable to query SMB sessions."
        }
        $SmbReport += ""

        # SMBv1 Security Check
        $SmbReport += "--- SMBv1 PROTOCOL STATUS (SECURITY CHECK) ---"
        try {
            $Smb1Config = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
            if ($Smb1Config) {
                $Smb1Enabled = $Smb1Config.EnableSMB1Protocol
                $SmbReport += "SMBv1 Protocol Enabled: $Smb1Enabled"
                if ($Smb1Enabled) {
                    $SmbReport += " [!] WARNING: SMBv1 is enabled on this system. It is considered insecure and vulnerable to WannaCry/EternalBlue."
                } else {
                    $SmbReport += " [OK] SMBv1 is disabled (Secure)."
                }
            } else {
                $RegSmb1 = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -ErrorAction SilentlyContinue).SMB1
                if ($RegSmb1 -eq 0) {
                    $SmbReport += " [OK] SMBv1 is disabled via Registry."
                } else {
                    $SmbReport += "SMBv1 registry state: $RegSmb1"
                }
            }
        } catch {
            $SmbReport += "Unable to inspect SMBv1 protocol configuration."
        }

        $SmbReport | Out-File -FilePath $SmbPath -Encoding utf8
        Write-Host " [OK] SMB diagnostics saved to $SmbPath" -ForegroundColor Green
        Write-Log "SMB diagnostics completed successfully."
    } catch {
        Write-Host " [!] Error checking SMB Diagnostics: $_" -ForegroundColor Red
        Write-Log "Error checking SMB Diagnostics: $_" "ERROR"
    }
}

function Get-StartupAndAccountInfo {
    Write-Host "`n[+] Collecting Startup Apps & User Account Info..." -ForegroundColor Cyan
    Write-Log "Starting Startup Apps & User Account Info collection..."

    $StartAccPath = Join-Path $WorkDir "StartupAndAccountInfo.txt"

    try {
        $Report = @()
        $Report += "=========================================="
        $Report += "     STARTUP APPS & USER ACCOUNTS INFO    "
        $Report += "=========================================="
        $Report += ""

        # Local User Accounts
        $Report += "--- LOCAL USER ACCOUNTS ---"
        try {
            $Users = Get-LocalUser -ErrorAction SilentlyContinue
            if ($Users) {
                foreach ($u in $Users) {
                    $Report += "Username: $($u.Name) | Enabled: $($u.Enabled) | LastLogon: $($u.LastLogon) | PasswordRequired: $($u.PasswordRequired)"
                }
            } else {
                $Report += (Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" | Select-Object Name, Disabled, PasswordRequired | Format-Table -AutoSize | Out-String)
            }
        } catch {
            $Report += "Unable to list local users."
        }
        $Report += ""

        # Local Administrators Group Members
        $Report += "--- LOCAL ADMINS GROUP MEMBERS ---"
        try {
            $Admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
            if ($Admins) {
                foreach ($a in $Admins) {
                    $Report += "Member: $($a.Name) | ObjectClass: $($a.ObjectClass) | PrincipalSource: $($a.PrincipalSource)"
                }
            } else {
                $Report += "Unable to query local Administrators group."
            }
        } catch {
            $Report += "Unable to query local Administrators group."
        }
        $Report += ""

        # Startup Applications (Registry + Startup Folder)
        $Report += "--- STARTUP APPLICATIONS (REGISTRY & CIM) ---"
        try {
            $CimStartup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
            if ($CimStartup) {
                foreach ($s in $CimStartup) {
                    $Report += "Name: $($s.Name) | Command: $($s.Command) | Location: $($s.Location) | User: $($s.User)"
                }
            } else {
                $Report += "No startup items found via Win32_StartupCommand."
            }
        } catch {
            $Report += "Unable to query startup commands."
        }

        $Report | Out-File -FilePath $StartAccPath -Encoding utf8
        Write-Host " [OK] Startup apps & user account info saved to $StartAccPath" -ForegroundColor Green
        Write-Log "Startup Apps & User Account Info collected successfully."
    } catch {
        Write-Host " [!] Error collecting Startup & Account Info: $_" -ForegroundColor Red
        Write-Log "Error collecting Startup & Account Info: $_" "ERROR"
    }
}

# SECTION 3: REPAIR, MAINTENANCE & UTILITY FUNCTIONS
# ==============================================================================

function Invoke-WindowsRepair {
    Write-Host "`n[+] Executing Windows Repair (DISM & SFC Scan)..." -ForegroundColor Yellow
    Write-Log "Starting Windows Repair routines (DISM & SFC)..."

    $RepairLog = Join-Path $WorkDir "WindowsRepair.txt"

    try {
        Write-Host " [1/2] Running DISM /Online /Cleanup-Image /RestoreHealth..." -ForegroundColor Cyan
        Write-Log "Executing DISM RestoreHealth..."
        $DismResult = DISM.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
        $DismResult | Out-File -FilePath $RepairLog -Encoding utf8

        Write-Host " [2/2] Running System File Checker (sfc /scannow)..." -ForegroundColor Cyan
        Write-Log "Executing SFC /scannow..."
        $SfcResult = sfc.exe /scannow 2>&1 | Out-String
        $SfcResult | Out-File -FilePath $RepairLog -Append -Encoding utf8

        Write-Host " [OK] DISM & SFC Scans completed. Results appended to $RepairLog" -ForegroundColor Green
        Write-Log "Windows Repair routines completed successfully."
    } catch {
        Write-Host " [!] Error during Windows Repair execution: $_" -ForegroundColor Red
        Write-Log "Error during Windows Repair execution: $_" "ERROR"
    }
}

function Invoke-CHKDSKScan {
    Write-Host "`n[+] Running Read-Only CHKDSK Scan..." -ForegroundColor Yellow
    Write-Log "Starting Read-Only CHKDSK Scan..."

    $ChkdskLog = Join-Path $WorkDir "CHKDSKScan.txt"

    try {
        Write-Host " Scanning C: volume in read-only mode..." -ForegroundColor Cyan
        $ChkdskOutput = chkdsk.exe C: 2>&1 | Out-String
        $ChkdskOutput | Out-File -FilePath $ChkdskLog -Encoding utf8

        Write-Host " [OK] Read-only CHKDSK scan completed. Report saved to $ChkdskLog" -ForegroundColor Green
        Write-Log "CHKDSK scan completed successfully."
    } catch {
        Write-Host " [!] Error running CHKDSK scan: $_" -ForegroundColor Red
        Write-Log "Error running CHKDSK scan: $_" "ERROR"
    }
}

function Get-BatteryReport {
    Write-Host "`n[+] Generating Laptop Battery Health Report..." -ForegroundColor Cyan
    Write-Log "Starting Battery Report generation..."

    $BatteryHtml = Join-Path $WorkDir "BatteryReport.html"
    $BatteryTxt = Join-Path $WorkDir "BatteryReport.txt"

    try {
        powercfg.exe /batteryreport /output $BatteryHtml | Out-Null

        if (Test-Path $BatteryHtml) {
            Write-Host " [OK] Battery HTML report saved to $BatteryHtml" -ForegroundColor Green
            Write-Log "Battery HTML report generated at $BatteryHtml."

            # Attempt capacity extraction via WMI if available
            try {
                $BatStats = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
                if ($BatStats) {
                    $BatText = "Battery Name: $($BatStats.Name)`n"
                    $BatText += "Status: $($BatStats.Status)`n"
                    $BatText += "Estimated Charge: $($BatStats.EstimatedChargeRemaining)%`n"
                    $BatText | Out-File -FilePath $BatteryTxt -Encoding utf8
                }
            } catch {}
        } else {
            Write-Host " [!] Battery report generation not supported or system has no battery." -ForegroundColor Yellow
            Write-Log "Battery report not supported or battery not present." "WARNING"
        }
    } catch {
        Write-Host " [!] Error generating battery report: $_" -ForegroundColor Red
        Write-Log "Error generating battery report: $_" "ERROR"
    }
}

function Invoke-MaintenanceUtilities {
    param([string]$Action)

    switch ($Action) {
        "FlushDNS" {
            Write-Host "`n[+] Flushing DNS Resolver Cache..." -ForegroundColor Cyan
            Write-Log "Flushing DNS Cache..."
            ipconfig /flushdns | Out-Null
            Write-Host " [OK] DNS Cache successfully flushed." -ForegroundColor Green
        }
        "ReleaseRenewIP" {
            Write-Host "`n[+] Releasing and Renewing IP Address..." -ForegroundColor Cyan
            Write-Log "Releasing and Renewing IP Address..."
            ipconfig /release | Out-Null
            ipconfig /renew | Out-Null
            Write-Host " [OK] IP Address lease successfully released and renewed." -ForegroundColor Green
        }
        "ResetWinsock" {
            Write-Host "`n[+] Resetting Winsock & IP Stack..." -ForegroundColor Cyan
            Write-Log "Resetting Winsock catalog..."
            netsh winsock reset | Out-Null
            netsh int ip reset | Out-Null
            Write-Host " [OK] Winsock catalog reset. System restart recommended." -ForegroundColor Green
        }
        "ClearTemp" {
            Write-Host "`n[+] Clearing Temporary Files & Recycle Bin..." -ForegroundColor Cyan
            Write-Log "Clearing Temp files and Recycle Bin..."
            $TempFolders = @($env:TEMP, "$env:SystemRoot\Temp", "$env:ALLUSERSPROFILE\Microsoft\Windows\WER")
            foreach ($folder in $TempFolders) {
                if (Test-Path $folder) {
                    Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            try {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            } catch {}
            Write-Host " [OK] Temporary files, error reports, and Recycle Bin cleared." -ForegroundColor Green
        }
        "PurgePrintQueue" {
            Write-Host "`n[+] Purging Print Queue & Restarting Spooler..." -ForegroundColor Cyan
            Write-Log "Purging Print Queue..."
            Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
            $SpoolDir = "$env:SystemRoot\System32\spool\PRINTERS"
            if (Test-Path $SpoolDir) {
                Get-ChildItem -Path $SpoolDir -Recurse -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
            Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
            Write-Host " [OK] Print queue purged and Spooler service restarted." -ForegroundColor Green
        }
        "RestartUpdateServices" {
            Write-Host "`n[+] Restarting Windows Update Services..." -ForegroundColor Cyan
            Write-Log "Restarting Windows Update services..."
            $WuServices = @("wuauserv", "bits", "cryptsvc")
            foreach ($svc in $WuServices) {
                Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
            }
            Write-Host " [OK] Windows Update services (wuauserv, bits, cryptsvc) restarted." -ForegroundColor Green
        }
        "CreateRestorePoint" {
            Write-Host "`n[+] Creating System Restore Point..." -ForegroundColor Cyan
            Write-Log "Creating System Restore Point..."
            try {
                Checkpoint-Computer -Description "SysAdmin_Toolkit_RestorePoint" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                Write-Host " [OK] System Restore Point created successfully." -ForegroundColor Green
                Write-Log "System Restore Point created successfully."
            } catch {
                Write-Host " [!] Failed to create System Restore Point: $_" -ForegroundColor Red
                Write-Log "Failed to create System Restore Point: $_" "ERROR"
            }
        }
        "UpdateDefenderSignatures" {
            Write-Host "`n[+] Updating Windows Defender Definitions..." -ForegroundColor Cyan
            Write-Log "Updating Windows Defender Signatures..."
            try {
                Update-MpSignature -ErrorAction Stop
                Write-Host " [OK] Windows Defender signatures updated successfully." -ForegroundColor Green
                Write-Log "Windows Defender signatures updated successfully."
            } catch {
                Write-Host " [!] Failed to update Defender signatures: $_" -ForegroundColor Red
                Write-Log "Failed to update Defender signatures: $_" "ERROR"
            }
        }
        "ResetUpdateCache" {
            Write-Host "`n[+] Resetting Windows Update Cache (SoftwareDistribution)..." -ForegroundColor Cyan
            Write-Log "Resetting Windows Update Cache..."
            try {
                Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "cryptsvc" -Force -ErrorAction SilentlyContinue

                $SoftDist = "$env:SystemRoot\SoftwareDistribution"
                $CatRoot2 = "$env:SystemRoot\System32\catroot2"

                if (Test-Path $SoftDist) {
                    Rename-Item -Path $SoftDist -NewName "SoftwareDistribution.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction SilentlyContinue
                }
                if (Test-Path $CatRoot2) {
                    Rename-Item -Path $CatRoot2 -NewName "catroot2.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction SilentlyContinue
                }

                Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
                Start-Service -Name "bits" -ErrorAction SilentlyContinue
                Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue

                Write-Host " [OK] Windows Update cache reset successfully." -ForegroundColor Green
                Write-Log "Windows Update cache reset successfully."
            } catch {
                Write-Host " [!] Error resetting Windows Update cache: $_" -ForegroundColor Red
                Write-Log "Error resetting Windows Update cache: $_" "ERROR"
            }
        }
    }
}

function Invoke-FullDiagnosticMode {
    Write-Host "`n=========================================================================" -ForegroundColor Magenta
    Write-Host "           STARTING FULL DIAGNOSTIC MODE (ALL CHECKS)                    " -ForegroundColor Magenta
    Write-Host "=========================================================================" -ForegroundColor Magenta
    Write-Log "Starting Full Diagnostic Mode..."

    Get-SystemInformation
    Get-HardwareInformation
    Get-DiskHealth
    Get-InstalledSoftware
    Get-DriverDiagnostics
    Get-NetworkDiagnostics
    Get-NetworkExtendedInfo
    Get-EventLogs
    Get-ServicesAndProcesses
    Get-FirewallStatus
    Get-WindowsUpdateHistory
    Get-SecurityDiagnostics
    Get-SmbDiagnostics
    Get-StartupAndAccountInfo
    Get-BatteryReport

    Write-Host "`n=========================================================================" -ForegroundColor Green
    Write-Host "  FULL DIAGNOSTICS COMPLETED! All reports saved in:" -ForegroundColor Green
    Write-Host "  $WorkDir" -ForegroundColor Yellow
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Log "Full Diagnostic Mode finished."
}

# ==============================================================================
# SECTION 4: INTERACTIVE MENU, REPORT LAUNCHER & TASK SCHEDULER
# ==============================================================================

function Open-ReportFolder {
    Write-Host "`n[+] Opening Report Folder: $WorkDir" -ForegroundColor Cyan
    Write-Log "Opening report folder..."
    try {
        Invoke-Item $WorkDir
    } catch {
        Write-Host " [!] Report Folder Path: $WorkDir" -ForegroundColor Yellow
    }
}

function Add-ScheduledTaskHelper {
    Write-Host "`n[+] Scheduling Automated Daily Toolkit Checks..." -ForegroundColor Cyan
    Write-Log "Setting up scheduled task for SysAdmin Toolkit..."

    $TaskName = "SysAdmin_Toolkit_Daily_Diagnostics"
    $ScriptPath = $MyInvocation.MyCommand.Definition

    if (-not $ScriptPath) {
        $ScriptPath = Join-Path $PSScriptRoot "SysAdmin_Toolkit.ps1"
    }

    try {
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -AutoRun"
        $Trigger = New-ScheduledTaskTrigger -Daily -At "08:00AM"
        $Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
        Write-Host " [OK] Scheduled Task '$TaskName' created successfully to run daily at 8:00 AM." -ForegroundColor Green
        Write-Log "Scheduled Task '$TaskName' created successfully."
    } catch {
        Write-Host " [!] Error creating Scheduled Task: $_" -ForegroundColor Red
        Write-Log "Error creating Scheduled Task: $_" "ERROR"
    }
}

function Show-MainUI {
    param([switch]$AutoRun)

    if ($AutoRun) {
        Invoke-FullDiagnosticMode
        return
    }

    do {
        Clear-Host
        Write-Host "========================================================================" -ForegroundColor Blue
        Write-Host "                        SYSADMIN TOOLKIT                                " -ForegroundColor Cyan
        Write-Host "             Diagnose. Repair. Keep Windows Running.                    " -ForegroundColor Yellow
        Write-Host "========================================================================" -ForegroundColor Blue
        Write-Host " Report Folder : $WorkDir" -ForegroundColor Gray
        Write-Host " Admin Status  : $(if ($IsAdmin) { 'Elevated (Administrator)' } else { 'Standard User' })" -ForegroundColor Gray
        Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " [1]  System Information       (OS, HW, Manufacturer, Serial, Uptime)" -ForegroundColor White
        Write-Host " [2]  Hardware Information     (CPU, RAM, Disks, GPU, Motherboard)" -ForegroundColor White
        Write-Host " [3]  Disk Health & Storage    (Volume Space, SMART Physical Disk Status)" -ForegroundColor White
        Write-Host " [4]  Network Diagnostics      (IP Config, Ping, DNS, Routes, Listening Ports)" -ForegroundColor White
        Write-Host " [5]  Event Logs               (System, App, Security Critical/Error Logs)" -ForegroundColor White
        Write-Host " [6]  Services & Processes     (Services Status, Top CPU/RAM Processes)" -ForegroundColor White
        Write-Host " [7]  Installed Software       (Export full software list to CSV)" -ForegroundColor White
        Write-Host " [8]  Windows Repair           (DISM RestoreHealth + SFC Scan)" -ForegroundColor White
        Write-Host " [9]  CHKDSK Scan              (Read-only volume health check)" -ForegroundColor White
        Write-Host " [10] Firewall Status          (Firewall Profiles & Rules Summary)" -ForegroundColor White
        Write-Host " [11] Windows Update History   (Hotfix list & installed update history)" -ForegroundColor White
        Write-Host " [12] Security Diagnostics     (Windows Defender, BitLocker, TPM status)" -ForegroundColor White
        Write-Host " [13] Startup & Accounts Info  (Local Users, Admins, Startup applications)" -ForegroundColor White
        Write-Host " [14] Battery Report           (Laptop battery health HTML report)" -ForegroundColor White
        Write-Host " [15] Driver Diagnostics       (PnP Error audit & missing driver check)" -ForegroundColor White
        Write-Host " [16] Extended Network Check   (Public IP, Hosts file security, WAN latency)" -ForegroundColor White
        Write-Host " [17] SMB Shares & Security    (Network shares, sessions & SMBv1 check)" -ForegroundColor White
        Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " [18] FULL DIAGNOSTIC MODE     (Run all diagnostic checks at once)" -ForegroundColor Yellow
        Write-Host " [19] Quick Utilities          (Flush DNS, Reset Winsock, Clear Temp, WU Cache, Defender Update, Restore Point)" -ForegroundColor Green
        Write-Host " [20] Schedule Daily Task      (Automate script via Task Scheduler)" -ForegroundColor Green
        Write-Host " [21] Open Report Folder       (Quick access to generated reports)" -ForegroundColor Green
        Write-Host " [0]  Exit Toolkit" -ForegroundColor Red
        Write-Host "========================================================================" -ForegroundColor Blue

        $Selection = Read-Host "Select an option [0-21]"

        switch ($Selection) {
            "1"  { Get-SystemInformation; Pause }
            "2"  { Get-HardwareInformation; Pause }
            "3"  { Get-DiskHealth; Pause }
            "4"  { Get-NetworkDiagnostics; Pause }
            "5"  { Get-EventLogs; Pause }
            "6"  { Get-ServicesAndProcesses; Pause }
            "7"  { Get-InstalledSoftware; Pause }
            "8"  { Invoke-WindowsRepair; Pause }
            "9"  { Invoke-CHKDSKScan; Pause }
            "10" { Get-FirewallStatus; Pause }
            "11" { Get-WindowsUpdateHistory; Pause }
            "12" { Get-SecurityDiagnostics; Pause }
            "13" { Get-StartupAndAccountInfo; Pause }
            "14" { Get-BatteryReport; Pause }
            "15" { Get-DriverDiagnostics; Pause }
            "16" { Get-NetworkExtendedInfo; Pause }
            "17" { Get-SmbDiagnostics; Pause }
            "18" { Invoke-FullDiagnosticMode; Pause }
            "19" {
                Write-Host "`nSelect Utility Action:" -ForegroundColor Cyan
                Write-Host " [A] Flush DNS Cache"
                Write-Host " [B] Release & Renew IP Address"
                Write-Host " [C] Reset Winsock & IP Stack"
                Write-Host " [D] Clear Temporary Files & Recycle Bin"
                Write-Host " [E] Purge Print Queue & Restart Spooler"
                Write-Host " [F] Restart Windows Update Services"
                Write-Host " [G] Create System Restore Point"
                Write-Host " [H] Update Windows Defender Signatures"
                Write-Host " [I] Reset Windows Update Cache (SoftwareDistribution)"
                $SubChoice = Read-Host "Choice"
                switch ($SubChoice.ToUpper()) {
                    "A" { Invoke-MaintenanceUtilities -Action "FlushDNS" }
                    "B" { Invoke-MaintenanceUtilities -Action "ReleaseRenewIP" }
                    "C" { Invoke-MaintenanceUtilities -Action "ResetWinsock" }
                    "D" { Invoke-MaintenanceUtilities -Action "ClearTemp" }
                    "E" { Invoke-MaintenanceUtilities -Action "PurgePrintQueue" }
                    "F" { Invoke-MaintenanceUtilities -Action "RestartUpdateServices" }
                    "G" { Invoke-MaintenanceUtilities -Action "CreateRestorePoint" }
                    "H" { Invoke-MaintenanceUtilities -Action "UpdateDefenderSignatures" }
                    "I" { Invoke-MaintenanceUtilities -Action "ResetUpdateCache" }
                }
                Pause
            }
            "20" { Add-ScheduledTaskHelper; Pause }
            "21" { Open-ReportFolder; Pause }
            "0"  { Write-Host "Exiting SysAdmin Toolkit. Goodbye!" -ForegroundColor Cyan; break }
            default { Write-Host "Invalid selection. Please try again." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($Selection -ne "0")
}

# Main Script Entrypoint
if ($args -contains "-AutoRun") {
    Show-MainUI -AutoRun
} else {
    Show-MainUI
}
