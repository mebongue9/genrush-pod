#!/usr/bin/env python3
"""genrush pod agent: tiny HTTP control plane on port 8000, reached through RunPod's HTTP proxy. Replaces SSH/scp
(public IPs are scarce and stall pod allocation; council 2026-09-17). Auth: header X-Token == $GENRUSH_AGENT_TOKEN.
  GET  /health                 -> {"ok":true,"comfy":bool,"hold":bool,"busy":bool}
  POST /put?path=P   (body)    -> write file
  GET  /get?path=P             -> file bytes
  POST /run?name=N   (body=sh) -> start `bash -c body` in background, log to /workspace/genrush/logs/N.log, N.exit on finish
  GET  /log?name=N&tail=K      -> last K bytes of the log + exit code if finished
  GET  /ls?path=P              -> names
"""
import json, os, subprocess, sys, urllib.request, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
TOKEN = os.environ.get("GENRUSH_AGENT_TOKEN", "")

# THE LOCK (RENDER-CHECKLIST.md). This agent is the ONLY way into the pod: no SSH, no public IP.
# It runs nothing except these approved entrypoints. Rendering only happens through pod_episode.py, which
# enforces every checklist gate. A script that tries to go around the pipeline gets HTTP 403 here.
# There is no override header and no admin flag. To allow something new, edit this list, commit, push.
import re as _re
APPROVED = [
    _re.compile(r"^export PATH=/workspace/bin:/workspace/venv/bin:\$PATH; cd /workspace/genrush && "
                r"/workspace/venv/bin/python -u pod_episode\.py episodes/[\w-]+\.json( --[\w-]+( [\w/.,-]+)?)*$"),
    _re.compile(r"^touch /workspace/genrush/HOLD$"),
    _re.compile(r"^rm -f /workspace/genrush/HOLD$"),
    _re.compile(r"^bash /workspace/genrush/(setup_volume|h3_download|chatterbox_provision)\.sh( --rebuild)?$"),
]


def approved(cmd: str) -> bool:
    return any(p.match(cmd.strip()) for p in APPROVED)
LOGS = Path("/workspace/genrush/logs"); LOGS.mkdir(parents=True, exist_ok=True)


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(data))); self.end_headers()
        self.wfile.write(data)

    def _auth(self):
        if not TOKEN or self.headers.get("X-Token") != TOKEN:
            self._send(401, {"error": "bad token"}); return False
        return True

    def log_message(self, *a):  # quiet
        pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = dict(urllib.parse.parse_qsl(u.query))
        if u.path == "/health":   # no auth: used as the readiness probe
            comfy = False
            try:
                urllib.request.urlopen("http://127.0.0.1:8188/system_stats", timeout=5); comfy = True
            except Exception:
                pass
            busy = any(not (LOGS / (f.name[:-4] + ".exit")).exists() for f in LOGS.glob("*.log"))
            return self._send(200, {"ok": True, "comfy": comfy, "hold": Path("/workspace/genrush/HOLD").exists(), "busy": busy,
                                    "setup": not (Path("/workspace/ComfyUI/main.py").exists() and Path("/workspace/venv/bin/python").exists())})
        if not self._auth(): return
        if u.path == "/get":
            p = Path(q["path"])
            if not p.is_file(): return self._send(404, {"error": "no file"})
            self.send_response(200); self.send_header("Content-Type", "application/octet-stream"); self.send_header("Content-Length", str(p.stat().st_size)); self.end_headers()
            with open(p, "rb") as f:
                while chunk := f.read(1 << 20):
                    self.wfile.write(chunk)
            return
        if u.path == "/log":
            n = q["name"]; lp, ep = LOGS / f"{n}.log", LOGS / f"{n}.exit"
            tail = int(q.get("tail", 4000)); txt = ""
            if lp.exists():
                with open(lp, "rb") as f:
                    f.seek(max(0, lp.stat().st_size - tail)); txt = f.read().decode(errors="replace")
            return self._send(200, {"log": txt, "exit": int(ep.read_text() or -1) if ep.exists() else None})
        if u.path == "/ls":
            p = Path(q.get("path", "/workspace"))
            return self._send(200, sorted(x.name for x in p.iterdir()) if p.is_dir() else [])
        self._send(404, {"error": "no route"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path); q = dict(urllib.parse.parse_qsl(u.query))
        if not self._auth(): return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if u.path == "/put":
            p = Path(q["path"]); p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(body)
            return self._send(200, {"ok": True, "bytes": len(body)})
        if u.path == "/run":
            if not approved(body.decode(errors="replace")):
                return self._send(403, {"error": "BLOCKED by the render checklist: not an approved entrypoint. "
                                                 "Render through genrush.py episode, never around it."})
            n = q["name"]; lp, ep = LOGS / f"{n}.log", LOGS / f"{n}.exit"
            ep.unlink(missing_ok=True)
            script = body.decode() + f"\necho $? > {ep}\n"
            subprocess.Popen(["bash", "-c", script], stdout=open(lp, "wb"), stderr=subprocess.STDOUT, cwd="/workspace/genrush", start_new_session=True)
            return self._send(200, {"ok": True, "log": str(lp)})
        self._send(404, {"error": "no route"})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1]) if len(sys.argv) > 1 else 8000), H).serve_forever()
