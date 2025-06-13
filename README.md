# 🌍 Hysteria2 一键部署管理脚本 🚀

**📌 Hysteria2 是什么？**
点击 👉 [官方介绍](https://v2.hysteria.network/zh/) 了解详细内容。

---

## 💡 脚本说明

* 🧠 本脚本适合不想折腾技术只想偷懒的领导，只要有台 *垃圾 VPS*，就能一键傻白甜安装！
* 📄 脚本文件为项目中的 [`hy2.sh`](https://github.com/georgetime1970/h2/blob/main/h2.sh)，建议阅读源代码确保安全。
* 📦 `hy2.sh` 实际调用的是 hysteria2 的 [官方安装脚本](https://v2.hysteria.network/zh/docs/getting-started/Installation/)

> ⚠️ **温馨提示**：
>
> 1️⃣ 不适合需要配置域名的领导
>
> 2️⃣ 不适合需要端口跳跃的领导
>
> 3️⃣ 安装时需设置 `端口` 和 `密码`：
>
> * 端口：建议使用 `443`（首选）
> * 备选端口：`8443`、`8080`、`80`（需伪装得更像网页）

---

## 📱 客户端软件下载

* 🤖 **安卓端**：[ClashMeta for Android](https://github.com/MetaCubeX/ClashMetaForAndroid/releases)
* 💻 **电脑端**：[Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev/releases)

---

## 🖥️ Hysteria2 服务部署教程

### ✅ 推荐系统环境

建议使用干净的 Linux VPS，系统推荐：

* Ubuntu 20.04 / 22.04
* Debian 12 x64
* 或其他稳定版本

---

### ⚡ 一键部署方式

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/h2.sh)
```

---

### 🛠️ 手动部署步骤

#### ① 安装 hysteria2

```bash
bash <(curl -fsSL https://get.hy2.sh/)
```

---

#### ② 生成自签名证书

```bash
sudo openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-signed.key -out /etc/hysteria/self-signed.crt -days 1000 -nodes -subj "/CN=localhost"
```

* 🔐 私钥位置：`/etc/hysteria/self-signed.key`
* 📄 证书位置：`/etc/hysteria/self-signed.crt`

---

#### ③ 编辑配置文件

```bash
sudo nano /etc/hysteria/config.yaml
```

填写如下内容：
- 根据需要修改 `listen` 端口 和 `password` 密码
```yaml
listen: :443

tls:
  cert: /etc/hysteria/self-signed.crt
  key: /etc/hysteria/self-signed.key

auth:
  type: password
  password: your_password_here888

masquerade:
  type: proxy
  proxy:
    url: https://www.google.com/
    rewriteHost: true
```

* 💾 `Ctrl+O` 保存
* ❌ `Ctrl+X` 退出

---

#### ④ 放开端口并检查防火墙

```bash
sudo ufw allow 443
sudo ufw status
```

---

#### ⑤ 设置证书权限

```bash
sudo chmod 644 /etc/hysteria/self-signed.crt
sudo chmod 644 /etc/hysteria/self-signed.key
```

---

#### ⑥ 重启服务 & 查看状态

```bash
sudo systemctl restart hysteria-server.service
sudo systemctl status hysteria-server.service
```

---

#### ⑦ 设置开机自启

```bash
sudo systemctl enable --now hysteria-server.service
```

---

## 📄 客户端 YAML 配置文件示例

- 将以下内容复制保存为 `H2.yaml`, 或直接下载本项目的 `H2.yaml` 文件进行修改
- 将 `server` 字段改为你自己的 `服务器IP`
- 将 `port` 字段改为你自己的 `端口号`
- 将 `password` 字段改为你自己的 `密码`

```yaml
proxies:
  - name: Hysteria2-Server
    type: hysteria2
    server: 1.1.1.1
    port: 8888
    password: your_password_here888
    sni: localhost
    skip-cert-verify: true

proxy-groups:
  - name: H2
    type: select
    proxies:
      - Hysteria2-Server

rules:
  - DOMAIN-SUFFIX,ruanyifeng.com,DIRECT
  - DOMAIN-SUFFIX,scenefrog.com,DIRECT
  - DOMAIN-SUFFIX,api.deepseek.com,DIRECT
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

## 🔐 VPN 安全性检测指南

### ✅ 1. IP 地址泄露检测

🔍 工具：[browserleaks.com/ip](https://browserleaks.com/ip)
👀 应看到的是 VPS 的公网 IP，而非本地真实 IP。

---

### ✅ 2. DNS 泄露检测

🔍 工具：[browserleaks.com/dns](https://browserleaks.com/dns)
🔧 解决方案：
启用「禁用智能多宿主名称解析」：
`Win + R → gpedit.msc → 计算机配置 → 管理模板 → 网络 → DNS 客户端`

---

### ✅ 3. WebRTC 泄露检测

🔍 工具：[browserleaks.com/webrtc](https://browserleaks.com/webrtc)
🔧 解决方案：
Chrome 安装 [WebRTC Network Limiter](https://chrome.google.com/webstore/detail/webrtc-network-limiter/eiadekoaikejlgdbkbdfeijglgfdalml)，并设置为「Use my proxy server」。

---

### ✅ 4. IPv6 泄露检测

🧪 同上工具页面检测 IPv6 地址
🔧 解决方案：电脑端禁用 IPv6：
控制面板 → 网络和共享中心 → 更改适配器 → 禁用 IPv6

---

### ✅ 5. 浏览器设置优化

* ❌ 关闭 QUIC 协议
  打开：`chrome://flags/#enable-quic` → 设置为 `Disabled`

* ❌ 关闭 “安全 DNS”
  打开：`chrome://settings/security` → 关闭【使用安全 DNS】
