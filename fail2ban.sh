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
echo -e "${RED}fail2ban 是用于保护服务器,防止 SSH 端口被恶意爆破的程序${NC}"
echo -e "${RED}你将自定义设置失败几次后封禁恶意 IP 和封禁的时长${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo
read -p "回车继续... Ctrl+c 退出" ENTER
# 获取用户输入的失败次数和封禁时间
read -p "请输入允许的最大失败登录次数（默认 5 次）: "MAXRETRY
MAXRETRY=${MAXRETRY:-5}   
read -p "请输入封禁时间，单位为秒（默认 864000 秒 10天）: " BAN_TIME
BAN_TIME=${BAN_TIME:-864000}

# 创建 /var/log/auth.log 文件（如果不存在）
if [ ! -f /var/log/auth.log ]; then
    touch /var/log/auth.log
fi
# 安装 fail2ban
sudo apt update
sudo apt install fail2ban -y

# 创建本地配置文件
sudo  cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
backend = auto
logpath = /var/log/auth.log
maxretry = $MAXRETRY
bantime = $BAN_TIME
findtime = 600
EOF

# 启动并设置开机自启 fail2ban 服务
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# 查看Fail2ban状态
sudo systemctl status fail2ban

# 显示爆破状态信息
echo -e "${GREEN}fail2ban 已成功安装并配置完成！${NC}"
sudo sudo fail2ban-client status sshd