(function () {
    "use strict";

    var API_BASE = "";
    var refreshInterval = null;
    var logRefreshInterval = null;
    var LOG_AUTO_REFRESH_MS = 2000;
    var STATUS_REFRESH_MS = 3000;

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
        text.textContent = status === "running" ? "Running" : status === "stopped" ? "Stopped" : status;
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
            showToast("请输入代理链接", "error");
            return;
        }
        var parsed = parseProxyLink(link);
        if (!parsed) {
            showToast("链接解析失败，请检查格式", "error");
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
            showToast("已导入: " + parsed.remarks, "success");
        } else {
            showToast("链接导入成功", "success");
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
                    showToast("Config saved", "success");
                } else {
                    showToast("Save failed: " + (res.message || ""), "error");
                }
            })
            .catch(function () {
                showToast("Save failed", "error");
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
        showToast("Config exported", "success");
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
                            showToast("Config imported", "success");
                        } else {
                            showToast("Import failed", "error");
                        }
                    });
            } catch (err) {
                showToast("Invalid JSON file", "error");
            }
        };
        reader.readAsText(file);
    }

    function loadLogs() {
        fetchJSON("/cgi-bin/api?endpoint=logs&lines=200")
            .then(function (data) {
                $("logView").textContent = data.logs || "No logs.";
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

    function gostAction(action) {
        fetchJSON("/cgi-bin/api?endpoint=" + action, { method: "POST" })
            .then(function (res) {
                showToast(res.message || (action + " done"), res.success ? "success" : "error");
                setTimeout(function () {
                    loadStatus();
                    loadCommand();
                }, 500);
            })
            .catch(function () {
                showToast(action + " failed", "error");
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

        loadStatus();
        loadConfig();
        loadCommand();
        startAutoRefresh();
        startLogAutoRefresh();
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
