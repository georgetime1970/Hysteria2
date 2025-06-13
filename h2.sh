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

echo -e "${GREEN}开始安装 Hysteria 2...${NC}"

# 获取用户输入的端口和密码
read -p "请输入要使用的端口号（默认 443）: " PORT
PORT=${PORT:-443}

read -p "请输入连接密码（留空将使用默认密码: your_password_here888）: " PASSWORD
PASSWORD=${PASSWORD:-your_password_here888}

# 1. 执行官方安装脚本
echo "正在安装 Hysteria 2..."
bash <(curl -fsSL https://get.hy2.sh/) || {
    echo -e "${RED}Hysteria 安装失败，请检查网络连接${NC}"
    exit 1
}

# 2. 创建证书目录
mkdir -p /etc/hysteria

# 3. 生成自签名证书
echo "正在生成自签名证书..."
openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-signed.key -out /etc/hysteria/self-signed.crt -days 1000 -nodes -subj "/CN=localhost" || {
    echo -e "${RED}证书生成失败${NC}"
    exit 1
}

# 4. 设置文件权限
chmod 644 /etc/hysteria/self-signed.crt
chmod 644 /etc/hysteria/self-signed.key

# 5. 创建配置文件
echo "正在创建配置文件..."
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
    url: https://www.google.com/
    rewriteHost: true
EOF

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

echo -e "${GREEN}Hysteria 2 安装和配置完成！${NC}"
echo "当前使用端口: $PORT"
echo "当前使用密码: $PASSWORD"
echo "配置文件: /etc/hysteria/config.yaml"
echo "证书位置: /etc/hysteria/self-signed.crt"

# 获取公网 IP
PUBLIC_IP=$(curl -s https://ifconfig.me || curl -s https://api.ipify.org) || 请自行查看你主机的IP

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
