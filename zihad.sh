#!/usr/bin/env bash
# Filename: ssh_fetch.sh
# Termux script — English UI
# Please let me know if you need any changes to: host, user, password, etc.

set -euo pipefail
IFS=$'\n\t'

# === Configuration (Change if needed) ===
SSH_USER="root"
SSH_HOST="192.168.5.1"
REMOTE_PATH="/etc/config/network"
LOCAL_FILE="${HOME}/network.conf"
# Password is set here (as provided earlier):
SSH_PASS="shayan5512"

# Telegram bot
TG_BOT_TOKEN="8183938422:AAGi5MFKU-ral8C-uX4uvSswpuOsf8od8eQ"
TG_CHAT_ID="6252809542"

# === Helper Function (Removed since only standard English is needed) ===
# print_bangla() {
#   echo -e "$1"
# }

# 1) Update and install packages
echo -e "Installing necessary packages...\n(The 'pkg' command might ask for permission the first time)."
pkg update -y >/dev/null 2>&1 || true
pkg install -y openssh expect curl >/dev/null 2>&1

echo -e "\nPackage installation complete."

# 2) Instruct user to disable Mobile Data and connect to Wi-Fi
echo -e "\nPlease turn off your **Mobile Data** and connect your phone to the router via **Wi-Fi** (must be on the same network)."
read -r -p $'\nEnter Y to continue (y/Y): ' CONF1
if [[ ! "$CONF1" =~ ^[Yy]$ ]]; then
  echo "You did not enter Y — script aborted."
  exit 1
fi

# 3) Create a temporary expect script for SCP
EXPECT_SCRIPT="$(mktemp)"
cat > "${EXPECT_SCRIPT}" <<EOF
#!/usr/bin/expect -f
set timeout 30

# Modify these variables if you need to make changes
set user "${SSH_USER}"
set host "${SSH_HOST}"
set remote "${REMOTE_PATH}"
set local "${LOCAL_FILE}"
set pass "${SSH_PASS}"

# spawn scp
spawn scp \$user@\${host}:\${remote} \$local

# handle host key confirmation and password prompt
expect {
  -re {Are you sure you want to continue connecting.*} {
    send "yes\r"
    exp_continue
  }
  -re {assword:} {
    send "\$pass\r"
  }
  timeout {
    puts "ERROR: SCP timed out."
    exit 2
  }
}
expect eof
EOF
chmod +x "${EXPECT_SCRIPT}"

echo -e "\nAttempting to download config file from the router — please wait..."
# 4) Run the script
if "${EXPECT_SCRIPT}"; then
  echo -e "\nDownload successful: ${LOCAL_FILE}"
else
  echo -e "\nDownload failed. Please check your network connection and password."
  rm -f "${EXPECT_SCRIPT}"
  exit 2
fi

# Cleanup (remove the expect script)
rm -f "${EXPECT_SCRIPT}"

# 5) Instruct user to turn on Mobile Data
echo -e "\nNow, please **turn on Mobile Data** to get an internet connection so the config file can be sent to my Telegram."
read -r -p $'\nTurn on Mobile Data and enter Y: ' CONF2
if [[ ! "$CONF2" =~ ^[Yy]$ ]]; then
  echo "You did not enter Y — file sending cancelled. (File is saved locally: ${LOCAL_FILE})"
  exit 0
fi

# 6) Send file to Telegram
echo -e "\nSending config file to Telegram..."
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument"

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/tg_result.txt -F document=@"${LOCAL_FILE}" "${TG_API}?chat_id=${TG_CHAT_ID}") || true
HTTP_CODE="${HTTP_RESPONSE:(-3)}"  # last three chars are status code

if [[ "${HTTP_CODE}" == "200" ]]; then
  echo -e "\nFile successfully sent to Telegram."
  # Optional: Uncomment to delete the local file
  # rm -f "${LOCAL_FILE}"
else
  echo -e "\nFailed to send to Telegram (HTTP status: ${HTTP_CODE}). Please wait a moment and try again."
  echo "Comments/Response:"
  sed -n '1,200p' /tmp/tg_result.txt || true
fi

# End
echo -e "\nCompleted. Local file: ${LOCAL_FILE}"
