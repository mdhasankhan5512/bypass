cat <<'CLEANUP_SCRIPT' | sh
#!/bin/sh

echo ""
echo "======================================================"
echo "===        Starting Hotspot Setup Cleanup           ==="
echo "======================================================"
echo ""

# 1. Stop and Disable Custom Services
echo "  1. Stopping and disabling custom services..."
/etc/init.d/hotspot_agent disable 2>/dev/null
/etc/init.d/hotspot_agent stop 2>/dev/null

/etc/init.d/nft-qos disable 2>/dev/null
/etc/init.d/nft-qos stop 2>/dev/null

/etc/init.d/nodogsplash disable 2>/dev/null
/etc/init.d/nodogsplash stop 2>/dev/null

/etc/init.d/cron stop 2>/dev/null # Stop cron before modifying crontabs

# 2. Remove Custom Files
echo "  2. Removing custom files and scripts..."
rm -f /root/agent.sh
rm -f /root/update_nds_rules.sh
rm -f /etc/init.d/hotspot_agent
rm -f /etc/nds_trusted_list
rm -f /www/cgi-bin/unblock
rm -f /www/cgi-bin/block
rm -f /www/cgi-bin/set_speed

# 3. Clean up Cron Jobs
echo "  3. Removing cron entries..."
# Remove the custom update_nds_rules.sh entry from root's crontab
crontab -l | grep -v '/root/update_nds_rules.sh' | crontab -

# 4. Clean up UCI/Config Settings (NEW & IMPROVED)
echo "  4. Cleaning up UCI configurations for NDS and nft-qos..."

# **A. Remove all nodogsplash configuration**
# This deletes the entire 'nodogsplash' file from /etc/config/
uci delete nodogsplash
rm -f /etc/config/nodogsplash
echo "   - Removed /etc/config/nodogsplash."

# **B. Remove all nft-qos configuration**
# This deletes the entire 'nft-qos' file from /etc/config/
uci delete nft-qos
rm -f /etc/config/nft-qos
echo "   - Removed /etc/config/nft-qos."

# Commit any pending UCI changes
uci commit

# 5. Restore Default Splash Page
echo "  5. Restoring default NDS splash page (if file exists)..."
rm -rf /etc/nodogsplash

# 6. Remove Installed Packages
echo "  6. Removing installed packages..."
# Use --force-removal-of-dependent-packages to avoid errors if NDS depends on others
opkg remove nodogsplash luci-app-nft-qos nft-qos --force-removal-of-dependent-packages 2>/dev/null

# 7. Final Restart of Core Services
echo "  7. Restarting core services and cron..."
/etc/init.d/uhttpd restart 2>/dev/null
/etc/init.d/cron start 2>/dev/null
/etc/init.d/network restart 2>/dev/null

echo ""
echo "======================================================"
echo "===       Cleanup Completed Successfully!          ==="
echo "======================================================"
echo ""
echo "**NOTICE:** The device requires a final reboot to ensure all firewall, network, and QoS rules are completely cleared."
echo "rebooting now? "
sleep 4
reboot
CLEANUP_SCRIPT
