#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本 (sudo)"
    exit 1
fi

# 使用 curl 从外部服务获取公网 IP
PUBLIC_IP=$(curl -s https://ifconfig.me || curl -s https://api.ipify.org || curl -s https://ipinfo.io/ip)
if [ -z "$PUBLIC_IP" ]; then
    echo "无法获取公网 IP，退出..."
    exit 1
fi

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始安装 Hysteria 2...${NC}"

# 获取用户输入的端口和密码
read -p "请输入要使用的端口号（默认 443）: " PORT
PORT=${PORT:-443}

read -p "请输入连接密码（留空将使用默认密码: 88888888）: " PASSWORD
PASSWORD=${PASSWORD:-88888888}

# 1. 执行官方安装脚本
echo "开始安装 Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/) || {
    echo -e "${RED}Hysteria 安装失败，请检查网络连接${NC}"
    exit 1
}

# 2. 创建证书目录
mkdir -p /etc/hysteria
# 3. 生成自签名证书
openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-signed.key -out /etc/hysteria/self-signed.crt -days 365 -nodes -subj "/CN=$PUBLIC_IP" -addext "subjectAltName=IP:$PUBLIC_IP" || {
    echo -e "${RED}证书生成失败${NC}"
    exit 1
}
echo -e "${GREEN}自签证书创建成功${NC}"

# 4. 设置文件权限
chmod 644 /etc/hysteria/self-signed.crt
chmod 644 /etc/hysteria/self-signed.key

# 5. 创建服务端配置文件
cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

tls:
  cert: /etc/hysteria/self-signed.crt
  key: /etc/hysteria/self-signed.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://www.aliyundrive.com/
    rewriteHost: true
EOF
echo -e "${GREEN}服务端配置文件创建成功${NC}"

# 6.创建客户端配置文件
cat > /etc/hysteria/h2.yaml << EOF
proxies:
  - name: $PUBLIC_IP
    type: hysteria2
    server: $PUBLIC_IP
    port: $PORT
    password: $PASSWORD
    sni: $PUBLIC_IP
    skip-cert-verify: false

proxy-groups:
  - name: H2
    type: select
    proxies:
      - $PUBLIC_IP

rules:
 # 国内流量直连
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
  - DOMAIN-SUFFIX,dune.com,DIRECT

  # 常见国内 IP 地址直连
  - GEOIP,CN,DIRECT

  # 国外流量通过代理
  - MATCH,H2
EOF
echo -e "${GREEN}客户端配置文件创建成功${NC}"

# 6. 开放防火墙端口
echo "正在配置防火墙..."
ufw allow $PORT
ufw status

# 7. 重启服务并设置开机自启
echo "正在重启 Hysteria 服务..."
systemctl restart hysteria-server.service
systemctl enable --now hysteria-server.service

# 8. 检查服务状态
echo "检查服务状态..."
sleep 2
systemctl status hysteria-server.service | head -n 10

# 显示最终信息
echo -e "${GREEN}Hysteria 2 安装和配置完成！${NC}"
echo "--------------------------------------------"
echo -e "🌐 服务器IP:  ${GREEN}$PUBLIC_IP${NC}"
echo -e "🚪 使用端口:  ${GREEN}$PORT${NC}"
echo -e "🔐 连接密码:  ${GREEN}$PASSWORD${NC}"
echo -e "📄 配置文件:  /etc/hysteria/config.yaml"
echo -e "🔏 证书路径:  /etc/hysteria/self-signed.crt"
echo "--------------------------------------------"
echo "现在你可以使用上述信息配置客户端连接啦 🎉"
echo
read -p "需要显示客户端具体配置内容,请按回车💕"
echo "---------------------------------------------------"
cat /etc/hysteria/h2.yaml
echo "---------------------------------------------------"