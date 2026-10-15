#!/usr/bin/env python3
# Run on VPS by /opt/x-digest/pull.sh: mirror gh-pages repo -> /var/www/x-digest with real .jpg images and plain HTML.
import os,re,base64,shutil
R='/opt/x-digest/repo'; W='/var/www/x-digest'
for root,dirs,files in os.walk(R):
    dirs[:]=[d for d in dirs if not d.startswith('.')]
    rel=os.path.relpath(root,R); out=os.path.join(W,rel); 
    if 'index.html' not in files: continue
    os.makedirs(out,exist_ok=True)
    h=open(os.path.join(root,'index.html')).read()
    for b in re.findall(r'data-b64="([^"]+)"',h):
        open(os.path.join(out,b[:-4]+'.jpg'),'wb').write(base64.b64decode(open(os.path.join(root,b)).read()))
        h=h.replace(f'data-b64="{b}" alt="loading…"',f'src="{b[:-4]}.jpg" loading=lazy')
    h=re.sub(r'<script>document\.querySelectorAll.*?</script>','',h,flags=re.S)
    open(os.path.join(out,'index.html'),'w').write(h)
