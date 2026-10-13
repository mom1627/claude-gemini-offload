#!/usr/bin/env bash
# claude-gemini-offload — best-effort installer for Ubuntu 24.04 (Oracle Cloud Always Free ARM)
# Usage: sudo DOMAIN=<YOUR_DOMAIN> ADMIN_PASSWORD=<YOUR_ADMIN_PASSWORD> bash install.sh
# Read this script before running it. Tested shape, not a guarantee.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${ADMIN_PASSWORD:?Set ADMIN_PASSWORD (min. 12 chars)}"
DOMAIN="${DOMAIN:-}"
SECRET_PATH="${SECRET_PATH:-$(openssl rand -hex 24)}"

# Fallback hostname via sslip.io if no domain given
if [ -z "$DOMAIN" ]; then
  IP="$(curl -fsS https://api.ipify.org)"
  DOMAIN="$(echo "$IP" | tr . -).sslip.io"
fi

echo "==> Packages"
apt-get update -y
apt-get install -y curl ca-certificates caddy openssl build-essential python3 iptables-persistent
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "==> OmniRoute"
npm install -g omniroute
id omni >/dev/null 2>&1 || useradd -m -s /bin/bash omni
sudo -u omni -H omniroute setup --non-interactive --password "$ADMIN_PASSWORD"
OMNI_BIN="$(command -v omniroute)"
sed "s#/usr/bin/omniroute#$OMNI_BIN#" "$(dirname "$0")/../examples/omniroute.service" > /etc/systemd/system/omniroute.service

echo "==> Key proxy (minimal Node reverse proxy that adds the API key)"
mkdir -p /opt/key-proxy /etc/key-proxy
cat > /opt/key-proxy/proxy.js <<'JS'
const http = require('http');
const { URL } = require('url');
const up = new URL(process.env.UPSTREAM || 'http://127.0.0.1:20128');
const key = process.env.OMNIROUTE_API_KEY;
const timeout = Number(process.env.REQUEST_TIMEOUT_MS || 600000);
http.createServer((req, res) => {
  const headers = { ...req.headers, host: up.host, authorization: `Bearer ${key}` };
  const p = http.request({ hostname: up.hostname, port: up.port, path: req.url, method: req.method, headers, timeout }, r => {
    res.writeHead(r.statusCode, r.headers); r.pipe(res);
  });
  p.on('error', e => { res.writeHead(502); res.end(String(e)); });
  req.pipe(p);
}).listen(Number(process.env.LISTEN_PORT || 20129), '127.0.0.1');
JS
[ -f /etc/key-proxy/.env ] || cp "$(dirname "$0")/../examples/.env.example" /etc/key-proxy/.env
chmod 600 /etc/key-proxy/.env; chown omni /etc/key-proxy/.env
cp "$(dirname "$0")/../examples/key-proxy.service" /etc/systemd/system/key-proxy.service

echo "==> Caddy"
sed -e "s#<YOUR_DOMAIN>#$DOMAIN#" -e "s#<YOUR_SECRET_PATH>#$SECRET_PATH#" \
  "$(dirname "$0")/../examples/Caddyfile" > /etc/caddy/Caddyfile

echo "==> Firewall (Oracle images use iptables; do not use ufw)"
iptables -I INPUT 5 -p tcp --dport 80  -m state --state NEW -j ACCEPT
iptables -I INPUT 5 -p tcp --dport 443 -m state --state NEW -j ACCEPT
netfilter-persistent save

systemctl daemon-reload
systemctl enable --now omniroute key-proxy
systemctl enable caddy && systemctl restart caddy

umask 077
echo "MCP URL (keep secret!): https://$DOMAIN/$SECRET_PATH/api/mcp/stream" > /root/claude-gemini-offload.txt
echo "Done. Dashboard: https://$DOMAIN"
echo "Next: add your Gemini key in the dashboard, create an OmniRoute API key,"
echo "put it into /etc/key-proxy/.env, then: systemctl restart key-proxy"
echo "Your secret MCP URL is in /root/claude-gemini-offload.txt"
