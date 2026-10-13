# Setup guide: Oracle Cloud Always Free + OmniRoute + Caddy

All values in `<ANGLE_BRACKETS>` are placeholders — replace them with your own and never commit them.

## 1. Create the VM

1. Sign up for Oracle Cloud (Always Free tier).
2. Compute → Instances → Create instance
   - Image: **Ubuntu 24.04** (aarch64)
   - Shape: **VM.Standard.A1.Flex**, 2 OCPU, 12 GB RAM
   - Add your SSH public key
3. Networking → VCN → Security List → add ingress rules for TCP **80** and **443** from `0.0.0.0/0`.
4. (Optional) point a DNS record at the VM, or use `<YOUR_IP_WITH_DASHES>.sslip.io` as a free hostname.

## 2. Open the host firewall

Oracle Ubuntu images block ports via iptables (don't use ufw here):

```bash
sudo iptables -I INPUT 5 -p tcp --dport 80  -m state --state NEW -j ACCEPT
sudo iptables -I INPUT 5 -p tcp --dport 443 -m state --state NEW -j ACCEPT
sudo netfilter-persistent save
```

## 3. Install Node.js and OmniRoute

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs build-essential python3
sudo npm install -g omniroute
sudo useradd -m -s /bin/bash omni
sudo -u omni -H omniroute setup --non-interactive --password '<YOUR_ADMIN_PASSWORD>'
```

Install the systemd unit from [`examples/omniroute.service`](../examples/omniroute.service):

```bash
sudo cp examples/omniroute.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now omniroute
```

OmniRoute now listens on `localhost:20128`.

## 4. Key proxy

The key proxy listens on `localhost:20129`, adds `Authorization: Bearer <OMNIROUTE_API_KEY>` and forwards to OmniRoute. This keeps the key out of the Claude connector URL.

```bash
sudo mkdir -p /etc/key-proxy
sudo cp examples/.env.example /etc/key-proxy/.env && sudo chmod 600 /etc/key-proxy/.env
sudo cp examples/key-proxy.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now key-proxy
```

## 5. Caddy (HTTPS)

```bash
sudo apt-get install -y caddy
sudo cp examples/Caddyfile /etc/caddy/Caddyfile   # edit placeholders first
sudo systemctl restart caddy
```

## 6. Gemini

1. Get a free API key from Google AI Studio.
2. Open `https://<YOUR_DOMAIN>` → OmniRoute dashboard → Providers → Gemini → paste key.
3. Enable `gemini-3.7-flash` and `gemini-3.5-flash`.
4. Raise request timeouts to **600 s** for long generations.
5. Create an OmniRoute API key and put it in `/etc/key-proxy/.env`.

## 7. Connect Claude

Claude → Settings → Connectors → **Add custom connector**:

```
https://<YOUR_DOMAIN>/<YOUR_SECRET_PATH>/api/mcp/stream
```

Generate a secret path with `openssl rand -hex 24`. Test by asking Claude: *"Use the Gemini tool to write a hello-world HTML page."*

## Troubleshooting

| Symptom | Fix |
|---|---|
| Browser can't reach the site | Check Oracle security list + iptables rules |
| Caddy TLS errors | DNS must point to the VM; ports 80/443 open |
| Timeouts on big tasks | Raise timeouts in OmniRoute and Caddy to 600 s |
| `journalctl -u omniroute -f` | Live OmniRoute logs |
