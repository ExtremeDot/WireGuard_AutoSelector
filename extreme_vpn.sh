#!/bin/bash
# extreme_vpn.sh — Clean stable version
# Tuned by ChatGPT
clear

echo "------------------------------------------------"
echo " EXTREME WIREGUARD CONFIG SELECTOR       VER:01 "
echo "------------------------------------------------"
CONFIG_DIR="/etc/wireguard/extreme_configs"
INTERFACE_NAME="wg-extreme"
LOG_FILE="/var/log/extreme_vpn.log"
SILENT_MODE=0
TEST_DURATION_LIMIT=10
CONNECTIVITY_URL="https://myip.wtf/json"
TEST_FILE="/tmp/speedtest.tmp"

SPEEDTEST_URLS=(
    "http://speedtest.ams1.nl.leaseweb.net/100mb.bin"
    "https://proof.ovh.net/files/100Mb.dat"
    "https://nbg1-speed.hetzner.com/100MB.bin"
    "https://fra.download.datapacket.com/100mb.bin"
)

SPEEDTEST_NAMES=("Leaseweb-AMS1" "OVH" "Hetzner-NBG1" "Datapacket-FRA")

# Ensure config directory exists
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${YELLOW}Creating config directory: $CONFIG_DIR${NC}"
    sudo mkdir -p "$CONFIG_DIR"
    sudo chmod 700 "$CONFIG_DIR"
fi


CLEANUP_REQUIRED=0

cleanup() {
    sudo wg-quick down "$INTERFACE_NAME" 2>/dev/null || true
    rm -f "$TEST_FILE"
    [ "$CLEANUP_REQUIRED" -eq 1 ] && echo "[!] Cleanup done." || echo "[!] Stopped."
    exit 0
}
trap cleanup SIGINT SIGTERM

msg() {
    
    if [ $# -eq 1 ]; then
        echo "$1"
        return
    fi

    
    local color=$1
    shift
    local message="$*"

    case "$color" in
        red)    color_code="\033[0;31m" ;;
        green)  color_code="\033[0;32m" ;;
        yellow) color_code="\033[0;33m" ;;
        blue)   color_code="\033[0;34m" ;;
        magenta) color_code="\033[0;35m" ;;
        cyan)   color_code="\033[0;36m" ;;
        white)  color_code="\033[0;37m" ;;
        *)      color_code="" ;;
    esac

    local reset="\033[0m"
    echo -e "${color_code}${message}${reset}"
}

check_software() {
    
    local pkgs=(wg curl jq bc)
        
    for pkg in "${pkgs[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            sudo apt update -y >/dev/null 2>&1
            sudo apt install -y "$pkg" >/dev/null 2>&1
        fi
    done
}


check_software_old() {
    msg "Checking required software..."
    for pkg in wg curl jq bc; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            msg "Installing $pkg..."
            sudo apt update -y && sudo apt install -y "$pkg"
        else
            msg "$pkg OK"
        fi
    done
}

check_and_fix_config() {
    local f=$1
    grep -q "^Table\s*=\s*off" "$f" || sudo sed -i '/^\[Interface\]/a Table = off' "$f"
}

test_datacenter_speed() {
    local url=$1; local name=$2
    rm -f "$TEST_FILE"
    local start=$(date +%s)
    timeout "$TEST_DURATION_LIMIT" curl -s -o "$TEST_FILE" "$url"
    local end=$(date +%s); local duration=$((end - start))
    [ $duration -eq 0 ] && duration=1
    local speed=0
    if [ -f "$TEST_FILE" ]; then
        local size=$(stat -c %s "$TEST_FILE" 2>/dev/null || echo 0)
        speed=$(echo "scale=2; ($size * 8) / $duration / 1000000" | bc)
    fi
    rm -f "$TEST_FILE"
    echo "$speed $name"
}

select_fastest_datacenter() {
	echo
    msg yellow "=============== Datacenter Tests ==============="
    best_speed=0; best_name=""; best_url=""
    declare -A results
    for i in "${!SPEEDTEST_URLS[@]}"; do
        read speed name <<< "$(test_datacenter_speed "${SPEEDTEST_URLS[$i]}" "${SPEEDTEST_NAMES[$i]}")"
        results["$name"]="$speed"
        msg "Datacenter $name | Speed ${speed} Mbps"
        if (( $(echo "$speed > $best_speed" | bc -l) )); then
            best_speed=$speed; best_name=$name; best_url="${SPEEDTEST_URLS[$i]}"
        fi
    done
	echo
    msg yellow "-----========== Datacenter Summary ==========-----"
    #for name in "${!results[@]}"; do
    #    msg "$name : ${results[$name]} Mbps"
    #done
    if (( $(echo "$best_speed == 0" | bc -l) )); then
        msg "No datacenter reachable."
        CLEANUP_REQUIRED=1
        cleanup
    else
        msg magenta "Selected datacenter: $best_name (${best_speed} Mbps)"
        SELECTED_SPEEDTEST_URL="$best_url"
		echo
    fi
}

test_speed_and_connectivity() {
    local config_file=$1
    local config_name=$(basename "$config_file" .conf)
    sudo wg-quick down "$INTERFACE_NAME" 2>/dev/null || true
    sudo cp "$config_file" "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo chmod 600 "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo wg-quick up "$INTERFACE_NAME" &> /dev/null || return 1
    sleep 2
    local ping_time=$(curl --interface "$INTERFACE_NAME" -s -o /dev/null -w "%{time_total}" "$CONNECTIVITY_URL")
    ping_ms=$(awk "BEGIN {printf \"%.0f\", $ping_time * 1000}")
    rm -f "$TEST_FILE"
    start=$(date +%s)
    timeout "$TEST_DURATION_LIMIT" curl --interface "$INTERFACE_NAME" -s -o "$TEST_FILE" "$SELECTED_SPEEDTEST_URL"
    end=$(date +%s); duration=$((end - start))
    [ $duration -eq 0 ] && duration=1
    speed=0
    if [ -f "$TEST_FILE" ]; then
        size=$(stat -c %s "$TEST_FILE" 2>/dev/null || echo 0)
        speed=$(echo "scale=2; ($size * 8) / $duration / 1000000" | bc)
    fi
    rm -f "$TEST_FILE"
    sudo wg-quick down "$INTERFACE_NAME" 2>/dev/null || true
    echo "$speed $ping_ms $config_name"
}

select_best_config() {
    msg yellow "=============== WireGuard Config Tests ==============="
    configs=("$CONFIG_DIR"/*.conf)
    best_score=0; best_config=""
    declare -A results
    P0=1000  

    for cfg in "${configs[@]}"; do
        check_and_fix_config "$cfg"
        read speed ping name <<< "$(test_speed_and_connectivity "$cfg")"
        results["$name"]="${speed} Mbps / ${ping} ms"

        # محاسبه score
        score=$(echo "$speed / (1 + $ping / $P0)" | bc -l)
		printf_score=$(printf "%.2f" "$score")

        msg "Config $name | Speed ${speed} Mbps | Ping ${ping} ms | Score ${printf_score}"

        # انتخاب بهترین بر اساس score
        if (( $(echo "$score > $best_score" | bc -l) )); then
            best_score=$score
            best_config=$cfg
        fi
    done
	echo

    msg yellow "-----========== WireGuard Summary ==========-----"
    #for k in "${!results[@]}"; do
    #    msg "$k : ${results[$k]}"
    #done

    [ -z "$best_config" ] && { msg "No valid config found!"; exit 1; }
    echo
	printf2_score=$(printf "%.2f" "$best_score")
    msg red "Best WireGuard config: $(basename "$best_config") (Score: ${printf2_score})"
    sudo cp "$best_config" "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo chmod 600 "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo wg-quick up "$INTERFACE_NAME" &> /dev/null
    echo ""
}


select_best_config_OLD() {
    msg yellow "=============== WireGuard Config Tests ==============="
    configs=("$CONFIG_DIR"/*.conf)
    best_speed=0; best_config=""
    declare -A results
    for cfg in "${configs[@]}"; do
        check_and_fix_config "$cfg"
        read speed ping name <<< "$(test_speed_and_connectivity "$cfg")"
        results["$name"]="${speed} Mbps / ${ping} ms"
        msg "Config $name | Speed ${speed} Mbps | Ping ${ping} ms"
        if (( $(echo "$speed > $best_speed" | bc -l) )); then
            best_speed=$speed; best_config=$cfg
        fi
    done
	echo
    msg yellow "-----========== WireGuard Summary ==========-----"
    for k in "${!results[@]}"; do
        msg "$k : ${results[$k]}"
    done
    [ -z "$best_config" ] && { msg "No valid config found!"; exit 1; }
	printf2_score=$(printf "%.2f" "$best_score")
	msg red "Best WireGuard config: $(basename "$best_config") (${printf2_score} Mbps)"
    sudo cp "$best_config" "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo chmod 600 "/etc/wireguard/$INTERFACE_NAME.conf"
    sudo wg-quick up "$INTERFACE_NAME" &> /dev/null
	echo
}

show_help() {
    echo "Extreme WireGuard VPN Auto Selector"
    echo "Usage: sudo ./extreme_vpn.sh [--silent] [--help]"
    echo
    echo "Options:"
    echo "  --silent   Run quietly (log only)"
    echo "  --help     Show this help menu"
    echo
    echo "This script auto-tests WireGuard configs and selects the fastest one."
	msg yellow "put all Wireguard's *.conf files into [/etc/wireguard/extreme_configs] directory."
	echo
    echo "Log file: $LOG_FILE"
}

if [[ "$1" == "--help" ]]; then show_help; exit 0; fi
if [[ "$1" == "--silent" ]]; then SILENT_MODE=1; fi

check_software
select_fastest_datacenter
select_best_config
