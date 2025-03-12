# hysteria 一键部署管理脚本

## 客户端
- 安卓端https://github.com/MetaCubeX/ClashMetaForAndroid/releases
- 电脑端：https://github.com/clash-verge-rev/clash-verge-rev/releases


## 1、hysteria 1一键部署管理脚本

```bash
curl -fsSL https://git.io/hysteria.sh
```

快捷管理命令为：`hihy`

安装教程：[自建hysteria服务器教程](https://github.com/Alvin9999/new-pac/wiki/%E8%87%AA%E5%BB%BAhysteria%E6%9C%8D%E5%8A%A1%E5%99%A8%E6%95%99%E7%A8%8B)

## 2、hysteria 2一键部署管理脚本

### 官方一键部署管理脚本
- bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/7feabd0e5b76707a31b3612efa4a9a4a78698e6d/h2.sh)

#### 服务端
1. 准备 一个干净的 Linux VPS，建议使用 Ubuntu 20.04/22.04 或类似的版本。
2. 使用 Hysteria 官方一键安装脚本
```bash
bash <(curl -fsSL https://get.hy2.sh/)
```
3.生成自签名证书
```bash
sudo openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-signed.key -out /etc/hysteria/self-signed.crt -days 1000 -nodes -subj "/CN=localhost"
```
 - 私钥位置：/etc/hysteria/self-signed.key
 - 证书位置：/etc/hysteria/self-signed.crt

4.修改 Hysteria 配置文件以使用自签名证书
 - 使用 nano 或 vim 编辑这个文件：
```bash
sudo nano /etc/hysteria/config.yaml
```
 - 直接覆盖原文件 `Ctrl+O 保存 Ctrl+X 退出`

```bash
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
5.放开443端口
 - 放开并检查端口
```bash
sudo ufw allow 443
sudo ufw status
```


6.文件权限设置

```bash
sudo chmod 644 /etc/hysteria/self-signed.crt
sudo chmod 644 /etc/hysteria/self-signed.key
```

7.重启Hysteria 服务并确认服务是否运行正常

```bash
sudo systemctl restart hysteria-server.service
sudo systemctl status hysteria-server.service
```
开机自启

```bash
systemctl enable --now hysteria-server.service
```

### 客户端：生成 YAML 配置文件

 - 将以下内容复制到一个文本编辑器（如 记事本）中，然后保存为 H2.yaml
```bash
proxies:
  - name: Hysteria2-Server
    type: hysteria2
    server: 149.28.77.203
    port: 443
    password: your_password_here888
    sni: localhost
    skip-cert-verify: true

proxy-groups:
  - name: H2
    type: select
    proxies:
      - Hysteria2-Server

rules:
  # 屏蔽广告
  - DOMAIN-SUFFIX,adsmogo.com,REJECT
  - DOMAIN-SUFFIX,adsense.com,REJECT
  - DOMAIN-SUFFIX,googleadservices.com,REJECT
  - DOMAIN-SUFFIX,googlesyndication.com,REJECT
  - DOMAIN-SUFFIX,googletagmanager.com,REJECT
  - DOMAIN-SUFFIX,googletagservices.com,REJECT
  - DOMAIN-SUFFIX,doubleclick.net,REJECT
  - DOMAIN-SUFFIX,moatads.com,REJECT
  - DOMAIN-SUFFIX,adnxs.com,REJECT

  # 国内流量直连
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

  # 常见国内 IP 地址直连
  - GEOIP,CN,DIRECT

  # 国外流量通过代理
  - MATCH,H2
```




## 3、sing-box精装桶一键脚本

```bash
curl -Ls https://gitlab.com/rwkgyg/sing-box-yg/raw/main/sb.sh
```

或者

```bash
wget -qO- https://gitlab.com/rwkgyg/sing-box-yg/raw/main/sb.sh 2> /dev/null
```

快捷管理命令为：`sb`

项目地址：[Sing-box-yg精装桶小白专享一键四协议共存脚本](https://github.com/yonggekkk/sing-box_hysteria2_tuic_argo_reality)


## 4、vpn安全性检测
### 检查信息泄露（IP、DNS、WebRTC）

1. IP 地址泄露检测

使用一些常见的在线工具来检测你的公共 IP 地址是否被泄露，特别是当你连接到 VPN 时：

https://ipleak.net

https://whatismyipaddress.com

https://browserleaks.com/ip

你应该看到的 IP 地址应该是 VPN 服务器的，而不是你本地的真实 IP。

2. DNS 泄露检测

DNS 泄露意味着你的域名查询请求可能会绕过 VPN 隧道，通过你的 ISP（互联网服务提供商）解析，而不是通过 VPN 指定的 DNS。

使用以下工具来检测 DNS 泄露：

https://browserleaks.com/dns

https://dnsleaktest.com

https://www.dnsleak.com

确保 DNS 查询请求显示的服务器与 VPN 服务器一致，而不是你的本地 ISP。

解决方案：在电脑端组策略(Win+R，输入gpedit.msc，计算机配置-->管理模板-->网络-->DNS客户端)中启用：禁用智能多宿主名称解析

3. WebRTC 泄露检测

WebRTC 是浏览器的一项功能，但它可能泄露本地 IP 地址，特别是在使用 VPN 的时候。

使用以下工具来检测 WebRTC 泄露：

https://browserleaks.com/webrtc

https://ipleak.net（也包含 WebRTC 检测）

如果检测结果中显示了你的本地 IP 地址，就说明存在 WebRTC 泄露。

解决方案：谷歌浏览器安装WebRTC Network Limiter，选择use my proxy server

4. IPv6 泄露检测

如果你的网络支持 IPv6，你也需要检测 IPv6 地址是否泄露。

在上面提到的工具上可以查看 IPv6 是否被正确隐藏。

解决方案：电脑端直接在适配器禁用ipv6

5. 浏览器设置

- 关闭浏览器的QUIC, 中国大陆的isp是限速udp的, 所以导致QUIC这个优秀的协议, 到了中国大陆的网络下成了个负面增益效果 chrome://flags/#enable-quic 设置为Disabled (点下方弹出的重启浏览器生效)；

- 关闭浏览器中的“安全DNS”。chrome://settings/security 找到【隐私和安全】 -【使用安全DNS】，关闭；
