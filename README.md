# Gost Proxy Magisk Module

在 Android 设备上通过 Magisk 运行 [gost](https://github.com/go-gost/gost) TCP 透明代理，配备 WebUI 管理界面。应用无需单独配置 SOCKS/HTTP 代理。

## 功能特性

- 🚀 **开机自启** - 通过 Magisk service.sh 自动启动 gost 代理和 WebUI
- 🌐 **WebUI 管理** - 浏览器可视化配置代理参数（端口、认证、上游链、TLS 等），纯 shell 后端无需 Python
- 📦 **WebUI 下载二进制** - 模块安装过程不联网；安装后由用户在 WebUI 手动下载对应架构的 gost，国内网络自动尝试加速镜像
- 🔀 **透明代理** - 使用 gost `red` 监听器和 iptables 自动接管本机 TCP 流量；上游仍支持 HTTP / SOCKS5 / Shadowsocks / TLS / WebSocket
- 📱 **多架构支持** - arm64-v8a / armeabi-v7a / x86_64 / x86
- 🛡️ **完整生命周期管理** - 启动 / 停止 / 重启 / 状态查询 / 日志查看

## 安装

### 方式一：直接刷入 Magisk

1. 将本项目打包为 zip 文件
2. 在 Magisk Manager 中选择「从存储安装」
3. 选择该 zip 文件并完成安装
4. 重启后打开 `http://127.0.0.1:8080`，点击「下载 Gost」手动安装二进制

### 方式二：手动放置二进制

1. 从 [gost releases](https://github.com/go-gost/gost/releases) 下载对应架构的二进制
2. 放置到 `gost/gost` 路径
3. 打包为 zip 后刷入 Magisk

## 使用

### WebUI

安装后访问：`http://127.0.0.1:8080`

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

| 设备 ABI | gost 资源 |
|----------|-----------|
| arm64-v8a | android_arm64 |
| armeabi-v7a | linux_armv7 |
| x86_64 | linux_amd64 |
| x86 | linux_386 |

## 配置

配置文件位于 `gost/config.json`，可通过 WebUI 或直接编辑修改。

本地监听固定为 TCP 透明代理（`red://`），由模块自动创建 `iptables` OUTPUT 规则。局域网、回环地址、WebUI 端口、透明监听端口以及 root UID 流量会被排除，防止 gost 上游连接被重复代理。停止或卸载模块时会先清理规则。

注意：当前实现仅透明代理 TCP；UDP 不会被接管。由于 gost 以 root 运行，为避免代理回环，Android 的 root/system UID 流量也会直连。

## 卸载

在 Magisk Manager 中移除模块即可，卸载脚本会自动停止所有 gost 进程。

## 项目结构

```
gost-magisk-module/
├── module.prop           # Magisk 模块信息
├── customize.sh          # 安装脚本（含自动下载）
├── service.sh            # 开机自启服务
├── post-fs-data.sh       # 早期初始化
├── uninstall.sh          # 卸载清理
├── gost/
│   ├── gost              # gost 二进制（自动下载，不入库）
│   └── config.json       # 代理配置
├── scripts/
│   ├── download_gost.sh  # 自动下载脚本
│   ├── start.sh          # 启动
│   ├── stop.sh           # 停止
│   ├── status.sh         # 状态
│   └── config.sh         # 配置读写
└── webui/                # Web 管理界面
    ├── server.sh         # 纯 shell HTTP 后端（无需 Python）
    ├── server.sh         # 纯 Shell 后端（busybox httpd + CGI，无需 Python）
    ├── cgi-bin/
    │   └── api           # CGI 脚本，处理所有 API 请求
    ├── index.html        # 前端页面
    ├── app.js            # 前端逻辑
    └── style.css         # 样式
```

## 致谢

- [gost](https://github.com/go-gost/gost) - GO Simple Tunnel
- [Magisk](https://github.com/topjohnwu/Magisk) - Android Magisk Framework
