<div align="center">

# 🌍 Hysteria2 极速+隐私 一键部署 🚀

[![hysteris2](https://img.shields.io/badge/hysteris2-orange)](https://v2.hysteria.network/zh/)
[![Clash Verge](https://img.shields.io/badge/Clash%20Verge-cb7fff)](https://www.clashverge.dev/)
![Debian](https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)

**🐯 本项目设计初衷: 追求极致的速度和严格的隐私加密保护**

</div>

本项目适合不想折腾技术只想忙里偷闲的官人，只要有台 _`垃圾 VPS`_ 服务器，就能一键安装！

使用本项目脚本前,请详细阅读以下内容,了解基本流程和注意事项,再进行安装部署.

**📌 Hysteria2 是什么？**
点击 👉 [官方介绍](https://v2.hysteria.network/zh/) 了解详细内容。

1. 📇 本教程主要适用于客户端是 `windows` 系统的官人使用, `macOS/Linux` 系统也可以使用,俺在`Ubuntu24`的桌面版也能正常使用客户端,只是需要下载对应的客户端软件,服务端客户端的配置文件都是一样的

2. 📄 脚本文件为本项目中的 [h2.sh](https://github.com/georgetime1970/h2/blob/main/h2.sh) 和 [h2_domain.sh](https://github.com/georgetime1970/h2/blob/main/h2_domain.sh) 文件,已开源,请放心食用

3. 📦 本项目脚本文件核心是调用的 hysteria2 [官方安装脚本](https://v2.hysteria.network/zh/docs/getting-started/Installation/)

4. 🛡️ 俺给小白提供了 [fail2ban.sh](https://github.com/georgetime1970/h2/blob/main/fail2ban.sh) 脚本用于保护服务器免受 SSH 暴力破解攻击,可选择性安装

---

## 💡 脚本说明

💖 本项目有 **2** 种模式

### 域名模式

**使用域名的自动获取证书模式**

- 需要注册域名,解析域名;
- 使用 [cloludflare](https://dash.cloudflare.com/) 进行域名解析时,本脚本可以自动获取证书并自动续期;如果你使用的其他域名解析商,请查看官方支持自动配置证书的服务商:👉[查看此处](https://v2.hysteria.network/zh/docs/advanced/ACME-DNS-Config/),然后修改[h2_domain.sh](https://github.com/georgetime1970/h2/blob/main/h2_domain.sh)对应的第5步配置即可

### 非域名模式

**不使用域名的自签证书模式**

- 直接使用 ip 进行连接,伪装性不如域名好,但是不影响长期使用,适用于审查不是很严的地方
- 这种模式下您发送的数据依旧是加密的,仅是伪装性不好,毕竟谁没事每天大流量访问一个IP呢?

### 🟢 推荐使用`域名模式`

- 非域名模式需要每个设备都安装证书才能最安全的使用,而域名模式则不需要;
- 如果要在设备上使用非域名模式,又不想安装证书则可将客户端配置中的`skip-cert-verify: false` 设置为`true`即可正常使用(无需修改服务端配置),您发送的数据依旧是加密的,只是如果有人伪造您的服务器,您的客户端将无法识别这个冒牌货.

> ⚠️ **温馨提示**：
> 1️⃣ 注册域名可使用 [DigitalPlat Domain](https://domain.digitalplat.org/),免费的域名注册服务,可获得至少一个二级域名
>
> 2️⃣ 域名和非域名模式选择一种安装即可,你需要一台能访问外网的服务器,俺使用的 [vultr](https://www.vultr.com/)
>
> 3️⃣ 安装时需设置服务器 `端口`, `443`、`8443`、`4433`、`8080`、`8888` 都可以,推荐使用`443`端口

---

## 🖥️ 服务端部署教程

### ✅ 推荐服务器系统环境

建议使用干净的 Linux VPS，系统推荐：

- Ubuntu 20.04 / 22.04 及以上
- Debian 12 x64 及以上
- 或其他稳定版本

---

### ⚡ 域名模式 一键部署

⚠️ **部署前请提前将域名解析指向你的 VPS 服务器**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/h2_domain.sh)
```

### ⚡ 非域名模式 一键部署

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/h2.sh)
```

---

### 🛡️ `fail2ban` 一键部署

- 安装成功后可选择安装 `fail2ban` 保护服务器,封禁恶意 IP, 防止 SSH 端口被恶意爆破
- 脚本来源于本项目的[fail2ban.sh](https://github.com/georgetime1970/h2/blob/main/fail2ban.sh) 文件,已开源,请放心食用

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/fail2ban.sh)
```

---

### 服务器常用命令

#### 放开端口并检查防火墙

```bash
sudo ufw allow 443
sudo ufw status
```

#### 启动 hysteria2 服务

首次启动执行

```bash
sudo systemctl start hysteria-server.service
```

#### 重启 hysteria2 服务

修改配置文件后执行

```bash
sudo systemctl restart hysteria-server.service
```

#### 设置 hysteria2 开机自启

```bash
sudo systemctl enable hysteria-server.service
```

#### 查看 hysteria2 服务状态

```bash
sudo systemctl status hysteria-server.service
```

#### 查询 hysteria2 服务端日志

如果 hysteria2 启动失败可查看原因

```bash
sudo journalctl --no-pager -e -u hysteria-server.service
```

#### 查询 fail2ban IP 封禁情况

```bash
sudo fail2ban-client status sshd
```

---

## 📱 客户端软件下载

- 🤖 **安卓端**：[ClashMeta for Android](https://github.com/MetaCubeX/ClashMetaForAndroid/releases)
- 💻 **电脑端**：[Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev/releases) ,有 linux 版本

---

## 📄 客户端 YAML 配置文件示例

- 将以下内容复制保存为 `H2.yaml`,;或服务器端安装完成后,按下回车键会获得对应的完整配置,直接复制使用即可;或直接下载本项目的 [H2.yaml](https://raw.githubusercontent.com/georgetime1970/h2/main/H2.yaml) 文件进行修改
- 将 `server` 字段改为你自己的 `服务器IP`或`域名`
- 将 `port` 字段改为你自己的 `端口号`
- 将 `password` 字段改为你自己的 `密码`
- 将 `sni` 字段改为你自己的 `服务器IP`或`域名`,必须与`server` 字段一致
- 然后就可以发送给 `Clash Verge` 电脑客户端或者 `ClashMeta for Android` 手机客户端使用了
- `Clash Verge` 客户端本地导入配置教程, 请点击 👉 [教程](https://www.clashverge.dev/guide/profile.html#_4)

```yaml
proxies:
  - name: Hysteria2-Server
    type: hysteria2
    server: 1.1.1.1 <你的服务器ip 或 域名>
    port: 443 <你设置的端口>
    password: your_password_here <你的密码>
    sni: 1.1.1.1 <你的服务器ip 或 域名 必须与 server字段 一致>
    # 是否跳过证书验证,默认验证证书,跳过验证连接将不再加密
    skip-cert-verify: false

proxy-groups:
  - name: H2
    type: select
    proxies:
      - Hysteria2-Server

rules:
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,qq.com,DIRECT
  - DOMAIN-SUFFIX,weibo.com,DIRECT
  - DOMAIN-SUFFIX,alibaba.com,DIRECT
  - DOMAIN-SUFFIX,tmall.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - DOMAIN-SUFFIX,163.com,DIRECT
  - DOMAIN-SUFFIX,360.cn,DIRECT
  - DOMAIN-SUFFIX,gov.cn,DIRECT
  - DOMAIN-SUFFIX,edu.cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,H2
```

---

## 常见问题

这里会列出常见的安装问题,新的问题会整理在这里,不断完善中

### 1. cloudflare_api_token 如何获取?

登录 [cloudflare](https://dash.cloudflare.com/), 管理账户 → 账户 API 令牌 → 创建令牌 → 编辑区域 DNS ,根据提示继续创建即可获得 API

## 🔐 VPN 安全性检测指南

### ✅ 1. IP 地址泄露检测

🔍 工具：[IP 检测](https://browserleaks.com/ip)

👀 应看到的是 VPS 的公网 IP，而非本地真实 IP。

---

### ✅ 2. WebRTC 泄露检测

🔍 工具：[WebRTC 检测](https://browserleaks.com/webrtc)
`WebRTC Leak Test`字段显示为`✔No Leak`,代表没有泄露.

🔧 解决方案：

- 已过时 ~~Chrome 安装 [WebRTC Network Limiter](https://chromewebstore.google.com/detail/webrtc-network-limiter/npeicpdbkakmehahjeeohfdhnlpdklia)，在 `扩展程序选项` 中选择 `Use my proxy server`。~~
- 在 `Clash Verge` 电脑端打开 `TUN模式` , 并开启 `严格路由` 模式 , 这样当你使用 `规则模式` 或 `全局模式` 时, 就不会出现 `WebRTC 泄露` 泄露了

---

### ✅ 3. DNS 泄露检测

🔍 工具：[DNS 检测](https://browserleaks.com/dns)

🔧 解决方案：

- 启用「`禁用智能多宿主名称解析`」：`Win + R` → `gpedit.msc` → `计算机配置` → `管理模板` → `网络` → `DNS 客户端`
- 在 `Clash Verge` 电脑端打开 `TUN模式` , 并开启 `严格路由` 模式 , 这样当你使用 **`全局模式`** 时,就不会出现 `DNS` 泄露了

---

### ✅ 4. IPv6 泄露检测

🔍 工具：[IP 检测](https://browserleaks.com/ip)
查看`IPv6 Address`字段,显示 为`n/a`即表示没有检测到 IPv6,这意味着只有 IPv4 流量可用，并且您的真实位置不能通过 IPv6 泄漏.

🔧 解决方案：电脑端禁用 IPv6：

控制面板 → 网络和 Internet → 网络和共享中心 → 更改适配器设置 → 选中网卡,右键`属性` → 取消勾选「`Internet 协议版本 6（TCP/IPv6）`」

---

## 🧭 `Clash Verge` 中「系统代理」和「TUN 模式」的区别与适用场景

| 模式名称     | 本质作用                                 | 覆盖范围                                             | 推荐使用场景                         |
| ------------ | ---------------------------------------- | ---------------------------------------------------- | ------------------------------------ |
| **系统代理** | 设置浏览器/应用的 HTTP/HTTPS/SOCKS5 代理 | ❗️**只作用于支持代理的软件**（如浏览器）             | 网页浏览、开发调试、轻量使用         |
| **TUN 模式** | 创建虚拟网卡，拦截系统层所有流量         | ✅ **拦截所有程序/服务的流量**，包括不支持代理的软件 | 游戏、音乐软件、系统级加速、全局代理 |

- 简单理解就是 **`系统代理`** 只会代理一部分软件, **`TUN 模式`** 会接管电脑的所有流量出入
- 如果要追求极致隐私, 就使用 **`TUN 模式`** 并设置 `严格路由`和`全局模式`, 但是会使访问变慢一点
- 如果不追求极致隐私, 又想访问快一点,就使用 **`系统代理`**
