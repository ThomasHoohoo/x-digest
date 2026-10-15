#!/usr/bin/env bash
# Run ON THE VPS as root (paste into your own SSH session). Serves http://<VPS>/ from /var/www/x-digest on port 80 only.
# Pulls the GitHub Pages branch every 30 min and converts the .b64 images back into normal .jpg + plain HTML.
set -e
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
# Safety: abort if port 80 is held by something other than nginx
if ss -ltnp 2>/dev/null | grep -E ':80\s' | grep -vq nginx; then echo "Port 80 used by another service; aborting:"; ss -ltnp | grep -E ':80\s'; exit 1; fi
command -v apt-get >/dev/null || { echo "Debian/Ubuntu (apt) only; aborting"; exit 1; }
command -v nginx >/dev/null || (apt-get update && apt-get install -y nginx git python3)
command -v git >/dev/null || apt-get install -y git
command -v python3 >/dev/null || apt-get install -y python3
mkdir -p /var/www/x-digest /opt/x-digest
cat > /opt/x-digest/pull.sh <<'P'
#!/usr/bin/env bash
set -e
R=/opt/x-digest/repo
[ -d $R ] || git clone -q --depth 1 -b gh-pages https://github.com/ThomasHoohoo/x-digest.git $R
git -C $R fetch -q --depth 1 origin gh-pages && git -C $R reset -q --hard origin/gh-pages
python3 - <<'PY'
import os,re,base64,shutil
R='/opt/x-digest/repo'; W='/var/www/x-digest'
shutil.copy(f'{R}/index.html',f'{W}/index.html')
for d in os.listdir(R):
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',d): continue
    os.makedirs(f'{W}/{d}',exist_ok=True)
    h=open(f'{R}/{d}/index.html').read()
    for b in re.findall(r'data-b64="([^"]+)"',h):
        open(f'{W}/{d}/{b[:-4]}.jpg','wb').write(base64.b64decode(open(f'{R}/{d}/{b}').read()))
        h=h.replace(f'data-b64="{b}" alt="loading…"',f'src="{b[:-4]}.jpg" loading=lazy')
    h=re.sub(r'<script>document\.querySelectorAll.*?</script>','',h,flags=re.S)
    open(f'{W}/{d}/index.html','w').write(h)
PY
P
chmod +x /opt/x-digest/pull.sh && /opt/x-digest/pull.sh
cat > /etc/nginx/sites-available/x-digest <<'N'
server { listen 80; listen [::]:80; server_name _; root /var/www/x-digest; index index.html;
  location / { try_files $uri $uri/ =404; } }
N
# Disable only the stock default site, and only if no other site is enabled
OTHER=$(ls /etc/nginx/sites-enabled 2>/dev/null | grep -vE '^(default|x-digest)$' || true)
if [ -n "$OTHER" ]; then echo "Other nginx sites exist ($OTHER); x-digest will be added but may not be the port-80 default. Check manually."; sed -i 's/listen 80;/listen 80 default_server;/;s/listen \[::\]:80;/listen [::]:80 default_server;/' /etc/nginx/sites-available/x-digest || true
  grep -rl default_server /etc/nginx/sites-enabled | grep -v x-digest >/dev/null && sed -i 's/ default_server//g' /etc/nginx/sites-available/x-digest
else rm -f /etc/nginx/sites-enabled/default; fi
ln -sf /etc/nginx/sites-available/x-digest /etc/nginx/sites-enabled/x-digest
if ! nginx -t; then rm -f /etc/nginx/sites-enabled/x-digest; [ -e /etc/nginx/sites-available/default ] && [ -z "$OTHER" ] && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default; echo "nginx config test failed; rolled back"; exit 1; fi
systemctl enable --now nginx && systemctl reload nginx
command -v ufw >/dev/null && ufw status | grep -q active && ufw allow 80/tcp || true
(crontab -l 2>/dev/null | grep -v x-digest/pull.sh; echo "*/30 * * * * /opt/x-digest/pull.sh >/dev/null 2>&1") | crontab -
curl -sI http://127.0.0.1/ | head -1 || true
echo "Done: http://$(hostname -I | awk '{print $1}')/"
