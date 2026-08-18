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
echo -e "${GREEN}Hysteria2 一键卸载${NC}"
echo "将停止面板和 Hysteria,删除本项目写入的配置,并解锁 resolv.conf"
echo -e "${RED}fail2ban、443 防火墙规则默认保留,需要时再确认删除${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo

read -p "确认卸载? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 从服务端配置读取 Hysteria 监听端口,供后面询问是否删除 ufw 规则
HY2_PORT=""
if [ -f /etc/hysteria/config.yaml ]; then
    HY2_PORT=$(grep -E '^listen:' /etc/hysteria/config.yaml | head -n 1 | sed 's/.*://;s/[^0-9]//g')
fi

# 1. === 停止并移除信息面板 ===
echo "正在停止信息面板..."
systemctl disable --now h2-panel.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/h2-panel.service
rm -f /usr/local/bin/h2-panel.py
rm -rf /var/lib/h2-panel

# 2. === 停止 Hysteria,调用官方脚本删除二进制和 systemd 单元 ===
echo "正在停止 Hysteria..."
systemctl disable --now hysteria-server.service >/dev/null 2>&1 || true
bash <(curl -fsSL https://get.hy2.sh/) --remove || {
    echo -e "${RED}官方卸载命令失败,将继续删除本项目残留文件${NC}"
}

# 3. === 删除配置、证书和 ACME 数据(官方 --remove 不会删这些) ===
echo "正在删除配置文件..."
rm -rf /etc/hysteria
rm -rf /var/lib/hysteria
userdel hysteria >/dev/null 2>&1 || true

systemctl daemon-reload

# 4. === 解锁 resolv.conf,不改回 nameserver,避免猜错原来的 DNS ===
if [ -f /etc/resolv.conf ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    echo "已解锁 /etc/resolv.conf (chattr -i),内容未改动"
fi

# 5. === 删除面板专用防火墙规则 ===
if command -v ufw >/dev/null 2>&1; then
    ufw --force delete allow 18080/tcp >/dev/null 2>&1 || true
    echo "已尝试删除 ufw 规则: 18080/tcp"
fi

# 6. === 可选: 删除 Hysteria 端口的 ufw 规则 ===
if command -v ufw >/dev/null 2>&1 && [ -n "$HY2_PORT" ]; then
    read -p "是否删除 ufw 中 UDP/TCP ${HY2_PORT} 规则? 若该端口还提供其他服务请选 n [y/N]: " DEL_PORT
    if [[ "$DEL_PORT" =~ ^[Yy]$ ]]; then
        ufw --force delete allow "$HY2_PORT" >/dev/null 2>&1 || true
        ufw --force delete allow "$HY2_PORT"/udp >/dev/null 2>&1 || true
        ufw --force delete allow "$HY2_PORT"/tcp >/dev/null 2>&1 || true
        echo "已尝试删除 ufw 规则: $HY2_PORT"
    fi
    if [ "$HY2_PORT" != "443" ]; then
        read -p "是否删除 ufw 中 TCP 443 规则(伪装站用过)? [y/N]: " DEL_443
        if [[ "$DEL_443" =~ ^[Yy]$ ]]; then
            ufw --force delete allow 443/tcp >/dev/null 2>&1 || true
            echo "已尝试删除 ufw 规则: 443/tcp"
        fi
    fi
fi

# 7. === 可选: 卸载 fail2ban,默认保留以防 SSH 爆破 ===
if systemctl list-unit-files fail2ban.service >/dev/null 2>&1; then
    read -p "是否同时卸载 fail2ban? 建议保留 [y/N]: " DEL_F2B
    if [[ "$DEL_F2B" =~ ^[Yy]$ ]]; then
        systemctl disable --now fail2ban >/dev/null 2>&1 || true
        apt remove -y fail2ban >/dev/null 2>&1 || true
        rm -f /etc/fail2ban/jail.local
        echo "已卸载 fail2ban"
    else
        echo "已保留 fail2ban"
    fi
fi

echo
echo -e "${GREEN}卸载完成${NC}"
echo "未删除 python3 / qrencode,其他程序可能仍在使用"
echo "云厂商安全组里若放行过 UDP 端口和 18080,请到控制台自行关掉"
echo
