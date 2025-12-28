#!/bin/bash
# =================================================================================
# Setup Auto Thermal Throttling (Intel & AMD)
# =================================================================================
# Description: Automates Thermal Design Power (TDP) and Frequency management
#              for Linux. Supports Intel RAPL and AMD P-State/RyzenAdj.
# Author:      ZauJulio
# Date:        2025-12-27
# License:     MIT
# =================================================================================

#  --- Internal Configuration ---------------------------------------------------------

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- [ 0. KERNEL MODULE LOADING ] ------------------------------------------------

log_info "Ensuring essential kernel modules are loaded..."

# Attempt to load MSR (necessary for Turbostat and some Intel readings)
modprobe msr 2>/dev/null

if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    # Essential for limiting PL1/PL2 via sysfs on Intel
    # 'modprobe' loads if not already loaded.
    if modprobe intel_rapl_msr 2>/dev/null; then
        log_success "Module loaded: intel_rapl_msr"
    elif modprobe intel_rapl_common 2>/dev/null; then
        log_success "Module loaded: intel_rapl_common"
    else
        log_warn "Could not load Intel RAPL modules. Power limits might fail."
    fi
    
elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    # AMD generally uses built-in drivers (amd_pstate) or acpi_cpufreq.
    # ryzenadj accesses hardware directly, does not depend on standard RAPL module.
    # But we can try loading msr if not already loaded.
    : # Nothing specific kernel module critical to manually load on modern AMD
fi

# 1. Default Values (Fallbacks)
# ---------------------------------------------------------------------------------

# PL1: Sustained Power Limit
PL1_WATTS=30

# PL2: Burst Power Limit
PL2_WATTS=45

# Time Windows (in nanoseconds)
PL1_TIME_US=28000000

# 2.44 ms for PL2
PL2_TIME_US=2440

# Max Frequency Cap (in GHz, 0 = No Cap)
MAX_FREQ_GHZ=4.0

# Governor: powersave or performance
TARGET_GOVERNOR="powersave"

# EPP Values
EPP_INTEL=84
EPP_AMD="balance_performance"

# 2. Load User Config
CONFIG_FILE="/etc/autothrottle.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ---------------------------------------------------------------------------------

# --- [ 2. HELPER FUNCTIONS ] -----------------------------------------------------

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo)."
        exit 1
    fi
}

check_tool() {
    if command -v "$1" &> /dev/null; then
        log_success "Tool found: $1"
        return 0
    else
        log_warn "Tool not found: $1 (Optional)"
        return 1
    fi
}

# --- [ 3. HARDWARE DETECTION ] ---------------------------------------------------

check_root

echo "========================================"
echo "    System Diagnostics & Setup"
echo "========================================"

# Detect Vendor
CPU_VENDOR=$(grep "vendor_id" /proc/cpuinfo | head -n 1 | awk '{print $3}')
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d ':' -f 2 | xargs)

log_info "CPU Detected: $CPU_VENDOR - $CPU_MODEL"

# Detect Driver
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ]; then
    CURRENT_DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)
    log_info "Scaling Driver: $CURRENT_DRIVER"
else
    log_error "No scaling driver loaded."
    exit 1
fi

# Check Tools
log_info "Checking installed utilities..."
check_tool "ryzenadj"
check_tool "turbostat"
check_tool "sensors"

# --- [ 4. UNIVERSAL CONFIGURATION ] ----------------------------------------------

echo ""
echo "========================================"
echo "    Applying Configuration"
echo "========================================"

# 4.1 Set Governor
log_info "Setting CPU Governor to: $TARGET_GOVERNOR..."
# IF intel use 'performance' for speed shift, else 'powersave' for amd p-state
if [ "$CPU_VENDOR" == "GenuineIntel" ] && [ "$TARGET_GOVERNOR" == "powersave" ]; then
    TARGET_GOVERNOR="performance"
    log_info "Intel CPU detected, overriding governor to 'performance' for Speed Shift."
elif [ "$CPU_VENDOR" == "AuthenticAMD" ] && [ "$TARGET_GOVERNOR" == "performance" ]; then
    TARGET_GOVERNOR="powersave"
    log_info "AMD CPU detected, overriding governor to 'powersave' for P-State."
fi

# Set Governor
if echo "$TARGET_GOVERNOR" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1; then
    log_success "Governor applied."
else
    log_error "Failed to set governor."
fi

# 4.2 Set Frequency Cap (If enabled)
if [ $(echo "$MAX_FREQ_GHZ > 0" | bc -l) -eq 1 ]; then
    FREQ_KHZ=$(echo "$MAX_FREQ_GHZ * 1000000" | bc | cut -d '.' -f 1)
    log_info "Capping Max Frequency to ${MAX_FREQ_GHZ} GHz ($FREQ_KHZ kHz)..."
    
    if echo "$FREQ_KHZ" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq > /dev/null 2>&1; then
        log_success "Frequency cap applied."
    else
        log_error "Failed to set max frequency."
    fi
else
    log_info "Frequency capping disabled (Set to 0)."
fi

# --- [ 5. VENDOR SPECIFIC LOGIC ] ------------------------------------------------
if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    # ================= INTEL LOGIC =================
    log_info "Starting Intel RAPL Configuration..."
    
    RAPL_PATH="/sys/class/powercap/intel-rapl:0"
    
    if [ -d "$RAPL_PATH" ]; then
        # Convert Watts to MicroWatts
        PL1_UW=$(($PL1_WATTS * 1000000))
        PL2_UW=$(($PL2_WATTS * 1000000))
        
        # Apply PL1
        echo "$PL1_UW" > "$RAPL_PATH/constraint_0_power_limit_uw"
        echo "$PL1_TIME_US" > "$RAPL_PATH/constraint_0_time_window_us"
        log_success "PL1 set to ${PL1_WATTS}W"
        
        # Apply PL2
        echo "$PL2_UW" > "$RAPL_PATH/constraint_1_power_limit_uw"
        echo "$PL2_TIME_US" > "$RAPL_PATH/constraint_1_time_window_us"
        log_success "PL2 set to ${PL2_WATTS}W"
        
        # Enable / Clamp
        echo 1 > "$RAPL_PATH/enabled"
        log_success "RAPL Constraints Enabled."
    else
        log_error "Intel RAPL interface not found at $RAPL_PATH"
    fi
    
    # Apply EPP (Intel)
    log_info "Setting EPP to: $EPP_INTEL"
    for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -f "$epp" ] && echo "$EPP_INTEL" > "$epp" 2>/dev/null
    done

elif [ "$CPU_VENDOR" == "AuthenticAMD" ]; then
    # ================= AMD LOGIC =================
    log_info "Starting AMD Configuration..."
    
    # Check for ryzenadj for TDP control
    if command -v ryzenadj &> /dev/null; then
        log_info "Using ryzenadj to set TDP..."
        # Convert Watts to Mili-Watts for ryzenadj
        PL1_MW=$(($PL1_WATTS * 1000))
        PL2_MW=$(($PL2_WATTS * 1000))
        
        # Apply: stapm (short), fast (burst), slow (sustained)
        ryzenadj --stapm-limit=$PL1_MW --fast-limit=$PL2_MW --slow-limit=$PL1_MW > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_success "ryzenadj: Limits set to ${PL1_WATTS}W / ${PL2_WATTS}W"
        else
            log_error "ryzenadj failed to apply settings."
        fi
    else
        log_warn "ryzenadj not found. Skipping Wattage control (Frequency cap only)."
    fi
    
    # Apply EPP (AMD)
    log_info "Setting EPP to: $EPP_AMD"
    for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        if [ -w "$epp" ]; then
             echo "$EPP_AMD" > "$epp" 2>/dev/null
        fi
    done
fi

echo ""
echo "========================================"
echo "    Status Report"
echo "========================================"
echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "Max Freq: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) kHz"

if [ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
    echo "EPP:      $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"
fi

if [ "$CPU_VENDOR" == "GenuineIntel" ]; then
    echo "PL1 Limit: $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw) uW"
    echo "PL2 Limit: $(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw) uW"
fi

log_success "Optimization Complete."