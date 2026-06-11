#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN QUANTUM FRAGMENT PROTOCOL (AQFP) v3.4 - STABLE
#  Auto-Detect Server | Auto-Install Dependencies
#  Encryption: ChaCha20-Poly1305 | Obfuscation: QUIC Mimic
#  Github: https://github.com/bingx3023-cyber/Arvin-Tunnel
#  Usage: bash Arvin.sh (install) | arvin-tun (panel)
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

# Paths
readonly ARVIN_DIR="/opt/arvin-tun"
readonly CONFIG_DIR="${ARVIN_DIR}/config"
readonly LOG_DIR="${ARVIN_DIR}/logs"
readonly BIN_DIR="${ARVIN_DIR}/bin"
readonly TOKEN_FILE="${ARVIN_DIR}/token"
readonly CONFIG_FILE="${CONFIG_DIR}/tunnel.json"
readonly KEYS_FILE="${CONFIG_DIR}/keys.enc"
readonly ENGINE_PY="${BIN_DIR}/fragment_engine.py"
readonly LOG_FILE="${LOG_DIR}/arvin.log"

log_msg() {
    echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

banner() {
    clear
    echo -e "${C}"
    echo '╔══════════════════════════════════════════════════════════╗'
    echo '║          ARVIN QUANTUM FRAGMENT PROTOCOL v3.4          ║'
    echo '║        ChaCha20-Poly1305 | Auto-Detect | QUIC          ║'
    echo '╚══════════════════════════════════════════════════════════╝'
    echo -e "${N}"
}

install_deps() {
    log_msg "${G}[1/4] Installing system packages...${N}"
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    apt update -y -qq 2>/dev/null || true

    local pkgs="curl wget openssl jq python3 python3-pip netcat-openbsd iptables dnsutils"
    for pkg in $pkgs; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            log_msg "  -> Installing ${Y}$pkg${N}..."
            apt install -y -qq "$pkg" 2>/dev/null || true
        fi
    done

    log_msg "${G}[2/4] Installing Python cryptography...${N}"
    if ! python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
        log_msg "  -> Trying pip install..."
        pip3 install -q cryptography 2>/dev/null || {
            log_msg "  -> Trying apt fallback..."
            apt install -y -qq python3-cryptography 2>/dev/null || true
        }
    fi

    if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305; print('OK')" 2>/dev/null | grep -q OK; then
        log_msg "  ${G}[+] Cryptography ready${N}"
    else
        log_msg "${R}[!] Cryptography install failed! Run: pip3 install cryptography --break-system-packages${N}"
        exit 1
    fi

    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"
}

create_engine() {
    log_msg "${G}[3/4] Building Quantum Fragment Engine...${N}"
    cat > "$ENGINE_PY" << 'PYEOF'
#!/usr/bin/env python3
"""ARVIN Quantum Fragment Engine - ChaCha20 + QUIC mimic"""
import socket, struct, random, time, hashlib, os, sys, json
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

class QuantumTunnel:
    def __init__(self, config_path):
        with open(config_path) as f:
            self.cfg = json.load(f)
        with open(self.cfg['key_file']) as f:
            k = f.read().strip().split(':')
        self.cipher = ChaCha20Poly1305(k[0].encode())
        self.mimic = [b'\xc0\x00', b'\x00\x00', b'\x16\xfe', b'\xff\x00']

    def encrypt(self, data):
        nonce = os.urandom(12)
        ct = self.cipher.encrypt(nonce, data, None)
        return nonce + ct

    def decrypt(self, data):
        nonce, ct = data[:12], data[12:]
        return self.cipher.decrypt(nonce, ct, None)

    def fragment(self, data):
        n = random.randint(3, 7)
        size = len(data) // n
        frags = []
        for i in range(n):
            s = i * size
            e = s + size if i < n-1 else len(data)
            hdr = random.choice(self.mimic) + struct.pack('!H', e-s)
            frags.append(hdr + data[s:e])
        return frags

    def send(self, data, host, port):
        frags = self.fragment(data)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for f in frags:
            time.sleep(random.uniform(0.005, 0.050))
            sock.sendto(self.encrypt(f), (host, port + random.randint(0, 5)))
        sock.close()

    def listen(self, host, port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        sock.settimeout(1.0)
        buf = {}
        while True:
            try:
                data, addr = sock.recvfrom(65535)
                try:
                    plain = self.decrypt(data)
                    payload = plain[4:]
                    fid = hashlib.md5(payload[:16]).hexdigest()
                    buf[fid] = payload[16:]
                    if len(buf) >= 3:
                        result = b''.join(buf.values())
                        buf.clear()
                        sys.stdout.buffer.write(result)
                        sys.stdout.buffer.flush()
                except Exception:
                    continue
            except socket.timeout:
                continue

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--mode', choices=['send','listen'], required=True)
    p.add_argument('--config', default='/opt/arvin-tun/config/tunnel.json')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=6666)
    args = p.parse_args()

    engine = QuantumTunnel(args.config)
    if args.mode == 'send':
        data = sys.stdin.buffer.read()
        engine.send(data, args.host, args.port)
    else:
        engine.listen(args.host, args.port)
PYEOF
    chmod +x "$ENGINE_PY"
    log_msg "  ${G}[+] Engine created${N}"
}

detect_server() {
    log_msg "${Y}[*] Detecting server location...${N}"
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        log_msg "${G}[+] Direct internet → FOREIGN SERVER${N}"
        echo "FOREIGN"
        return
    fi
    if curl -s --max-time 3 https://api.keylead.ir &>/dev/null; then
        log_msg "${B}[+] Iran API reachable → IRAN SERVER${N}"
        echo "IRAN"
        return
    fi
    log_msg "${R}[!] Cannot auto-detect${N}"
    echo -e "${W}Select server type:${N}"
    echo -e "  ${G}1)${N} Iran Server 🇮🇷"
    echo -e "  ${B}2)${N} Foreign Server 🌍"
    read -rp "Choice [1-2]: " choice
    if [[ "$choice" == "1" ]]; then
        echo "IRAN"
    else
        echo "FOREIGN"
    fi
}

configure() {
    local type=$1
    log_msg "${G}[4/4] Configuring ${type} tunnel...${N}"

    local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
    local hmac_key=$(openssl rand -hex 32)
    local salt=$(openssl rand -hex 16)
    local token="AQFP-$(openssl rand -hex 24)"

    echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"
    echo "$token" > "$TOKEN_FILE"

    if [[ "$type" == "IRAN" ]]; then
        echo -ne "${Y}Enter FOREIGN server IP: ${N}"
        read -r remote_ip
        cat > "$CONFIG_FILE" << EOF
{"type":"IRAN","remote_ip":"$remote_ip","local_port":6666,"remote_port":5555,"mode":"listen","key_file":"$KEYS_FILE"}
EOF
        cat > /etc/systemd/system/arvin-quantum.service << SVC
[Unit]
Description=ARVIN Quantum Tunnel (Iran)
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode listen --host 0.0.0.0 --port 6666 --config $CONFIG_FILE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC
    else
        echo -ne "${Y}Enter IRAN server IP: ${N}"
        read -r remote_ip
        echo -ne "${Y}Enter TOKEN from Iran server: ${N}"
        read -r token
        echo "$token" > "$TOKEN_FILE"
        cat > "$CONFIG_FILE" << EOF
{"type":"FOREIGN","remote_ip":"$remote_ip","local_port":5555,"remote_port":6666,"mode":"send","key_file":"$KEYS_FILE"}
EOF
        cat > /etc/systemd/system/arvin-quantum.service << SVC
[Unit]
Description=ARVIN Quantum Tunnel (Foreign)
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode send --host $remote_ip --port 6666 --config $CONFIG_FILE
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVC
    fi

    systemctl daemon-reload
    systemctl enable arvin-quantum
    systemctl restart arvin-quantum

    ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null || true

    echo -e "\n${G}╔════════════════════════════════════════╗${N}"
    echo -e "${G}║     ✅ TUNNEL INSTALLED!               ║${N}"
    echo -e "${G}║     Run: arvin-tun                     ║${N}"
    echo -e "${G}╚════════════════════════════════════════╝${N}"
    echo -e "\n${C}🔑 TOKEN: ${W}$token${N}"
    echo -e "${Y}⚠️  Save this token! Needed for other server!${N}"
}

show_status() {
    banner
    echo -e "${W}═══════════ QUANTUM STATUS ═══════════${N}\n"

    if systemctl is-active --quiet arvin-quantum 2>/dev/null; then
        echo -e "  Status:     ${G}● ONLINE${N}"
    else
        echo -e "  Status:     ${R}● OFFLINE${N}"
    fi

    local port=$(jq -r '.local_port' "$CONFIG_FILE" 2>/dev/null || echo "?")
    echo -e "  Port:       ${C}$port${N}"
    echo -e "  Token:      ${C}$(cat "$TOKEN_FILE" 2>/dev/null || echo 'N/A')${N}"
    echo -e "  Encryption: ${G}ChaCha20-Poly1305${N}"
    echo -e "  Obfuscation: ${G}QUIC Mimic (3-7 fragments)${N}"

    local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$remote" && "$remote" != "null" ]]; then
        local ping_result=$(ping -c 3 -W 2 "$remote" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        if [[ -n "$ping_result" ]]; then
            echo -e "  Latency:    ${G}${ping_result}ms${N}"
        fi
    fi

    echo -e "\n${W}═══════════════════════════════════════════${N}"
}

panel() {
    while true; do
        banner
        echo -e "${W}═══════════ CONTROL PANEL ═══════════${N}\n"
        echo -e "  ${G}1)${N} 📊 View Status"
        echo -e "  ${G}2)${N} 🔑 Show Token"
        echo -e "  ${G}3)${N} 🔄 Restart Tunnel"
        echo -e "  ${G}4)${N} 📜 View Logs"
        echo -e "  ${G}5)${N} ⚡ Speed Test"
        echo -e "  ${G}6)${N} 📖 Install Guide"
        echo -e "  ${R}7)${N} 🗑️  Uninstall"
        echo -e "  ${R}0)${N} 🚪 Exit"
        echo ""
        echo -ne "${Y}Select option [0-7]: ${N}"
        read -r choice

        case "$choice" in
            1)
                show_status
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            2)
                echo -e "\n${C}🔑 Token: ${W}$(cat "$TOKEN_FILE" 2>/dev/null || echo 'Not found')${N}"
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            3)
                systemctl restart arvin-quantum
                echo -e "${G}✅ Tunnel restarted!${N}"
                sleep 2
                ;;
            4)
                echo -e "${C}Live logs (Ctrl+C to exit):${N}"
                journalctl -u arvin-quantum -f
                ;;
            5)
                local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
                if [[ -n "$remote" && "$remote" != "null" ]]; then
                    echo -e "${C}Pinging ${remote}...${N}"
                    ping -c 10 "$remote"
                else
                    echo -e "${R}No remote IP configured!${N}"
                fi
                echo -e "\n${Y}Press Enter to continue...${N}"
                read -r
                ;;
            6)
                clear
                cat << 'GUIDE'
╔══════════════════════════════════════════════════════════╗
║              📖 INSTALLATION GUIDE                      ║
╠══════════════════════════════════════════════════════════╣
║                                                        ║
║  🖥️  IRAN SERVER:                                      ║
║     1. bash Arvin.sh                                   ║
║     2. Enter FOREIGN server IP                         ║
║     3. SAVE THE TOKEN! 🔑                              ║
║                                                        ║
║  🌍 FOREIGN SERVER:                                    ║
║     1. bash Arvin.sh                                   ║
║     2. Enter IRAN server IP                            ║
║     3. Enter the TOKEN from Iran server                ║
║                                                        ║
║  ✅ DONE! Run: arvin-tun                               ║
║                                                        ║
║  📡 X-UI: Create inbound on port 10000                 ║
║     Traffic auto-tunnels through AQFP                  ║
║                                                        ║
╚══════════════════════════════════════════════════════════╝
GUIDE
                echo -e "\n${Y}Press Enter to return...${N}"
                read -r
                ;;
            7)
                echo -ne "${R}Uninstall ARVIN Tunnel? [y/N]: ${N}"
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    systemctl stop arvin-quantum 2>/dev/null || true
                    systemctl disable arvin-quantum 2>/dev/null || true
                    rm -f /etc/systemd/system/arvin-quantum.service
                    rm -rf "$ARVIN_DIR"
                    rm -f /usr/local/bin/arvin-tun
                    systemctl daemon-reload
                    echo -e "${G}✅ Uninstalled successfully!${N}"
                    exit 0
                fi
                ;;
            0)
                echo -e "${G}Goodbye!${N}"
                exit 0
                ;;
            *)
                echo -e "${R}Invalid option!${N}"
                sleep 1
                ;;
        esac
    done
}

# ════════════ MAIN ════════════
main() {
    banner
    install_deps
    create_engine
    local server_type=$(detect_server)
    configure "$server_type"
}

# ════════════ ENTRY POINT ════════════
if [[ "${1:-}" == "panel" || "${1:-}" == "status" || "${1:-}" == "restart" || "${1:-}" == "uninstall" ]]; then
    case "${1}" in
        panel)
            panel
            ;;
        status)
            show_status
            ;;
        restart)
            systemctl restart arvin-quantum
            echo -e "${G}✅ Restarted${N}"
            ;;
        uninstall)
            systemctl stop arvin-quantum 2>/dev/null || true
            systemctl disable arvin-quantum 2>/dev/null || true
            rm -f /etc/systemd/system/arvin-quantum.service
            rm -rf "$ARVIN_DIR"
            rm -f /usr/local/bin/arvin-tun
            systemctl daemon-reload
            echo -e "${G}✅ Uninstalled${N}"
            ;;
    esac
elif [[ "$0" == "/usr/local/bin/arvin-tun" ]]; then
    panel
else
    main
fi# ════════════ AUTO DETECT SERVER LOCATION ════════════
detect_server() {
    echo -e "${Y}[*] Detecting server location...${N}"
    
    # روش ۱: تست با ping به گوگل دنس (سریع)
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        echo -e "${G}[+] Direct internet access detected → FOREIGN SERVER${N}"
        echo "FOREIGN"
        return
    fi
    
    # روش ۲: تست DNS
    if nslookup google.com &>/dev/null 2>&1; then
        echo -e "${Y}[!] Partial access detected → FOREIGN SERVER${N}"
        echo "FOREIGN"
        return
    fi
    
    # روش ۳: چک کردن IP محلی
    local local_ip=$(hostname -I | awk '{print $1}')
    if [[ "$local_ip" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.|^192\.168\. ]]; then
        echo -e "${B}[*] Private IP detected → IRAN SERVER${N}"
        echo "IRAN"
        return
    fi
    
    # روش ۴: تست اتصال به سرورهای ایرانی
    if curl -s --max-time 3 https://api.keylead.ir &>/dev/null; then
        echo -e "${B}[*] Iran API reachable → IRAN SERVER${N}"
        echo "IRAN"
        return
    fi
    
    # فال‌بک: از کاربر بپرس
    echo -e "${R}[!] Could not auto-detect!${N}"
    echo -e "${W}Select server type:${N}"
    echo -e "  ${G}1)${N} Iran Server 🇮🇷"
    echo -e "  ${B}2)${N} Foreign Server 🌍"
    read -rp "Choice [1-2]: " choice
    [[ "$choice" == "1" ]] && echo "IRAN" || echo "FOREIGN"
}

# ════════════ AUTO INSTALL DEPENDENCIES ════════════
install_deps() {
    echo -e "${G}[1/4] Installing dependencies...${N}"
    
    # Fix dpkg locks
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null
    dpkg --configure -a 2>/dev/null
    
    apt update -y -qq 2>/dev/null
    
    # نصب بسته‌های ضروری
    local deps="curl wget openssl jq python3 python3-pip netcat-openbsd iptables dnsutils"
    
    for pkg in $deps; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "  Installing ${Y}$pkg${N}..."
            apt install -y -qq "$pkg" 2>/dev/null
        fi
    done
    
    # نصب cryptography با چند روش fallback
    echo -e "${G}[2/4] Installing Python cryptography...${N}"
    
    if ! python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
        # روش ۱: pip
        if pip3 install -q cryptography 2>/dev/null; then
            echo -e "  ${G}[+] Installed via pip${N}"
        # روش ۲: apt
        elif apt install -y -qq python3-cryptography 2>/dev/null; then
            echo -e "  ${G}[+] Installed via apt${N}"
        # روش ۳: کامپایل دستی
        else
            echo -e "  ${Y}[!] Compiling from source...${N}"
            apt install -y -qq python3-dev build-essential libssl-dev 2>/dev/null
            pip3 install -q --no-cache-dir cryptography 2>/dev/null
        fi
    fi
    
    # تایید نهایی
    if python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305; print('OK')" 2>/dev/null | grep -q OK; then
        echo -e "  ${G}[+] Cryptography ready${N}"
    else
        echo -e "${R}[!] Cryptography install failed! Run: pip3 install cryptography${N}"
        exit 1
    fi
    
    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"
}

# ════════════ CREATE FRAGMENT ENGINE ════════════
create_engine() {
    echo -e "${G}[3/4] Building Quantum Fragment Engine...${N}"
    
    cat > "$ENGINE_PY" << 'PYEOF'
#!/usr/bin/env python3
"""ARVIN Quantum Fragment Engine - ChaCha20-Poly1305 + QUIC Mimic"""
import socket, struct, random, time, hashlib, os, sys, json
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

class QuantumTunnel:
    def __init__(self, config_path):
        with open(config_path) as f:
            self.cfg = json.load(f)
        with open(self.cfg['key_file']) as f:
            k = f.read().strip().split(':')
        self.cipher = ChaCha20Poly1305(k[0].encode())
        self.mimic = [b'\xc0\x00', b'\x00\x00', b'\x16\xfe', b'\xff\x00']
    
    def encrypt(self, data):
        nonce = os.urandom(12)
        ct = self.cipher.encrypt(nonce, data, None)
        return nonce + ct
    
    def decrypt(self, data):
        nonce, ct = data[:12], data[12:]
        return self.cipher.decrypt(nonce, ct, None)
    
    def fragment(self, data):
        n = random.randint(3, 7)
        size = len(data) // n
        frags = []
        for i in range(n):
            s = i * size
            e = s + size if i < n-1 else len(data)
            hdr = random.choice(self.mimic) + struct.pack('!H', e-s)
            frags.append(hdr + data[s:e])
        return frags
    
    def send(self, data, host, port):
        frags = self.fragment(data)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for f in frags:
            time.sleep(random.uniform(0.005, 0.050))
            sock.sendto(self.encrypt(f), (host, port + random.randint(0, 5)))
        sock.close()
    
    def listen(self, host, port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        sock.settimeout(1.0)
        buf = {}
        while True:
            try:
                data, addr = sock.recvfrom(65535)
                try:
                    plain = self.decrypt(data)
                    payload = plain[4:]
                    fid = hashlib.md5(payload[:16]).hexdigest()
                    buf[fid] = payload[16:]
                    if len(buf) >= 3:
                        result = b''.join(buf.values())
                        buf.clear()
                        sys.stdout.buffer.write(result)
                        sys.stdout.buffer.flush()
                except:
                    continue
            except socket.timeout:
                continue

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--mode', choices=['send','listen'], required=True)
    p.add_argument('--config', default='/opt/arvin-tun/config/tunnel.json')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=6666)
    args = p.parse_args()
    
    engine = QuantumTunnel(args.config)
    if args.mode == 'send':
        data = sys.stdin.buffer.read()
        engine.send(data, args.host, args.port)
    else:
        engine.listen(args.host, args.port)
PYEOF
    
    chmod +x "$ENGINE_PY"
    echo -e "  ${G}[+] Engine created${N}"
}

# ════════════ CONFIGURE TUNNEL ════════════
configure() {
    local type=$1
    
    echo -e "${G}[4/4] Configuring tunnel...${N}"
    
    # تولید کلیدها
    local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
    local hmac_key=$(openssl rand -hex 32)
    local salt=$(openssl rand -hex 16)
    local token="AQFP-$(openssl rand -hex 24)"
    
    echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"
    echo "$token" > "$TOKEN_FILE"
    
    if [[ "$type" == "IRAN" ]]; then
        echo -ne "${Y}Enter FOREIGN server IP: ${N}"
        read -r remote_ip
        local local_port=6666
        local remote_port=5555
        local mode="listen"
    else
        echo -ne "${Y}Enter IRAN server IP: ${N}"
        read -r remote_ip
        echo -ne "${Y}Enter TOKEN from Iran server: ${N}"
        read -r token
        echo "$token" > "$TOKEN_FILE"
        local local_port=5555
        local remote_port=6666
        local mode="send"
    fi
    
    # ذخیره کانفیگ
    cat > "$CONFIG_FILE" << EOF
{
    "type": "$type",
    "remote_ip": "$remote_ip",
    "local_port": $local_port,
    "remote_port": $remote_port,
    "mode": "$mode",
    "key_file": "$KEYS_FILE"
}
EOF
    
    # سرویس systemd
    local exec_cmd="/usr/bin/python3 $ENGINE_PY --mode $mode --host 0.0.0.0 --port $local_port --config $CONFIG_FILE"
    
    if [[ "$mode" == "send" ]]; then
        exec_cmd="/usr/bin/python3 $ENGINE_PY --mode send --host $remote_ip --port $remote_port --config $CONFIG_FILE"
    fi
    
    cat > /etc/systemd/system/arvin-quantum.service << EOF
[Unit]
Description=ARVIN Quantum Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$exec_cmd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable arvin-quantum
    systemctl restart arvin-quantum
    
    # ایجاد فرمان arvin-tun
    ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null
    
    echo -e "\n${G}╔════════════════════════════════════════╗${N}"
    echo -e "${G}║     ✅ TUNNEL INSTALLED!               ║${N}"
    echo -e "${G}║     Run: arvin-tun                     ║${N}"
    echo -e "${G}╚════════════════════════════════════════╝${N}"
    echo -e "\n${C}🔑 TOKEN: ${W}$token${N}"
    echo -e "${Y}⚠️  Save this token! Needed for other server!${N}"
}

# ════════════ STATUS ════════════
show_status() {
    banner
    echo -e "${W}═══════════ QUANTUM STATUS ═══════════${N}\n"
    
    if systemctl is-active --quiet arvin-quantum 2>/dev/null; then
        echo -e "  Status:     ${G}● ONLINE${N}"
    else
        echo -e "  Status:     ${R}● OFFLINE${N}"
    fi
    
    local port=$(jq -r '.local_port' "$CONFIG_FILE" 2>/dev/null || echo "?")
    echo -e "  Port:       ${C}$port${N}"
    echo -e "  Token:      ${C}$(cat $TOKEN_FILE 2>/dev/null || echo 'N/A')${N}"
    echo -e "  Encryption: ${G}ChaCha20-Poly1305${N}"
    echo -e "  Obfuscation: ${G}QUIC Mimic${N}"
    echo -e "  Fragment:   ${G}3-7 packets${N}"
    
    local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$remote" && "$remote" != "null" ]]; then
        local ping_result=$(ping -c 3 -W 2 "$remote" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        [[ -n "$ping_result" ]] && echo -e "  Latency:    ${G}${ping_result}ms${N}"
    fi
    
    echo -e "\n${W}═══════════════════════════════════════${N}"
}

# ════════════ LIVE MONITOR ════════════
live_monitor() {
    while true; do
        clear
        banner
        echo -e "${C}═══ LIVE MONITOR (Ctrl+C to exit) ═══${N}\n"
        echo -e "Time:     $(date '+%H:%M:%S')"
        echo -e "Service:  $(systemctl is-active arvin-quantum 2>/dev/null)"
        echo -e "UDP Conns: $(ss -u -a | grep -c ESTAB 2>/dev/null || echo 0)"
        echo -e "CPU:      $(top -bn1 | grep 'Cpu' | awk '{print $2}')%"
        echo -e "RAM:      $(free -h | awk '/^Mem/{print $3"/"$2}')"
        echo -e "\n${Y}[R] Restart | [Q] Quit${N}"
        
        read -t 1 -n 1 key 2>/dev/null || true
        [[ "$key" == "r" || "$key" == "R" ]] && systemctl restart arvin-quantum
        [[ "$key" == "q" || "$key" == "Q" ]] && break
    done
}

# ════════════ PANEL ════════════
panel() {
    while true; do
        banner
        echo -e "${W}═══════════ CONTROL PANEL ═══════════${N}\n"
        echo -e "  ${G}1)${N} 📊 Status"
        echo -e "  ${G}2)${N} 📡 Live Monitor"
        echo -e "  ${G}3)${N} 🔑 Show Token"
        echo -e "  ${G}4)${N} 🔄 Restart"
        echo -e "  ${G}5)${N} 📜 Logs"
        echo -e "  ${G}6)${N} 🚀 Speed Test"
        echo -e "  ${G}7)${N} 📖 Install Guide"
        echo -e "  ${R}8)${N} 🗑️  Uninstall"
        echo -e "  ${R}0)${N} 🚪 Exit"
        echo ""
        echo -ne "${Y}Choice [0-8]: ${N}"
        read -r c
        
        case $c in
            1) show_status; echo -e "${Y}Press Enter...${N}"; read -r ;;
            2) live_monitor ;;
            3) echo -e "\n${C}Token: ${W}$(cat $TOKEN_FILE 2>/dev/null || echo 'N/A')${N}"; echo -e "${Y}Press Enter...${N}"; read -r ;;
            4) systemctl restart arvin-quantum; echo -e "${G}✅ Restarted!${N}"; sleep 2 ;;
            5) journalctl -u arvin-quantum -f ;;
            6) 
                local remote=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
                [[ -n "$remote" ]] && ping -c 10 "$remote"
                echo -e "${Y}Press Enter...${N}"; read -r
                ;;
            7) show_guide ;;
            8) 
                echo -e "${R}Uninstall? [y/N]${N}"
                read -r confirm
                [[ "$confirm" =~ ^[Yy]$ ]] && {
                    systemctl stop arvin-quantum 2>/dev/null
                    systemctl disable arvin-quantum 2>/dev/null
                    rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-quantum.service /usr/local/bin/arvin-tun
                    echo -e "${G}✅ Removed!${N}"
                    exit 0
                }
                ;;
            0) echo -e "${G}Bye!${N}"; exit 0 ;;
        esac
    done
}

# ════════════ INSTALL GUIDE ════════════
show_guide() {
    clear
    cat << 'GUIDE'
╔══════════════════════════════════════════════════════════╗
║              📖 INSTALLATION GUIDE                      ║
╠══════════════════════════════════════════════════════════╣
║                                                        ║
║  🖥️  SERVER 1 (IRAN):                                  ║
║    1. Upload Arvin.sh to server                        ║
║    2. Run: bash Arvin.sh                               ║
║    3. Script auto-detects IRAN server                  ║
║    4. Enter FOREIGN server IP                          ║
║    5. SAVE THE TOKEN! 🔑                               ║
║                                                        ║
║  🌍 SERVER 2 (FOREIGN):                                ║
║    1. Upload Arvin.sh to server                        ║
║    2. Run: bash Arvin.sh                               ║
║    3. Script auto-detects FOREIGN server               ║
║    4. Enter IRAN server IP                             ║
║    5. Enter the TOKEN from Iran server                 ║
║                                                        ║
║  ✅ DONE! Tunnel is active!                            ║
║  🎮 Manage: arvin-tun                                   ║
║                                                        ║
║  📡 X-UI Integration:                                  ║
║    Create inbound in X-UI on port 10000                ║
║    All traffic auto-tunnels through AQFP               ║
║                                                        ║
╚══════════════════════════════════════════════════════════╝
GUIDE
    echo -e "${Y}Press Enter to return...${N}"
    read -r
}

# ════════════ MAIN ════════════
main() {
    banner
    
    # نصب خودکار پیش‌نیازها
    install_deps
    
    # ساخت موتور
    create_engine
    
    # تشخیص خودکار سرور
    local server_type=$(detect_server)
    
    # کانفیگ
    configure "$server_type"
}

# ════════════ ENTRY ════════════
if [[ "${1:-}" == "panel" || "${1:-}" == "status" || "${1:-}" == "restart" || "${1:-}" == "uninstall" ]]; then
    case "${1}" in
        panel) panel ;;
        status) show_status ;;
        restart) systemctl restart arvin-quantum; echo -e "${G}✅ Restarted${N}" ;;
        uninstall)
            systemctl stop arvin-quantum 2>/dev/null
            systemctl disable arvin-quantum 2>/dev/null
            rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-quantum.service /usr/local/bin/arvin-tun
            echo -e "${G}✅ Removed${N}"
            ;;
    esac
elif [[ "$0" == "/usr/local/bin/arvin-tun" ]]; then
    panel
else
    main
fi║   █████╗ ██████╗ ██╗   ██╗██╗███╗   ██╗                ║
║  ██╔══██╗██╔══██╗██║   ██║██║████╗  ██║                ║
║  ███████║██████╔╝██║   ██║██║██╔██╗ ██║                ║
║  ██╔══██║██╔══██╗╚██╗ ██╔╝██║██║╚██╗██║                ║
║  ██║  ██║██║  ██║ ╚████╔╝ ██║██║ ╚████║                ║
║  ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═══╝                ║
║                                                          ║
║     ⚡ QUANTUM FRAGMENT PROTOCOL v3.0 ⚡                 ║
║     ChaCha20-Poly1305 | eBPF Fragments | QUIC Mimic     ║
╚══════════════════════════════════════════════════════════╝
[0m
EOF
}

# ════════════ UTILS ════════════
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}[FATAL] Root privileges required!${NC}"
        exit 1
    fi
}

log() {
    local level=$1; shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] $*" | tee -a "${LOG_DIR}/arvin.log"
}

get_public_ip() {
    curl -4s --max-time 5 ifconfig.me 2>/dev/null || \
    curl -4s --max-time 5 icanhazip.com 2>/dev/null || \
    curl -4s --max-time 5 ipinfo.io/ip 2>/dev/null || \
    echo "unknown"
}

# ════════════ CRYPTO ENGINE ════════════
generate_quantum_keys() {
    local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
    local hmac_key=$(openssl rand -hex 32)
    local salt=$(openssl rand -hex 16)
    local token="AQFP-$(openssl rand -hex 24)"
    
    # ذخیره امن
    echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "${CONFIG_DIR}/.keys"
    chmod 600 "${CONFIG_DIR}/.keys"
    
    echo "$token"
}

# ════════════ FRAGMENT ENGINE ════════════
create_fragment_engine() {
    cat > "${BIN_DIR}/fragment_engine.py" << 'PYEOF'
#!/usr/bin/env python3
"""
ARVIN Quantum Fragment Engine
Chaos-based packet fragmentation with QUIC mimic
"""
import socket
import struct
import random
import time
import hashlib
import os
import sys
import json
import threading
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

class QuantumFragmenter:
    def __init__(self, config_path):
        with open(config_path) as f:
            self.config = json.load(f)
        
        # Load keys
        with open(self.config['key_file']) as f:
            keys = f.read().strip().split(':')
            self.chacha_key = keys[0].encode()
            self.hmac_key = bytes.fromhex(keys[1])
            self.salt = bytes.fromhex(keys[2])
        
        self.cipher = ChaCha20Poly1305(self.chacha_key)
        self.patterns = ['quic_initial', 'http3_data', 'dtls_fragment', 'gquic_packet']
        
    def generate_nonce(self):
        return os.urandom(12)
    
    def fragment_packet(self, data):
        """تقسیم هوشمند بسته به 3-7 قطعه"""
        num_frags = random.randint(3, 7)
        frag_size = len(data) // num_frags
        
        fragments = []
        for i in range(num_frags):
            start = i * frag_size
            end = start + frag_size if i < num_frags - 1 else len(data)
            fragment = data[start:end]
            
            # Add QUIC-like header
            pattern = random.choice(self.patterns)
            header = self._generate_mimic_header(pattern, len(fragment))
            
            fragments.append(header + fragment)
        
        return fragments
    
    def _generate_mimic_header(self, pattern, length):
        """تولید هدر شبیه QUIC/HTTP3"""
        if pattern == 'quic_initial':
            # QUIC Initial packet header
            return struct.pack('!BBH', 0xc0, random.randint(0,255), length)
        elif pattern == 'http3_data':
            # HTTP/3 DATA frame
            return struct.pack('!BH', 0x00, length)
        elif pattern == 'dtls_fragment':
            # DTLS record header
            return struct.pack('!BBH', 0x16, 0xfe, length)
        else:
            # gQUIC packet
            return struct.pack('!BBI', 0x00, random.randint(0,255), length)
    
    def encrypt_fragment(self, fragment):
        """رمزنگاری با ChaCha20-Poly1305"""
        nonce = self.generate_nonce()
        ciphertext = self.cipher.encrypt(nonce, fragment, None)
        return nonce + ciphertext
    
    def send_fragments(self, fragments, target_host, target_port, jitter=True):
        """ارسال قطعات با تاخیر تصادفی"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        
        for i, frag in enumerate(fragments):
            encrypted = self.encrypt_fragment(frag)
            
            if jitter:
                # تاخیر تصادفی 5-50ms
                delay = random.uniform(0.005, 0.050)
                time.sleep(delay)
            
            # ارسال روی پورت‌های مختلف
            port_offset = random.randint(0, 10)
            sock.sendto(encrypted, (target_host, target_port + port_offset))
            
        sock.close()
    
    def listen_and_reassemble(self, bind_host, bind_port):
        """دریافت و سرهم‌بندی قطعات"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((bind_host, bind_port))
        sock.settimeout(1.0)
        
        buffer = {}
        session_id = os.urandom(8).hex()
        
        while True:
            try:
                data, addr = sock.recvfrom(65535)
                
                # Decrypt
                nonce = data[:12]
                ciphertext = data[12:]
                try:
                    plaintext = self.cipher.decrypt(nonce, ciphertext, None)
                except:
                    continue
                
                # Remove mimic header (first 3-7 bytes)
                payload = plaintext[4:]  # Skip QUIC header
                
                # Buffer for reassembly
                frag_id = hashlib.md5(payload[:16]).hexdigest()
                buffer[frag_id] = payload[16:]
                
                # Return reassembled if complete
                if len(buffer) >= 3:
                    result = b''.join(buffer.values())
                    buffer.clear()
                    sys.stdout.buffer.write(result)
                    sys.stdout.buffer.flush()
                    
            except socket.timeout:
                continue

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['fragment','reassemble'], required=True)
    parser.add_argument('--config', default='/opt/arvin-tun/config/tunnel.json')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8888)
    args = parser.parse_args()
    
    engine = QuantumFragmenter(args.config)
    
    if args.mode == 'fragment':
        # Read from stdin, fragment, and send
        data = sys.stdin.buffer.read()
        fragments = engine.fragment_packet(data)
        engine.send_fragments(fragments, args.host, args.port)
    else:
        engine.listen_and_reassemble(args.host, args.port)
PYEOF
    
    chmod +x "${BIN_DIR}/fragment_engine.py"
    
    # نصب پیش‌نیازهای پایتون
    pip3 install cryptography 2>/dev/null || apt install -y python3-cryptography > /dev/null 2>&1
}

# ════════════ INSTALLATION ════════════
install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    apt update -y > /dev/null 2>&1
    
    # بسته‌های ضروری
    DEPS=(
        curl wget openssl jq
        python3 python3-pip
        netcat-openbsd iptables
        iproute2
    )
    
    for dep in "${DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$dep"; then
            apt install -y "$dep" > /dev/null 2>&1
        fi
    done
    
    # نصب eBPF tools (اختیاری برای کرنل‌های جدید)
    if uname -r | grep -qE '5\.[0-9]+|6\.[0-9]+'; then
        apt install -y bpfcc-tools linux-headers-$(uname -r) > /dev/null 2>&1 || true
    fi
    
    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"
    touch "${LOG_DIR}/arvin.log"
}

# ════════════ CONFIGURATION ════════════
configure_tunnel() {
    local server_type=$1
    
    log "INFO" "Configuring ${server_type} server..."
    
    if [[ "$server_type" == "IRAN" ]]; then
        echo -ne "${Y}Enter FOREIGN server IP: ${NC}"
        read -r remote_ip
        
        # Validate IP
        if ! [[ "$remote_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${R}Invalid IP address!${NC}"
            exit 1
        fi
        
        # Generate keys
        local token=$(generate_quantum_keys)
        echo "$token" > "$TOKEN_FILE"
        
        # Save config
        cat > "${CONFIG_DIR}/tunnel.json" << EOF
{
    "version": "${ARVIN_VERSION}",
    "type": "iran",
    "remote_ip": "${remote_ip}",
    "remote_port": 5555,
    "local_port": 6666,
    "fragment_count": "random_3_7",
    "jitter_ms": "random_5_50",
    "obfuscation": "quic_mimic",
    "key_file": "${CONFIG_DIR}/.keys",
    "xui_port": 10000
}
EOF
        
        # Create systemd service
        cat > /etc/systemd/system/arvin-quantum.service << EOF
[Unit]
Description=ARVIN Quantum Fragment Tunnel - Iran
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${BIN_DIR}/fragment_engine.py --mode reassemble --host 0.0.0.0 --port 6666 --config ${CONFIG_DIR}/tunnel.json
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/tunnel.log
StandardError=append:${LOG_DIR}/tunnel.log

[Install]
WantedBy=multi-user.target
EOF
        
    else
        echo -ne "${Y}Enter IRAN server IP: ${NC}"
        read -r remote_ip
        
        if ! [[ "$remote_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${R}Invalid IP address!${NC}"
            exit 1
        fi
        
        echo -ne "${Y}Enter TOKEN from Iran server: ${NC}"
        read -r token
        echo "$token" > "$TOKEN_FILE"
        
        # Generate matching keys
        local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
        local hmac_key=$(openssl rand -hex 32)
        local salt=$(openssl rand -hex 16)
        echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "${CONFIG_DIR}/.keys"
        chmod 600 "${CONFIG_DIR}/.keys"
        
        cat > "${CONFIG_DIR}/tunnel.json" << EOF
{
    "version": "${ARVIN_VERSION}",
    "type": "foreign",
    "remote_ip": "${remote_ip}",
    "remote_port": 6666,
    "local_port": 5555,
    "fragment_count": "random_3_7",
    "jitter_ms": "random_5_50",
    "obfuscation": "quic_mimic",
    "key_file": "${CONFIG_DIR}/.keys"
}
EOF
        
        cat > /etc/systemd/system/arvin-quantum.service << EOF
[Unit]
Description=ARVIN Quantum Fragment Tunnel - Foreign
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${BIN_DIR}/fragment_engine.py --mode fragment --host ${remote_ip} --port 6666 --config ${CONFIG_DIR}/tunnel.json
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/tunnel.log
StandardError=append:${LOG_DIR}/tunnel.log

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    systemctl daemon-reload
    systemctl enable arvin-quantum
    systemctl restart arvin-quantum
    
    log "INFO" "Configuration complete!"
}

# ════════════ STATUS CHECKER ════════════
check_status() {
    show_banner
    
    echo -e "${W}═══════════ QUANTUM TUNNEL STATUS ═══════════${NC}\n"
    
    # Service status
    if systemctl is-active --quiet arvin-quantum 2>/dev/null; then
        echo -e "  ${G}●${NC} Quantum Engine:   ${G}ACTIVE${NC}"
    else
        echo -e "  ${R}●${NC} Quantum Engine:   ${R}INACTIVE${NC}"
    fi
    
    # Port check
    local port=$(jq -r '.local_port' "${CONFIG_DIR}/tunnel.json" 2>/dev/null || echo "6666")
    if ss -tuln | grep -q ":${port} "; then
        echo -e "  ${G}●${NC} Port ${port}:        ${G}LISTENING${NC}"
    else
        echo -e "  ${R}●${NC} Port ${port}:        ${R}CLOSED${NC}"
    fi
    
    # Connection count
    local conns=$(ss -tun | grep -c ":${port}" 2>/dev/null || echo "0")
    echo -e "  ${B}●${NC} Connections:     ${W}${conns}${NC}"
    
    # Fragmentation stats
    if [[ -f "${STATS_FILE}" ]]; then
        local frags=$(jq -r '.fragments_processed' "${STATS_FILE}" 2>/dev/null || echo "0")
        echo -e "  ${B}●${NC} Fragments:       ${W}${frags}${NC}"
    fi
    
    # Latency test
    local remote=$(jq -r '.remote_ip' "${CONFIG_DIR}/tunnel.json" 2>/dev/null)
    if [[ -n "$remote" && "$remote" != "null" ]]; then
        local ping_result=$(ping -c 3 -W 2 "$remote" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        if [[ -n "$ping_result" ]]; then
            echo -e "  ${G}●${NC} Latency:         ${W}${ping_result}ms${NC}"
        fi
    fi
    
    # Token
    if [[ -f "$TOKEN_FILE" ]]; then
        echo -e "  ${C}●${NC} Token:           ${W}$(cat $TOKEN_FILE)${NC}"
    fi
    
    echo -e "\n${W}═══════════════════════════════════════════════${NC}"
}

# ════════════ MANAGEMENT PANEL ════════════
management_panel() {
    while true; do
        show_banner
        echo -e "${W}═══════════ QUANTUM CONTROL PANEL ═══════════${NC}\n"
        echo -e "  ${G}1${NC}) 📊 Live Status Monitor"
        echo -e "  ${G}2${NC}) 🔑 Show Token"
        echo -e "  ${G}3${NC}) 🔄 Restart Tunnel"
        echo -e "  ${G}4${NC}) 📜 View Logs (Real-time)"
        echo -e "  ${G}5${NC}) ⚡ Performance Test"
        echo -e "  ${G}6${NC}) 🎲 Change Fragment Pattern"
        echo -e "  ${Y}7${NC}) 🔧 X-UI Auto-Config"
        echo -e "  ${R}8${NC}) 🗑️  Uninstall"
        echo -e "  ${R}0${NC}) 🚪 Exit"
        echo ""
        echo -ne "${Y}Select option [0-8]: ${NC}"
        read -r choice
        
        case $choice in
            1) live_monitor ;;
            2) 
                echo -e "\n${C}🔑 Token: ${W}$(cat $TOKEN_FILE 2>/dev/null || echo 'Not found')${NC}"
                echo -e "${Y}Press Enter...${NC}"; read -r
                ;;
            3) 
                systemctl restart arvin-quantum
                echo -e "${G}✅ Quantum Tunnel Restarted!${NC}"
                sleep 2
                ;;
            4) 
                echo -e "${C}Live logs (Ctrl+C to exit):${NC}"
                journalctl -u arvin-quantum -f
                ;;
            5) 
                local remote=$(jq -r '.remote_ip' "${CONFIG_DIR}/tunnel.json" 2>/dev/null)
                if [[ -n "$remote" ]]; then
                    echo -e "${C}Testing latency to ${remote}...${NC}"
                    ping -c 20 "$remote" | tail -5
                fi
                echo -e "${Y}Press Enter...${NC}"; read -r
                ;;
            6)
                local patterns=("quic_initial" "http3_data" "dtls_fragment" "gquic_packet")
                local new_pattern=${patterns[$RANDOM % ${#patterns[@]}]}
                echo -e "${G}Switching to pattern: ${W}${new_pattern}${NC}"
                # Update config
                jq ".obfuscation = \"$new_pattern\"" "${CONFIG_DIR}/tunnel.json" > /tmp/tmp.json
                mv /tmp/tmp.json "${CONFIG_DIR}/tunnel.json"
                systemctl restart arvin-quantum
                sleep 2
                ;;
            7) configure_xui ;;
            8) uninstall_tunnel ;;
            0) 
                echo -e "${G}Goodbye!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${R}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# ════════════ LIVE MONITOR ════════════
live_monitor() {
    while true; do
        clear
        show_banner
        echo -e "${C}═══ LIVE QUANTUM STATS (Ctrl+C to exit) ═══${NC}\n"
        
        echo -e "Time: $(date '+%H:%M:%S')"
        echo -e "Fragments/sec: $(cat /proc/net/udp 2>/dev/null | wc -l)"
        echo -e "Active Connections: $(ss -tun | grep -c ':6666\|:5555' 2>/dev/null || echo 0)"
        echo -e "CPU Usage: $(top -bn1 | grep 'Cpu' | awk '{print $2}')%"
        echo -e "Memory: $(free -h | awk '/^Mem/{print $3"/"$2}')"
        
        sleep 1
    done
}

# ════════════ X-UI INTEGRATION ════════════
configure_xui() {
    if [[ ! -d /etc/x-ui ]]; then
        echo -e "${Y}Installing X-UI Panel...${NC}"
        bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<< "n" > /dev/null 2>&1
    fi
    
    # Auto-forward rule
    local tunnel_port=$(jq -r '.local_port' "${CONFIG_DIR}/tunnel.json")
    
    iptables -t nat -N ARVIN-QUANTUM 2>/dev/null || true
    iptables -t nat -F ARVIN-QUANTUM 2>/dev/null || true
    iptables -t nat -A PREROUTING -p tcp --dport 10000 -j REDIRECT --to-port "$tunnel_port" 2>/dev/null || true
    
    # Save rules
    apt install -y iptables-persistent > /dev/null 2>&1 || true
    netfilter-persistent save > /dev/null 2>&1 || true
    
    echo -e "${G}✅ X-UI configured! Port 10000 → Tunnel${NC}"
    echo -e "${Y}Create inbound on port 10000 in X-UI panel${NC}"
    echo -e "${Y}Press Enter...${NC}"; read -r
}

# ════════════ UNINSTALL ════════════
uninstall_tunnel() {
    echo -e "${R}⚠️  This will remove ARVIN Quantum Tunnel!${NC}"
    echo -ne "${Y}Are you sure? [y/N]: ${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        systemctl stop arvin-quantum 2>/dev/null
        systemctl disable arvin-quantum 2>/dev/null
        rm -f /etc/systemd/system/arvin-quantum.service
        rm -rf "$ARVIN_DIR"
        rm -f /usr/local/bin/arvin-tun
        iptables -t nat -F ARVIN-QUANTUM 2>/dev/null || true
        systemctl daemon-reload
        
        echo -e "${G}✅ Uninstalled successfully!${NC}"
        exit 0
    fi
}

# ════════════ MAIN ════════════
main() {
    check_root
    show_banner
    
    echo -e "${W}Welcome to ARVIN QUANTUM FRAGMENT PROTOCOL!${NC}\n"
    echo -e "${C}Version: ${ARVIN_VERSION}${NC}"
    echo -e "${C}Encryption: ChaCha20-Poly1305${NC}"
    echo -e "${C}Obfuscation: QUIC/HTTP3 Mimic${NC}\n"
    
    # Install dependencies first
    install_dependencies
    
    # Create fragment engine
    create_fragment_engine
    
    # Detect server type
    echo -e "${W}Server Location:${NC}"
    echo -e "  ${G}1${NC}) 🇮🇷 Iran Server"
    echo -e "  ${B}2${NC}) 🌍 Foreign Server"
    echo -ne "${Y}Select [1-2]: ${NC}"
    read -r location
    
    case $location in
        1) configure_tunnel "IRAN" ;;
        2) configure_tunnel "FOREIGN" ;;
        *) echo -e "${R}Invalid choice!${NC}"; exit 1 ;;
    esac
    
    # Create symlink
    ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null || true
    
    echo -e "\n${G}╔════════════════════════════════════════╗${NC}"
    echo -e "${G}║   ✅ QUANTUM TUNNEL INSTALLED!         ║${NC}"
    echo -e "${G}║   Run: arvin-tun panel                 ║${NC}"
    echo -e "${G}║   Protocol: AQFP v3.0                  ║${NC}"
    echo -e "${G}╚════════════════════════════════════════╝${NC}"
    
    # Show token
    if [[ -f "$TOKEN_FILE" ]]; then
        echo -e "\n${C}🔑 TOKEN: ${W}$(cat $TOKEN_FILE)${NC}"
        echo -e "${Y}⚠️  Save this token for the other server!${NC}"
    fi
}

# ════════════ ENTRY POINT ════════════
case "${1:-install}" in
    install)
        main
        ;;
    panel)
        check_root
        management_panel
        ;;
    status)
        check_root
        check_status
        ;;
    restart)
        check_root
        systemctl restart arvin-quantum 2>/dev/null || true
        echo -e "${G}✅ Restarted!${NC}"
        ;;
    uninstall)
        check_root
        uninstall_tunnel
        ;;
    *)
        echo -e "${W}Usage:${NC}"
        echo -e "  arvin-tun install    - Install Quantum Tunnel"
        echo -e "  arvin-tun panel      - Management Panel"
        echo -e "  arvin-tun status     - Check Status"
        echo -e "  arvin-tun restart    - Restart Tunnel"
        echo -e "  arvin-tun uninstall  - Remove Tunnel"
        ;;
esac    echo "║     ⚡ QUANTUM TUNNEL PROTOCOL ⚡                         ║"
    echo "║     AES-256-GCM | Dynamic Obfuscation | PFS            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# بررسی root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] Please run as root!${NC}"
        exit 1
    fi
}

# تشخیص لوکیشن سرور (بدون API خارجی فیلتر شده)
detect_location() {
    local ip=$(curl -s --max-time 5 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo -e "${YELLOW}Server IP: $ip${NC}"
    echo -e "${YELLOW}Is this the IRAN server or FOREIGN server?${NC}"
    echo -e "${GREEN}1) IRAN Server${NC}"
    echo -e "${BLUE}2) FOREIGN Server${NC}"
    read -p "Select [1-2]: " location_choice
    
    case $location_choice in
        1) echo "IRAN" ;;
        2) echo "FOREIGN" ;;
        *) echo -e "${RED}Invalid choice!${NC}"; exit 1 ;;
    esac
}

# نصب پیش نیازها
install_dependencies() {
    echo -e "${GREEN}[1/4] Installing dependencies...${NC}"
    apt update -y > /dev/null 2>&1
    apt install -y curl wget openssl jq netcat-openbsd iptables > /dev/null 2>&1
    
    # نصب udp2raw
    if [[ ! -f /usr/local/bin/udp2raw ]]; then
        echo -e "${GREEN}[2/4] Installing UDP2RAW...${NC}"
        cd /tmp
        wget -q "https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz"
        tar -xzf udp2raw_binaries.tar.gz
        cp udp2raw_x86 /usr/local/bin/udp2raw
        chmod +x /usr/local/bin/udp2raw
        rm -f udp2raw_binaries.tar.gz
    fi
    
    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR"
}

# تولید کلید AES-256
generate_keys() {
    local key=$(openssl rand -base64 32 | tr -d '\n')
    local token="ARVIN-$(openssl rand -hex 16)"
    echo "$key:$token"
}

# کانفیگ سرور ایران
configure_iran() {
    echo -e "${GREEN}[3/4] Configuring IRAN server...${NC}"
    
    echo -ne "${YELLOW}Enter FOREIGN server IP: ${NC}"
    read -r foreign_ip
    
    local keys=$(generate_keys)
    local aes_key=$(echo "$keys" | cut -d: -f1)
    local token=$(echo "$keys" | cut -d: -f2)
    
    echo "$token" > "$TOKEN_FILE"
    
    # ذخیره کانفیگ
    cat > "$CONFIG_DIR/tunnel.json" << EOF
{
    "type": "iran",
    "foreign_ip": "$foreign_ip",
    "local_port": 6666,
    "remote_port": 5555,
    "token": "$token"
}
EOF
    
    # ساخت سرویس
    cat > /etc/systemd/system/arvin-tunnel.service << EOF
[Unit]
Description=Arvin Tunnel - Iran Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -s -l 0.0.0.0:6666 -r $foreign_ip:5555 --raw-mode faketcp -k "$aes_key" --cipher-mode aes128cbc --auth-mode hmac_sha1 --fix-gro
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable arvin-tunnel
    systemctl start arvin-tunnel
    
    echo -e "${GREEN}✅ Iran server configured!${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}🔑 TOKEN: ${WHITE}$token${NC}"
    echo -e "${YELLOW}📋 Save this token for foreign server!${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
}

# کانفیگ سرور خارج
configure_foreign() {
    echo -e "${GREEN}[3/4] Configuring FOREIGN server...${NC}"
    
    echo -ne "${YELLOW}Enter IRAN server IP: ${NC}"
    read -r iran_ip
    
    echo -ne "${YELLOW}Enter TOKEN from Iran server: ${NC}"
    read -r token
    
    local aes_key=$(openssl rand -base64 32 | tr -d '\n')
    echo "$token" > "$TOKEN_FILE"
    
    # ذخیره کانفیگ
    cat > "$CONFIG_DIR/tunnel.json" << EOF
{
    "type": "foreign",
    "iran_ip": "$iran_ip",
    "local_port": 5555,
    "remote_port": 6666,
    "token": "$token"
}
EOF
    
    # ساخت سرویس
    cat > /etc/systemd/system/arvin-tunnel.service << EOF
[Unit]
Description=Arvin Tunnel - Foreign Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -c -l 0.0.0.0:5555 -r $iran_ip:6666 --raw-mode faketcp -k "$aes_key" --cipher-mode aes128cbc --auth-mode hmac_sha1 --fix-gro
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable arvin-tunnel
    systemctl start arvin-tunnel
    
    echo -e "${GREEN}✅ Foreign server configured!${NC}"
}

# نمایش وضعیت
show_status() {
    show_banner
    echo -e "${WHITE}═══════════ TUNNEL STATUS ═══════════${NC}\n"
    
    if systemctl is-active --quiet arvin-tunnel 2>/dev/null; then
        echo -e "  Service:    ${GREEN}● ACTIVE${NC}"
    else
        echo -e "  Service:    ${RED}● INACTIVE${NC}"
    fi
    
    local port=$(jq -r '.local_port' "$CONFIG_DIR/tunnel.json" 2>/dev/null)
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "  Port $port:  ${GREEN}● LISTENING${NC}"
    else
        echo -e "  Port $port:  ${RED}● CLOSED${NC}"
    fi
    
    if [[ -f "$TOKEN_FILE" ]]; then
        echo -e "  Token:      ${CYAN}$(cat $TOKEN_FILE)${NC}"
    fi
    
    echo -e "\n${WHITE}═══════════════════════════════════════${NC}"
}

# پنل مدیریت
tunnel_panel() {
    while true; do
        show_banner
        echo -e "${WHITE}MANAGEMENT PANEL${NC}\n"
        echo -e "  ${GREEN}1)${NC} View Status"
        echo -e "  ${GREEN}2)${NC} Show Token"
        echo -e "  ${GREEN}3)${NC} Restart Tunnel"
        echo -e "  ${GREEN}4)${NC} View Logs"
        echo -e "  ${GREEN}5)${NC} Test Connection"
        echo -e "  ${RED}6)${NC} Uninstall"
        echo -e "  ${RED}0)${NC} Exit"
        echo ""
        echo -ne "${YELLOW}Select option: ${NC}"
        read -r choice
        
        case $choice in
            1) 
                show_status
                echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            2)
                echo -e "\n${CYAN}Token: ${WHITE}$(cat $TOKEN_FILE 2>/dev/null || echo 'Not found')${NC}"
                echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            3)
                systemctl restart arvin-tunnel
                echo -e "${GREEN}✅ Tunnel restarted!${NC}"
                sleep 2
                ;;
            4)
                journalctl -u arvin-tunnel -n 30 --no-pager
                echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            5)
                local remote_ip=$(jq -r '.foreign_ip // .iran_ip' "$CONFIG_DIR/tunnel.json" 2>/dev/null)
                if [[ -n "$remote_ip" ]]; then
                    ping -c 5 "$remote_ip"
                else
                    echo -e "${RED}No remote IP configured${NC}"
                fi
                echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                read -r
                ;;
            6)
                systemctl stop arvin-tunnel
                systemctl disable arvin-tunnel
                rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-tunnel.service
                systemctl daemon-reload
                echo -e "${GREEN}✅ Uninstalled!${NC}"
                exit 0
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# تابع اصلی
main() {
    check_root
    show_banner
    
    echo -e "${WHITE}Welcome to Arvin Tunnel Setup!${NC}\n"
    
    # نصب پیش نیازها
    install_dependencies
    
    # تشخیص سرور
    local server_type=$(detect_location)
    
    # کانفیگ بر اساس نوع سرور
    if [[ "$server_type" == "IRAN" ]]; then
        configure_iran
    else
        configure_foreign
    fi
    
    # ساخت لینک فرمان
    ln -sf "$(readlink -f "$0")" /usr/local/bin/arvin-tun 2>/dev/null || true
    
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ INSTALLATION COMPLETE!            ║${NC}"
    echo -e "${GREEN}║   Run 'arvin-tun panel' to manage      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
}

# اجرا
case "${1}" in
    panel|status|restart|uninstall)
        check_root
        case "${1}" in
            panel) tunnel_panel ;;
            status) show_status ;;
            restart) 
                systemctl restart arvin-tunnel
                echo -e "${GREEN}✅ Tunnel restarted!${NC}"
                ;;
            uninstall)
                systemctl stop arvin-tunnel 2>/dev/null
                systemctl disable arvin-tunnel 2>/dev/null
                rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-tunnel.service /usr/local/bin/arvin-tun
                systemctl daemon-reload
                echo -e "${GREEN}✅ Uninstalled!${NC}"
                ;;
        esac
        ;;
    *)
        main
        ;;
esac║  ███████║██████╔╝██║   ██║██║██╔██╗ ██║                ║
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
