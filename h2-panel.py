#!/usr/bin/env python3
# Hysteria2 常驻信息面板: UUID 订阅 + Basic 鉴权页面 + 本机流量统计

import base64
import json
import os
import secrets
import ssl
import subprocess
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

# 面板配置文件路径,由安装脚本写入
ENV_PATH = "/etc/hysteria/panel.env"
# systemd 服务名,用于显示运行状态
HYSTERIA_UNIT = "hysteria-server.service"
# 客户端安装包缓存目录,按版本号分文件保存
CLIENT_CACHE_DIR = "/var/lib/h2-panel/clients"
# 访问 GitHub API 必须带 User-Agent,否则会被拒绝
GITHUB_UA = "h2-panel"

# 各平台对应的 GitHub 仓库,以及如何从 latest 资源列表里挑出正确安装包
CLIENT_SPECS = {
    "windows": {
        "repo": "clash-verge-rev/clash-verge-rev",
        "label": "Windows 64 位",
    },
    "linux": {
        "repo": "clash-verge-rev/clash-verge-rev",
        "label": "Linux 64 位 deb",
    },
    "android": {
        "repo": "MetaCubeX/ClashMetaForAndroid",
        "label": "安卓 64 位",
    },
}


def load_env(path):
    """读取 KEY=VALUE 配置,等号后的内容原样作为值(密码可含特殊字符)"""
    data = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            data[key.strip()] = value
    return data


def html_escape(text):
    """把用户输入转成可安全放进 HTML 的文本"""
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def bytes_to_mib(num):
    """把字节换算成 MiB 字符串,失败时返回 --"""
    try:
        return "%.2f" % (float(num) / 1024.0 / 1024.0)
    except (TypeError, ValueError):
        return "--"


def fetch_traffic(url, password):
    """从本机 Hysteria 流量 API 汇总所有用户的 tx/rx,单位字节"""
    req = urllib.request.Request(url, headers={"Authorization": password})
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            payload = json.loads(resp.read().decode("utf-8") or "{}")
    except (urllib.error.URLError, ValueError, TimeoutError, json.JSONDecodeError):
        return None, None
    tx_total = 0
    rx_total = 0
    if isinstance(payload, dict):
        for item in payload.values():
            if isinstance(item, dict):
                tx_total += int(item.get("tx") or 0)
                rx_total += int(item.get("rx") or 0)
    return tx_total, rx_total


def hysteria_running():
    """Hysteria 服务是否处于 active"""
    try:
        return subprocess.call(
            ["systemctl", "is-active", "--quiet", HYSTERIA_UNIT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
    except OSError:
        return False


def match_client_asset(kind, name):
    """按文件名特征匹配官方安装包,不写死版本号"""
    if kind == "windows":
        return name.endswith("_x64-setup.exe") and "fixed_webview2" not in name
    if kind == "linux":
        return name.endswith("_amd64.deb") and not name.endswith(".sig")
    if kind == "android":
        return name.endswith(".apk") and "arm64-v8a" in name
    return False


def github_latest(repo):
    """拉取指定仓库的最新正式版 Release JSON"""
    url = "https://api.github.com/repos/%s/releases/latest" % repo
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": GITHUB_UA,
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def pick_client_asset(kind):
    """从 latest 接口选出对应平台的下载地址和文件名"""
    spec = CLIENT_SPECS[kind]
    data = github_latest(spec["repo"])
    tag = data.get("tag_name") or "latest"
    for asset in data.get("assets") or []:
        name = asset.get("name") or ""
        url = asset.get("browser_download_url") or ""
        if url and match_client_asset(kind, name):
            return tag, name, url
    raise LookupError("未找到 %s 的官方安装包" % kind)


def ensure_client_file(kind):
    """懒加载: 本地没有该版本则由服务器从 GitHub 下载并缓存"""
    os.makedirs(CLIENT_CACHE_DIR, exist_ok=True)
    tag, name, url = pick_client_asset(kind)
    dest = os.path.join(CLIENT_CACHE_DIR, "%s-%s-%s" % (kind, tag, name))
    if os.path.isfile(dest) and os.path.getsize(dest) > 0:
        return dest, name
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": GITHUB_UA})
    try:
        with urllib.request.urlopen(req, timeout=300) as resp, open(tmp, "wb") as out:
            while True:
                chunk = resp.read(256 * 1024)
                if not chunk:
                    break
                out.write(chunk)
        os.replace(tmp, dest)
    except Exception:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise
    return dest, name


def fail2ban_status():
    """读取 fail2ban sshd 监狱的当前封禁列表,未安装或未运行则说明原因"""
    try:
        active = subprocess.call(
            ["systemctl", "is-active", "--quiet", "fail2ban"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
        if not active:
            return {"ok": False, "reason": "fail2ban 未运行"}
        out = subprocess.check_output(
            ["fail2ban-client", "status", "sshd"],
            stderr=subprocess.STDOUT,
            timeout=5,
        )
        text = out.decode("utf-8", errors="replace")
    except FileNotFoundError:
        return {"ok": False, "reason": "未安装 fail2ban"}
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {"ok": False, "reason": "无法读取 fail2ban 状态"}
    current = "0"
    total = "0"
    ips = []
    for line in text.splitlines():
        if "Currently banned" in line:
            current = line.split(":")[-1].strip()
        elif "Total banned" in line:
            total = line.split(":")[-1].strip()
        elif "Banned IP list" in line:
            rest = line.split(":", 1)[-1].strip()
            ips = rest.split() if rest else []
    return {"ok": True, "current": current, "total": total, "ips": ips}


def render_ban_block():
    """生成 SSH 黑名单卡片 HTML"""
    info = fail2ban_status()
    if not info["ok"]:
        return (
            '<div class="card dlbox">'
            '<div style="font-size:16px;font-weight:650;margin-bottom:8px">SSH 黑名单</div>'
            '<p class="foot" style="margin:0">%s。安装 fail2ban 后可在此查看被封禁的 IP。</p>'
            "</div>"
        ) % html_escape(info["reason"])
    if info["ips"]:
        chips = "".join(
            '<span class="ip">%s</span>' % html_escape(ip) for ip in info["ips"]
        )
    else:
        chips = '<span class="foot">当前没有被封禁的 IP</span>'
    return (
        '<div class="card dlbox">'
        '<div style="font-size:16px;font-weight:650;margin-bottom:8px">SSH 黑名单</div>'
        '<div class="stats">'
        '<div class="stat"><span>当前封禁</span><b>%s</b></div>'
        '<div class="stat"><span>累计封禁</span><b>%s</b></div>'
        "</div>"
        '<div class="iplist">%s</div>'
        '<p class="foot" style="margin:12px 0 0">来自 fail2ban 的 sshd 监狱,防止 SSH 暴力破解。</p>'
        "</div>"
    ) % (html_escape(info["current"]), html_escape(info["total"]), chips)


def make_qr_svg(url):
    """用 qrencode 生成订阅链接的 SVG,失败返回空字符串"""
    try:
        out = subprocess.check_output(
            ["qrencode", "-t", "SVG", "-o", "-", url],
            stderr=subprocess.DEVNULL,
        )
        text = out.decode("utf-8", errors="replace")
        start = text.find("<svg")
        return text[start:] if start >= 0 else ""
    except (OSError, subprocess.CalledProcessError):
        return ""


class PanelState:
    """进程内配置与证书缓存,供请求处理和 TLS 热加载使用"""

    def __init__(self, env):
        self.env = env
        # 监听端口,默认 18080
        self.port = int(env.get("PANEL_PORT") or "18080")
        # 面板登录密码,与 Hysteria 连接密码相同
        self.password = env.get("PANEL_PASSWORD") or ""
        # 订阅路径中的随机 token,Clash 靠它拿到 yaml
        self.token = env.get("SUB_TOKEN") or ""
        # 客户端配置文件绝对路径
        self.yaml_path = env.get("H2_YAML") or "/etc/hysteria/h2.yaml"
        # 展示用的服务器地址(域名或 IP)
        self.server_host = env.get("SERVER_HOST") or ""
        # Hysteria 连接端口
        self.server_port = env.get("SERVER_PORT") or "443"
        # 本机流量 API
        self.traffic_url = env.get("TRAFFIC_URL") or "http://127.0.0.1:9999/traffic"
        # 是否启用 HTTPS
        self.use_tls = env.get("USE_TLS") == "1"
        self.cert_file = env.get("CERT_FILE") or ""
        self.key_file = env.get("KEY_FILE") or ""
        self.cert_mtime = 0
        self.ssl_context = None

    def public_scheme(self):
        """对外打印/页面使用的协议"""
        return "https" if self.use_tls else "http"

    def sub_filename(self):
        """Clash 导入订阅时用作配置名称,用域名或 IP,避免显示成 h2.yaml"""
        host = self.server_host or "h2"
        safe = []
        for ch in host:
            if ch.isalnum() or ch in ".-_":
                safe.append(ch)
            else:
                safe.append("_")
        return "".join(safe) + ".yaml"

    def sub_url(self):
        """Clash 订阅完整 URL"""
        return "%s://%s:%s/%s/h2.yaml" % (
            self.public_scheme(),
            self.server_host,
            self.port,
            self.token,
        )

    def reload_cert_if_needed(self):
        """证书文件更新后重新加载,ACME 续期后不必重启面板"""
        if not self.use_tls or not self.cert_file or not self.key_file:
            return
        if not os.path.isfile(self.cert_file) or not os.path.isfile(self.key_file):
            return
        mtime = max(os.path.getmtime(self.cert_file), os.path.getmtime(self.key_file))
        if self.ssl_context is not None and mtime == self.cert_mtime:
            return
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(self.cert_file, self.key_file)
        self.ssl_context = ctx
        self.cert_mtime = mtime


STATE = None


def check_basic_auth(header_value, password):
    """校验 HTTP Basic,只比对密码,用户名随意"""
    if not header_value or not header_value.startswith("Basic "):
        return False
    try:
        decoded = base64.b64decode(header_value[6:]).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return False
    _, _, supplied = decoded.partition(":")
    return secrets.compare_digest(supplied, password)


def render_page(state):
    """生成深色信息面板 HTML"""
    running = hysteria_running()
    tx, rx = fetch_traffic(state.traffic_url, state.password)
    tx_text = bytes_to_mib(tx) if tx is not None else "--"
    rx_text = bytes_to_mib(rx) if rx is not None else "--"
    sub = state.sub_url()
    qr = make_qr_svg(sub)
    status_class = "ok" if running else "bad"
    status_text = "运行中" if running else "已停止"
    qr_block = qr if qr else "<p class='hint'>二维码生成失败,请复制订阅链接</p>"
    ban_block = render_ban_block()
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hysteria 2</title>
<style>
:root { --bg:#0f1419; --card:#1a2332; --line:#2a3548; --text:#e8eef7; --muted:#8b9bb4; --green:#3ddc84; --red:#f07178; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font-family:ui-sans-serif,"PingFang SC","Microsoft YaHei",sans-serif; }
.wrap { max-width:920px; margin:0 auto; padding:20px 16px 32px; }
.top { display:flex; justify-content:space-between; align-items:center; margin-bottom:16px; }
h1 { margin:0; font-size:22px; font-weight:650; }
.dot { width:8px; height:8px; border-radius:50%%; display:inline-block; margin-right:6px; }
.ok .dot { background:var(--green); }
.bad .dot { background:var(--red); }
.status { color:var(--muted); font-size:14px; }
.grid { display:grid; grid-template-columns: 1fr 1.2fr; gap:16px; }
@media (max-width:720px) { .grid { grid-template-columns:1fr; } }
.card { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px; }
.qr { background:#fff; border-radius:12px; padding:14px; display:flex; justify-content:center; }
.qr svg { width:220px; height:220px; display:block; }
.stats { display:flex; gap:12px; margin-bottom:16px; }
.stat { flex:1; background:#121a26; border-radius:10px; padding:12px 14px; }
.stat b { display:block; font-size:22px; margin-top:4px; }
.stat span { color:var(--muted); font-size:12px; }
.row { display:flex; gap:8px; margin:10px 0; align-items:flex-start; }
.k { width:72px; color:var(--muted); flex-shrink:0; padding-top:8px; font-size:13px; }
.v { flex:1; word-break:break-all; background:#121a26; border-radius:8px; padding:8px 10px; font-size:14px; }
.btns { display:flex; gap:8px; flex-shrink:0; }
button { background:#243044; color:var(--text); border:1px solid var(--line); border-radius:8px; padding:8px 10px; cursor:pointer; }
button:hover { border-color:var(--green); color:var(--green); }
.foot { margin-top:16px; color:var(--muted); font-size:13px; line-height:1.6; }
.hint { color:#666; }
.dlbox { margin-top:16px; }
.dl { display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }
.dlbtn { background:#243044; color:var(--text); border:1px solid var(--line); border-radius:8px; padding:10px 12px; text-decoration:none; font-size:14px; }
.dlbtn:hover { border-color:var(--green); color:var(--green); }
.iplist { display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }
.ip { background:#121a26; border:1px solid var(--line); border-radius:8px; padding:6px 10px; font-size:13px; font-family:ui-monospace,monospace; }
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <h1>Hysteria 2</h1>
    <div class="status %s"><span class="dot"></span>%s</div>
  </div>
  <div class="grid">
    <div class="card">
      <div class="qr">%s</div>
      <p class="foot" style="margin:12px 0 0">手机扫描二维码导入订阅</p>
    </div>
    <div class="card">
      <div class="stats">
        <div class="stat"><span>上行</span><b>%s MiB</b></div>
        <div class="stat"><span>下行</span><b>%s MiB</b></div>
      </div>
      <div class="row"><div class="k">服务器</div><div class="v">%s</div></div>
      <div class="row"><div class="k">端口</div><div class="v">%s</div></div>
      <div class="row">
        <div class="k">密码</div>
        <div class="v" id="pw">********</div>
        <div class="btns"><button type="button" id="toggle">显示</button></div>
      </div>
      <div class="row">
        <div class="k">订阅</div>
        <div class="v" id="sub">%s</div>
        <div class="btns"><button type="button" id="copy">复制链接</button></div>
      </div>
    </div>
  </div>
  <div class="card dlbox">
    <div style="font-size:16px;font-weight:650;margin-bottom:8px">客户端下载</div>
    <p class="foot" style="margin:0">这里提供官方最新正式版,由这台服务器代为从 GitHub 获取后给你下载,无需 VPN / 代理。没有节点时也能先装上 Clash,再导入上方订阅即可使用。首次点击可能需要等待一会儿。</p>
    <div class="dl">
      <a class="dlbtn" href="/clients/windows">Windows 64 位 (Clash Verge)</a>
      <a class="dlbtn" href="/clients/android">安卓 64 位 (ClashMeta)</a>
      <a class="dlbtn" href="/clients/linux">Linux 64 位 deb (Clash Verge)</a>
    </div>
  </div>
  %s
  <p class="foot">订阅链接含随机路径,不要发到群里。面板服务停止后,Clash 将无法在线更新该订阅。</p>
</div>
<script>
var realPw = %s;
var hidden = true;
document.getElementById("toggle").onclick = function () {
  hidden = !hidden;
  document.getElementById("pw").textContent = hidden ? "********" : realPw;
  this.textContent = hidden ? "显示" : "隐藏";
};
document.getElementById("copy").onclick = function () {
  var t = document.getElementById("sub").textContent;
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(t);
  }
  this.textContent = "已复制";
  var btn = this;
  setTimeout(function () { btn.textContent = "复制链接"; }, 1500);
};
</script>
</body>
</html>
""" % (
        status_class,
        status_text,
        qr_block,
        html_escape(tx_text),
        html_escape(rx_text),
        html_escape(state.server_host),
        html_escape(state.server_port),
        html_escape(sub),
        ban_block,
        json.dumps(state.password, ensure_ascii=False),
    )


class Handler(BaseHTTPRequestHandler):
    """只处理订阅 yaml 和鉴权后面板,其它路径一律 404"""

    def log_message(self, fmt, *args):
        return

    def send_unauthorized(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Hysteria2"')
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"auth required")

    def send_bytes(self, code, content_type, body, extra=None):
        if not isinstance(body, bytes):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_file(self, filepath, filename):
        """把缓存的安装包按附件方式发给浏览器,避免整文件读进内存"""
        size = os.path.getsize(filepath)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % filename)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(filepath, "rb") as f:
            while True:
                chunk = f.read(256 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        state = STATE
        path = self.path.split("?", 1)[0]
        sub_path = "/%s/h2.yaml" % state.token
        if path == sub_path:
            try:
                with open(state.yaml_path, "rb") as f:
                    data = f.read()
            except OSError:
                self.send_bytes(404, "text/plain; charset=utf-8", "yaml not found")
                return
            self.send_bytes(
                200,
                "text/yaml; charset=utf-8",
                data,
                {
                    "Content-Disposition": "attachment; filename=%s" % state.sub_filename(),
                    "profile-title": state.server_host or "Hysteria2",
                },
            )
            return
        if path != "/":
            if path.startswith("/clients/"):
                if not check_basic_auth(self.headers.get("Authorization"), state.password):
                    self.send_unauthorized()
                    return
                kind = path.rsplit("/", 1)[-1]
                if kind not in CLIENT_SPECS:
                    self.send_bytes(404, "text/plain; charset=utf-8", "not found")
                    return
                try:
                    filepath, filename = ensure_client_file(kind)
                    self.send_file(filepath, filename)
                except Exception:
                    self.send_bytes(
                        502,
                        "text/plain; charset=utf-8",
                        "从 GitHub 获取安装包失败,请稍后重试",
                    )
                return
            self.send_bytes(404, "text/plain; charset=utf-8", "not found")
            return
        if not check_basic_auth(self.headers.get("Authorization"), state.password):
            self.send_unauthorized()
            return
        self.send_bytes(200, "text/html; charset=utf-8", render_page(state))


class PanelServer(HTTPServer):
    """每次连接前检查证书是否已续期"""

    def get_request(self):
        sock, addr = super().get_request()
        STATE.reload_cert_if_needed()
        if STATE.ssl_context is not None:
            sock = STATE.ssl_context.wrap_socket(sock, server_side=True)
        return sock, addr


def main():
    global STATE
    STATE = PanelState(load_env(ENV_PATH))
    if STATE.use_tls:
        STATE.reload_cert_if_needed()
        if STATE.ssl_context is None:
            raise SystemExit("USE_TLS=1 但证书文件不可读")
    server = PanelServer(("0.0.0.0", STATE.port), Handler)
    scheme = STATE.public_scheme()
    print("h2-panel listening on %s://0.0.0.0:%s" % (scheme, STATE.port))
    server.serve_forever()


if __name__ == "__main__":
    main()
