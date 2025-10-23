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
echo -e "${GREEN}fail2ban 是用于保护服务器,防止 SSH 端口被恶意爆破的程序${NC}"
echo -e "${GREEN}你将自定义设置失败几次后封禁恶意 IP 和封禁的时长${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo
# 获取用户输入的失败次数和封禁时间
read -p "请输入允许的最大失败登录次数（默认 5 次）: " MAXRETRY
MAXRETRY=${MAXRETRY:-5}   
read -p "请输入封禁时间，单位为秒（默认 864000 秒 10天）: " BAN_TIME
BAN_TIME=${BAN_TIME:-864000}

# 使用 curl 从外部服务获取公网 IP
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me \
  || curl -s --max-time 5 https://api.ipify.org \
  || curl -s --max-time 5 https://ipinfo.io/ip \
  || curl -s --max-time 5 https://checkip.amazonaws.com)
if [ -z "$PUBLIC_IP" ]; then
    echo "❌ 无法获取公网 IP，退出..."
    exit 1
else
    echo "✅ 公网 IP: $PUBLIC_IP"
fi

# 安装 fail2ban
apt update
apt install fail2ban -y

# 写入配置文件, 使用这个服务器代理的节点登录,不会被封禁
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = $BAN_TIME
findtime = 600
maxretry = $MAXRETRY
ignoreip = 127.0.0.1/8 ::1 $PUBLIC_IP

[sshd]
enabled = true
backend = systemd
EOF

# 检查配置语法
fail2ban-client -d >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ 配置有误，请检查 /etc/fail2ban/jail.local"
    exit 1
fi

# 启动并设置开机自启 fail2ban 服务
systemctl enable --now fail2ban

# 查看Fail2ban状态
systemctl status fail2ban | head -n 10

# 显示爆破状态信息
echo
echo -e "${GREEN}✅ fail2ban 已成功安装并配置完成！${NC}"
echo -e "${GREEN}使用命令 sudo fail2ban-client status sshd 即可查看以下封禁情况${NC}"
fail2ban-client status sshd