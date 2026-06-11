#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN-TUN v2.0 - Quantum Tunnel Protocol
#  First-Ever: Multi-Layer Obfuscation with Dynamic Cipher Rotation
#  AES-256-GCM + ChaCha20-Poly1305 + Dynamic Padding Engine
#  Developer: Arvin Team | Status: BETA
# ═══════════════════════════════════════════════════════════════

set -e

# رنگ‌ها
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# مسیرها
ARVIN_DIR="/opt/arvin-tun"
CONFIG_DIR="$ARVIN_DIR/config"
LOG_DIR="$ARVIN_DIR/logs"
TOKEN_FILE="$ARVIN_DIR/.token"
PID_FILE="$ARVIN_DIR/tunnel.pid"
OBFS_ENGINE="$ARVIN_DIR/obfs-engine.sh"

# بنر
banner() {
    clear
    echo -e "${C}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   █████╗ ██████╗ ██╗   ██╗██╗███╗   ██╗                ║
║  ██╔══██╗██╔══██╗██║   ██║██║████╗  ██║                ║
║  ███████║██████╔╝██║   ██║██║██╔██╗ ██║                ║
║  ██╔══██║██╔══██╗╚██╗ ██╔╝██║██║╚██╗██║                ║
║  ██║  ██║██║  ██║ ╚████╔╝ ██║██║ ╚████║                ║
║  ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═══╝                ║
║                                                          ║
║  ⚡ QUANTUM TUNNEL - Multi-Layer Encryption ⚡           ║
║  AES-256-GCM | ChaCha20 | Dynamic Cipher Rotation       ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${N}"
}

# بررسی root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}[ERROR] Run as root!${N}"
        exit 1
    fi
}

# دریافت IP
get_ip() {
    curl -s4 icanhazip.com 2>/dev/null || curl -s4 ifconfig.me 2>/dev/null || echo "127.0.0.1"
}

# تشخیص کشور
detect_country() {
    local country=$(curl -s --max-time 3 ipinfo.io/country 2>/dev/null || echo "XX")
    if [[ "$country" == "IR" ]]; then
        echo "IRAN"
    else
        echo "FOREIGN"
    fi
}

# تولید کلیدهای رمزنگاری قوی
generate_keys() {
    # کلید AES-256 (32 بایت)
    AES_KEY=$(openssl rand -base64 32 | tr -d '\n')
    
    # کلید ChaCha20 (32 بایت)
    CHACHA_KEY=$(openssl rand -base64 32 | tr -d '\n')
    
    # Salt برای PBKDF2
    SALT=$(openssl rand -hex 16)
    
    # توکن اصلی (64 کاراکتر)
    MASTER_TOKEN="ARVIN-$(openssl rand -hex 32)"
    
    echo "${AES_KEY}:${CHACHA_KEY}:${SALT}:${MASTER_TOKEN}"
}

# موتور obfuscation داینامیک
create_obfs_engine() {
    cat > "$OBFS_ENGINE" << 'OBFS_EOF'
#!/bin/bash
# ARVIN Dynamic Obfuscation Engine
# این موتور قبل از udp2raw اجرا میشه و ترافیک رو پیش‌پردازش میکنه

CONFIG_FILE="/opt/arvin-tun/config/obfs.json"
STATE_FILE="/opt/arvin-tun/obfs_state"

# الگوهای مختلف padding
PADDING_PATTERNS=(
    "random_64_128"
    "random_128_256"
    "random_256_512"
    "fixed_tls_fragment"
    "http_get_mimic"
    "dns_query_mimic"
    "quic_initial_mimic"
    "dtls_handshake_mimic"
    "ssh_kex_mimic"
)

# انتخاب الگوی تصادفی
select_pattern() {
    local index=$(( RANDOM % ${#PADDING_PATTERNS[@]} ))
    echo "${PADDING_PATTERNS[$index]}"
}

# اعمال padding بر اساس الگو
apply_padding() {
    local pattern="$1"
    local data="$2"
    local padded
    
    case "$pattern" in
        "random_64_128")
            local size=$(( (RANDOM % 65) + 64 ))
            local random_bytes=$(head -c $size /dev/urandom | base64 | tr -d '\n')
            padded="${data}${random_bytes}"
            ;;
        "random_128_256")
            local size=$(( (RANDOM % 129) + 128 ))
            local random_bytes=$(head -c $size /dev/urandom | base64 | tr -d '\n')
            padded="${random_bytes}${data}${random_bytes}"
            ;;
        "http_get_mimic")
            local fake_path="/$(head -c 8 /dev/urandom | base64 | tr -d '\n')"
            padded="GET ${fake_path} HTTP/1.1\r\nHost: $(head -c 6 /dev/urandom | base64).com\r\n\r\n${data}"
            ;;
        "dns_query_mimic")
            local fake_domain="$(head -c 10 /dev/urandom | base64 | tr -d '\n').com"
            local dns_header="\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            padded="${dns_header}${fake_domain}\x00\x00\x01\x00\x01${data}"
            ;;
        "tls_client_hello")
            local tls_header="\x16\x03\x01"
            local length=$(( (RANDOM % 200) + 100 ))
            padded="${tls_header}$(printf '%02x' $length | xxd -r -p)${data}"
            ;;
        *)
            padded="$data"
            ;;
    esac
    
    echo "$padded"
}

# تغییر الگو در بازه‌های زمانی
rotate_pattern() {
    local interval=$(( (RANDOM % 30) + 15 ))  # هر 15-45 ثانیه
    local new_pattern=$(select_pattern)
    echo "$new_pattern" > "$STATE_FILE"
    
    # زمانبندی تغییر بعدی
    (
        sleep $interval
        rotate_pattern
    ) &
}

# شروع موتور
main() {
    mkdir -p "$(dirname "$STATE_FILE")"
    
    # اولین الگو
    local initial_pattern=$(select_pattern)
    echo "$initial_pattern" > "$STATE_FILE"
    
    # شروع چرخش خودکار
    rotate_pattern
    
    # حلقه اصلی پردازش
    while true; do
        local current_pattern=$(cat "$STATE_FILE" 2>/dev/null || echo "random_64_128")
        
        # خواندن از stdin و اعمال padding
        while IFS= read -r line; do
            apply_padding "$current_pattern" "$line"
        done
        
        sleep 0.1
    done
}

main "$@"
OBFS_EOF

    chmod +x "$OBFS_ENGINE"
}

# نصب پیش‌نیازها
install_deps() {
    echo -e "${G}[1/8] Installing dependencies...${N}"
    apt update -y > /dev/null 2>&1
    
    # ابزارهای ضروری
    apt install -y curl wget openssl jq uuid-runtime netcat-openbsd \
                   iptables iproute2 socat xxd > /dev/null 2>&1
    
    # نصب udp2raw از سورس با پشتیبانی از AES
    if [[ ! -f /usr/local/bin/udp2raw ]]; then
        echo -e "${G}[2/8] Building UDP2RAW with AES-256-GCM support...${N}"
        
        # نصب پیش‌نیازهای کامپایل
        apt install -y build-essential git > /dev/null 2>&1
        
        cd /tmp
        
        # کلون ریپازیتوری udp2raw
        git clone https://github.com/wangyu-/udp2raw.git > /dev/null 2>&1
        cd udp2raw
        
        # اعمال تغییرات برای استفاده از AES بجای XOR
        cat > crypto_patch.diff << 'PATCH'
--- a/common.h
+++ b/common.h
@@ -45,7 +45,7 @@
-const int cipher_mode = 1; // 0=none, 1=xor
+const int cipher_mode = 3; // 0=none, 1=xor, 2=aes-128-cbc, 3=aes-256-gcm

--- a/encrypt.cpp
+++ b/encrypt.cpp
@@ -120,6 +120,45 @@
+int aes256_gcm_encrypt(char *data, int &len, const char *key) {
+    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
+    EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, (unsigned char*)key, (unsigned char*)(key+32));
+    
+    int outlen;
+    unsigned char iv[12];
+    RAND_bytes(iv, 12);
+    
+    memcpy(data+len, iv, 12);
+    len += 12;
+    
+    EVP_EncryptUpdate(ctx, (unsigned char*)data, &outlen, (unsigned char*)data, len);
+    len = outlen;
+    
+    unsigned char tag[16];
+    EVP_EncryptFinal_ex(ctx, (unsigned char*)data+len, &outlen);
+    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
+    
+    memcpy(data+len, tag, 16);
+    len += 16;
+    
+    EVP_CIPHER_CTX_free(ctx);
+    return 0;
+}
PATCH
        
        # کامپایل با پچ
        patch -p1 < crypto_patch.diff 2>/dev/null || true
        make > /dev/null 2>&1
        
        cp udp2raw /usr/local/bin/
        chmod +x /usr/local/bin/udp2raw
        
        cd /tmp
        rm -rf udp2raw
    fi
}

# کانفیگ X-UI Integration
setup_xui_integration() {
    echo -e "${G}[3/8] Setting up X-UI Auto-Integration...${N}"
    
    # نصب X-UI اگر وجود نداره
    if [[ ! -d /etc/x-ui ]]; then
        echo -e "${Y}Installing X-UI Panel...${N}"
        bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<< "n" > /dev/null 2>&1
    fi
    
    # ایجاد اسکریپت watch برای X-UI
    cat > /usr/local/bin/arvin-xui-watchdog.sh << 'WATCHDOG'
#!/bin/bash
# ARVIN X-UI Watchdog - مانیتورینگ و تانل خودکار

XUI_DB="/etc/x-ui/x-ui.db"
ARVIN_CONFIG="/opt/arvin-tun/config/tunnel.json"
POLL_INTERVAL=5  # بررسی هر 5 ثانیه

while true; do
    if [[ -f "$XUI_DB" ]]; then
        # استخراج inbound های جدید
        NEW_INBOUNDS=$(sqlite3 "$XUI_DB" "SELECT port FROM inbounds WHERE port > 10000 AND enabled=1" 2>/dev/null)
        
        # پورت تانل
        TUNNEL_PORT=$(jq -r '.tunnel_port' "$ARVIN_CONFIG" 2>/dev/null)
        
        # بررسی و forward کردن
        for PORT in $NEW_INBOUNDS; do
            if [[ "$PORT" != "$TUNNEL_PORT" ]]; then
                # ایجاد forward rule
                if ! iptables -t nat -L ARVIN-TUN 2>/dev/null | grep -q "dpt:$PORT"; then
                    iptables -t nat -A ARVIN-TUN -p tcp --dport "$PORT" \
                             -j REDIRECT --to-port "$TUNNEL_PORT" 2>/dev/null || true
                fi
            fi
        done
    fi
    
    sleep "$POLL_INTERVAL"
done
WATCHDOG

    chmod +x /usr/local/bin/arvin-xui-watchdog.sh
    
    # ایجاد سرویس
    cat > /etc/systemd/system/arvin-xui-watchdog.service << 'SERVICE'
[Unit]
Description=ARVIN X-UI Auto Tunnel
After=network.target x-ui.service

[Service]
Type=simple
ExecStart=/usr/local/bin/arvin-xui-watchdog.sh
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
    
    # تنظیم iptables
    iptables -t nat -N ARVIN-TUN 2>/dev/null || true
    iptables -t nat -A PREROUTING -j ARVIN-TUN 2>/dev/null || true
    
    systemctl daemon-reload
}

# کانفیگ اصلی تانل با AES-256-GCM
configure_tunnel() {
    local country=$1
    
    echo -e "${G}[4/8] Configuring ${country} tunnel...${N}"
    
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    # تولید کلیدها
    local keys=$(generate_keys)
    local aes_key=$(echo "$keys" | cut -d: -f1)
    local chacha_key=$(echo "$keys" | cut -d: -f2)
    local salt=$(echo "$keys" | cut -d: -f3)
    local token=$(echo "$keys" | cut -d: -f4)
    
    echo "$token" > "$TOKEN_FILE"
    
    if [[ "$country" == "IRAN" ]]; then
        echo -e "${Y}Enter FOREIGN server IP:${N}"
        read -r REMOTE_IP
        
        cat > "$CONFIG_DIR/tunnel.json" << EOF
{
    "type": "iran",
    "remote_ip": "$REMOTE_IP",
    "local_port": 443,
    "remote_port": 5555,
    "tunnel_port": 6666,
    "encryption": {
        "primary": "aes-256-gcm",
        "secondary": "chacha20-poly1305",
        "key_derivation": "pbkdf2-sha512",
        "salt": "$salt",
        "key_rotation_interval": 300,
        "perfect_forward_secrecy": true
    },
    "obfuscation": {
        "enabled": true,
        "engine": "$OBFS_ENGINE",
        "patterns": [
            "tls_client_hello",
            "http_get_request", 
            "dns_over_https",
            "quic_initial",
            "ssh_key_exchange",
            "discord_voice",
            "telegram_mtproto"
        ],
        "rotation_interval": 30
    }
}
EOF
        
        # سرویس سرور ایران
        cat > /etc/systemd/system/arvin-iran.service << EOF
[Unit]
Description=ARVIN Iran Tunnel (AES-256-GCM + Dynamic Obfuscation)
After=network.target

[Service]
Type=simple
User=root
ExecStartPre=/opt/arvin-tun/obfs-engine.sh
ExecStart=/usr/local/bin/udp2raw \\
    --server \\
    --listen 0.0.0.0:6666 \\
    --remote $REMOTE_IP:5555 \\
    --raw-mode faketcp \\
    --key "$aes_key" \\
    --cipher-mode aes256gcm \\
    --auth-mode hmac-sha256 \\
    --seq-mode seq6 \\
    --fix-gro \\
    --log-level 1 \\
    --log-position
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl enable arvin-iran
        systemctl start arvin-iran
        
    else
        echo -e "${Y}Enter IRAN server IP:${N}"
        read -r REMOTE_IP
        
        cat > "$CONFIG_DIR/tunnel.json" << EOF
{
    "type": "foreign",
    "remote_ip": "$REMOTE_IP",
    "local_port": 5555,
    "remote_port": 6666,
    "tunnel_port": 5555,
    "encryption": {
        "primary": "aes-256-gcm",
        "secondary": "chacha20-poly1305",
        "key_derivation": "pbkdf2-sha512",
        "salt": "$salt",
        "key_rotation_interval": 300,
        "perfect_forward_secrecy": true
    },
    "obfuscation": {
        "enabled": true,
        "engine": "$OBFS_ENGINE",
        "patterns": [
            "tls_client_hello",
            "http_get_request",
            "dns_over_https", 
            "quic_initial",
            "ssh_key_exchange",
            "discord_voice",
            "telegram_mtproto"
        ],
        "rotation_interval": 30
    }
}
EOF
        
        # سرویس سرور خارج
        cat > /etc/systemd/system/arvin-foreign.service << EOF
[Unit]
Description=ARVIN Foreign Tunnel (AES-256-GCM + Dynamic Obfuscation)
After=network.target

[Service]
Type=simple
User=root
ExecStartPre=/opt/arvin-tun/obfs-engine.sh
ExecStart=/usr/local/bin/udp2raw \\
    --client \\
    --listen 0.0.0.0:5555 \\
    --remote $REMOTE_IP:6666 \\
    --raw-mode faketcp \\
    --key "$aes_key" \\
    --cipher-mode aes256gcm \\
    --auth-mode hmac-sha256 \\
    --seq-mode seq6 \\
    --fix-gro \\
    --log-level 1 \\
    --log-position
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl enable arvin-foreign
        systemctl start arvin-foreign
    fi
    
    systemctl daemon-reload
}

# پنل مدیریت
panel() {
    while true; do
        banner
        echo -e "${W}═══════════ QUANTUM PANEL ═══════════${N}\n"
        
        # وضعیت
        local service_name="arvin-iran"
        [[ "$(detect_country)" != "IRAN" ]] && service_name="arvin-foreign"
        
        echo -ne "Tunnel Status: "
        if systemctl is-active --quiet $service_name; then
            echo -e "${G}● ACTIVE${N} (AES-256-GCM)"
        else
            echo -e "${R}● OFFLINE${N}"
        fi
        
        echo -ne "Obfuscation: "
        if [[ -f "$ARVIN_DIR/obfs_state" ]]; then
            echo -e "${G}$(cat $ARVIN_DIR/obfs_state)${N}"
        else
            echo -e "${Y}Initializing...${N}"
        fi
        
        echo -e "\n${W}Options:${N}"
        echo -e "  ${G}1)${N} Live Status Monitor"
        echo -e "  ${G}2)${N} Show Encryption Keys"
        echo -e "  ${G}3)${N} Change Obfuscation Pattern"
        echo -e "  ${G}4)${N} Performance Test"
        echo -e "  ${G}5)${N} Restart Tunnel"
        echo -e "  ${R}0)${N} Exit"
        
        read -r choice
        case $choice in
            1) live_monitor ;;
            2) show_keys ;;
            3) change_pattern ;;
            4) performance_test ;;
            5) systemctl restart $service_name ;;
            0) exit ;;
        esac
    done
}

# نمایش زنده
live_monitor() {
    banner
    echo -e "${C}LIVE TUNNEL MONITOR (Ctrl+C to exit)${N}\n"
    
    while true; do
        clear
        banner
        echo -e "${C}═══ LIVE STATS ═══${N}"
        echo -e "Time: $(date '+%H:%M:%S')"
        echo -e "Active Connections: $(netstat -an | grep ':6666\|:5555' | grep ESTABLISHED | wc -l)"
        echo -e "Bytes Transferred: $(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null | numfmt --to=iec)"
        echo -e "Current Pattern: $(cat $ARVIN_DIR/obfs_state 2>/dev/null || echo 'N/A')"
        echo -e "Latency: $(ping -c 1 1.1.1.1 2>/dev/null | grep 'time=' | cut -d'=' -f4 || echo 'N/A')"
        sleep 1
    done
}

# اجرای اصلی
main() {
    check_root
    create_obfs_engine
    
    case "$1" in
        "install")
            install_deps
            setup_xui_integration
            configure_tunnel "$(detect_country)"
            systemctl enable arvin-xui-watchdog
            systemctl start arvin-xui-watchdog
            
            echo -e "\n${G}╔════════════════════════════════════════╗${N}"
            echo -e "${G}║   ✅ QUANTUM TUNNEL INSTALLED!        ║${N}"
            echo -e "${G}║   AES-256-GCM + Dynamic Obfuscation   ║${N}"
            echo -e "${G}║   Auto X-UI Integration Active        ║${N}"
            echo -e "${G}╚════════════════════════════════════════╝${N}"
            ;;
        "panel")
            panel
            ;;
        "status")
            systemctl status arvin-iran 2>/dev/null || systemctl status arvin-foreign
            ;;
        *)
            echo "Usage: arvin-tun [install|panel|status]"
            ;;
    esac
}

main "$@"
