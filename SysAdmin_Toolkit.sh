#!/usr/bin/env bash
# ==============================================================================
# SYSADMIN TOOLKIT - LINUX IT TECHNICIAN TOOLKIT
# Tagline: Diagnose. Repair. Keep Linux Running.
# Version: 1.1.0
# Description: All-in-one diagnostic, repair, and maintenance toolkit for Linux systems.
#              Collects system info, hardware details, scans disks, gathers logs,
#              performs package/system repairs, audits drivers, SMB/NFS shares, and more.
# ==============================================================================

# Check for root/sudo privileges
IS_ROOT=0
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=1
fi

if [ "$IS_ROOT" -eq 0 ]; then
    echo "WARNING: SysAdmin Toolkit is running without root (sudo) privileges."
    echo "Many diagnostic and repair features (smartctl, journalctl, firewall, package repairs) require root access."
    echo "You can re-run with: sudo ./SysAdmin_Toolkit.sh"
    echo ""
fi

# Set bash options
set -o pipefail 2>/dev/null || true

# Setup Output Folder and Logging
DATE_STAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DESKTOP_DIR="$HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ]; then
    DESKTOP_DIR="$HOME"
fi
WORK_DIR="$DESKTOP_DIR/IT_Toolkit_Report_$DATE_STAMP"

mkdir -p "$WORK_DIR"
LOG_FILE="$WORK_DIR/Technician_Log.txt"

write_log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

write_log "SysAdmin Toolkit initialized. Output directory: $WORK_DIR"

pause_prompt() {
    echo ""
    read -rp "Press [Enter] key to continue..."
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ==============================================================================
# SECTION 1: CORE DIAGNOSTIC FUNCTIONS
# ==============================================================================

get_system_information() {
    echo -e "\n[+] Collecting System Information..."
    write_log "Starting System Information collection..."

    local sys_info_path="$WORK_DIR/SystemInfo.txt"
    local comp_info_path="$WORK_DIR/ComputerInfo.txt"
    local os_info_path="$WORK_DIR/OperatingSystem.txt"

    {
        echo "=========================================="
        echo "           SYSTEM SUMMARY INFO            "
        echo "=========================================="
        echo "Hostname        : $(hostname)"
        echo "Kernel Version  : $(uname -r)"
        echo "Architecture    : $(uname -m)"
        echo "Uptime          : $(uptime -p 2>/dev/null || uptime)"
        echo "Current User    : $(whoami)"
        echo "Date & Time     : $(date)"
    } > "$sys_info_path"

    {
        echo "=========================================="
        echo "           HARDWARE / SYSTEM INFO         "
        echo "=========================================="
        if has_cmd dmidecode && [ "$IS_ROOT" -eq 1 ]; then
            dmidecode -t system 2>/dev/null || echo "dmidecode failed."
        else
            if [ -f /sys/class/dmi/id/product_name ]; then
                echo "Product Name    : $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
                echo "Product Vendor  : $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
                echo "Serial Number   : $(cat /sys/class/dmi/id/product_serial 2>/dev/null)"
            else
                echo "DMI info not accessible (run as root or dmidecode unavailable)."
            fi
        fi
    } > "$comp_info_path"

    {
        echo "=========================================="
        echo "        OPERATING SYSTEM DETAILS          "
        echo "=========================================="
        if [ -f /etc/os-release ]; then
            cat /etc/os-release
        elif has_cmd lsb_release; then
            lsb_release -a 2>/dev/null
        else
            uname -a
        fi
        echo ""
        echo "--- HOSTNAME CONTROL INFO ---"
        if has_cmd hostnamectl; then
            hostnamectl 2>/dev/null
        fi
    } > "$os_info_path"

    echo " [OK] System information successfully saved to $WORK_DIR"
    write_log "System Information collected successfully."
}

get_hardware_information() {
    echo -e "\n[+] Collecting Hardware Information..."
    write_log "Starting Hardware Information collection..."

    local hw_info_path="$WORK_DIR/HardwareInfo.txt"

    {
        echo "=========================================="
        echo "           HARDWARE INFORMATION           "
        echo "=========================================="
        echo ""

        echo "--- PROCESSOR (CPU) ---"
        if has_cmd lscpu; then
            lscpu
        else
            grep -E 'model name|cpu MHz|cache size|cpu cores' /proc/cpuinfo | head -20
        fi
        echo ""

        echo "--- PHYSICAL MEMORY (RAM) ---"
        if has_cmd free; then
            free -h
        fi
        echo ""
        if has_cmd dmidecode && [ "$IS_ROOT" -eq 1 ]; then
            echo "Memory Devices (DMI):"
            dmidecode -t memory 2>/dev/null | grep -E "Size:|Speed:|Manufacturer|Type:|Locator:" | grep -v "No Module Installed" || true
        fi
        echo ""

        echo "--- MOTHERBOARD / SYSTEM BOARD ---"
        if [ -f /sys/class/dmi/id/board_name ]; then
            echo "Manufacturer : $(cat /sys/class/dmi/id/board_vendor 2>/dev/null)"
            echo "Product      : $(cat /sys/class/dmi/id/board_name 2>/dev/null)"
            echo "Version      : $(cat /sys/class/dmi/id/board_version 2>/dev/null)"
            echo "Serial Number: $(cat /sys/class/dmi/id/board_serial 2>/dev/null)"
        elif has_cmd dmidecode && [ "$IS_ROOT" -eq 1 ]; then
            dmidecode -t baseboard 2>/dev/null || echo "Baseboard query failed."
        else
            echo "Motherboard info unavailable."
        fi
        echo ""

        echo "--- GRAPHICS CONTROLLER (GPU) ---"
        if has_cmd lspci; then
            lspci -nnk | grep -iA3 "VGA\|3D\|Display"
        else
            echo "lspci command not available."
        fi
        if has_cmd nvidia-smi; then
            echo ""
            echo "--- NVIDIA GPU STATUS ---"
            nvidia-smi 2>/dev/null || true
        fi
    } > "$hw_info_path"

    echo " [OK] Hardware information saved to $hw_info_path"
    write_log "Hardware Information collected successfully."
}

get_disk_health() {
    echo -e "\n[+] Checking Disk Health & Storage..."
    write_log "Starting Disk Health & Storage check..."

    local disk_info_path="$WORK_DIR/DiskHealth.txt"

    {
        echo "=========================================="
        echo "         DISK HEALTH & STORAGE            "
        echo "=========================================="
        echo ""

        echo "--- LOGICAL VOLUMES & FILE SYSTEM USAGE ---"
        df -hT
        echo ""

        echo "--- BLOCK DEVICES LAYOUT ---"
        if has_cmd lsblk; then
            lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,MODEL,SERIAL
        fi
        echo ""

        echo "--- PHYSICAL DISKS & SMART HEALTH ---"
        if has_cmd smartctl && [ "$IS_ROOT" -eq 1 ]; then
            local drive
            for drive in /dev/sd[a-z] /dev/nvme[0-9]n1 /dev/vd[a-z]; do
                if [ -b "$drive" ]; then
                    echo "------------------------------------------"
                    echo "SMART Status for $drive:"
                    smartctl -H "$drive" 2>/dev/null || echo "Unable to query SMART status for $drive"
                fi
            done
        else
            echo " [!] smartctl (smartmontools) not installed or root privileges required for SMART checks."
        fi
    } > "$disk_info_path"

    echo " [OK] Disk health & storage report saved to $disk_info_path"
    write_log "Disk health & storage report saved successfully."
}

get_installed_software() {
    echo -e "\n[+] Collecting Installed Software List..."
    write_log "Starting Installed Software collection..."

    local csv_path="$WORK_DIR/InstalledSoftware.csv"
    local txt_path="$WORK_DIR/InstalledSoftware.txt"

    {
        echo "DisplayName,DisplayVersion,Publisher,PackageType"
        if has_cmd dpkg-query; then
            dpkg-query -W -f='${Package},${Version},Debian/Ubuntu,dpkg\n' 2>/dev/null
        fi
        if has_cmd rpm; then
            rpm -qa --qf '%{NAME},%{VERSION}-%{RELEASE},%{VENDOR},rpm\n' 2>/dev/null
        fi
        if has_cmd pacman; then
            pacman -Q --native 2>/dev/null | awk '{print $1 "," $2 ",Arch,pacman"}'
        fi
        if has_cmd snap; then
            snap list 2>/dev/null | tail -n +2 | awk '{print $1 "," $2 "," $4 ",snap"}'
        fi
        if has_cmd flatpak; then
            flatpak list --columns=name,version,origin 2>/dev/null | awk -F'\t' '{print $1 "," $2 "," $3 ",flatpak"}'
        fi
    } > "$csv_path"

    {
        echo "=========================================="
        echo "         INSTALLED SOFTWARE INVENTORY     "
        echo "=========================================="
        echo ""
        if has_cmd dpkg; then
            echo "--- DPKG / APT PACKAGES ---"
            dpkg -l 2>/dev/null | head -50
            echo "... (Full list exported to InstalledSoftware.csv)"
            echo ""
        fi
        if has_cmd rpm; then
            echo "--- RPM PACKAGES ---"
            rpm -qa 2>/dev/null | head -50
            echo "... (Full list exported to InstalledSoftware.csv)"
            echo ""
        fi
        if has_cmd pacman; then
            echo "--- PACMAN PACKAGES ---"
            pacman -Q 2>/dev/null | head -50
            echo ""
        fi
        if has_cmd snap; then
            echo "--- SNAP PACKAGES ---"
            snap list 2>/dev/null
            echo ""
        fi
        if has_cmd flatpak; then
            echo "--- FLATPAK PACKAGES ---"
            flatpak list 2>/dev/null
            echo ""
        fi
    } > "$txt_path"

    echo " [OK] Installed software list saved to CSV and TXT in $WORK_DIR"
    write_log "Installed Software list collected successfully."
}

get_driver_diagnostics() {
    echo -e "\n[+] Checking Device Drivers & Kernel Diagnostics..."
    write_log "Starting Device Driver & Kernel Diagnostics audit..."

    local driver_path="$WORK_DIR/DriverDiagnostics.txt"

    {
        echo "=========================================="
        echo "   DEVICE DRIVERS & HARDWARE DIAGNOSTICS  "
        echo "=========================================="
        echo ""

        echo "--- KERNEL WARNINGS & ERRORS (DMESG) ---"
        if has_cmd dmesg; then
            if [ "$IS_ROOT" -eq 1 ]; then
                dmesg -l err,crit,alert,emerg 2>/dev/null | tail -n 50 || dmesg 2>/dev/null | grep -iE 'error|fail|warn|missing|firmware' | tail -n 50
            else
                dmesg 2>/dev/null | grep -iE 'error|fail|warn|missing|firmware' | tail -n 50 || echo "dmesg restricted without root privileges."
            fi
        else
            echo "dmesg command not found."
        fi
        echo ""

        echo "--- MISSING FIRMWARE AUDIT ---"
        if has_cmd dmesg; then
            dmesg 2>/dev/null | grep -i 'firmware' | grep -iE 'failed|missing|error' || echo " [OK] No missing firmware errors detected in dmesg."
        fi
        echo ""

        echo "--- PCI DEVICES & KERNEL MODULES ---"
        if has_cmd lspci; then
            lspci -k
        fi
        echo ""

        echo "--- USB DEVICES ---"
        if has_cmd lsusb; then
            lsusb
        fi
    } > "$driver_path"

    echo " [OK] Driver diagnostics report saved to $driver_path"
    write_log "Driver diagnostics completed successfully."
}

# ==============================================================================
# SECTION 2: NETWORK, LOGGING, AND MONITORING FUNCTIONS
# ==============================================================================

get_network_diagnostics() {
    echo -e "\n[+] Running Network Diagnostics..."
    write_log "Starting Network Diagnostics..."

    local net_path="$WORK_DIR/NetworkDiagnostics.txt"

    {
        echo "=========================================="
        echo "           NETWORK DIAGNOSTICS            "
        echo "=========================================="
        echo ""

        echo "--- IP ADDRESSES & ADAPTER STATUS ---"
        if has_cmd ip; then
            ip addr show
        else
            ifconfig -a 2>/dev/null
        fi
        echo ""

        echo "--- DNS SERVERS CONFIGURATION ---"
        if has_cmd resolvectl; then
            resolvectl status 2>/dev/null || cat /etc/resolv.conf
        else
            cat /etc/resolv.conf
        fi
        echo ""

        echo "--- PING CONNECTIVITY TEST ---"
        local target
        for target in "1.1.1.1" "8.8.8.8" "google.com"; do
            if ping -c 2 -W 3 "$target" >/dev/null 2>&1; then
                echo "Ping $target : SUCCESS"
            else
                echo "Ping $target : FAILED"
            fi
        done
        echo ""

        echo "--- ROUTING TABLE ---"
        if has_cmd ip; then
            ip route show
        else
            netstat -rn 2>/dev/null
        fi
        echo ""

        echo "--- ARP / NEIGHBOR TABLE ---"
        if has_cmd ip; then
            ip neighbor show
        else
            arp -an 2>/dev/null
        fi
        echo ""

        echo "--- LISTENING PORTS (TCP/UDP) ---"
        if has_cmd ss; then
            ss -tulpn
        elif has_cmd netstat; then
            netstat -tulpn
        fi
    } > "$net_path"

    echo " [OK] Network diagnostics saved to $net_path"
    write_log "Network Diagnostics completed successfully."
}

get_network_extended_info() {
    echo -e "\n[+] Checking Public IP & Hosts File Security..."
    write_log "Starting Extended Network & Hosts File inspection..."

    local net_ext_path="$WORK_DIR/NetworkExtended.txt"

    {
        echo "=========================================="
        echo "   EXTENDED NETWORK & HOSTS FILE CHECK    "
        echo "=========================================="
        echo ""

        echo "--- EXTERNAL / PUBLIC IP ADDRESS ---"
        local public_ip=""
        if has_cmd curl; then
            public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me/ip 2>/dev/null)
        elif has_cmd wget; then
            public_ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null)
        fi

        if [ -n "$public_ip" ]; then
            echo "Public IP Address: $public_ip"
        else
            echo "Public IP Address: Unable to retrieve (Offline or blocked)"
        fi
        echo ""

        echo "--- HOSTS FILE AUDIT (/etc/hosts) ---"
        if [ -f /etc/hosts ]; then
            local custom_hosts
            custom_hosts=$(grep -v '^\s*#' /etc/hosts | grep -v '^\s*$' | grep -vE '127\.0\.0\.1|::1|localhost' || true)
            if [ -n "$custom_hosts" ]; then
                echo "Custom / Non-Standard Hosts Entries Found:"
                echo "$custom_hosts"
            else
                echo " [OK] /etc/hosts contains only default loopback comments/entries."
            fi
        else
            echo " [!] /etc/hosts file not found!"
        fi
        echo ""

        echo "--- WAN DOMAIN RESOLUTION & LATENCY ---"
        local domain
        for domain in "microsoft.com" "cloudflare.com" "google.com"; do
            if has_cmd host; then
                host "$domain" 2>/dev/null | head -3
            elif has_cmd nslookup; then
                nslookup "$domain" 2>/dev/null | grep -A2 "Name:"
            elif has_cmd ping; then
                ping -c 1 -W 3 "$domain" 2>/dev/null | head -2
            fi
        done
        echo ""

        echo "--- NETWORK PATH TRACE (TRACEROUTE) ---"
        local trace_target="8.8.8.8"
        if has_cmd traceroute; then
            traceroute -m 15 -n "$trace_target" 2>&1
        elif has_cmd tracepath; then
            tracepath -m 15 -n "$trace_target" 2>&1
        else
            echo "Neither traceroute nor tracepath installed."
        fi
    } > "$net_ext_path"

    echo " [OK] Extended network info saved to $net_ext_path"
    write_log "Extended network info collected successfully."
}

get_event_logs() {
    echo -e "\n[+] Gathering Recent System Event Logs..."
    write_log "Starting Event Logs gathering..."

    local log_path="$WORK_DIR/EventLogs_RecentErrors.txt"

    {
        echo "=========================================="
        echo "      RECENT EVENT LOGS (ERRORS/CRITICAL) "
        echo "=========================================="
        echo ""

        if has_cmd journalctl; then
            echo "--- SYSTEMD JOURNAL CRITICAL & ERROR LOGS ---"
            journalctl -p err..emerg -n 50 --no-pager 2>/dev/null || echo "Unable to query journalctl."
            echo ""
        fi

        echo "--- SYSTEM CRASH & COREDUMP LOGS (/var/crash & coredumpctl) ---"
        if [ -d /var/crash ]; then
            ls -la /var/crash 2>/dev/null || true
        fi
        if has_cmd coredumpctl; then
            coredumpctl list -n 10 2>/dev/null || true
        fi
        echo ""
        echo "--- RECENT SYSLOG ERRORS (/var/log) ---"
        if [ -f /var/log/syslog ]; then
            grep -iE 'error|crit|failed|fatal' /var/log/syslog | tail -n 30
        elif [ -f /var/log/messages ]; then
            grep -iE 'error|crit|failed|fatal' /var/log/messages | tail -n 30
        fi
        echo ""

        echo "--- AUTHENTICATION LOGS (/var/log/auth.log or /var/log/secure) ---"
        if [ -f /var/log/auth.log ]; then
            grep -iE 'failed|invalid|accepted' /var/log/auth.log | tail -n 30
        elif [ -f /var/log/secure ]; then
            grep -iE 'failed|invalid|accepted' /var/log/secure | tail -n 30
        fi
    } > "$log_path"

    echo " [OK] Event logs summary saved to $log_path"
    write_log "Event Logs gathered successfully."
}

get_services_and_processes() {
    echo -e "\n[+] Gathering Services & Processes Information..."
    write_log "Starting Services & Processes collection..."

    local svc_path="$WORK_DIR/Services.txt"
    local proc_path="$WORK_DIR/TopProcesses.txt"

    {
        echo "=========================================="
        echo "           SYSTEM SERVICES STATUS         "
        echo "=========================================="
        echo ""

        if has_cmd systemctl; then
            echo "--- FAILED SERVICES ---"
            systemctl list-units --type=service --state=failed --no-pager
            echo ""
            echo "--- ACTIVE SERVICES SUMMARY ---"
            systemctl list-units --type=service --state=running --no-pager | head -40
            echo "... (truncated)"
        else
            service --status-all 2>/dev/null
        fi
    } > "$svc_path"

    {
        echo "=========================================="
        echo "      TOP CPU & MEMORY CONSUMING PROCESSES"
        echo "=========================================="
        echo ""

        echo "--- TOP 15 PROCESSES BY MEMORY USAGE ---"
        ps aux --sort=-%mem | head -16
        echo ""

        echo "--- TOP 15 PROCESSES BY CPU USAGE ---"
        ps aux --sort=-%cpu | head -16
    } > "$proc_path"

    echo " [OK] Services & Top Processes saved to $WORK_DIR"
    write_log "Services & Processes collected successfully."
}

get_firewall_status() {
    echo -e "\n[+] Checking Firewall Status..."
    write_log "Starting Firewall Status check..."

    local fw_path="$WORK_DIR/FirewallStatus.txt"

    {
        echo "=========================================="
        echo "             FIREWALL STATUS              "
        echo "=========================================="
        echo ""

        if has_cmd ufw; then
            echo "--- UFW (UNCOMPLICATED FIREWALL) STATUS ---"
            if [ "$IS_ROOT" -eq 1 ]; then
                ufw status verbose
            else
                ufw status 2>/dev/null || echo "UFW check requires root."
            fi
            echo ""
        fi

        if has_cmd firewall-cmd; then
            echo "--- FIREWALLD STATUS ---"
            firewall-cmd --state 2>/dev/null
            firewall-cmd --list-all 2>/dev/null
            echo ""
        fi

        if has_cmd iptables && [ "$IS_ROOT" -eq 1 ]; then
            echo "--- IPTABLES SUMMARY ---"
            iptables -L -n -v | head -30
            echo ""
        fi

        if has_cmd nft && [ "$IS_ROOT" -eq 1 ]; then
            echo "--- NFTABLES SUMMARY ---"
            nft list ruleset 2>/dev/null | head -30
            echo ""
        fi
    } > "$fw_path"

    echo " [OK] Firewall status report saved to $fw_path"
    write_log "Firewall Status checked successfully."
}

get_package_update_history() {
    echo -e "\n[+] Gathering System & Package Update History..."
    write_log "Starting Package Update History collection..."

    local wu_path="$WORK_DIR/PackageUpdateHistory.txt"

    {
        echo "=========================================="
        echo "        PACKAGE UPDATE HISTORY            "
        echo "=========================================="
        echo ""

        if [ -f /var/log/dpkg.log ]; then
            echo "--- RECENT DPKG INSTALL/UPDATE HISTORY ---"
            grep -E 'install|upgrade' /var/log/dpkg.log | tail -n 40
            echo ""
        fi

        if [ -f /var/log/apt/history.log ]; then
            echo "--- RECENT APT TRANSACTION HISTORY ---"
            tail -n 40 /var/log/apt/history.log
            echo ""
        fi

        if has_cmd dnf; then
            echo "--- RECENT DNF TRANSACTION HISTORY ---"
            dnf history list 2>/dev/null | head -20
            echo ""
        fi

        if [ -f /var/log/pacman.log ]; then
            echo "--- RECENT PACMAN UPDATE HISTORY ---"
            grep -E 'upgraded|installed' /var/log/pacman.log | tail -n 40
            echo ""
        fi
    } > "$wu_path"

    echo " [OK] Package update history saved to $wu_path"
    write_log "Package Update History collected successfully."
}

get_security_diagnostics() {
    echo -e "\n[+] Checking Security Diagnostics (SELinux, AppArmor, LUKS, TPM)..."
    write_log "Starting Security Diagnostics check..."

    local sec_path="$WORK_DIR/SecurityDiagnostics.txt"

    {
        echo "=========================================="
        echo "           SECURITY DIAGNOSTICS           "
        echo "=========================================="
        echo ""

        echo "--- SELINUX / APPARMOR MODULE STATUS ---"
        if has_cmd sestatus; then
            sestatus
        elif has_cmd aa-status; then
            if [ "$IS_ROOT" -eq 1 ]; then
                aa-status
            else
                echo "AppArmor status requires root."
            fi
        else
            echo "Neither SELinux nor AppArmor active/installed."
        fi
        echo ""

        echo "--- DISK ENCRYPTION (LUKS / CRYPTSETUP) ---"
        if has_cmd cryptsetup && [ "$IS_ROOT" -eq 1 ]; then
            lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINT | grep -i crypt || echo "No active LUKS encrypted devices found."
        else
            echo "cryptsetup status unavailable (requires root)."
        fi
        echo ""

        echo "--- TPM (TRUSTED PLATFORM MODULE) STATUS ---"
        if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
            echo "TPM Device detected in /dev:"
            ls -l /dev/tpm* 2>/dev/null
        else
            echo "No TPM device (/dev/tpm*) detected."
        fi
        echo ""

        echo "--- ANTIVIRUS / SECURITY SOFTWARE ---"
        if has_cmd clamscan; then
            echo "ClamAV is installed."
            if [ -f /var/lib/clamav/daily.cvd ]; then
                echo "ClamAV Signatures Date: $(stat -c %y /var/lib/clamav/daily.cvd 2>/dev/null)"
            fi
        fi
        if has_cmd mdatp; then
            echo "Microsoft Defender for Endpoint (mdatp) installed:"
            mdatp health 2>/dev/null
        fi
    } > "$sec_path"

    echo " [OK] Security diagnostics report saved to $sec_path"
    write_log "Security Diagnostics checked successfully."
}

get_smb_diagnostics() {
    echo -e "\n[+] Auditing SMB / NFS Shares & Protocol Security..."
    write_log "Starting SMB Diagnostics audit..."

    local smb_path="$WORK_DIR/SmbDiagnostics.txt"

    {
        echo "=========================================="
        echo "   SMB & NETWORK SHARES SECURITY AUDIT    "
        echo "=========================================="
        echo ""

        echo "--- SAMBA / SMB SHARES (/etc/samba/smb.conf) ---"
        if [ -f /etc/samba/smb.conf ]; then
            grep -v '^\s*#' /etc/samba/smb.conf | grep -v '^\s*;' | grep -v '^\s*$'
            echo ""
            echo "--- SMB PROTOCOL MIN/MAX PROTOCOL CHECK ---"
            grep -iE 'protocol' /etc/samba/smb.conf || echo "No explicit SMB protocol restrictions found in smb.conf."
        else
            echo "No /etc/samba/smb.conf file found."
        fi
        echo ""

        echo "--- ACTIVE SMB SESSIONS (smbstatus) ---"
        if has_cmd smbstatus && [ "$IS_ROOT" -eq 1 ]; then
            smbstatus 2>/dev/null
        else
            echo "smbstatus not available or requires root."
        fi
        echo ""

        echo "--- NFS EXPORTS (/etc/exports) ---"
        if [ -f /etc/exports ]; then
            grep -v '^\s*#' /etc/exports | grep -v '^\s*$' || echo "No active NFS exports."
        fi
    } > "$smb_path"

    echo " [OK] SMB diagnostics saved to $smb_path"
    write_log "SMB diagnostics completed successfully."
}

get_startup_and_account_info() {
    echo -e "\n[+] Collecting Startup Apps & User Account Info..."
    write_log "Starting Startup Apps & User Account Info collection..."

    local start_acc_path="$WORK_DIR/StartupAndAccountInfo.txt"

    {
        echo "=========================================="
        echo "     STARTUP APPS & USER ACCOUNTS INFO    "
        echo "=========================================="
        echo ""

        echo "--- LOCAL USER ACCOUNTS (/etc/passwd) ---"
        awk -F: '$3 >= 1000 && $3 < 60000 {print "Username: " $1 " | UID: " $3 " | Shell: " $7 " | Home: " $6}' /etc/passwd
        echo ""

        echo "--- SUDO / ADMINISTRATIVE USERS ---"
        echo "Members of 'sudo' group:"
        getent group sudo 2>/dev/null || true
        echo "Members of 'wheel' group:"
        getent group wheel 2>/dev/null || true
        echo ""

        echo "--- PASSWORD AGING & ACCOUNT POLICY (CHAGE / PASSWD) ---"
        if [ "$IS_ROOT" -eq 1 ] && [ -f /etc/shadow ]; then
            awk -F: '$2 !~ /^\*/ && $2 !~ /^!/ {print $1}' /etc/shadow | while read -r usr; do
                if has_cmd chage; then
                    echo "User Policy: $usr"
                    chage -l "$usr" 2>/dev/null | grep -E 'Password expires|Maximum number of days|Account expires'
                fi
            done
        elif [ -f /etc/login.defs ]; then
            grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE' /etc/login.defs 2>/dev/null || true
        else
            echo "Password policy information unavailable."
        fi
        echo ""

        echo "--- ENABLED SYSTEMD SERVICES AT BOOT ---"
        if has_cmd systemctl; then
            systemctl list-unit-files --type=service --state=enabled --no-pager | head -30
        fi
        echo ""

        echo "--- AUTOSTART DESKTOP APPLICATIONS ---"
        if [ -d /etc/xdg/autostart ]; then
            echo "Global Autostart Items (/etc/xdg/autostart):"
            ls -1 /etc/xdg/autostart/*.desktop 2>/dev/null || true
        fi
        if [ -d "$HOME/.config/autostart" ]; then
            echo "User Autostart Items (~/.config/autostart):"
            ls -1 "$HOME/.config/autostart/*.desktop" 2>/dev/null || true
        fi
    } > "$start_acc_path"

    echo " [OK] Startup apps & user account info saved to $start_acc_path"
    write_log "Startup Apps & User Account Info collected successfully."
}

# ==============================================================================
# SECTION 3: REPAIR, MAINTENANCE & UTILITY FUNCTIONS
# ==============================================================================

invoke_system_repair() {
    echo -e "\n[+] Executing System & Package Repair Routines..."
    write_log "Starting System & Package Repair routines..."

    local repair_log="$WORK_DIR/SystemRepair.txt"

    {
        echo "=========================================="
        echo "      SYSTEM & PACKAGE REPAIR LOG         "
        echo "=========================================="
        echo ""

        if [ "$IS_ROOT" -ne 1 ]; then
            echo " [!] Root privileges required for package and system repair actions."
        else
            if has_cmd dpkg; then
                echo "[1/3] Running dpkg --configure -a..."
                dpkg --configure -a 2>&1
                echo ""
                echo "[2/3] Running apt-get check & apt-get -f install..."
                apt-get check 2>&1
                apt-get install -f -y 2>&1
                echo ""
            elif has_cmd dnf; then
                echo "[1/2] Running dnf check..."
                dnf check 2>&1
                echo ""
            elif has_cmd pacman; then
                echo "[1/1] Database consistency check..."
                pacman -Dk 2>&1
                echo ""
            fi

            if has_cmd systemctl; then
                echo "[+] Resetting failed systemd units..."
                systemctl reset-failed 2>&1
            fi
        fi
    } > "$repair_log"

    echo " [OK] System & Package Repair routines completed. Log saved to $repair_log"
    write_log "System Repair routines completed successfully."
}

invoke_filesystem_scan() {
    echo -e "\n[+] Running Read-Only Filesystem Health Check..."
    write_log "Starting Read-Only Filesystem Health Check..."

    local fs_log="$WORK_DIR/FilesystemCheck.txt"

    {
        echo "=========================================="
        echo "     FILESYSTEM HEALTH CHECK (READ-ONLY)  "
        echo "=========================================="
        echo ""

        if has_cmd journalctl; then
            echo "--- RECENT FILESYSTEM ERRORS IN JOURNAL ---"
            journalctl -k -p err..emerg --no-pager 2>/dev/null | grep -iE 'ext4|xfs|btrfs|fsck|error' | tail -n 30 || echo "No filesystem errors found in journal."
            echo ""
        fi

        echo "--- MOUNTED FILESYSTEMS READ-ONLY INTEGRITY CHECK ---"
        if [ "$IS_ROOT" -eq 1 ]; then
            if has_cmd e2fsck; then
                echo "e2fsck available for ext2/ext3/ext4 read-only checks."
            fi
            echo "Checking mounted filesystem status:"
            touch /test_rw_check 2>/dev/null && rm -f /test_rw_check && echo "Root filesystem is writable and healthy."
        else
            echo "Root access required to execute raw fsck scan."
        fi
    } > "$fs_log"

    echo " [OK] Filesystem check completed. Report saved to $fs_log"
    write_log "Filesystem check completed successfully."
}

get_battery_report() {
    echo -e "\n[+] Generating Laptop Battery Health Report..."
    write_log "Starting Battery Report generation..."

    local battery_html="$WORK_DIR/BatteryReport.html"
    local battery_txt="$WORK_DIR/BatteryReport.txt"

    {
        echo "=========================================="
        echo "        BATTERY HEALTH REPORT             "
        echo "=========================================="
        echo ""

        if has_cmd upower; then
            local bat_dev
            bat_dev=$(upower -e | grep 'BAT' | head -1)
            if [ -n "$bat_dev" ]; then
                upower -i "$bat_dev"
            else
                echo "No battery device found via upower."
            fi
        elif [ -d /sys/class/power_supply ]; then
            local bat
            for bat in /sys/class/power_supply/BAT*; do
                if [ -d "$bat" ]; then
                    echo "Battery: $(basename "$bat")"
                    echo "Status : $(cat "$bat/status" 2>/dev/null)"
                    echo "Capacity: $(cat "$bat/capacity" 2>/dev/null)%"
                fi
            done
        else
            echo "Battery information not supported or system has no battery."
        fi
    } > "$battery_txt"

    {
        echo "<html><head><title>Battery Report</title></head><body>"
        echo "<h1>Laptop Battery Health Report</h1>"
        echo "<pre>"
        cat "$battery_txt"
        echo "</pre></body></html>"
    } > "$battery_html"

    echo " [OK] Battery report saved to $battery_txt and $battery_html"
    write_log "Battery report generated successfully."
}

invoke_maintenance_utilities() {
    local action="$1"

    case "$action" in
        "RestartBluetooth")
            echo -e "\n[+] Restarting Bluetooth & Wireless Stack..."
            write_log "Restarting Bluetooth Service..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd systemctl; then
                    systemctl restart bluetooth 2>/dev/null || true
                fi
                if has_cmd rfkill; then
                    rfkill unblock all 2>/dev/null || true
                fi
                echo " [OK] Bluetooth service restarted and rfkill unblocked."
            else
                echo " [!] Root privileges required to restart Bluetooth service."
            fi
            ;;
        "CheckEnvironment")
            echo -e "\n[+] Auditing Environment & PATH Variables..."
            write_log "Auditing Environment & PATH..."
            echo "Current PATH: $PATH"
            if [[ ":$PATH:" != *":/usr/bin:"* || ":$PATH:" != *":/bin:"* ]]; then
                echo " [!] WARNING: Standard system binaries (/bin or /usr/bin) missing from PATH."
            else
                echo " [OK] Standard binary paths present in PATH."
            fi
            ;;
        "FlushDNS")
            echo -e "\n[+] Flushing DNS Resolver Cache..."
            write_log "Flushing DNS Cache..."
            if has_cmd resolvectl; then
                resolvectl flush-caches 2>/dev/null || systemd-resolve --flush-caches 2>/dev/null
            elif has_cmd nscd; then
                nscd -i hosts 2>/dev/null
            fi
            echo " [OK] DNS Cache successfully flushed."
            ;;
        "ReleaseRenewIP")
            echo -e "\n[+] Releasing and Renewing IP Address..."
            write_log "Releasing and Renewing IP Address..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd dhclient; then
                    dhclient -r 2>/dev/null
                    dhclient 2>/dev/null
                elif has_cmd nmcli; then
                    nmcli networking off && nmcli networking on
                fi
                echo " [OK] IP Address lease successfully released and renewed."
            else
                echo " [!] Root privileges required for IP renewal."
            fi
            ;;
        "ResetNetworkStack")
            echo -e "\n[+] Restarting Network Stack & NetworkManager..."
            write_log "Restarting Network Services..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd systemctl; then
                    systemctl restart NetworkManager 2>/dev/null || systemctl restart networking 2>/dev/null
                fi
                echo " [OK] Network stack restarted."
            else
                echo " [!] Root privileges required to restart network stack."
            fi
            ;;
        "ClearTemp")
            echo -e "\n[+] Clearing Temporary Files & Caches..."
            write_log "Clearing Temp files..."
            if [ "$IS_ROOT" -eq 1 ]; then
                rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
            fi
            rm -rf "$HOME/.cache/*" 2>/dev/null || true
            echo " [OK] Temporary files and user caches cleared."
            ;;
        "PurgePrintQueue")
            echo -e "\n[+] Purging Print Queue & Restarting CUPS..."
            write_log "Purging Print Queue..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd cancel; then
                    cancel -a -x 2>/dev/null || true
                fi
                if has_cmd systemctl; then
                    systemctl restart cups 2>/dev/null || true
                fi
                echo " [OK] Print queue purged and CUPS restarted."
            else
                echo " [!] Root privileges required to clear CUPS print queue."
            fi
            ;;
        "RestartUpdateServices")
            echo -e "\n[+] Restarting Package Manager & Systemd Services..."
            write_log "Restarting system services..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd systemctl; then
                    systemctl restart packagekit 2>/dev/null || true
                fi
                echo " [OK] System update services restarted."
            else
                echo " [!] Root privileges required."
            fi
            ;;
        "CreateSnapshot")
            echo -e "\n[+] Creating System Snapshot (Timeshift / Snapper)..."
            write_log "Creating System Snapshot..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd timeshift; then
                    timeshift --create --comments "SysAdmin_Toolkit_Snapshot" 2>/dev/null
                    echo " [OK] Timeshift snapshot created."
                elif has_cmd snapper; then
                    snapper create --description "SysAdmin_Toolkit_Snapshot" 2>/dev/null
                    echo " [OK] Snapper snapshot created."
                else
                    echo " [!] Neither Timeshift nor Snapper found."
                fi
            else
                echo " [!] Root privileges required for system snapshots."
            fi
            ;;
        "UpdateAVSignatures")
            echo -e "\n[+] Updating Antivirus Signatures (ClamAV)..."
            write_log "Updating Antivirus Signatures..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd freshclam; then
                    freshclam 2>/dev/null
                    echo " [OK] ClamAV signatures updated."
                elif has_cmd mdatp; then
                    mdatp definitions update 2>/dev/null
                    echo " [OK] Antivirus definitions updated."
                else
                    echo "No recognized Linux AV signature update utility found."
                fi
            else
                echo " [!] Root privileges required for AV updates."
            fi
            ;;
        "ResetPackageCache")
            echo -e "\n[+] Resetting Package Manager Cache..."
            write_log "Resetting Package Manager Cache..."
            if [ "$IS_ROOT" -eq 1 ]; then
                if has_cmd apt-get; then
                    apt-get clean 2>/dev/null
                elif has_cmd dnf; then
                    dnf clean all 2>/dev/null
                elif has_cmd pacman; then
                    pacman -Sc --noconfirm 2>/dev/null
                fi
                echo " [OK] Package manager cache reset successfully."
            else
                echo " [!] Root privileges required to clear package cache."
            fi
            ;;
        "ForceKillProcess")
            echo -e "\n[+] Force Kill Process (kill -9 / pkill)..."
            write_log "Starting Force Kill Process..."
            read -rp "Enter Process Name or Process ID (PID) to kill: " proc_input
            if [ -z "$proc_input" ]; then
                echo " [!] No input provided."
            else
                if [[ "$proc_input" =~ ^[0-9]+$ ]]; then
                    kill -9 "$proc_input" 2>&1
                    echo " [OK] Signal SIGKILL (-9) sent to PID $proc_input."
                    write_log "Process PID $proc_input killed."
                else
                    pkill -9 -f "$proc_input" 2>&1
                    echo " [OK] pkill -9 executed for pattern '$proc_input'."
                    write_log "pkill -9 executed for '$proc_input'."
                fi
            fi
            ;;
        "ManageUserAccount")
            echo -e "\n[+] Local User Account Management..."
            echo " [1] Create New Local User"
            echo " [2] Delete Local User"
            echo " [3] Grant Sudo/Admin Rights to User"
            read -rp "Select Action [1-3]: " user_choice
            case "$user_choice" in
                1)
                    read -rp "Enter new username: " uname
                    if [ -n "$uname" ]; then
                        if [ "$IS_ROOT" -eq 1 ]; then
                            useradd -m "$uname" 2>&1
                            echo "Set password for $uname:"
                            passwd "$uname"
                            write_log "User '$uname' created."
                        else
                            echo " [!] Root privileges required to create users."
                        fi
                    fi
                    ;;
                2)
                    read -rp "Enter username to delete: " uname
                    if [ -n "$uname" ]; then
                        if [ "$IS_ROOT" -eq 1 ]; then
                            userdel -r "$uname" 2>&1
                            echo " [OK] Local user '$uname' deleted."
                            write_log "User '$uname' deleted."
                        else
                            echo " [!] Root privileges required to delete users."
                        fi
                    fi
                    ;;
                3)
                    read -rp "Enter username to add to sudo/wheel group: " uname
                    if [ -n "$uname" ]; then
                        if [ "$IS_ROOT" -eq 1 ]; then
                            if getent group sudo >/dev/null 2>&1; then
                                usermod -aG sudo "$uname" 2>&1
                                echo " [OK] User '$uname' added to 'sudo' group."
                            elif getent group wheel >/dev/null 2>&1; then
                                usermod -aG wheel "$uname" 2>&1
                                echo " [OK] User '$uname' added to 'wheel' group."
                            fi
                            write_log "User '$uname' added to admin group."
                        else
                            echo " [!] Root privileges required."
                        fi
                    fi
                    ;;
            esac
            ;;
        "LaunchAdminTools")
            echo -e "\n[+] Linux Administration & Diagnostic Tools Launcher..."
            echo " [1] System Monitor / Process Viewer (htop / top)"
            echo " [2] Network Configuration TUI (nmtui)"
            echo " [3] Systemd Journal Logs Monitor (journalctl -f)"
            echo " [4] Disk Usage Analyzer (ncdu / df -h)"
            echo " [5] Interactive Firewall Configuration (ufw status / firewall-cmd)"
            read -rp "Select Tool to launch [1-5]: " tool_choice
            case "$tool_choice" in
                1) if has_cmd htop; then htop; else top; fi ;;
                2) if has_cmd nmtui; then nmtui; else ip addr; fi ;;
                3) journalctl -f --no-pager -n 50 ;;
                4) if has_cmd ncdu; then ncdu; else df -h; read -rp "Press enter..."; fi ;;
                5)
                    if has_cmd ufw && [ "$IS_ROOT" -eq 1 ]; then
                        ufw status verbose
                    elif has_cmd firewall-cmd; then
                        firewall-cmd --list-all
                    else
                        iptables -L -n -v | head -30
                    fi
                    read -rp "Press enter..."
                    ;;
            esac
            ;;
    esac
}

invoke_full_diagnostic_mode() {
    echo -e "\n========================================================================="
    echo "           STARTING FULL DIAGNOSTIC MODE (ALL CHECKS)                    "
    echo "========================================================================="
    write_log "Starting Full Diagnostic Mode..."

    get_system_information
    get_hardware_information
    get_disk_health
    get_installed_software
    get_driver_diagnostics
    get_network_diagnostics
    get_network_extended_info
    get_event_logs
    get_services_and_processes
    get_firewall_status
    get_package_update_history
    get_security_diagnostics
    get_smb_diagnostics
    get_startup_and_account_info
    get_battery_report

    echo -e "\n========================================================================="
    echo "  FULL DIAGNOSTICS COMPLETED! All reports saved in:"
    echo "  $WORK_DIR"
    echo "========================================================================="
    write_log "Full Diagnostic Mode finished."
}

# ==============================================================================
# SECTION 4: INTERACTIVE MENU, REPORT LAUNCHER & SCHEDULER
# ==============================================================================

open_report_folder() {
    echo -e "\n[+] Opening Report Folder: $WORK_DIR"
    write_log "Opening report folder..."
    if has_cmd xdg-open; then
        xdg-open "$WORK_DIR" 2>/dev/null || echo " [!] Report Folder Path: $WORK_DIR"
    else
        echo " [!] Report Folder Path: $WORK_DIR"
    fi
}

add_scheduled_task_helper() {
    echo -e "\n[+] Scheduling Automated Daily Toolkit Checks (Cron)..."
    write_log "Setting up cron task for SysAdmin Toolkit..."

    local script_path
    script_path=$(readlink -f "$0")

    local cron_cmd="0 8 * * * root $script_path -AutoRun >/dev/null 2>&1"
    local cron_file="/etc/cron.d/sysadmin_toolkit_daily"

    if [ "$IS_ROOT" -eq 1 ]; then
        echo "$cron_cmd" > "$cron_file"
        chmod 644 "$cron_file"
        echo " [OK] Scheduled Cron Task created at $cron_file to run daily at 8:00 AM."
        write_log "Scheduled Task created successfully at $cron_file."
    else
        echo " [!] Root privileges required to install daily cron job in /etc/cron.d/"
    fi
}

show_main_ui() {
    local autorun="$1"

    if [ "$autorun" = "-AutoRun" ]; then
        invoke_full_diagnostic_mode
        return
    fi

    while true; do
        clear
        echo "========================================================================"
        echo "                        SYSADMIN TOOLKIT (LINUX)                        "
        echo "             Diagnose. Repair. Keep Linux Running.                      "
        echo "========================================================================"
        echo " Report Folder : $WORK_DIR"
        echo " Privilege     : $(if [ "$IS_ROOT" -eq 1 ]; then echo 'Elevated (root)'; else echo 'Standard User'; fi)"
        echo "------------------------------------------------------------------------"
        echo " [1]  System Information       (OS, Kernel, Hostname, Uptime)"
        echo " [2]  Hardware Information     (CPU, RAM, Disks, GPU, Motherboard)"
        echo " [3]  Disk Health & Storage    (Volume Space, SMART Physical Disk Status)"
        echo " [4]  Network Diagnostics      (IP Config, Ping, DNS, Routes, Listening Ports)"
        echo " [5]  Event Logs               (Journald Critical/Error Logs & Syslog)"
        echo " [6]  Services & Processes     (Failed Services, Top CPU/RAM Processes)"
        echo " [7]  Installed Software       (Export full software list to CSV/TXT)"
        echo " [8]  System & Package Repair  (Fix broken packages & systemd failed units)"
        echo " [9]  Filesystem Health Scan   (Read-only journal & mount health check)"
        echo " [10] Firewall Status          (UFW, Firewalld, Iptables Summary)"
        echo " [11] Package Update History   (Apt/Dnf/Pacman transaction logs)"
        echo " [12] Security Diagnostics     (SELinux, AppArmor, LUKS, TPM status)"
        echo " [13] Startup & Accounts Info  (Local Users, Sudoers, Autostart apps)"
        echo " [14] Battery Report           (Laptop battery health report)"
        echo " [15] Driver Diagnostics       (Kernel dmesg hardware/firmware audit)"
        echo " [16] Extended Network Check   (Public IP, Hosts file security, WAN latency)"
        echo " [17] SMB & NFS Shares         (Network shares, sessions & Samba security)"
        echo "------------------------------------------------------------------------"
        echo " [18] FULL DIAGNOSTIC MODE     (Run all diagnostic checks at once)"
        echo " [19] Quick Utilities          (Flush DNS, Reset Stack, Clear Temp, Kill Process, User Mgmt, Admin Tools)"
        echo " [20] Schedule Daily Task      (Automate script via Cron daily task)"
        echo " [21] Open Report Folder       (Quick access to generated reports)"
        echo " [0]  Exit Toolkit"
        echo "========================================================================"

        read -rp "Select an option [0-21]: " selection

        case "$selection" in
            1)  get_system_information; pause_prompt ;;
            2)  get_hardware_information; pause_prompt ;;
            3)  get_disk_health; pause_prompt ;;
            4)  get_network_diagnostics; pause_prompt ;;
            5)  get_event_logs; pause_prompt ;;
            6)  get_services_and_processes; pause_prompt ;;
            7)  get_installed_software; pause_prompt ;;
            8)  invoke_system_repair; pause_prompt ;;
            9)  invoke_filesystem_scan; pause_prompt ;;
            10) get_firewall_status; pause_prompt ;;
            11) get_package_update_history; pause_prompt ;;
            12) get_security_diagnostics; pause_prompt ;;
            13) get_startup_and_account_info; pause_prompt ;;
            14) get_battery_report; pause_prompt ;;
            15) get_driver_diagnostics; pause_prompt ;;
            16) get_network_extended_info; pause_prompt ;;
            17) get_smb_diagnostics; pause_prompt ;;
            18) invoke_full_diagnostic_mode; pause_prompt ;;
            19)
                echo -e "\nSelect Utility Action:"
                echo " [A] Flush DNS Cache"
                echo " [B] Release & Renew IP Address"
                echo " [C] Reset Network Stack / NetworkManager"
                echo " [D] Clear Temporary Files & User Cache"
                echo " [E] Purge Print Queue & Restart CUPS"
                echo " [F] Restart Update Services"
                echo " [G] Create System Snapshot (Timeshift / Snapper)"
                echo " [H] Update Antivirus Signatures (ClamAV)"
                echo " [I] Reset Package Manager Cache"
                echo " [J] Force Kill Process (kill -9 / pkill)"
                echo " [K] Local User Account Management (useradd / userdel / usermod)"
                echo " [L] Launch Admin Console / Diagnostic Tools (htop, nmtui, journalctl)"
                echo " [M] Restart Bluetooth & Wireless Stack"
                echo " [N] Check Environment & PATH Variables"
                read -rp "Choice: " subchoice
                case "${subchoice^^}" in
                    A) invoke_maintenance_utilities "FlushDNS" ;;
                    B) invoke_maintenance_utilities "ReleaseRenewIP" ;;
                    C) invoke_maintenance_utilities "ResetNetworkStack" ;;
                    D) invoke_maintenance_utilities "ClearTemp" ;;
                    E) invoke_maintenance_utilities "PurgePrintQueue" ;;
                    F) invoke_maintenance_utilities "RestartUpdateServices" ;;
                    G) invoke_maintenance_utilities "CreateSnapshot" ;;
                    H) invoke_maintenance_utilities "UpdateAVSignatures" ;;
                    I) invoke_maintenance_utilities "ResetPackageCache" ;;
                    J) invoke_maintenance_utilities "ForceKillProcess" ;;
                    K) invoke_maintenance_utilities "ManageUserAccount" ;;
                    L) invoke_maintenance_utilities "LaunchAdminTools" ;;
                    M) invoke_maintenance_utilities "RestartBluetooth" ;;
                    N) invoke_maintenance_utilities "CheckEnvironment" ;;
                esac
                pause_prompt
                ;;
            20) add_scheduled_task_helper; pause_prompt ;;
            21) open_report_folder; pause_prompt ;;
            0)  echo "Exiting SysAdmin Toolkit. Goodbye!"; break ;;
            *)  echo "Invalid selection. Please try again."; sleep 1 ;;
        esac
    done
}

chmod +x "$0" 2>/dev/null || true

if [ "$1" = "-AutoRun" ]; then
    show_main_ui "-AutoRun"
else
    show_main_ui "$@"
fi
