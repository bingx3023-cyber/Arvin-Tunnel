#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  ARVIN QUANTUM FRAGMENT PROTOCOL v4.0 - STABLE
#  Auto-Detect | Auto-Deps | ChaCha20-Poly1305 | QUIC Mimic
#  Github: https://github.com/bingx3023-cyber/Arvin-Tunnel
#  Install: bash Arvin.sh
#  Panel: arvin-tun
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

ARVIN_DIR="/opt/arvin-tun"
CONFIG_DIR="${ARVIN_DIR}/config"
LOG_DIR="${ARVIN_DIR}/logs"
BIN_DIR="${ARVIN_DIR}/bin"
TOKEN_FILE="${ARVIN_DIR}/token"
CONFIG_FILE="${CONFIG_DIR}/tunnel.json"
KEYS_FILE="${CONFIG_DIR}/keys.enc"
ENGINE_PY="${BIN_DIR}/fragment_engine.py"

banner() {
    clear
    echo -e "${C}"
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════╗
║          ARVIN QUANTUM FRAGMENT PROTOCOL v4.0          ║
║        ChaCha20-Poly1305 | Auto-Detect | QUIC          ║
╚══════════════════════════════════════════════════════════╝
BANNER
    echo -e "${N}"
}

install_deps() {
    echo -e "${G}[1/3] Installing dependencies...${N}"
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    apt update -y -qq 2>/dev/null || true

    for pkg in curl wget openssl jq python3 python3-pip netcat-openbsd iptables dnsutils; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "  -> ${Y}$pkg${N}"
            apt install -y -qq "$pkg" 2>/dev/null || true
        fi
    done

    echo -e "${G}[2/3] Installing cryptography...${N}"
    if ! python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
        pip3 install -q cryptography 2>/dev/null || \
        pip3 install -q --break-system-packages cryptography 2>/dev/null || \
        apt install -y -qq python3-cryptography 2>/dev/null || true
    fi

    if ! python3 -c "from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305" 2>/dev/null; then
        echo -e "${R}[!] Failed! Run: pip3 install cryptography --break-system-packages${N}"
        exit 1
    fi

    echo -e "  ${G}[+] OK${N}"
    mkdir -p "$ARVIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BIN_DIR"
}

create_engine() {
    echo -e "${G}[3/3] Building Quantum Engine...${N}"
    cat > "$ENGINE_PY" << 'PYEOF'
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
        return nonce + self.cipher.encrypt(nonce, data, None)

    def decrypt(self, data):
        return self.cipher.decrypt(data[:12], data[12:], None)

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
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for f in self.fragment(data):
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
    echo -e "  ${G}[+] Engine ready${N}"
}

detect_server() {
    echo -e "${Y}[*] Detecting server...${N}"
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        echo -e "${G}[+] FOREIGN SERVER${N}"
        echo "FOREIGN"
    elif curl -s --max-time 3 https://api.keylead.ir &>/dev/null; then
        echo -e "${B}[+] IRAN SERVER${N}"
        echo "IRAN"
    else
        echo -e "${W}1) Iran 🇮🇷  2) Foreign 🌍${N}"
        read -r c
        [[ "$c" == "1" ]] && echo "IRAN" || echo "FOREIGN"
    fi
}

configure() {
    local type=$1
    echo -e "${G}[4/4] Configuring...${N}"

    local chacha_key=$(openssl rand -base64 32 | tr -d '\n+/=' | head -c 32)
    local hmac_key=$(openssl rand -hex 32)
    local salt=$(openssl rand -hex 16)
    local token="AQFP-$(openssl rand -hex 24)"

    echo "${chacha_key}:${hmac_key}:${salt}:${token}" > "$KEYS_FILE"
    chmod 600 "$KEYS_FILE"
    echo "$token" > "$TOKEN_FILE"

    if [[ "$type" == "IRAN" ]]; then
        echo -ne "${Y}Foreign IP: ${N}"
        read -r rip
        cat > "$CONFIG_FILE" << EOF
{"type":"IRAN","remote_ip":"$rip","local_port":6666,"remote_port":5555,"mode":"listen","key_file":"$KEYS_FILE"}
EOF
        cat > /etc/systemd/system/arvin-quantum.service << SVC
[Unit]
Description=ARVIN Quantum Iran
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
        echo -ne "${Y}Iran IP: ${N}"
        read -r rip
        echo -ne "${Y}Token: ${N}"
        read -r token
        echo "$token" > "$TOKEN_FILE"
        cat > "$CONFIG_FILE" << EOF
{"type":"FOREIGN","remote_ip":"$rip","local_port":5555,"remote_port":6666,"mode":"send","key_file":"$KEYS_FILE"}
EOF
        cat > /etc/systemd/system/arvin-quantum.service << SVC
[Unit]
Description=ARVIN Quantum Foreign
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $ENGINE_PY --mode send --host $rip --port 6666 --config $CONFIG_FILE
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

    echo ""
    echo -e "${G}╔══════════════════════════════════╗${N}"
    echo -e "${G}║     ✅ TUNNEL INSTALLED!        ║${N}"
    echo -e "${G}║     Run: arvin-tun              ║${N}"
    echo -e "${G}╚══════════════════════════════════╝${N}"
    echo -e "${C}Token: ${W}$token${N}"
}

show_status() {
    banner
    echo -e "${W}═══════ STATUS ═══════${N}"
    systemctl is-active --quiet arvin-quantum && echo -e "Tunnel: ${G}ONLINE${N}" || echo -e "Tunnel: ${R}OFFLINE${N}"
    echo -e "Token: ${C}$(cat "$TOKEN_FILE" 2>/dev/null || echo N/A)${N}"
    local rip=$(jq -r '.remote_ip' "$CONFIG_FILE" 2>/dev/null)
    [[ -n "$rip" && "$rip" != "null" ]] && echo -e "Ping: ${G}$(ping -c 2 -W 1 "$rip" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')ms${N}"
}

panel() {
    while true; do
        banner
        echo -e "${W}1) Status  2) Token  3) Restart  4) Logs  5) Guide  6) Uninstall  0) Exit${N}"
        read -r c
        case $c in
            1) show_status; echo -e "${Y}Enter...${N}"; read -r ;;
            2) echo -e "${C}$(cat "$TOKEN_FILE" 2>/dev/null || echo N/A)${N}"; echo -e "${Y}Enter...${N}"; read -r ;;
            3) systemctl restart arvin-quantum; echo -e "${G}OK${N}"; sleep 2 ;;
            4) journalctl -u arvin-quantum -f ;;
            5) cat << 'GUIDE'
Iran: bash Arvin.sh -> Foreign IP -> Save Token
Foreign: bash Arvin.sh -> Iran IP -> Enter Token
arvin-tun = Panel | arvin-tun status = Status
GUIDE
               echo -e "${Y}Enter...${N}"; read -r ;;
            6) systemctl stop arvin-quantum 2>/dev/null; systemctl disable arvin-quantum 2>/dev/null
               rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-quantum.service /usr/local/bin/arvin-tun
               echo -e "${G}Removed${N}"; exit 0 ;;
            0) exit 0 ;;
        esac
    done
}

main() {
    banner
    install_deps
    create_engine
    configure "$(detect_server)"
}

case "${1:-}" in
    panel) panel ;;
    status) show_status ;;
    restart) systemctl restart arvin-quantum; echo -e "${G}OK${N}" ;;
    uninstall)
        systemctl stop arvin-quantum 2>/dev/null
        systemctl disable arvin-quantum 2>/dev/null
        rm -rf "$ARVIN_DIR" /etc/systemd/system/arvin-quantum.service /usr/local/bin/arvin-tun
        echo -e "${G}Removed${N}"
        ;;
    *) main ;;
esac
