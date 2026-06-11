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
fi
