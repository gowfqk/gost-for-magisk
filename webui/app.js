(function () {
    "use strict";

    var API_BASE = "";
    var refreshInterval = null;
    var logRefreshInterval = null;
    var LOG_AUTO_REFRESH_MS = 2000;
    var STATUS_REFRESH_MS = 3000;
    var currentLang = "en";

    // ---- i18n Dictionary ----
    var i18n = {
        en: {
            loading: "Loading",
            nav_dashboard: "Dashboard", nav_proxy: "Proxy", nav_nodes: "Nodes",
            nav_advanced: "Advanced", nav_logs: "Logs",
            status: "Status", gost: "Gost", configuration: "Configuration",
            proxy_type: "Proxy Type", listen: "Listen", port: "Port", node: "Node",
            system: "System", architecture: "Architecture", webui_port: "WebUI Port",
            start: "Start", stop: "Stop", restart: "Restart", gost_command: "Gost Command",
            type: "Type", http_proxy: "HTTP Proxy", socks5_proxy: "SOCKS5 Proxy",
            shadowsocks: "Shadowsocks", tls_tunnel: "TLS Tunnel", ws_tunnel: "WebSocket Tunnel",
            listen_addr: "Listen Address", listen_port: "Listen Port",
            authentication: "Authentication", username: "Username", password: "Password",
            encrypt_method: "Encrypt Method", cert_path: "Certificate Path",
            key_path: "Key Path", ca_path: "CA Path", ws_path: "WS Path", ws_host: "WS Host",
            upstream_proxy: "Upstream Proxy", address: "Address", transport: "Transport",
            direct: "Direct", import_link: "Import Link", import_link_ph: "Paste proxy link, e.g. socks://...",
            save_config: "Save Config", export: "Export", import: "Import",
            save_current_as_node: "Save Current as Node", node_name: "Node Name",
            node_name_ph: "e.g. hk-node", save: "Save", saved_nodes: "Saved Nodes",
            refresh: "Refresh", loading_nodes: "Loading nodes...",
            dns_servers: "DNS Servers", logging: "Logging", log_level: "Log Level",
            multi_port_listen: "Multi-Port Listen",
            additional_listen_ports: "Additional Listen Ports (comma separated)",
            routes: "Routes", route_rules: "Route Rules (JSON array)",
            save_advanced_config: "Save Advanced Config",
            gost_logs: "Gost Logs", auto: "Auto", loading_logs: "Loading logs...",
            // Dynamic text
            running: "Running", stopped: "Stopped",
            no_nodes: "No saved nodes. Save current config as a node above.",
            failed_load_nodes: "Failed to load nodes.",
            in_use: "In Use", switch_btn: "Switch", delete_btn: "Delete",
            node_saved: "Node '{name}' saved", node_switched: "Switched to node '{name}'",
            node_deleted: "Node '{name}' deleted", save_failed: "Save failed",
            switch_failed: "Switch failed", delete_failed: "Delete failed",
            enter_node_name: "Please enter a node name",
            confirm_delete: "Delete node '{name}'?",
            config_saved: "Config saved", config_loaded: "Config loaded",
            config_exported: "Config exported", config_imported: "Config imported",
            start_ok: "Gost started", start_fail: "Failed to start gost",
            stop_ok: "Gost stopped", stop_fail: "Failed to stop gost",
            restart_ok: "Gost restarted", restart_fail: "Failed to restart gost",
            import_success: "Imported successfully", import_fail: "Import failed",
            no_active_config: "No active config to save",
            enter_link: "Please enter a proxy link", link_parse_fail: "Parse failed, check format",
            imported_remarks: "Imported: {name}", invalid_json: "Invalid JSON file",
            no_logs: "No logs.", save_failed_msg: "Save failed: {msg}",
            lang_btn: "中"
        },
        zh: {
            loading: "加载中",
            nav_dashboard: "仪表盘", nav_proxy: "代理", nav_nodes: "节点",
            nav_advanced: "高级", nav_logs: "日志",
            status: "状态", gost: "Gost", configuration: "配置",
            proxy_type: "代理类型", listen: "监听", port: "端口", node: "节点",
            system: "系统", architecture: "架构", webui_port: "WebUI 端口",
            start: "启动", stop: "停止", restart: "重启", gost_command: "Gost 命令",
            type: "类型", http_proxy: "HTTP 代理", socks5_proxy: "SOCKS5 代理",
            shadowsocks: "Shadowsocks", tls_tunnel: "TLS 隧道", ws_tunnel: "WebSocket 隧道",
            listen_addr: "监听地址", listen_port: "监听端口",
            authentication: "认证", username: "用户名", password: "密码",
            encrypt_method: "加密方式", cert_path: "证书路径",
            key_path: "密钥路径", ca_path: "CA 路径", ws_path: "WS 路径", ws_host: "WS 主机",
            upstream_proxy: "上游代理", address: "地址", transport: "传输",
            direct: "直连", import_link: "导入链接", import_link_ph: "粘贴代理链接，如 socks://...",
            save_config: "保存配置", export: "导出", import: "导入",
            save_current_as_node: "保存当前为节点", node_name: "节点名称",
            node_name_ph: "例如 hk-node", save: "保存", saved_nodes: "已保存节点",
            refresh: "刷新", loading_nodes: "加载节点中...",
            dns_servers: "DNS 服务器", logging: "日志", log_level: "日志级别",
            multi_port_listen: "多端口监听",
            additional_listen_ports: "额外监听端口（逗号分隔）",
            routes: "路由", route_rules: "路由规则（JSON 数组）",
            save_advanced_config: "保存高级配置",
            gost_logs: "Gost 日志", auto: "自动", loading_logs: "加载日志中...",
            // Dynamic text
            running: "运行中", stopped: "已停止",
            no_nodes: "暂无保存的节点。请在上方保存当前配置为节点。",
            failed_load_nodes: "加载节点失败。",
            in_use: "使用中", switch_btn: "切换", delete_btn: "删除",
            node_saved: "节点 '{name}' 已保存", node_switched: "已切换到节点 '{name}'",
            node_deleted: "节点 '{name}' 已删除", save_failed: "保存失败",
            switch_failed: "切换失败", delete_failed: "删除失败",
            enter_node_name: "请输入节点名称",
            confirm_delete: "确认删除节点 '{name}'？",
            config_saved: "配置已保存", config_loaded: "配置已加载",
            config_exported: "配置已导出", config_imported: "配置已导入",
            start_ok: "Gost 已启动", start_fail: "启动失败",
            stop_ok: "Gost 已停止", stop_fail: "停止失败",
            restart_ok: "Gost 已重启", restart_fail: "重启失败",
            import_success: "导入成功", import_fail: "导入失败",
            no_active_config: "没有活动配置可保存",
            enter_link: "请输入代理链接", link_parse_fail: "链接解析失败，请检查格式",
            imported_remarks: "已导入: {name}", invalid_json: "无效的 JSON 文件",
            no_logs: "暂无日志。", save_failed_msg: "保存失败: {msg}",
            lang_btn: "EN"
        }
    };

    function t(key, vars) {
        var str = (i18n[currentLang] && i18n[currentLang][key]) || (i18n.en[key]) || key;
        if (vars) {
            Object.keys(vars).forEach(function (k) {
                str = str.replace("{" + k + "}", vars[k]);
            });
        }
        return str;
    }

    function applyLanguage() {
        document.querySelectorAll("[data-i18n]").forEach(function (el) {
            el.textContent = t(el.getAttribute("data-i18n"));
        });
        document.querySelectorAll("[data-i18n-ph]").forEach(function (el) {
            el.setAttribute("placeholder", t(el.getAttribute("data-i18n-ph")));
        });
        $("btnLang").textContent = t("lang_btn");
    }

    function toggleLanguage() {
        currentLang = currentLang === "en" ? "zh" : "en";
        try { localStorage.setItem("gost_lang", currentLang); } catch (e) {}
        applyLanguage();
        // Re-render dynamic content
        loadStatus();
        loadNodes();
        loadLogs();
    }

    function $(id) {
        return document.getElementById(id);
    }

    function fetchJSON(url, options) {
        options = options || {};
        return fetch(API_BASE + url, {
            method: options.method || "GET",
            headers: Object.assign({ "Content-Type": "application/json" }, options.headers || {}),
            body: options.body ? JSON.stringify(options.body) : undefined
        }).then(function (res) {
            return res.json();
        });
    }

    function showToast(message, type) {
        type = type || "info";
        var toast = $("toast");
        toast.textContent = message;
        toast.className = "toast show " + type;
        setTimeout(function () {
            toast.className = "toast";
        }, 3000);
    }

    function switchPage(pageName) {
        var pages = document.querySelectorAll(".page");
        pages.forEach(function (p) {
            p.classList.remove("active");
        });
        var navBtns = document.querySelectorAll(".nav-btn");
        navBtns.forEach(function (b) {
            b.classList.remove("active");
        });
        var target = $("page-" + pageName);
        if (target) target.classList.add("active");
        var btn = document.querySelector('.nav-btn[data-page="' + pageName + '"]');
        if (btn) btn.classList.add("active");
    }

    function updateGlobalStatus(status) {
        var badge = $("globalStatus");
        var dot = badge.querySelector(".status-dot");
        var text = badge.querySelector(".status-text");
        badge.className = "status-badge " + status;
        text.textContent = status === "running" ? t("running") : status === "stopped" ? t("stopped") : status;
    }

    function updateDashboard(data) {
        var gostStatus = data.gost ? data.gost.status : "unknown";
        var gostPid = data.gost && data.gost.pid ? data.gost.pid : "-";

        $("dashGostStatus").textContent = gostStatus;
        $("dashGostStatus").className = "info-value " + gostStatus;
        $("dashGostPid").textContent = gostPid;
        $("dashWebuiStatus").textContent = data.webui ? data.webui.status : "-";
        $("dashWebuiStatus").className = "info-value " + (data.webui ? data.webui.status : "");
        $("dashProxyType").textContent = data.proxy_type || "-";
        $("dashListenAddr").textContent = data.listen_addr || "-";
        $("dashListenPort").textContent = data.listen_port || "-";
        $("dashArch").textContent = data.arch || "-";
        $("dashWebuiPort").textContent = data.webui ? data.webui.port : "-";
        $("dashActiveNode").textContent = data.active_node || "-";

        updateGlobalStatus(gostStatus);
        $("archBadge").textContent = data.arch || "";
    }

    function loadStatus() {
        fetchJSON("/cgi-bin/api?endpoint=status")
            .then(function (data) {
                updateDashboard(data);
            })
            .catch(function () {});
    }

    function loadConfig() {
        fetchJSON("/cgi-bin/api?endpoint=config")
            .then(function (config) {
                applyConfigToForm(config);
            })
            .catch(function () {});
    }

    function applyConfigToForm(config) {
        $("proxyType").value = config.proxy_type || "http";
        $("listenAddr").value = config.listen_addr || "0.0.0.0";
        $("listenPort").value = config.listen_port || 1080;

        var auth = config.auth || {};
        $("authEnabled").checked = !!auth.enabled;
        toggleAuthFields();
        $("authUsername").value = auth.username || "";
        $("authPassword").value = auth.password || "";

        var ss = config.shadowsocks || {};
        $("ssMethod").value = ss.method || "aes-256-cfb";
        $("ssPassword").value = ss.password || "";

        var tls = config.tls || {};
        $("tlsCert").value = tls.cert || "";
        $("tlsKey").value = tls.key || "";
        $("tlsCa").value = tls.ca || "";

        var ws = config.websocket || {};
        $("wsPath").value = ws.path || "/ws";
        $("wsHost").value = ws.host || "";

        var upstream = config.upstream || {};
        $("upstreamEnabled").checked = !!upstream.enabled;
        toggleUpstreamFields();
        $("upstreamType").value = upstream.type || "http";
        $("upstreamAddr").value = upstream.addr || "";
        $("upstreamPort").value = upstream.port || "";
        $("upstreamUsername").value = upstream.username || "";
        $("upstreamPassword").value = upstream.password || "";
        $("upstreamRoute").value = upstream.route || "";
        $("upstreamWsPath").value = upstream.ws_path || "";
        $("upstreamWsHost").value = upstream.ws_host || "";

        var adv = config.advanced || {};
        $("advDns").value = adv.dns || "";
        $("advLogLevel").value = adv.log_level || "info";
        $("advWebuiPort").value = config.webui_port || 8080;
        $("advMultiListen").value = (adv.multi_listen || []).join(",");
        try {
            $("advRoutes").value = JSON.stringify(adv.routes || [], null, 2);
        } catch (e) {
            $("advRoutes").value = "[]";
        }

        updateProxyTypeFields();
    }

    function collectConfig() {
        var multiListen = [];
        var mlStr = $("advMultiListen").value.trim();
        if (mlStr) {
            multiListen = mlStr.split(",").map(function (s) {
                return s.trim();
            }).filter(Boolean);
        }

        var routes = [];
        try {
            routes = JSON.parse($("advRoutes").value || "[]");
        } catch (e) {}

        return {
            proxy_type: $("proxyType").value,
            listen_addr: $("listenAddr").value,
            listen_port: parseInt($("listenPort").value, 10) || 1080,
            webui_port: parseInt($("advWebuiPort").value, 10) || 8080,
            auth: {
                enabled: $("authEnabled").checked,
                username: $("authUsername").value,
                password: $("authPassword").value
            },
            upstream: {
                enabled: $("upstreamEnabled").checked,
                type: $("upstreamType").value,
                addr: $("upstreamAddr").value,
                port: parseInt($("upstreamPort").value, 10) || 0,
                username: $("upstreamUsername").value,
                password: $("upstreamPassword").value,
                route: $("upstreamRoute").value,
                ws_path: $("upstreamWsPath").value,
                ws_host: $("upstreamWsHost").value
            },
            shadowsocks: {
                method: $("ssMethod").value,
                password: $("ssPassword").value
            },
            tls: {
                cert: $("tlsCert").value,
                key: $("tlsKey").value,
                ca: $("tlsCa").value
            },
            websocket: {
                path: $("wsPath").value,
                host: $("wsHost").value
            },
            advanced: {
                dns: $("advDns").value,
                log_level: $("advLogLevel").value,
                routes: routes,
                multi_listen: multiListen
            }
        };
    }

    function updateProxyTypeFields() {
        var type = $("proxyType").value;
        $("ssCard").style.display = type === "ss" ? "" : "none";
        $("tlsCard").style.display = type === "tls" ? "" : "none";
        $("wsCard").style.display = type === "ws" ? "" : "none";
    }

    function toggleAuthFields() {
        $("authFields").style.display = $("authEnabled").checked ? "" : "none";
    }

    function toggleUpstreamFields() {
        $("upstreamFields").style.display = $("upstreamEnabled").checked ? "" : "none";
        toggleUpstreamRouteFields();
    }

    function toggleUpstreamRouteFields() {
        var route = $("upstreamRoute").value;
        var show = route === "ws" || route === "wss";
        $("upstreamWsPathGroup").style.display = show ? "" : "none";
        $("upstreamWsHostGroup").style.display = show ? "" : "none";
    }

    function b64Decode(s) {
        // Add padding if needed
        while (s.length % 4 !== 0) s += "=";
        return atob(s);
    }

    function parseProxyLink(link) {
        try {
            // Manual parse to avoid URL() issues with non-standard schemes and hostname lowercasing
            var schemeEnd = link.indexOf("://");
            if (schemeEnd === -1) return null;
            var scheme = link.substring(0, schemeEnd);
            var rest = link.substring(schemeEnd + 3);
            var qIdx = rest.indexOf("?");
            var encodedPart, queryString;
            if (qIdx !== -1) {
                encodedPart = rest.substring(0, qIdx);
                queryString = rest.substring(qIdx + 1);
            } else {
                encodedPart = rest;
                queryString = "";
            }
            var decoded = decodeURIComponent(b64Decode(encodedPart));
            var atIdx = decoded.lastIndexOf("@");
            if (atIdx === -1) return null;
            var authPart = decoded.substring(0, atIdx);
            var hostPort = decoded.substring(atIdx + 1);
            var colonIdx = authPart.lastIndexOf(":");
            var username = authPart.substring(0, colonIdx);
            var password = authPart.substring(colonIdx + 1);
            var hpColon = hostPort.lastIndexOf(":");
            var host = hostPort.substring(0, hpColon);
            var port = parseInt(hostPort.substring(hpColon + 1), 10);
            // Parse query string manually
            var params = {};
            queryString.split("&").forEach(function(pair) {
                var eq = pair.indexOf("=");
                if (eq !== -1) {
                    params[decodeURIComponent(pair.substring(0, eq))] = decodeURIComponent(pair.substring(eq + 1));
                }
            });
            var remarks = params["remarks"] || "";
            var gostB64 = params["gost"] || "";
            var gostObj = {};
            if (gostB64) {
                try {
                    gostObj = JSON.parse(b64Decode(gostB64));
                } catch (e) {}
            }
            return {
                scheme: scheme,
                username: username,
                password: password,
                host: host,
                port: port,
                remarks: remarks,
                gost: gostObj
            };
        } catch (e) {
            return null;
        }
    }

    function importProxyLink() {
        var link = $("importLinkInput").value.trim();
        if (!link) {
            showToast(t("enter_link"), "error");
            return;
        }
        var parsed = parseProxyLink(link);
        if (!parsed) {
            showToast(t("link_parse_fail"), "error");
            return;
        }
        var proxyType = "socks5";
        if (parsed.scheme === "http" || parsed.scheme === "https") {
            proxyType = "http";
        } else if (parsed.scheme === "ss") {
            proxyType = "ss";
        }
        $("proxyType").value = proxyType;
        $("upstreamEnabled").checked = true;
        toggleUpstreamFields();
        $("upstreamType").value = "socks5";
        if (parsed.scheme === "http" || parsed.scheme === "https") {
            $("upstreamType").value = "http";
        } else if (parsed.scheme === "ss") {
            $("upstreamType").value = "ss";
        }
        $("upstreamAddr").value = parsed.host;
        $("upstreamPort").value = parsed.port;
        $("upstreamUsername").value = parsed.username;
        $("upstreamPassword").value = parsed.password;
        if (parsed.gost && parsed.gost.route === "ws") {
            $("upstreamRoute").value = "ws";
            $("upstreamWsPath").value = parsed.gost.path || "";
            $("upstreamWsHost").value = parsed.gost.host || "";
        } else {
            $("upstreamRoute").value = "";
            $("upstreamWsPath").value = "";
            $("upstreamWsHost").value = "";
        }
        toggleUpstreamRouteFields();
        updateProxyTypeFields();
        if (parsed.remarks) {
            showToast(t("imported_remarks", {name: parsed.remarks}), "success");
        } else {
            showToast(t("import_success"), "success");
        }
        saveConfig();
    }

    function saveConfig() {
        var config = collectConfig();
        fetchJSON("/cgi-bin/api?endpoint=config", {
            method: "POST",
            body: config
        })
            .then(function (res) {
                if (res.success) {
                    showToast(t("config_saved"), "success");
                } else {
                    showToast(t("save_failed_msg", {msg: res.message || ""}), "error");
                }
            })
            .catch(function () {
                showToast(t("save_failed"), "error");
            });
    }

    function exportConfig() {
        var config = collectConfig();
        var blob = new Blob([JSON.stringify(config, null, 2)], { type: "application/json" });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = "gost-config.json";
        a.click();
        URL.revokeObjectURL(url);
        showToast(t("config_exported"), "success");
    }

    function importConfig(file) {
        var reader = new FileReader();
        reader.onload = function (e) {
            try {
                var config = JSON.parse(e.target.result);
                fetchJSON("/cgi-bin/api?endpoint=config", {
                    method: "POST",
                    body: config
                })
                    .then(function (res) {
                        if (res.success) {
                            applyConfigToForm(config);
                            showToast(t("config_imported"), "success");
                        } else {
                            showToast(t("import_fail"), "error");
                        }
                    });
            } catch (err) {
                showToast(t("invalid_json"), "error");
            }
        };
        reader.readAsText(file);
    }

    function loadLogs() {
        fetchJSON("/cgi-bin/api?endpoint=logs&lines=200")
            .then(function (data) {
                $("logView").textContent = data.logs || t("no_logs");
                var logView = $("logView");
                logView.scrollTop = logView.scrollHeight;
            })
            .catch(function () {});
    }

    function loadCommand() {
        fetchJSON("/cgi-bin/api?endpoint=command")
            .then(function (data) {
                $("commandPreview").textContent = data.command || "-";
            })
            .catch(function () {
                $("commandPreview").textContent = "-";
            });
    }

    // ---- Node Management ----
    function loadNodes() {
        fetchJSON("/cgi-bin/api?endpoint=nodes")
            .then(function (data) {
                renderNodeList(data.nodes || [], data.active || "");
            })
            .catch(function () {
                $("nodeList").innerHTML = '<p class="text-muted">' + t("failed_load_nodes") + '</p>';
            });
    }

    function renderNodeList(nodes, active) {
        var container = $("nodeList");
        if (!nodes.length) {
            container.innerHTML = '<p class="text-muted">' + t("no_nodes") + '</p>';
            return;
        }
        var html = "";
        nodes.forEach(function (node) {
            var isActive = node.active || node.name === active;
            var upInfo = t("direct");
            if (node.upstream && node.upstream.enabled === "true") {
                upInfo = (node.upstream.type || "http") + "://" + (node.upstream.addr || "?") + ":" + (node.upstream.port || "?");
            }
            html += '<div class="node-item' + (isActive ? " node-active" : "") + '">';
            html += '  <div class="node-info">';
            html += '    <span class="node-name">' + escapeHtml(node.name) + (isActive ? ' <span class="node-badge">' + (currentLang === "zh" ? "使用中" : "ACTIVE") + '</span>' : "") + "</span>";
            html += '    <span class="node-detail">' + escapeHtml(node.proxy_type || "http") + "://:" + (node.listen_port || 1080) + " &rarr; " + escapeHtml(upInfo) + "</span>";
            html += "  </div>";
            html += '  <div class="node-actions">';
            if (!isActive) {
                html += '    <button class="btn btn-sm btn-primary" onclick="window.__app.switchNode(\'' + escapeHtml(node.name) + '\')">' + t("switch_btn") + '</button>';
                html += '    <button class="btn btn-sm btn-danger" onclick="window.__app.deleteNode(\'' + escapeHtml(node.name) + '\')">' + t("delete_btn") + '</button>';
            } else {
                html += '    <span class="text-muted">' + t("in_use") + '</span>';
            }
            html += "  </div>";
            html += "</div>";
        });
        container.innerHTML = html;
    }

    function escapeHtml(str) {
        if (!str) return "";
        return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
    }

    function saveNode() {
        var name = $("nodeSaveName").value.trim();
        if (!name) {
            showToast(t("enter_node_name"), "error");
            return;
        }
        // First save current config, then save as node
        var config = collectConfig();
        fetchJSON("/cgi-bin/api?endpoint=config", {
            method: "POST",
            body: config
        }).then(function () {
            return fetchJSON("/cgi-bin/api?endpoint=nodes/save", {
                method: "POST",
                body: { name: name }
            });
        }).then(function (res) {
            if (res.success) {
                showToast(t("node_saved", {name: name}), "success");
                $("nodeSaveName").value = "";
                loadNodes();
            } else {
                showToast(res.message || t("save_failed"), "error");
            }
        }).catch(function () {
            showToast(t("save_failed"), "error");
        });
    }

    function switchNode(name) {
        fetchJSON("/cgi-bin/api?endpoint=nodes/switch", {
            method: "POST",
            body: { name: name }
        }).then(function (res) {
            if (res.success) {
                showToast(t("node_switched", {name: name}), "success");
                loadNodes();
                loadConfig();
                loadStatus();
                loadCommand();
            } else {
                showToast(res.message || t("switch_failed"), "error");
            }
        }).catch(function () {
            showToast(t("switch_failed"), "error");
        });
    }

    function deleteNode(name) {
        if (!confirm(t("confirm_delete", {name: name}))) return;
        fetchJSON("/cgi-bin/api?endpoint=nodes/delete", {
            method: "POST",
            body: { name: name }
        }).then(function (res) {
            if (res.success) {
                showToast(t("node_deleted", {name: name}), "success");
                loadNodes();
            } else {
                showToast(res.message || t("delete_failed"), "error");
            }
        }).catch(function () {
            showToast(t("delete_failed"), "error");
        });
    }

    function gostAction(action) {
        fetchJSON("/cgi-bin/api?endpoint=" + action, { method: "POST" })
            .then(function (res) {
                var actionKeys = { start: "start_ok", stop: "stop_ok", restart: "restart_ok" };
                var failKeys = { start: "start_fail", stop: "stop_fail", restart: "restart_fail" };
                showToast(res.message || t(actionKeys[action] || action), res.success ? "success" : "error");
                setTimeout(function () {
                    loadStatus();
                    loadCommand();
                }, 500);
            })
            .catch(function () {
                var failKeys = { start: "start_fail", stop: "stop_fail", restart: "restart_fail" };
                showToast(t(failKeys[action] || "save_failed"), "error");
            });
    }

    function startAutoRefresh() {
        if (refreshInterval) clearInterval(refreshInterval);
        refreshInterval = setInterval(function () {
            loadStatus();
            loadCommand();
        }, STATUS_REFRESH_MS);
    }

    function startLogAutoRefresh() {
        if (logRefreshInterval) clearInterval(logRefreshInterval);
        logRefreshInterval = setInterval(function () {
            if ($("logAutoRefresh").checked) {
                loadLogs();
            }
        }, LOG_AUTO_REFRESH_MS);
    }

    function init() {
        var navBtns = document.querySelectorAll(".nav-btn");
        navBtns.forEach(function (btn) {
            btn.addEventListener("click", function () {
                switchPage(this.getAttribute("data-page"));
            });
        });

        $("btnStart").addEventListener("click", function () {
            gostAction("start");
        });
        $("btnStop").addEventListener("click", function () {
            gostAction("stop");
        });
        $("btnRestart").addEventListener("click", function () {
            gostAction("restart");
        });

        $("proxyType").addEventListener("change", updateProxyTypeFields);
        $("authEnabled").addEventListener("change", toggleAuthFields);
        $("upstreamEnabled").addEventListener("change", toggleUpstreamFields);
        $("upstreamRoute").addEventListener("change", toggleUpstreamRouteFields);

        $("btnSaveConfig").addEventListener("click", saveConfig);
        $("btnSaveAdvanced").addEventListener("click", saveConfig);
        $("btnExportConfig").addEventListener("click", exportConfig);
        $("btnImportConfig").addEventListener("click", function () {
            $("importFileInput").click();
        });
        $("importFileInput").addEventListener("change", function () {
            if (this.files && this.files[0]) {
                importConfig(this.files[0]);
                this.value = "";
            }
        });

        $("btnImportLink").addEventListener("click", importProxyLink);

        $("btnRefreshLogs").addEventListener("click", loadLogs);

        // Language toggle
        try { currentLang = localStorage.getItem("gost_lang") || "en"; } catch (e) {}
        applyLanguage();
        $("btnLang").addEventListener("click", toggleLanguage);

        // Node management
        $("btnNodeSave").addEventListener("click", saveNode);
        $("btnRefreshNodes").addEventListener("click", loadNodes);
        // Expose for inline onclick handlers
        window.__app = { switchNode: switchNode, deleteNode: deleteNode };

        loadStatus();
        loadConfig();
        loadCommand();
        loadNodes();
        startAutoRefresh();
        startLogAutoRefresh();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
