#!/usr/bin/env python3
import json
import os
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def run(cmd, *, cwd=REPO, env=None, input_text=None, timeout=20):
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


class SecurityRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.host_validator = Path(tempfile.mkdtemp(prefix="gost-validator-")) / "config-validator"
        result = run(
            ["go", "build", "-trimpath", "-o", str(cls.host_validator), "."],
            cwd=REPO / "dns/src",
            env=os.environ.copy(),
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stdout)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.host_validator.parent, ignore_errors=True)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="gost-regression-"))

    def tearDown(self):
        subprocess.run(
            ["pkill", "-f", str(self.tmp)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        Path("/tmp/gost.pid").unlink(missing_ok=True)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def make_module(self):
        for directory in ("webui/cgi-bin", "gost/nodes", "logs", "scripts", "dns/bin"):
            (self.tmp / directory).mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO / "webui/cgi-bin/api", self.tmp / "webui/cgi-bin/api")
        shutil.copy2(REPO / "scripts/config.sh", self.tmp / "scripts/config.sh")
        shutil.copy2(REPO / "scripts/start.sh", self.tmp / "scripts/start.sh")
        shutil.copy2(REPO / "scripts/stop.sh", self.tmp / "scripts/stop.sh")
        shutil.copy2(REPO / "scripts/restart.sh", self.tmp / "scripts/restart.sh")
        shutil.copy2(REPO / "scripts/iptables.sh", self.tmp / "scripts/iptables.sh")
        validator = REPO / "dns/bin/dns-filter-arm64"
        if validator.exists():
            shutil.copy2(validator, self.tmp / "dns/bin/dns-filter-arm64")
        return self.tmp

    def call_api(self, mod, endpoint, body="", method="POST"):
        env = os.environ.copy()
        env.update(
            QUERY_STRING=f"endpoint={endpoint}",
            REQUEST_METHOD=method,
            CONTENT_LENGTH=str(len(body.encode())),
            GOST_CONFIG_VALIDATOR=str(self.host_validator),
        )
        result = run(["sh", str(mod / "webui/cgi-bin/api")], cwd=mod, env=env, input_text=body)
        payload = result.stdout.replace("\r\n", "\n").split("\n\n", 1)[-1]
        return result, json.loads(payload)

    def test_node_renderer_uses_dom_events_not_inline_javascript(self):
        source = (REPO / "webui/app.js").read_text()
        renderer = source[source.index("function makeNodeAction"):source.index("function saveNode")]
        self.assertNotIn("onclick=", renderer)
        self.assertIn("addEventListener", renderer)
        self.assertIn("textContent", renderer)

    def test_api_rejects_malformed_json(self):
        mod = self.make_module()
        malformed = '{"proxy_type":"redirect","listen_port":1080,,"webui_port":8080}'
        _, response = self.call_api(mod, "config", malformed)
        self.assertFalse(response["success"])
        self.assertFalse((mod / "gost/config.json").exists())

    def test_cli_rejects_path_traversal_node_names(self):
        mod = self.make_module()
        (mod / "gost/config.json").write_text('{"proxy_type":"redirect"}')
        escaped = mod / "outside/escaped.json"
        escaped.parent.mkdir()
        result = run(["sh", str(mod / "scripts/config.sh"), str(mod), "node", "save", "../../outside/escaped"])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(escaped.exists())

    def test_cli_config_and_node_files_are_private(self):
        mod = self.make_module()
        config = '{"proxy_type":"redirect","listen_port":1080,"webui_port":8080}'
        result = run(["sh", str(mod / "scripts/config.sh"), str(mod), "write", config])
        self.assertEqual(result.returncode, 0, result.stdout)
        result = run(["sh", str(mod / "scripts/config.sh"), str(mod), "node", "save", "private"])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(stat.S_IMODE((mod / "gost/config.json").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((mod / "gost/nodes/private.json").stat().st_mode), 0o600)

    def test_start_ignores_stale_pid_owned_by_another_process(self):
        mod = self.make_module()
        (mod / "gost/config.json").write_text(
            '{"proxy_type":"socks5","listen_port":1080,"webui_port":8080,'
            '"auth":{"enabled":false},"upstream":{"enabled":false},'
            '"routing":{"enabled":false},"geodata":{"enabled":false},"advanced":{}}'
        )
        (mod / "gost/gost").write_text("#!/bin/sh\nsleep 20\n")
        (mod / "gost/gost").chmod(0o755)
        (mod / "scripts/iptables.sh").write_text("#!/bin/sh\nexit 0\n")
        (mod / "scripts/iptables.sh").chmod(0o755)
        sleeper = subprocess.Popen(["sleep", "20"])
        try:
            Path("/tmp/gost.pid").write_text(str(sleeper.pid))
            result = run(["sh", str(mod / "scripts/start.sh"), str(mod)], timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout)
            new_pid = int(Path("/tmp/gost.pid").read_text())
            self.assertNotEqual(new_pid, sleeper.pid)
        finally:
            sleeper.terminate()
            sleeper.wait(timeout=5)

    def test_concurrent_start_creates_only_one_process(self):
        mod = self.make_module()
        (mod / "gost/config.json").write_text(
            '{"proxy_type":"socks5","listen_port":1080,"webui_port":8080,'
            '"auth":{"enabled":false},"upstream":{"enabled":false},'
            '"routing":{"enabled":false},"geodata":{"enabled":false},"advanced":{}}'
        )
        (mod / "gost/gost").write_text("#!/bin/sh\nsleep 20\n")
        (mod / "gost/gost").chmod(0o755)
        (mod / "scripts/iptables.sh").write_text("#!/bin/sh\nexit 0\n")
        (mod / "scripts/iptables.sh").chmod(0o755)
        p1 = subprocess.Popen(["sh", str(mod / "scripts/start.sh"), str(mod)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        p2 = subprocess.Popen(["sh", str(mod / "scripts/start.sh"), str(mod)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        p1.communicate(timeout=10)
        p2.communicate(timeout=10)
        ps = run(["pgrep", "-af", str(mod / "gost/gost")])
        matches = [line for line in ps.stdout.splitlines() if str(mod / "gost/gost") in line]
        self.assertEqual(len(matches), 1, matches)

    def test_restart_keeps_lock_across_stop_and_start(self):
        source = (REPO / "scripts/restart.sh").read_text()
        self.assertIn("GOST_LOCK_HELD=1", source)
        self.assertIn('scripts/stop.sh', source)
        self.assertIn('scripts/start.sh', source)
        api = (REPO / "webui/cgi-bin/api").read_text()
        self.assertIn('scripts/restart.sh', api)

    def test_runtime_config_is_private(self):
        mod = self.make_module()
        (mod / "gost/config.json").write_text(
            '{"proxy_type":"socks5","listen_port":1080,"webui_port":8080,'
            '"auth":{"enabled":false},"upstream":{"enabled":true,"type":"http",'
            '"addr":"127.0.0.1","port":3128,"username":"u","password":"secret"},'
            '"routing":{"enabled":true,"bypass":["example.com"]},'
            '"geodata":{"enabled":false},"advanced":{}}'
        )
        (mod / "gost/gost").write_text("#!/bin/sh\nsleep 20\n")
        (mod / "gost/gost").chmod(0o755)
        result = run(["sh", str(mod / "scripts/start.sh"), str(mod)], timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(stat.S_IMODE((mod / "gost/runtime.json").stat().st_mode), 0o600)

    def test_download_checksum_never_comes_from_accelerator(self):
        source = (REPO / "scripts/download_gost.sh").read_text()
        checksum_block = source[source.index("EXPECTED_SHA256="):source.index("log \"Target asset")]
        self.assertNotIn('selected_url "${GOST_RELEASE_BASE}/${GOST_TAG}/checksums.txt"', checksum_block)
        verification = source[source.index("verify_binary()") : source.index("# ============ Main")]
        self.assertNotIn("assuming OK", verification)
        self.assertIn('err "Binary version check failed', verification)
        self.assertIn("return 1", verification)
        self.assertIn("Restored the previous Gost binary", source)

    def test_iptables_uses_checked_rule_helpers_and_honors_exclude_lan(self):
        source = (REPO / "scripts/iptables.sh").read_text()
        self.assertIn("add_required_rule", source)
        self.assertIn("EXCLUDE_LAN", source)
        lan_block = source[source.index("0.0.0.0/8") - 300 : source.index("240.0.0.0/4") + 100]
        self.assertIn("EXCLUDE_LAN", lan_block)

    def test_nc_handler_rejects_oversized_body_before_dd(self):
        source = (REPO / "webui/server.sh").read_text()
        handler = source[: source.index("# Server Mode")]
        limit_pos = handler.index("MAX_BODY_SIZE")
        dd_pos = handler.index('BODY=$(dd')
        self.assertLess(limit_pos, dd_pos)
        self.assertIn("Request Entity Too Large", handler)

    def test_ipv6_switch_is_wired_through_config_ui_and_runtime(self):
        default = json.loads((REPO / "gost/nodes/default.json.example").read_text())
        self.assertIn("ipv6_enabled", default["transparent"])
        html = (REPO / "webui/index.html").read_text()
        app = (REPO / "webui/app.js").read_text()
        start = (REPO / "scripts/start.sh").read_text()
        firewall = (REPO / "scripts/iptables.sh").read_text()
        dns = (REPO / "scripts/dns_filter.sh").read_text()
        self.assertIn('id="ipv6Enabled"', html)
        self.assertIn('$("ipv6Enabled")', app)
        self.assertIn("IPV6_ENABLED", start)
        self.assertIn("IPV6_ENABLED", firewall)
        self.assertIn("GOST_IPV6_BLOCK", firewall)
        self.assertIn("filter-all-aaaa", dns)

    def test_installer_enforces_private_runtime_permissions(self):
        source = (REPO / "customize.sh").read_text()
        self.assertIn('chmod 600 "$MODDIR/gost/config.json"', source)
        self.assertIn('find "$MODDIR/gost/nodes"', source)
        self.assertIn("chmod 600", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
