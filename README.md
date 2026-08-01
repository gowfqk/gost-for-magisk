# Gost Proxy Magisk Module

在 Android 设备上通过 Magisk 运行 [gost](https://github.com/go-gost/gost) 本地代理，配备 WebUI 管理界面。可选择自动接管本机 TCP 的 REDIRECT 模式，或供应用手动连接的 SOCKS5 模式。

## 功能特性

- 🚀 **开机自启** - 通过 Magisk service.sh 自动启动 gost 代理和 WebUI
- 🌐 **WebUI 管理** - 浏览器可视化配置代理参数（端口、认证、上游链、TLS 等），纯 shell 后端无需 Python
- 📦 **WebUI 下载二进制** - 模块安装过程不联网；安装后由用户在 WebUI 手动下载对应架构的 gost，国内网络自动尝试加速镜像
- 🔗 **链接导入** - 一个输入框同时支持单条和批量代理链接导入（每行一条），节点名称自动读取链接备注
- 🔀 **双本地模式** - REDIRECT 使用 gost `red` 和 iptables 自动接管本机 TCP；SOCKS5 开放普通代理端口且不修改系统流量规则；上游仍支持 HTTP / SOCKS5 / Shadowsocks / TLS / WebSocket
- 🧭 **IPv4-only DNS 兼容** - 内核缺少 IPv6 NAT 时自动过滤 Google 相关域名的 AAAA 应答，防止双栈流量绕过 IPv4 透明代理
- 🇨🇳 **GeoData 自动分流** - 可下载 GeoSite/GeoIP 数据，将中国域名及 CIDR 设为直连
- ♻️ **免重启更新 WebUI** - 更新模块后自动从新模块目录热重启 WebUI，不影响正在运行的 gost 代理
- 📱 **ARM64 精简包** - 仅支持现代 Android 设备常用的 arm64-v8a，显著减小安装包体积
- 🛡️ **完整生命周期管理** - 启动 / 停止 / 重启 / 状态查询 / 日志查看

## 安装

### 方式一：直接刷入 Magisk

1. 从 [Releases](https://github.com/gowfqk/gost-for-magisk/releases) 下载最新的 `gost-proxy-v*.zip`
2. 在 Magisk / KernelSU / APatch 管理器中选择「从存储安装」
3. 选择下载的 ZIP 并完成安装
4. 首次安装建议重启手机，让模块服务和透明代理规则正常初始化
5. 重启后打开 `http://127.0.0.1:8080`，点击「下载 Gost」手动安装二进制

更新已安装模块时，安装脚本会保留配置、节点、GeoData 缓存和已有 Gost 二进制，并自动热重启 WebUI。更新后的管理界面无需重启手机即可生效，正在运行的 Gost 代理不会被中断；若热重启失败，重启手机后会按正常流程启动。

### 方式二：手动放置二进制

1. 从 [gost releases](https://github.com/go-gost/gost/releases) 下载对应架构的二进制
2. 放置到 `gost/gost` 路径
3. 打包为 zip 后刷入 Magisk

## 使用

### WebUI

安装后访问：`http://127.0.0.1:8080`（若修改过 `webui_port`，请使用配置的端口）。

WebUI 支持代理配置、节点保存与切换、链接导入、Gost 下载、运行状态、日志、代理测试及 GeoData 分流管理。导入链接时可粘贴单条链接，也可粘贴多条链接并保持每行一条。

### 命令行

```bash
# 启动代理
sh /data/adb/modules/gost_proxy/scripts/start.sh

# 停止代理
sh /data/adb/modules/gost_proxy/scripts/stop.sh

# 查看状态
sh /data/adb/modules/gost_proxy/scripts/status.sh

# 手动下载/更新 gost 二进制
sh /data/adb/modules/gost_proxy/scripts/download_gost.sh
```

## 手动下载脚本

WebUI 的「下载 Gost」按钮会调用 `scripts/download_gost.sh`；安装模块时不会执行该脚本。该脚本提供：

- **架构自动检测** - 通过 `getprop` (Android) 或 `uname` (Linux) 检测设备架构
- **国内网络检测** - 通过 GitHub API 连通性测试 + IP 地理位置双重检测
- **加速镜像** - 检测到国内网络时自动使用 GitHub 加速镜像（支持多个镜像源自动切换）
- **版本自动获取** - 从 GitHub API 获取最新 release 版本
- **完整性验证** - 下载后自动解压、安装、验证二进制

### 架构映射

| 设备 ABI | gost 资源 | DNS 过滤器 |
|----------|-----------|------------|
| arm64-v8a | android_arm64 | 内置支持 |

当前精简版安装器仅接受 `arm64-v8a`，不再打包 32 位 ARM、x86_64 或 x86 的 DNS 过滤器。

## 配置

运行时配置位于模块目录的 `gost/config.json`，可通过 WebUI 或直接编辑修改。节点配置保存在 `gost/nodes/`，当前节点记录在 `gost/active`。这些运行时文件可能包含代理凭据，不会提交到仓库；首次安装会从 `gost/nodes/default.json.example` 创建默认配置。

本地代理模式可在 WebUI 中选择：

- **REDIRECT**（默认，兼容旧配置）：使用 `red://` 监听器，并自动创建 `iptables`/`ip6tables` OUTPUT 规则接管本机 IPv4 与 IPv6 TCP。局域网、回环地址、WebUI 端口、透明监听端口以及 root UID 流量会被排除，防止 gost 上游连接被重复代理。
- **SOCKS5**：使用 `socks5://` 普通监听器，可选用户名/密码认证。该模式不会自动接管系统流量，也不会安装透明代理、QUIC 或 DNS 重定向规则；应用需手动配置模块的监听地址和端口。由 REDIRECT 切换到 SOCKS5 并重启后，会主动清理旧透明规则。

部分 Android 内核虽提供 `ip6tables`，但缺少 IPv6 `nat` 表。仅在 REDIRECT 模式下，模块检测到这种情况后会保留 IPv4 TCP 代理，并自动启动本地 DNS 过滤器：Google、YouTube 等目标域名的 A 查询正常转发，AAAA 查询返回空答案，从而让应用改用可被代理的 IPv4。过滤列表位于 `dns/ipv4-only-domains.txt`。支持 IPv6 NAT 的设备不会启用此兼容模式。

注意：REDIRECT 当前只透明代理 TCP；普通 UDP 不会被接管。兼容模式只额外接管传统 DNS 的 UDP/TCP 53。为避免 Chrome/Google 通过 UDP/443 的 QUIC 绕过 TCP 代理，REDIRECT 模式会拒绝非 root 应用的 QUIC，使其立即回退到已代理的 HTTPS/TCP。Android 私人 DNS（DoT）或应用内安全 DNS（DoH）不经过 53 端口，启用时可能绕过本地 DNS 过滤；遇到此情况请关闭私人 DNS和 Chrome 安全 DNS。SOCKS5 模式不应用这些全局规则。由于 gost 以 root 运行，为避免 REDIRECT 代理回环，Android 的 root/system UID 流量仍会直连。

## 卸载

在 Magisk Manager 中移除模块即可，卸载脚本会自动停止所有 gost 进程。

## 项目结构

```
gost-magisk-module/
├── module.prop           # Magisk 模块信息
├── customize.sh          # 安装、数据保留及 WebUI 热重启
├── service.sh            # 开机自启 gost 和 WebUI
├── post-fs-data.sh       # 早期恢复持久化 Gost 二进制
├── uninstall.sh          # 卸载及规则清理
├── gost/
│   ├── geodata/          # GeoData 缓存（运行时生成）
│   ├── nodes/            # 节点配置与默认模板
│   └── tools/            # GeoData 辅助工具（运行时下载）
├── scripts/
│   ├── config.sh         # 配置读写
│   ├── download_gost.sh  # 手动下载/更新 Gost
│   ├── iptables.sh       # 透明代理规则管理
│   ├── start.sh          # 启动代理
│   ├── status.sh         # 状态查询
│   ├── stop.sh           # 停止代理
│   ├── test_proxy.sh     # 代理连通性测试
│   ├── update_geodata.sh # 下载并更新 GeoData 分流数据
│   └── dns_filter.sh     # IPv4-only DNS 过滤器进程管理
├── dns/
│   ├── bin/              # 各 Android ABI 的 DNS 过滤器
│   ├── src/              # DNS 过滤器 Go 源码
│   └── ipv4-only-domains.txt # AAAA 过滤域名列表
└── webui/                # Web 管理界面
    ├── server.sh         # 纯 Shell HTTP 服务（BusyBox httpd/nc）
    ├── cgi-bin/
    │   └── api           # CGI 脚本，处理所有 API 请求
    ├── index.html        # 前端页面
    ├── app.js            # 前端逻辑
    └── style.css         # 样式
```

## 致谢

- [gost](https://github.com/go-gost/gost) - GO Simple Tunnel
- [Magisk](https://github.com/topjohnwu/Magisk) - Android Magisk Framework
