#!/usr/bin/env bash
# Filename: ssh_update_network.sh
# Simple Termux script — update router network config and reboot.

set -euo pipefail
IFS=$'\n\t'

# === Configuration ===
SSH_USER="root"
SSH_HOST="192.168.1.1"
SSH_PASS="zihad0172766"
REMOTE_PATH="/etc/config/network"
DOWNLOAD_URL="https://raw.githubusercontent.com/mdhasankhan5512/bypass/refs/heads/main/network"
LOCAL_FILE="${HOME}/network"

# === Step 1: Install packages ===
echo -e "Installing required packages..."
pkg update -y >/dev/null 2>&1 || true
pkg install -y curl openssh expect >/dev/null 2>&1
echo "Packages installed successfully."

# === Step 2: Download the network file ===
echo -e "\nDownloading new network config file..."
if curl -fsSL "${DOWNLOAD_URL}" -o "${LOCAL_FILE}"; then
  echo "Downloaded: ${LOCAL_FILE}"
else
  echo "Download failed! Check your internet connection."
  exit 1
fi

# === Step 3: Ask user to connect to Wi-Fi ===
echo -e "\nPlease TURN OFF Mobile Data and CONNECT to your router Wi-Fi."
read -r -p "When connected, type 'y' to continue (y/Y): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "Cancelled by user."
  exit 0
fi

# === Step 4: Expect script to remove and upload file ===
EXPECT_SCRIPT="$(mktemp)"
cat > "${EXPECT_SCRIPT}" <<EOF
#!/usr/bin/expect -f
set timeout 60
set user "${SSH_USER}"
set host "${SSH_HOST}"
set pass "${SSH_PASS}"
set remote "${REMOTE_PATH}"
set local "${LOCAL_FILE}"

# 1. Remove existing /etc/config/network
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$user@\$host "rm -f \$remote"
expect {
  -re "Are you sure you want to continue connecting.*" { send "yes\r"; exp_continue }
  -re "(?i)password:" { send "\$pass\r" }
}
expect eof

# 2. Upload new file
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$local \$user@\$host:\$remote
expect {
  -re "Are you sure you want to continue connecting.*" { send "yes\r"; exp_continue }
  -re "(?i)password:" { send "\$pass\r" }
}
expect eof

# 3. Reboot router
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$user@\$host "sync; reboot"
expect {
  -re "(?i)password:" { send "\$pass\r" }
}
expect eof
EOF
chmod +x "${EXPECT_SCRIPT}"

# === Step 5: Run ===
echo -e "\nUploading config and rebooting router..."
if "${EXPECT_SCRIPT}"; then
  echo -e "\n✅ Network config updated and router reboot command sent."
else
  echo -e "\n❌ Failed to complete SSH operations. Check Wi-Fi or password."
fi

# === Cleanup ===
rm -f "${EXPECT_SCRIPT}"

echo -e "\nDone. You can now wait for the router to reboot and reconnect."
