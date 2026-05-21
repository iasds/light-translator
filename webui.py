#!/usr/bin/env python3
"""Translation Web UI — 极端轻量，单文件，零依赖"""
import http.server
import json
import sys
import os
import urllib.parse
from translate import TranslationService, LANGUAGES

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PORT = 8080

HTML = r'''<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>翻译</title>
<style>
:root{--bg:#0d1117;--fg:#c9d1d9;--border:#30363d;--accent:#58a6ff;--input:#161b22}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,sans-serif;min-height:100vh;display:flex;justify-content:center;padding:20px}
main{width:100%;max-width:720px}
h1{font-size:18px;font-weight:600;margin-bottom:16px;color:var(--accent)}
.row{display:flex;gap:8px;margin-bottom:8px}
.row select{flex:1}
textarea,select{width:100%;background:var(--input);color:var(--fg);border:1px solid var(--border);border-radius:6px;padding:10px 12px;font:inherit;outline:none;resize:vertical}
textarea:focus,select:focus{border-color:var(--accent)}
textarea{min-height:140px;margin-bottom:8px}
textarea[readonly]{min-height:100px}
button{width:100%;background:var(--accent);color:#fff;border:none;border-radius:6px;padding:10px;font:inherit;font-weight:600;cursor:pointer;margin-bottom:8px}
button:hover{opacity:.9}
button:disabled{opacity:.4;cursor:not-allowed}
.status{font-size:12px;color:#8b949e;text-align:center;margin-top:4px}
.spin{animation:spin .6s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head>
<body>
<main>
<h1>Qubes 翻译</h1>
<div class="row">
  <select id="src"></select>
  <span style="color:#8b949e;align-self:center;font-size:18px">→</span>
  <select id="tgt"></select>
</div>
<textarea id="input" placeholder="输入文本...&#10;支持中文、英文、日文等 33 种语言" autofocus></textarea>
<button id="btn" onclick="translate()">翻译</button>
<textarea id="output" readonly placeholder="翻译结果..."></textarea>
<div class="status" id="status">就绪</div>
</main>
<script>
const LANG={{LANG_JSON}};
const sel=(id)=>document.getElementById(id);
function buildOpts(){
  const o=Object.entries(LANG).map(([k,v])=>`<option value="${k}">${v}</option>`).join('');
  sel('src').innerHTML='<option value="auto">自动检测</option>'+o;
  sel('tgt').innerHTML=o;
  sel('tgt').value='en';
}
async function translate(){
  const btn=sel('btn'),st=sel('status'),input=sel('input').value.trim();
  if(!input)return;
  btn.disabled=true;st.textContent='翻译中...';
  try{
    const r=await fetch('/api/translate',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({text:input,source:sel('src').value,target:sel('tgt').value})
    });
    const d=await r.json();
    sel('output').value=d.translation||d.error||'';
    st.textContent=d.time?`${(d.time/1000).toFixed(1)}s`:d.error||'完成';
  }catch(e){st.textContent='网络错误'}
  btn.disabled=false;
}
sel('input').addEventListener('keydown',e=>{if(e.key==='Enter'&&e.ctrlKey)translate()});
buildOpts();
</script>
</body>
</html>'''

class Handler(http.server.BaseHTTPRequestHandler):
    service = None

    def do_GET(self):
        if self.path == '/':
            self._serve_html()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == '/api/translate':
            self._handle_translate()
        else:
            self.send_error(404)

    def _serve_html(self):
        lang_json = json.dumps({k: v for k, v in sorted(LANGUAGES.items())}, ensure_ascii=False)
        html = HTML.replace('{{LANG_JSON}}', lang_json)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode())

    def _handle_translate(self):
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length))
        text = body.get('text', '')
        src = body.get('source', 'auto')
        tgt = body.get('target', 'en')
        import time
        t0 = time.time()
        result = self.service.translate(text, src, tgt)
        elapsed = int((time.time() - t0) * 1000)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.end_headers()
        self.wfile.write(json.dumps({'translation': result, 'time': elapsed}, ensure_ascii=False).encode())

    def log_message(self, format, *args):
        pass  # 静默 HTTP 日志


def main():
    print("正在加载模型...")
    service = TranslationService()
    if not service.load_model():
        sys.exit(1)

    Handler.service = service
    print(f"Web UI 已启动: http://localhost:{PORT}")
    print("在其他 VM 的浏览器访问 translation qube 的 IP")
    httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n关闭")
        httpd.server_close()


if __name__ == '__main__':
    main()
