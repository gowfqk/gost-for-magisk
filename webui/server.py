#!/usr/bin/env python3

import http.server
import json
import os
import subprocess
import signal
import socketserver
import urllib.parse
import threading
import time
import sys
import base64
from pathlib import Path

MODDIR = sys.argv[1] if len(sys.argv) > 1 else "/data/adb/modules/gost_proxy"
WEBUI_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080

CONFIG_PATH = os.path.join(MODDIR, "gost", "config.json")
LOG_PATH = os.path.join(MODDIR, "logs", "gost.log")
GOST_PID_FILE = "/tmp/gost.pid"
WEBUI_PID_FILE = "/tmp/gost-webui.pid"
WEBUI_DIR = os.path.join(MODDIR, "webui")

MAX_LOG_LINES = 200


def read_config():
    try:
        with open(CONFIG_PATH, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {
            "proxy_type": "http",
            "listen_port": 1080,
            "listen_addr": "0.0.0.0",
            "webui_port": 8080,
            "auth": {"enabled": False, "username": "", "password": ""},
            "upstream": {"enabled": False, "type": "http", "addr": "", "port": 0, "username": "", "password": "", "route": "", "ws_path": "", "ws_host": ""},
            "shadowsocks": {"method": "aes-256-cfb", "password": ""},
            "tls": {"cert": "", "key": "", "ca": ""},
            "websocket": {"path": "/ws", "host": ""},
            "advanced": {"dns": "", "log_level": "info", "routes": [], "multi_listen": []}
        }


def write_config(config_data):
    tmp_path = CONFIG_PATH + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(config_data, f, indent=4, ensure_ascii=False)
    os.replace(tmp_path, CONFIG_PATH)


def get_gost_status():
    try:
        with open(GOST_PID_FILE, "r") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return "running", pid
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        return "stopped", None


def get_arch():
    try:
        result = subprocess.run(
            ["getprop", "ro.product.cpu.abi"],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def get_logs(lines=MAX_LOG_LINES):
    try:
        with open(LOG_PATH, "r") as f:
            all_lines = f.readlines()
        return "".join(all_lines[-lines:])
    except FileNotFoundError:
        return "No logs available."
    except Exception as e:
        return f"Error reading logs: {str(e)}"


def start_gost():
    status, pid = get_gost_status()
    if status == "running":
        return {"success": False, "message": f"gost is already running (PID: {pid})"}
    try:
        start_script = os.path.join(MODDIR, "scripts", "start.sh")
        subprocess.Popen(
            ["sh", start_script, MODDIR],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(1)
        new_status, new_pid = get_gost_status()
        if new_status == "running":
            return {"success": True, "message": f"gost started (PID: {new_pid})"}
        return {"success": False, "message": "gost failed to start"}
    except Exception as e:
        return {"success": False, "message": f"Error: {str(e)}"}


def stop_gost():
    status, pid = get_gost_status()
    if status == "stopped":
        return {"success": False, "message": "gost is not running"}
    try:
        stop_script = os.path.join(MODDIR, "scripts", "stop.sh")
        subprocess.Popen(
            ["sh", stop_script, MODDIR],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(1)
        new_status, _ = get_gost_status()
        if new_status == "stopped":
            return {"success": True, "message": f"gost stopped (PID: {pid})"}
        return {"success": False, "message": "gost failed to stop"}
    except Exception as e:
        return {"success": False, "message": f"Error: {str(e)}"}


def restart_gost():
    stop_result = stop_gost()
    time.sleep(1)
    start_result = start_gost()
    return {
        "success": start_result["success"],
        "message": f"Restart: stop={stop_result['message']}, start={start_result['message']}"
    }


def _b64decode(s):
    """Base64 decode with automatic padding."""
    padding = len(s) % 4
    if padding:
        s += "=" * (4 - padding)
    return base64.b64decode(s)


def parse_proxy_link(link):
    try:
        # Manual parse to avoid urlparse lowercasing hostname / scheme issues
        scheme_end = link.index("://")
        scheme = link[:scheme_end]
        rest = link[scheme_end + 3:]
        if "?" in rest:
            encoded_part, query_string = rest.split("?", 1)
        else:
            encoded_part = rest
            query_string = ""
        decoded = urllib.parse.unquote(_b64decode(encoded_part).decode("utf-8"))
        at_idx = decoded.rfind("@")
        if at_idx == -1:
            return None
        auth_part = decoded[:at_idx]
        host_port = decoded[at_idx + 1:]
        colon_idx = auth_part.rfind(":")
        username = auth_part[:colon_idx]
        password = auth_part[colon_idx + 1:]
        hp_colon = host_port.rfind(":")
        host = host_port[:hp_colon]
        port = int(host_port[hp_colon + 1:])
        params = urllib.parse.parse_qs(query_string)
        remarks = params.get("remarks", [""])[0]
        remarks = urllib.parse.unquote(remarks)
        gost_b64 = params.get("gost", [""])[0]
        gost_obj = {}
        if gost_b64:
            try:
                gost_obj = json.loads(_b64decode(gost_b64).decode("utf-8"))
            except Exception:
                pass
        return {
            "scheme": scheme,
            "username": username,
            "password": password,
            "host": host,
            "port": port,
            "remarks": remarks,
            "gost": gost_obj
        }
    except Exception:
        return None


def build_gost_command(config):
    proxy_type = config.get("proxy_type", "http")
    listen_addr = config.get("listen_addr", "0.0.0.0")
    listen_port = config.get("listen_port", 1080)
    auth = config.get("auth", {})
    upstream = config.get("upstream", {})
    ss = config.get("shadowsocks", {})
    tls = config.get("tls", {})
    ws = config.get("websocket", {})

    listen_part = f"{listen_addr}:{listen_port}"

    if proxy_type == "http":
        listen_scheme = "http"
    elif proxy_type == "socks5":
        listen_scheme = "socks5"
    elif proxy_type == "ss":
        listen_scheme = "ss"
    elif proxy_type == "tls":
        listen_scheme = "tls"
    elif proxy_type == "ws":
        listen_scheme = "ws"
    else:
        listen_scheme = "http"

    if auth.get("enabled") and auth.get("username"):
        listen_url = f"{listen_scheme}://{auth['username']}:{auth['password']}@{listen_part}"
    else:
        listen_url = f"{listen_scheme}://{listen_part}"

    if proxy_type == "ss" and ss.get("password"):
        listen_url = f"ss://{ss['method']}:{ss['password']}@{listen_part}"

    if proxy_type == "tls":
        tls_opts = []
        if tls.get("cert"):
            tls_opts.append(f"certFile={tls['cert']}")
        if tls.get("key"):
            tls_opts.append(f"keyFile={tls['key']}")
        if tls_opts:
            listen_url += "?" + "&".join(tls_opts)

    if proxy_type == "ws" and ws.get("path"):
        ws_opts = [f"path={ws['path']}"]
        if ws.get("host"):
            ws_opts.append(f"host={ws['host']}")
        listen_url += "?" + "&".join(ws_opts)

    chain = ""
    if upstream.get("enabled") and upstream.get("addr"):
        up_type = upstream.get("type", "http")
        up_addr = f"{upstream['addr']}:{upstream.get('port', 0)}"
        up_route = upstream.get("route", "")
        if up_route == "ws":
            up_scheme = f"ws+{up_type}"
        elif up_route == "wss":
            up_scheme = f"wss+{up_type}"
        else:
            up_scheme = up_type
        if upstream.get("username"):
            up_user = urllib.parse.quote(str(upstream["username"]), safe="")
            up_pass = urllib.parse.quote(str(upstream["password"]), safe="")
            chain = f" -F \"{up_scheme}://{up_user}:{up_pass}@{up_addr}"
        else:
            chain = f" -F \"{up_scheme}://{up_addr}"
        if up_route in ("ws", "wss"):
            ws_opts = []
            ws_path = upstream.get("ws_path", "")
            ws_host = upstream.get("ws_host", "")
            if ws_path:
                ws_opts.append(f"path={ws_path}")
            if ws_host:
                ws_opts.append(f"host={ws_host}")
            if ws_opts:
                chain += "?" + "&".join(ws_opts)
        chain += "\""

    return f"-L {listen_url}{chain}"


def generate_gost_native_config(config):
    """Convert custom config to gost v2 native JSON format (ServeNodes/ChainNodes)."""
    proxy_type = config.get("proxy_type", "http")
    listen_addr = config.get("listen_addr", "0.0.0.0")
    listen_port = config.get("listen_port", 1080)
    auth = config.get("auth", {})
    upstream = config.get("upstream", {})
    ss = config.get("shadowsocks", {})
    tls = config.get("tls", {})
    ws = config.get("websocket", {})
    advanced = config.get("advanced", {})

    listen_part = f"{listen_addr}:{listen_port}"

    if proxy_type == "http":
        listen_scheme = "http"
    elif proxy_type == "socks5":
        listen_scheme = "socks5"
    elif proxy_type == "ss":
        listen_scheme = "ss"
    elif proxy_type == "tls":
        listen_scheme = "tls"
    elif proxy_type == "ws":
        listen_scheme = "ws"
    else:
        listen_scheme = "http"

    if auth.get("enabled") and auth.get("username"):
        listen_url = f"{listen_scheme}://{auth['username']}:{auth['password']}@{listen_part}"
    else:
        listen_url = f"{listen_scheme}://{listen_part}"

    if proxy_type == "ss" and ss.get("password"):
        listen_url = f"ss://{ss['method']}:{ss['password']}@{listen_part}"

    if proxy_type == "tls":
        tls_opts = []
        if tls.get("cert"):
            tls_opts.append(f"certFile={tls['cert']}")
        if tls.get("key"):
            tls_opts.append(f"keyFile={tls['key']}")
        if tls_opts:
            listen_url += "?" + "&".join(tls_opts)

    if proxy_type == "ws" and ws.get("path"):
        ws_opts = [f"path={ws['path']}"]
        if ws.get("host"):
            ws_opts.append(f"host={ws['host']}")
        listen_url += "?" + "&".join(ws_opts)

    serve_nodes = [listen_url]
    # Support multi_listen from advanced config
    for ml in advanced.get("multi_listen", []):
        if ml.get("url"):
            serve_nodes.append(ml["url"])

    chain_nodes = []
    if upstream.get("enabled") and upstream.get("addr"):
        up_type = upstream.get("type", "http")
        up_addr = f"{upstream['addr']}:{upstream.get('port', 0)}"
        up_route = upstream.get("route", "")
        if up_route == "ws":
            up_scheme = f"ws+{up_type}"
        elif up_route == "wss":
            up_scheme = f"wss+{up_type}"
        else:
            up_scheme = up_type
        if upstream.get("username"):
            up_user = urllib.parse.quote(str(upstream["username"]), safe="")
            up_pass = urllib.parse.quote(str(upstream["password"]), safe="")
            chain_url = f"{up_scheme}://{up_user}:{up_pass}@{up_addr}"
        else:
            chain_url = f"{up_scheme}://{up_addr}"
        if up_route in ("ws", "wss"):
            ws_opts = []
            ws_path = upstream.get("ws_path", "")
            ws_host = upstream.get("ws_host", "")
            if ws_path:
                ws_opts.append(f"path={ws_path}")
            if ws_host:
                ws_opts.append(f"host={ws_host}")
            if ws_opts:
                chain_url += "?" + "&".join(ws_opts)
        chain_nodes.append(chain_url)

    native_config = {
        "Debug": advanced.get("log_level", "info") == "debug",
        "ServeNodes": serve_nodes,
        "ChainNodes": chain_nodes
    }

    return native_config


def write_gost_native_config(config):
    """Generate gost native config and write to gost_native.json."""
    native_config = generate_gost_native_config(config)
    native_path = os.path.join(MODDIR, "gost", "gost_native.json")
    with open(native_path, "w") as f:
        json.dump(native_config, f, indent=2)
    return native_path


class GostAPIHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEBUI_DIR, **kwargs)

    def log_message(self, format, *args):
        pass

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/status":
            status, pid = get_gost_status()
            arch = get_arch()
            config = read_config()
            self.send_json({
                "gost": {"status": status, "pid": pid},
                "webui": {"status": "running", "port": WEBUI_PORT},
                "arch": arch,
                "listen_port": config.get("listen_port", 1080),
                "proxy_type": config.get("proxy_type", "http"),
                "listen_addr": config.get("listen_addr", "0.0.0.0")
            })
        elif path == "/api/config":
            config = read_config()
            self.send_json(config)
        elif path == "/api/logs":
            query = urllib.parse.parse_qs(parsed.query)
            lines = int(query.get("lines", [MAX_LOG_LINES])[0])
            logs = get_logs(lines)
            self.send_json({"logs": logs})
        elif path == "/api/arch":
            self.send_json({"arch": get_arch()})
        elif path == "/api/command":
            config = read_config()
            cmd = build_gost_command(config)
            self.send_json({"command": cmd})
        elif path.startswith("/api/"):
            self.send_json({"error": "Not found"}, 404)
        else:
            super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/start":
            result = start_gost()
            self.send_json(result)
        elif path == "/api/stop":
            result = stop_gost()
            self.send_json(result)
        elif path == "/api/restart":
            result = restart_gost()
            self.send_json(result)
        elif path == "/api/config":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                config_data = json.loads(body.decode("utf-8"))
                write_config(config_data)
                self.send_json({"success": True, "message": "Config saved"})
            except json.JSONDecodeError as e:
                self.send_json({"success": False, "message": f"Invalid JSON: {str(e)}"}, 400)
            except Exception as e:
                self.send_json({"success": False, "message": f"Error: {str(e)}"}, 500)
        elif path == "/api/config/import":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                config_data = json.loads(body.decode("utf-8"))
                write_config(config_data)
                self.send_json({"success": True, "message": "Config imported"})
            except Exception as e:
                self.send_json({"success": False, "message": f"Import error: {str(e)}"}, 400)
        elif path == "/api/parse-link":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
                link = data.get("link", "")
                result = parse_proxy_link(link)
                if result:
                    self.send_json({"success": True, "parsed": result})
                else:
                    self.send_json({"success": False, "message": "Failed to parse link"}, 400)
            except Exception as e:
                self.send_json({"success": False, "message": f"Parse error: {str(e)}"}, 400)
        elif path.startswith("/api/"):
            self.send_json({"error": "Not found"}, 404)
        else:
            self.send_json({"error": "Method not allowed"}, 405)


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True
    allow_reuse_port = True


def main():
    os.chdir(WEBUI_DIR)

    try:
        with open(WEBUI_PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass

    server = ReusableTCPServer(("0.0.0.0", WEBUI_PORT), GostAPIHandler)
    print(f"Gost WebUI server running on http://0.0.0.0:{WEBUI_PORT}")
    print(f"Module directory: {MODDIR}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server.server_close()
        try:
            os.remove(WEBUI_PID_FILE)
        except Exception:
            pass


if __name__ == "__main__":
    main()
