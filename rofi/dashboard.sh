#!/usr/bin/env bash
# dashboard.sh - Launch Imperium System Dashboard & App Browser

# 1. Read live CPU temperature from thermal sensors
cpu_temp="55°C"
for zone in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -f "$zone" ]]; then
        raw_val=$(cat "$zone" 2>/dev/null)
        if [[ -n "$raw_val" && "$raw_val" -gt 25000 && "$raw_val" -lt 110000 ]]; then
            cpu_temp="$(( raw_val / 1000 ))°C"
            break
        fi
    fi
done

# 2. Read memory, power, and kernel telemetry
ram_usage=$(free -h --si 2>/dev/null | awk '/Mem:/ {print $3 " / " $2}')
battery_pct=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
[[ -n "$battery_pct" ]] && battery_str="⚡ ${battery_pct}%" || battery_str="🔌 AC Powered"
uptime_str=$(uptime -p 2>/dev/null | sed 's/up //; s/ hours\?/h/g; s/ minutes\?/m/g; s/, / /g')
kernel_ver=$(uname -r | cut -d '-' -f 1)

# 3. Format structured telemetry HUD for left panel
TELEMETRY_HUD="✠ VOLUTA TELEMETRY ✠
───────────────────────────
🌡 CPU Temp   : $cpu_temp
󰍛 Memoria    : $ram_usage
$battery_str
⏳ Aevum      : $uptime_str
󰒋 Nucleus    : $kernel_ver"

# 4. Launch 2-column Rofi System Dashboard
exec rofi -show drun -theme "$HOME/.config/rofi/dashboard.rasi" -mesg "$TELEMETRY_HUD"
