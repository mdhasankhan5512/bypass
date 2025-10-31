#!/bin/sh
ROUTER_ID="Server1"
ROUTER_AUTH_KEY="Jdid8beje"

# =================================================================
# === NEW: User Input Check ===
# =================================================================
# Check if ROUTER_ID is empty
if [ -z "$ROUTER_ID" ]; then
    echo "======================================================"
    echo "=== Configuration Required: Router ID                ==="
    echo "======================================================"
    read -p "Please enter the unique Router ID: " ROUTER_ID
    # Basic validation (optional, but good practice)
    if [ -z "$ROUTER_ID" ]; then
        echo "✗ Error: Router ID cannot be empty. Aborting setup."
        exit 1
    fi
fi

# Check if ROUTER_AUTH_KEY is empty
if [ -z "$ROUTER_AUTH_KEY" ]; then
    echo ""
    echo "======================================================"
    echo "=== Configuration Required: Router Auth Key          ==="
    echo "======================================================"
    read -p "Please enter the Router Authentication Key: " ROUTER_AUTH_KEY
    if [ -z "$ROUTER_AUTH_KEY" ]; then
        echo "✗ Error: Router Auth Key cannot be empty. Aborting setup."
        exit 1
    fi
fi

# Function to display progress messages
show_progress() {
    echo "  $1"
    sleep 2
}

clear

echo ""
echo "======================================================"
echo "===  Initializing Secure Hotspot Setup v2.3      ==="
echo "===  Router ID: $ROUTER_ID                          ==="
echo "======================================================"
echo ""
echo "WARNING: This process will configure the device."
echo "Please do not interrupt or power off the device."
echo ""
sleep 3

# ---
## 1. System Preparation & Package Installation
# ---
show_progress "Updating package lists. Please wait..."
opkg update >/dev/null 2>&1

# === UPDATED: Using --force-overwrite for package installation ===
show_progress "Deploying core service components (Force overwrite enabled)..."
# Ensure all necessary packages are installed with force-overwrite
# Use the force-overwrite flag to replace existing configuration files
opkg install --force-overwrite nodogsplash luci-app-nft-qos nft-qos && opkg install uhttpd-mod-ubus jsonfilter wget jq>/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo ""
    echo "  ✗ Error: Core component installation failed."
    echo "  Please check your internet connection and try again."
    echo "  Aborting setup."
    echo ""
    exit 1
fi
echo "  ✓ Core services deployed successfully."
sleep 2

# ---
## 2. Configuring Network Rules Engine (No changes here)
# ---
show_progress "Configuring dynamic network rules engine..."
{
cat <<EOF > /root/update_nds_rules.sh
#!/bin/sh
DOMAIN="wifi-hotspot-zone.onrender.com"
CONFIG_FILE="/etc/config/nodogsplash"
STATIC_DNS_RULE_1="list preauthenticated_users 'allow tcp port 53 to 8.8.8.8'"
STATIC_DNS_RULE_2="list preauthenticated_users 'allow udp port 53 to 8.8.8.8'"
CURRENT_IPS=\$(nslookup \$DOMAIN | grep 'Address:' | awk '{print \$2}' | grep -v '127.0.0.1' | sort)
if [ -z "\$CURRENT_IPS" ]; then exit 1; fi
OLD_IPS=\$(grep "preauthenticated_users.*allow tcp port 443 to" \$CONFIG_FILE | awk -F 'to ' '{print \$2}' | tr -d "'" | sort)
DNS_RULE_1_EXISTS=\$(grep -c -F "\$STATIC_DNS_RULE_1" \$CONFIG_FILE)
DNS_RULE_2_EXISTS=\$(grep -c -F "\$STATIC_DNS_RULE_2" \$CONFIG_FILE)
if [ "\$CURRENT_IPS" = "\$OLD_IPS" ] && [ "\$DNS_RULE_1_EXISTS" -gt 0 ] && [ "\$DNS_RULE_2_EXISTS" -gt 0 ]; then exit 0; fi
sed -i "/preauthenticated_users.*allow tcp port 443 to/d" \$CONFIG_FILE
sed -i "/preauthenticated_users.*allow tcp port 53 to 8.8.8.8/d" \$CONFIG_FILE
sed -i "/preauthenticated_users.*allow udp port 53 to 8.8.8.8/d" \$CONFIG_FILE
echo " \${STATIC_DNS_RULE_1}" >> \$CONFIG_FILE
echo " \${STATIC_DNS_RULE_2}" >> \$CONFIG_FILE
for IP in \$CURRENT_IPS; do echo " list preauthenticated_users 'allow tcp port 443 to \$IP'" >> \$CONFIG_FILE; done
/etc/init.d/nodogsplash reload >/dev/null 2>&1
EOF
chmod +x /root/update_nds_rules.sh
echo '0 * * * * /root/update_nds_rules.sh' > /etc/crontabs/root
/root/update_nds_rules.sh
/etc/init.d/cron enable
/etc/init.d/cron restart
/etc/init.d/nodogsplash enable
/etc/init.d/nodogsplash reload
} >/dev/null 2>&1
echo "  ✓ Network engine configured."
sleep 2

# ---
## 3 & 4. APIs and Portal (set_speed script is now improved)
# ---
show_progress "Deploying APIs and customizing portal..."
{
touch /etc/nds_trusted_list
cat <<EOF > /www/cgi-bin/unblock
#!/bin/sh
MAC=\$1; [ -z "\$MAC" ] && exit 1; LIST_FILE="/etc/nds_trusted_list"; ndsctl trust "\$MAC"; if ! grep -q -i "^\${MAC}$" "\$LIST_FILE"; then echo "\$MAC" >> "\$LIST_FILE"; fi
EOF
cat <<EOF > /www/cgi-bin/block
#!/bin/sh
MAC=\$1; [ -z "\$MAC" ] && exit 1; LIST_FILE="/etc/nds_trusted_list"; ndsctl untrust "\$MAC"; sed -i "/^\${MAC}$/Id" "\$LIST_FILE"
EOF

# === IMPROVED set_speed SCRIPT ===
cat <<'EOF' > /www/cgi-bin/set_speed
#!/bin/sh
MAC=$1
DL_MBPS=$2

# Exit if MAC or Speed is not provided
[ -z "$MAC" ] && exit 1
[ -z "$DL_MBPS" ] && DL_MBPS=0

# --- Find client IP address reliably using ndsctl and jq ---
CLIENT_IP=$(ndsctl json | jq -r --arg mac "$MAC" '.clients[] | select(.mac | ascii_downcase == ($mac | ascii_downcase)) | .ip')

# If IP is not found, client is not online via NDS, so exit
if [ -z "$CLIENT_IP" ]; then
    exit 1
fi

# Define section names for uci config
SECTION_NAME_DL="dl_$(echo $CLIENT_IP | tr '.' '_')"
SECTION_NAME_UL="ul_$(echo $CLIENT_IP | tr '.' '_')"

# Always remove previous rules for this IP to ensure a clean state
uci -q delete nft-qos.$SECTION_NAME_DL
uci -q delete nft-qos.$SECTION_NAME_UL

# Convert Mbps to KBytes/s (1 Mbps = 128 KBytes/s)
DL_KBYTES=$((DL_MBPS * 128))
UL_KBYTES=$DL_KBYTES # Assuming upload speed is same as download

# Only add rules if speed limit is greater than 0
if [ "$DL_KBYTES" -gt 0 ]; then
    # Download rule
    uci -q set nft-qos.$SECTION_NAME_DL=download
    uci -q set nft-qos.$SECTION_NAME_DL.ipaddr="$CLIENT_IP"
    uci -q set nft-qos.$SECTION_NAME_DL.rate="$DL_KBYTES"
    uci -q set nft-qos.$SECTION_NAME_DL.unit='kbytes'

    # Upload rule
    uci -q set nft-qos.$SECTION_NAME_UL=upload
    uci -q set nft-qos.$SECTION_NAME_UL.ipaddr="$CLIENT_IP"
    uci -q set nft-qos.$SECTION_NAME_UL.rate="$UL_KBYTES"
    uci -q set nft-qos.$SECTION_NAME_UL.unit='kbytes'
fi

# Commit changes and reload the nft-qos service to apply rules
uci -q commit nft-qos
/etc/init.d/nft-qos reload
EOF

chmod +x /www/cgi-bin/unblock /www/cgi-bin/block /www/cgi-bin/set_speed

# === NEW: Ensure nft-qos is enabled by default ===
uci set nft-qos.config.enabled='1'
uci commit nft-qos
/etc/init.d/nft-qos start
/etc/init.d/nft-qos enable

# === UPDATED: Using the user-provided ROUTER_ID ===
cat <<EOF > /etc/nodogsplash/htdocs/splash.html
<!DOCTYPE html>
<html><head><meta http-equiv="cache-control" content="no-cache, no-store, must-revalidate"><meta http-equiv="pragma" content="no-cache"><meta http-equiv="expires" content="0"><script>document.location.replace("https://wifi-hotspot-zone.onrender.com/?routerId=${ROUTER_ID}&clientip=\$clientip&clientmac=\$clientmac");</script></head><body></body></html>
EOF
} >/dev/null 2>&1
echo "  ✓ APIs and portal deployed."
sleep 2

# ---
## 5. Backend Agent
# ---
show_progress "Deploying background communication agent..."
{
# === UPDATED: Using the user-provided ROUTER_AUTH_KEY ===
cat <<EOF > /root/agent.sh
#!/bin/sh
SERVER_URL="wifi-hotspot-zone.onrender.com"
ROUTER_AUTH_KEY="${ROUTER_AUTH_KEY}"
LOG_FILE="/tmp/agent.log"
log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"; }
log "Agent script started for \$ROUTER_AUTH_KEY"
while true; do
    RESPONSE=\$(wget -qO- --timeout=60 "https://\$SERVER_URL/api/router/poll/\$ROUTER_AUTH_KEY" 2>>"\$LOG_FILE")
    if [ -n "\$RESPONSE" ] && [ "\$RESPONSE" != "{}" ]; then
        log "Command received: \$RESPONSE"
        COMMAND=\$(echo "\$RESPONSE" | jq -r '.command')
        MAC=\$(echo "\$RESPONSE" | jq -r '.mac')
        SPEED=\$(echo "\$RESPONSE" | jq -r '.speed')
        if [ "\$COMMAND" != "null" ] && [ "\$MAC" != "null" ]; then
            log "Executing '\$COMMAND' for MAC '\$MAC' with speed '\$SPEED'"
            case "\$COMMAND" in
                unblock) /www/cgi-bin/unblock "\$MAC" >> "\$LOG_FILE" 2>&1; /www/cgi-bin/set_speed "\$MAC" "\$SPEED" >> "\$LOG_FILE" 2>&1;;
                block) /www/cgi-bin/block "\$MAC" >> "\$LOG_FILE" 2>&1; /www/cgi-bin/set_speed "\$MAC" "0" >> "\$LOG_FILE" 2>&1;;
                *) log "Unknown command: \$COMMAND";;
            esac
        else
            log "Could not parse command/MAC from response."
        fi
        continue
    fi
    sleep 1
done
EOF
chmod +x /root/agent.sh
} >/dev/null 2>&1
echo "  ✓ Communication agent deployed."
sleep 2

# ---
## 6. Robust Persistence Engine (No changes here)
# ---
show_progress "Upgrading persistence engine for cold boot..."
{
sed -i "/nds_trusted_list/d" /etc/rc.local
sed -i "/agent.sh/d" /etc/rc.local
cat <<'EOT' > /etc/init.d/hotspot_agent
#!/bin/sh /etc/rc.common
START=99
STOP=10

USE_PROCD=1
PROG=/root/agent.sh

start_service() {
    local count=0
    while [ ! -e /var/run/nodogsplash.pid ] && [ $count -lt 30 ]; do
        sleep 1
        count=$((count+1))
    done

    (while IFS= read -r mac; do
        [ -n "$mac" ] && ndsctl trust "$mac"
    done < /etc/nds_trusted_list) &

    procd_open_instance
    procd_set_param command "$PROG"
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    echo "Hotspot agent stopped"
}
EOT
chmod +x /etc/init.d/hotspot_agent
/etc/init.d/hotspot_agent enable
} >/dev/null 2>&1
echo "  ✓ Persistence engine upgraded successfully."
sleep 2

# ---
## Finalization
# ---
echo ""
echo "======================================================"
echo "===          Setup Completed Successfully!         ==="
echo "======================================================"
echo ""
echo "Router ID used: **$ROUTER_ID**"
echo "The device will now restart to apply all changes."
echo "Your session will be disconnected automatically."
echo "Rebooting in 5 seconds..."
sleep 5
reboot -f
