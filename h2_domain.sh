
#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本 (sudo)"
    exit 1
fi

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}欢迎使用 hysteria2 域名模式安装脚本${NC}"
echo -e "${RED}!!安装之前请确认你已经解析好域名!!${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo

# 1. === 获取用户输入的域名,cloudflare DNS API,端口和密码 ===
read -p "请输入要使用的域名: " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "域名不能为空,请重新运行脚本并输入有效域名"
    exit 1
fi

read -p "请输入 cloudflare DNS API: " CLOUDFLAREAPI
if [ -z "$CLOUDFLAREAPI" ]; then
    echo "Cloudflare DNS API不能为空,请重新运行脚本并输入有效API密钥"
    exit 1
fi

read -p "请输入要使用的端口号(默认 443): " PORT
PORT=${PORT:-443}

read -p "请输入连接密码(默认密码: 88888888): " PASSWORD
PASSWORD=${PASSWORD:-88888888}


# 2. === 修改 /etc/resolv.conf 强制系统使用IPv4 进行解析 ===
cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
echo -e "${GREEN}------ resolv.conf配置文件修改成功 ------${NC}"

# 3. === 防止系统重启修改 ===
chattr +i /etc/resolv.conf


# 4. === 执行官方安装脚本 ===
bash <(curl -fsSL https://get.hy2.sh/) || {
    echo -e "${RED}Hysteria 安装失败,请检查网络连接${NC}"
    exit 1
}
echo -e "${GREEN}------ Hysteria 2 核心已成功安装! ------${NC}"

# 5. === 创建服务端配置文件,acme的API权限要选择 DNS 读写 ===
cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

acme:
  domains:
    - "$DOMAIN"
  email: ok@email.com
  type: dns
  dns:
    name: cloudflare
    config:
      cloudflare_api_token: $CLOUDFLAREAPI

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://www.aliyundrive.com/
    rewriteHost: true
EOF
echo -e "${GREEN}------ 服务端配置文件创建成功! ------${NC}"

# 6. === 创建客户端配置文件 ===
cat > /etc/hysteria/H2.yaml << EOF
proxies:
  - name: $DOMAIN
    type: hysteria2
    server: $DOMAIN
    port: $PORT
    password: $PASSWORD
    sni: $DOMAIN
    skip-cert-verify: false

proxy-groups:
  - name: H2
    type: select
    proxies:
      - $DOMAIN

rules:
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
  - DOMAIN-SUFFIX,dune.com,DIRECT

  # 常见国内 IP 地址直连
  - GEOIP,CN,DIRECT

  # 国外流量通过代理
  - MATCH,H2
EOF
echo -e "${GREEN}------ 客户端配置文件创建成功! ------${NC}"

# 7. === 开放防火墙端口 ===
ufw allow $PORT
ufw status
echo -e "${GREEN}------ 防火墙配置完成! ------${NC}"

# 8. === 立即启动服务,设置开机自启 === 
echo "正在启动 Hysteria 服务..."
systemctl start hysteria-server.service
systemctl enable hysteria-server.service

# 9. === 检查服务状态 ===
echo "检查服务状态..."
sleep 2
systemctl status hysteria-server.service | head -n 10

# 10. === 获取公网 IP ===
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me \
  || curl -s --max-time 5 https://api.ipify.org \
  || curl -s --max-time 5 https://ipinfo.io/ip \
  || curl -s --max-time 5 https://checkip.amazonaws.com) \
  || 请自行查看你主机的IP

# 11. === 显示最终信息 ===
echo -e "${GREEN}------ Hysteria 2 安装和配置完成! ------${NC}"
echo "--------------------------------------------"
echo -e "📇 您的域名:  ${GREEN}$DOMAIN${NC}"
echo -e "🌐 服务器IP:  ${GREEN}$PUBLIC_IP${NC}"
echo -e "🚪 使用端口:  ${GREEN}$PORT${NC}"
echo -e "🔐 连接密码:  ${GREEN}$PASSWORD${NC}"
echo -e "📄 服务端配置:  /etc/hysteria/config.yaml"
echo -e "📄 客户端配置:  /etc/hysteria/H2.yaml"
echo "--------------------------------------------"
echo "现在你可以使用上述信息配置客户端连接啦 🎉"
echo
read -p "需要显示客户端具体配置内容,请按回车💕"
echo "---------------------------------------------------"
echo -e 复制以下配置内容到电脑上保存为 H2.yaml 文件:
cat /etc/hysteria/H2.yaml
echo "---------------------------------------------------"