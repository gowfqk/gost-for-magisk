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
            gost_binary: "Gost Binary", gost_binary_ready: "Installed", gost_binary_missing: "Not installed",
            download_gost: "Download Gost", downloading_gost: "Downloading...", gost_download_started: "Gost download started",
            gost_download_failed: "Download failed", gost_download_hint: "Install the Gost binary manually after module installation. Download progress is written to the service log.",
            proxy_type: "Proxy Type", listen: "Listen", port: "Port", node: "Node",
            system: "System", architecture: "Architecture", webui_port: "WebUI Port",
            start: "Start", stop: "Stop", restart: "Restart", test_proxy: "Test Proxy",
            proxy_test_result: "Proxy Test Result", test_running: "Testing transparent proxy...",
            gost_command: "Gost Command",
            type: "Type", http_proxy: "HTTP Proxy", socks5_proxy: "SOCKS5 Proxy",
            shadowsocks: "Shadowsocks", tls_tunnel: "TLS Tunnel", ws_tunnel: "WebSocket Tunnel",
            listen_addr: "Listen Address", listen_port: "Listen Port",
            authentication: "Authentication", username: "Username", password: "Password",
            encrypt_method: "Encrypt Method", cert_path: "Certificate Path",
            key_path: "Key Path", ca_path: "CA Path", ws_path: "WS Path", ws_host: "WS Host",
            upstream_proxy: "Upstream Proxy", address: "Address", transport: "Transport",
            direct: "Direct", import_link: "Import Link",
            bulk_import_links_ph: "Paste one or more proxy links, one per line",
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
            in_use: "In Use", edit_btn: "Edit", switch_btn: "Switch", delete_btn: "Delete",
            node_saved: "Node '{name}' saved and activated", node_switched: "Switched to node '{name}'",
            node_editing: "Editing node '{name}'. Save config to apply changes.",
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
            bulk_import_empty: "Please enter at least one proxy link", bulk_import_result: "Imported {success} of {total} links",
            invalid_json: "Invalid JSON file",
            no_logs: "No logs.", save_failed_msg: "Save failed: {msg}",
            transparent_proxy_tcp: "Transparent Proxy (TCP)",
            transparent_proxy_hint: "Local TCP traffic is captured automatically with iptables; apps do not need SOCKS settings.",
            optional: "(optional)", shadowsocks_password: "Shadowsocks password",
            webui: "WebUI", tcp_split_routing: "TCP Split Routing",
            enable_custom_split_routing: "Enable custom split routing",
            direct_rules: "Direct domains / IP / CIDR (one per line)",
            direct_uids: "Direct Android UIDs (comma separated)",
            split_routing_hint: "Domain/IP rules bypass the upstream chain. UID rules bypass transparent interception. TCP only.",
            geodata_auto_split: "GeoData Auto-Split", geodata_enable: "Enable GeoData bypass (China direct)",
            geodata_auto_update: "Auto-update on boot", geodata_update: "Update GeoData Now",
            geodata_hint: "Downloads GeoSite/GeoIP databases, extracts China domains and CIDRs, and uses them as bypass rules. Requires upstream proxy enabled. File-based bypass supports 70k+ rules.",
            updating: "Updating...", geodata_update_started: "GeoData update started",
            geodata_update_failed: "Update failed", geodata_update_request_failed: "Update request failed",
            geodata_updating_hint: "Updating... please wait", geodata_last_update: "Last update: {value}",
            geodata_rules: "Rules: {rules} ({domains} domains, {cidrs} CIDRs)",
            geodata_not_downloaded: "Not downloaded", geodata_status_load_failed: "Failed to load status",
            pass: "PASS", fail: "FAIL", test_port: "Port: {value}", test_elapsed: "Elapsed: {value}s", test_url: "URL: {value}",
            api_request_failed: "Request failed", rename: "Rename", rename_prompt: "Enter new node name", rename_failed: "Rename failed",
            lang_btn: "中"
        },
        zh: {
            loading: "加载中",
            nav_dashboard: "仪表盘", nav_proxy: "代理", nav_nodes: "节点",
            nav_advanced: "高级", nav_logs: "日志",
            status: "状态", gost: "Gost", configuration: "配置",
            gost_binary: "Gost 二进制", gost_binary_ready: "已安装", gost_binary_missing: "未安装",
            download_gost: "下载 Gost", downloading_gost: "正在下载…", gost_download_started: "Gost 下载已开始",
            gost_download_failed: "下载失败", gost_download_hint: "模块安装后在这里手动安装 Gost 二进制，下载进度会写入服务日志。",
            proxy_type: "代理类型", listen: "监听", port: "端口", node: "节点",
            system: "系统", architecture: "架构", webui_port: "WebUI 端口",
            start: "启动", stop: "停止", restart: "重启", test_proxy: "测试代理",
            proxy_test_result: "代理测试结果", test_running: "正在测试透明代理……",
            gost_command: "Gost 命令",
            type: "类型", http_proxy: "HTTP 代理", socks5_proxy: "SOCKS5 代理",
            shadowsocks: "Shadowsocks", tls_tunnel: "TLS 隧道", ws_tunnel: "WebSocket 隧道",
            listen_addr: "监听地址", listen_port: "监听端口",
            authentication: "认证", username: "用户名", password: "密码",
            encrypt_method: "加密方式", cert_path: "证书路径",
            key_path: "密钥路径", ca_path: "CA 路径", ws_path: "WS 路径", ws_host: "WS 主机",
            upstream_proxy: "上游代理", address: "地址", transport: "传输",
            direct: "直连", import_link: "导入链接",
            bulk_import_links_ph: "粘贴一个或多个代理链接，每行一个",
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
            in_use: "使用中", edit_btn: "编辑", switch_btn: "切换", delete_btn: "删除",
            node_saved: "节点 '{name}' 已保存并设为活动节点", node_switched: "已切换到节点 '{name}'",
            node_editing: "正在编辑节点 '{name}'，保存配置后生效。",
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
            bulk_import_empty: "请至少输入一个代理链接", bulk_import_result: "已导入 {success} / {total} 个链接",
            invalid_json: "无效的 JSON 文件",
            no_logs: "暂无日志。", save_failed_msg: "保存失败: {msg}",
            transparent_proxy_tcp: "透明代理（TCP）",
            transparent_proxy_hint: "本机 TCP 流量会由 iptables 自动接管，应用无需配置 SOCKS 代理。",
            optional: "（可选）", shadowsocks_password: "Shadowsocks 密码",
            webui: "WebUI", tcp_split_routing: "TCP 分流",
            enable_custom_split_routing: "启用自定义分流",
            direct_rules: "直连域名 / IP / CIDR（每行一条）",
            direct_uids: "直连 Android UID（逗号分隔）",
            split_routing_hint: "域名/IP 规则会绕过上游链路；UID 规则会绕过透明接管。仅支持 TCP。",
            geodata_auto_split: "GeoData 自动分流", geodata_enable: "启用 GeoData 分流（中国大陆直连）",
            geodata_auto_update: "开机自动更新", geodata_update: "立即更新 GeoData",
            geodata_hint: "下载 GeoSite/GeoIP 数据库，提取中国大陆域名和 CIDR，并作为直连分流规则。需要先启用上游代理。文件规则支持 7 万条以上。",
            updating: "更新中…", geodata_update_started: "GeoData 更新已开始",
            geodata_update_failed: "更新失败", geodata_update_request_failed: "更新请求失败",
            geodata_updating_hint: "正在更新，请稍候…", geodata_last_update: "上次更新：{value}",
            geodata_rules: "规则：{rules}（{domains} 条域名，{cidrs} 条 CIDR）",
            geodata_not_downloaded: "尚未下载", geodata_status_load_failed: "加载状态失败",
            pass: "通过", fail: "失败", test_port: "端口：{value}", test_elapsed: "耗时：{value} 秒", test_url: "网址：{value}",
            api_request_failed: "请求失败", rename: "重命名", rename_prompt: "输入新的节点名称", rename_failed: "重命名失败",
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
        // A running Gost process is definitive proof that the binary exists.
        // This fallback also keeps the UI correct while an older API handler is
        // still serving requests immediately after a module update.
        var binaryReady = !!(data.gost && (data.gost.binary_ready || data.gost.status === "running"));
        $("dashGostBinary").textContent = binaryReady ? t("gost_binary_ready") : t("gost_binary_missing");
        $("dashGostBinary").className = "info-value " + (binaryReady ? "running" : "stopped");
        $("btnDownloadGost").disabled = !!(data.gost && (binaryReady || data.gost.downloading));
        $("btnDownloadGost").textContent = data.gost && data.gost.downloading ? t("downloading_gost") : t("download_gost");
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

    function downloadGost() {
        var button = $("btnDownloadGost");
        button.disabled = true;
        button.textContent = t("downloading_gost");
        fetchJSON("/cgi-bin/api?endpoint=gost/download", {method: "POST"})
            .then(function (res) {
                if (!res.success) throw new Error(res.message || t("gost_download_failed"));
                showToast(t("gost_download_started"), "success");
                loadStatus();
            })
            .catch(function (err) {
                button.disabled = false;
                button.textContent = t("download_gost");
                showToast((err && err.message) || t("gost_download_failed"), "error");
            });
    }

    function loadConfig() {
        fetchJSON("/cgi-bin/api?endpoint=config")
            .then(function (config) {
                applyConfigToForm(config);
            })
            .catch(function () {});
    }

    function applyConfigToForm(config) {
        $("proxyType").value = "redirect";
        $("listenAddr").value = config.listen_addr || "0.0.0.0";
        $("listenPort").value = config.listen_port || 1080;

        var auth = config.auth || {};
        $("authEnabled").checked = false;
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
        $("wsPath").value = ws.path || "";
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
        $("advLogLevel").value = adv.log_level || "info";
        $("advWebuiPort").value = config.webui_port || 8080;
        $("advMultiListen").value = (adv.multi_listen || []).join(",");
        var routing = config.routing || {};
        $("routingEnabled").checked = !!routing.enabled;
        $("routingBypass").value = (routing.bypass || []).join("\n");
        $("routingDirectUids").value = (routing.direct_uids || []).join(",");
        var geodata = config.geodata || {};
        $("geodataEnabled").checked = !!geodata.enabled;
        $("geodataAutoUpdate").checked = !!geodata.auto_update;

        updateProxyTypeFields();
    }

    function splitList(value) {
        return String(value || "").split(/[\n,]+/).map(function (s) { return s.trim(); }).filter(Boolean);
    }

    function collectConfig() {
        var multiListen = [];
        var mlStr = $("advMultiListen").value.trim();
        if (mlStr) {
            multiListen = mlStr.split(",").map(function (s) {
                return s.trim();
            }).filter(Boolean);
        }

        return {
            proxy_type: "redirect",
            listen_addr: $("listenAddr").value,
            listen_port: parseInt($("listenPort").value, 10) || 1080,
            webui_port: parseInt($("advWebuiPort").value, 10) || 8080,
            transparent: {
                enabled: true,
                sniffing: true,
                sniffing_timeout: "5s",
                sniffing_fallback: true,
                sniffing_dial_original_dst: false,
                mark: 100,
                exclude_lan: true
            },
            auth: {
                enabled: false,
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
            routing: {
                enabled: $("routingEnabled").checked,
                bypass: splitList($("routingBypass").value),
                direct_uids: splitList($("routingDirectUids").value)
            },
            geodata: {
                enabled: $("geodataEnabled").checked,
                auto_update: $("geodataAutoUpdate").checked
            },
            advanced: {
                log_level: $("advLogLevel").value,
                multi_listen: multiListen
            }
        };
    }

    function updateProxyTypeFields() {
        var type = $("proxyType").value;
        $("ssCard").style.display = "none";
        $("tlsCard").style.display = "none";
        $("wsCard").style.display = "none";
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

    function safeNodeId(name) {
        var safe = String(name || "").trim()
            .replace(/[^A-Za-z0-9._-]+/g, "-")
            .replace(/^-+|-+$/g, "")
            .replace(/\.\.+/g, ".")
            .substring(0, 40);
        if (!safe || safe.charAt(0) === ".") safe = "node";
        return safe + "-" + Date.now().toString(36);
    }

    function cleanDisplayName(name, fallback) {
        var display = String(name || "").trim().replace(/[\x00-\x1f\x7f]/g, "").substring(0, 64);
        return display || String(fallback || "Imported node").substring(0, 64);
    }

    function configFromProxyLink(parsed, displayName) {
        var config = collectConfig();
        config.node_name = displayName;
        config.upstream.enabled = true;
        config.upstream.type = parsed.scheme === "http" ? "http" : parsed.scheme === "https" ? "http+tls" : parsed.scheme === "ss" ? "ss" : "socks5";
        config.upstream.addr = parsed.host;
        config.upstream.port = parsed.port;
        config.upstream.username = parsed.username;
        config.upstream.password = parsed.password;
        config.upstream.route = "";
        config.upstream.ws_path = "";
        config.upstream.ws_host = "";
        if (parsed.gost && (parsed.gost.route === "ws" || parsed.gost.route === "wss")) {
            config.upstream.route = parsed.gost.route;
            config.upstream.type += "+" + parsed.gost.route;
            config.upstream.ws_path = parsed.gost.path || "";
            config.upstream.ws_host = parsed.gost.host || "";
        }
        return config;
    }

    function importSavedNode(config, nodeId) {
        return fetchJSON("/cgi-bin/api?endpoint=nodes/import&name=" + encodeURIComponent(nodeId) + "&activate=false", {
            method: "POST",
            body: config
        });
    }

    function updateBulkImportButton() {
        $("btnBulkImportLinks").disabled = !$("bulkImportLinks").value.trim();
    }

    function bulkImportProxyLinks() {
        var links = $("bulkImportLinks").value.split(/\r?\n/).map(function (link) { return link.trim(); }).filter(Boolean);
        if (!links.length) {
            showToast(t("bulk_import_empty"), "error");
            return;
        }
        var button = $("btnBulkImportLinks");
        button.disabled = true;
        var imported = 0;
        var chain = Promise.resolve();
        links.forEach(function (link) {
            chain = chain.then(function () {
                var parsed = parseProxyLink(link);
                if (!parsed) return;
                var displayName = cleanDisplayName("", parsed.remarks || parsed.host);
                return importSavedNode(configFromProxyLink(parsed, displayName), safeNodeId(displayName)).then(function (res) {
                    if (res.success) imported++;
                });
            });
        });
        chain.then(function () {
            $("bulkImportLinks").value = "";
            loadNodes();
            showToast(t("bulk_import_result", {success: imported, total: links.length}), imported ? "success" : "error");
        }).catch(function () {
            showToast(t("import_fail"), "error");
        }).then(function () {
            updateBulkImportButton();
        });
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
            var isActive = node.active || node.id === active;
            var nodeId = node.id || node.name;
            var displayName = node.display_name || node.name || nodeId;
            var upInfo = t("direct");
            if (node.upstream && node.upstream.enabled === "true") {
                upInfo = (node.upstream.type || "http") + "://" + (node.upstream.addr || "?") + ":" + (node.upstream.port || "?");
            }
            html += '<div class="node-item' + (isActive ? " node-active" : "") + '">';
            html += '  <div class="node-info">';
            html += '    <span class="node-name">' + escapeHtml(displayName) + (isActive ? ' <span class="node-badge">' + (currentLang === "zh" ? "使用中" : "ACTIVE") + '</span>' : "") + "</span>";
            html += '    <span class="node-detail">' + escapeHtml(node.proxy_type || "http") + "://:" + (node.listen_port || 1080) + " &rarr; " + escapeHtml(upInfo) + "</span>";
            html += "  </div>";
            html += '  <div class="node-actions">';
            html += '    <button class="btn btn-sm btn-secondary" onclick="window.__app.renameNode(\'' + escapeHtml(nodeId) + '\',\'' + escapeHtml(displayName) + '\')">' + t("rename") + '</button>';
            html += '    <button class="btn btn-sm btn-secondary" onclick="window.__app.editNode(\'' + escapeHtml(nodeId) + '\')">' + t("edit_btn") + '</button>';
            if (!isActive) {
                html += '    <button class="btn btn-sm btn-primary" onclick="window.__app.switchNode(\'' + escapeHtml(nodeId) + '\')">' + t("switch_btn") + '</button>';
                html += '    <button class="btn btn-sm btn-danger" onclick="window.__app.deleteNode(\'' + escapeHtml(nodeId) + '\')">' + t("delete_btn") + '</button>';
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
        var rawName = $("nodeSaveName").value.trim();
        var name = safeNodeId(rawName);
        if (!rawName) {
            showToast(t("enter_node_name"), "error");
            return;
        }
        // First save current config, then save as node
        var config = collectConfig();
        config.node_name = cleanDisplayName(rawName, name);
        fetchJSON("/cgi-bin/api?endpoint=config", {
            method: "POST",
            body: config
        }).then(function (res) {
            if (!res.success) {
                throw new Error(res.message || t("save_failed"));
            }
            return fetchJSON("/cgi-bin/api?endpoint=nodes/save", {
                method: "POST",
                body: { name: name }
            });
        }).then(function (res) {
            if (res.success) {
                showToast(t("node_saved", {name: name}), "success");
                $("nodeSaveName").value = "";
                loadNodes();
                loadStatus();
            } else {
                showToast(res.message || t("save_failed"), "error");
            }
        }).catch(function () {
            showToast(t("save_failed"), "error");
        });
    }

    function editNode(name) {
        fetchJSON("/cgi-bin/api?endpoint=nodes/switch", {
            method: "POST",
            body: { name: name }
        }).then(function (res) {
            if (res.success) {
                loadConfig();
                loadNodes();
                loadStatus();
                loadCommand();
                switchPage("proxy");
                showToast(t("node_editing", {name: name}), "success");
            } else {
                showToast(res.message || t("switch_failed"), "error");
            }
        }).catch(function () {
            showToast(t("switch_failed"), "error");
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

    function renameNode(name, currentDisplayName) {
        var nextName = prompt(t("rename_prompt"), currentDisplayName || "");
        if (nextName === null) return;
        nextName = cleanDisplayName(nextName, currentDisplayName);
        fetchJSON("/cgi-bin/api?endpoint=nodes/rename", {
            method: "POST",
            body: { name: name, display_name: nextName }
        }).then(function (res) {
            if (!res.success) throw new Error(res.message || t("rename_failed"));
            loadNodes();
            loadConfig();
            loadStatus();
        }).catch(function (err) {
            showToast((err && err.message) || t("rename_failed"), "error");
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

    function testProxy() {
        var button = $("btnTestProxy");
        var card = $("proxyTestCard");
        var result = $("proxyTestResult");
        button.disabled = true;
        card.style.display = "";
        result.textContent = t("test_running");
        fetchJSON("/cgi-bin/api?endpoint=test", { method: "POST" })
            .then(function (res) {
                var lines = [
                    (res.success ? t("pass") : t("fail")) + " [" + (res.stage || "unknown") + "]",
                    res.message || "",
                    res.listen_port ? t("test_port", {value: res.listen_port}) : "",
                    res.elapsed !== undefined ? t("test_elapsed", {value: res.elapsed}) : "",
                    res.test_url ? t("test_url", {value: res.test_url}) : ""
                ].filter(Boolean);
                result.textContent = lines.join("\n");
                result.className = "command-preview " + (res.success ? "test-success" : "test-failure");
            })
            .catch(function (err) {
                result.textContent = t("fail") + " [api]\n" + ((err && err.message) || t("api_request_failed"));
                result.className = "command-preview test-failure";
            })
            .then(function () { button.disabled = false; });
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

    var geodataPollInterval = null;

    function loadGeodataStatus() {
        fetchJSON("/cgi-bin/api?endpoint=geodata/status")
            .then(function (data) {
                var el = $("geodataStatus");
                if (data.updating) {
                    el.textContent = t("geodata_updating_hint");
                    el.className = "command-preview";
                    if (!geodataPollInterval) {
                        geodataPollInterval = setInterval(function () {
                            loadGeodataStatus();
                        }, 3000);
                    }
                    return;
                }
                if (geodataPollInterval) {
                    clearInterval(geodataPollInterval);
                    geodataPollInterval = null;
                }
                if (data.success) {
                    var lines = [
                        t("geodata_last_update", {value: data.updated_at || "unknown"}),
                        t("geodata_rules", {rules: data.rules || 0, domains: data.domain_rules || 0, cidrs: data.cidr_rules || 0}),
                        "GeoSite: " + (data.geosite_tag || "?"),
                        "GeoIP: " + (data.geoip_tag || "?"),
                        "GeoView: " + (data.geoview || "?")
                    ];
                    el.textContent = lines.join("\n");
                    el.className = "command-preview test-success";
                } else {
                    el.textContent = data.message || t("geodata_not_downloaded");
                    el.className = "command-preview";
                }
            })
            .catch(function () {
                $("geodataStatus").textContent = t("geodata_status_load_failed");
            });
    }

    function updateGeodata() {
        var btn = $("btnGeodataUpdate");
        btn.disabled = true;
        btn.textContent = t("updating");
        fetchJSON("/cgi-bin/api?endpoint=geodata/update", { method: "POST" })
            .then(function (res) {
                if (res.success) {
                    showToast(t("geodata_update_started"), "success");
                    loadGeodataStatus();
                } else {
                    showToast(res.message || t("geodata_update_failed"), "error");
                    btn.disabled = false;
                    btn.textContent = t("geodata_update");
                }
            })
            .catch(function () {
                showToast(t("geodata_update_request_failed"), "error");
                btn.disabled = false;
                btn.textContent = t("geodata_update");
            })
            .then(function () {
                // Re-enable button after polling completes
                setTimeout(function () {
                    btn.disabled = false;
                    btn.textContent = t("geodata_update");
                }, 5000);
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
        $("btnTestProxy").addEventListener("click", testProxy);
        $("btnDownloadGost").addEventListener("click", downloadGost);

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

        $("bulkImportLinks").addEventListener("input", updateBulkImportButton);
        $("bulkImportLinks").addEventListener("change", updateBulkImportButton);
        $("bulkImportLinks").addEventListener("paste", function () {
            setTimeout(updateBulkImportButton, 0);
        });
        $("btnBulkImportLinks").addEventListener("click", bulkImportProxyLinks);
        updateBulkImportButton();

        $("btnRefreshLogs").addEventListener("click", loadLogs);

        $("btnGeodataUpdate").addEventListener("click", updateGeodata);

        // Language toggle
        try { currentLang = localStorage.getItem("gost_lang") || "en"; } catch (e) {}
        applyLanguage();
        $("btnLang").addEventListener("click", toggleLanguage);

        // Node management
        $("btnNodeSave").addEventListener("click", saveNode);
        $("btnRefreshNodes").addEventListener("click", loadNodes);
        // Expose for inline onclick handlers
        window.__app = { renameNode: renameNode, editNode: editNode, switchNode: switchNode, deleteNode: deleteNode };

        loadStatus();
        loadConfig();
        loadCommand();
        loadNodes();
        loadGeodataStatus();
        startAutoRefresh();
        startLogAutoRefresh();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
