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

# 面板监听端口
PANEL_PORT=18080
# 面板程序与 unit 的下载地址
PANEL_RAW="https://raw.githubusercontent.com/georgetime1970/h2/main"

# 将 YAML 值写成双引号字符串,避免被解析成数字或布尔值
yaml_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "$s"
}

# 若 ufw 未安装或未启用则处理
ensure_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        apt update
        apt install -y ufw
    fi
    if ! ufw status 2>/dev/null | grep -q "Status: active"; then
        echo "正在启用 ufw 防火墙..."
        ufw --force enable
    fi
}

# 安装并启动常驻信息面板(非域名模式使用 HTTP,避免自签证书告警)
# $1 对外主机名(公网 IP)
install_h2_panel() {
    local host="$1"
    echo "正在安装信息面板..."
    apt update
    apt install -y python3 qrencode || {
        echo -e "${RED}python3 或 qrencode 安装失败,跳过信息面板${NC}"
        return 1
    }
    curl -fsSL "$PANEL_RAW/h2-panel.py" -o /usr/local/bin/h2-panel.py || {
        echo -e "${RED}下载 h2-panel.py 失败${NC}"
        return 1
    }
    curl -fsSL "$PANEL_RAW/h2-panel.service" -o /etc/systemd/system/h2-panel.service || {
        echo -e "${RED}下载 h2-panel.service 失败${NC}"
        return 1
    }
    chmod 644 /usr/local/bin/h2-panel.py

    local token
    token=$(cat /proc/sys/kernel/random/uuid)

    cat > /etc/hysteria/panel.env << EOF
PANEL_PORT=$PANEL_PORT
PANEL_PASSWORD=$PASSWORD
SUB_TOKEN=$token
H2_YAML=/etc/hysteria/h2.yaml
SERVER_HOST=$host
SERVER_PORT=$PORT
TRAFFIC_URL=http://127.0.0.1:9999/traffic
USE_TLS=0
CERT_FILE=
KEY_FILE=
EOF
    chmod 600 /etc/hysteria/panel.env

    ufw allow "$PANEL_PORT"/tcp >/dev/null
    systemctl daemon-reload
    systemctl enable --now h2-panel.service

    PANEL_URL="http://$host:$PANEL_PORT/"
    SUB_URL="http://$host:$PANEL_PORT/$token/h2.yaml"
    echo -e "${GREEN}信息面板: ${PANEL_URL}${NC}"
    echo "浏览器打开后,用户名随意,密码为连接密码"
    echo -e "${GREEN}订阅链接: ${SUB_URL}${NC}"
    if command -v qrencode >/dev/null 2>&1; then
        echo "手机可扫描下面的二维码导入订阅:"
        qrencode -t ansiutf8 "$SUB_URL"
    fi
}

echo
echo -e "${GREEN}欢迎使用 hysteria2 非域名模式 安装脚本 ${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo

# 1. === 获取用户输入的端口和密码 ===
while true; do
    read -p "请输入要使用的端口号（默认 443）: " PORT
    PORT=${PORT:-443}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    fi
    echo -e "${RED}端口必须是 1 到 65535 的数字${NC}"
done

while true; do
    read -p "请输入连接密码（留空将使用默认密码: 88888888）: " PASSWORD
    PASSWORD=${PASSWORD:-88888888}
    if [ ${#PASSWORD} -lt 4 ]; then
        echo -e "${RED}密码长度至少4个字符,请重新输入${NC}"
        continue
    fi
    break
done

# 2. === 获取公网 IP ===
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me \
  || curl -s --max-time 5 https://api.ipify.org \
  || curl -s --max-time 5 https://ipinfo.io/ip \
  || curl -s --max-time 5 https://checkip.amazonaws.com)
if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}无法获取公网 IP,无法签发自签证书,请检查网络后重试${NC}"
    exit 1
fi

# 3. === 修改 /etc/resolv.conf 强制系统使用IPv4 进行解析 ===
cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
echo -e "${GREEN}------ resolv.conf配置文件修改成功 ------${NC}"

# 4. === 防止系统重启修改 ===
chattr +i /etc/resolv.conf

# 5. === 执行官方安装脚本 ===
bash <(curl -fsSL https://get.hy2.sh/) || {
    echo -e "${RED}Hysteria 安装失败，请检查网络连接${NC}"
    exit 1
}
echo -e "${GREEN}Hysteria 2 服务已成功安装,进入配置${NC}"

# 6. === 创建证书目录 ===
mkdir -p /etc/hysteria
# 7. === 生成365天的自签名证书 ===
openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/self-signed.key -out /etc/hysteria/self-signed.crt -days 365 -nodes -subj "/CN=$PUBLIC_IP" -addext "subjectAltName=IP:$PUBLIC_IP" || {
    echo -e "${RED}证书生成失败${NC}"
    exit 1
}
echo -e "${GREEN}自签证书创建成功${NC}"

# 8. === 设置文件权限 ===
chmod 644 /etc/hysteria/self-signed.crt
chmod 600 /etc/hysteria/self-signed.key

# 9. === 创建服务端配置文件 ===
cat > /etc/hysteria/config.yaml << EOF
listen: :$PORT

tls:
  cert: /etc/hysteria/self-signed.crt
  key: /etc/hysteria/self-signed.key

auth:
  type: password
  password: $(yaml_quote "$PASSWORD")

trafficStats:
  listen: 127.0.0.1:9999
  secret: $(yaml_quote "$PASSWORD")

obfs:
  type: salamander
  salamander:
    password: $(yaml_quote "$PASSWORD")

masquerade:
  type: proxy
  proxy:
    url: https://ruanyifeng.com/
    rewriteHost: true
  listenHTTPS: :443
  forceHTTPS: true
EOF
echo -e "${GREEN}服务端配置文件创建成功${NC}"

# 10. === 创建客户端配置文件 ===
cat > /etc/hysteria/h2.yaml << EOF
proxies:
  - name: $PUBLIC_IP
    type: hysteria2
    server: $PUBLIC_IP
    port: $PORT
    password: $(yaml_quote "$PASSWORD")
    sni: $PUBLIC_IP
    obfs: salamander
    obfs-password: $(yaml_quote "$PASSWORD")
    skip-cert-verify: false

proxy-groups:
  - name: H2
    type: select
    proxies:
      - $PUBLIC_IP

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
echo -e "${GREEN}客户端配置文件创建成功${NC}"

# 11. === 开放防火墙端口 ===
ensure_ufw
ufw allow "$PORT"
ufw allow 443/tcp
ufw allow "$PANEL_PORT"/tcp
ufw status
echo -e "${GREEN}防火墙完成！${NC}"
echo "若使用云厂商安全组,请放行 UDP $PORT、TCP 443、TCP $PANEL_PORT"

# 12. === 启动服务并设置开机自启 ===
echo "正在启动 Hysteria 服务..."
systemctl start hysteria-server.service
systemctl enable hysteria-server.service

# 13. === 检查服务状态,最多等待约15秒 ===
echo "检查服务状态..."
HY2_OK=false
for i in $(seq 1 15); do
    if systemctl is-active --quiet hysteria-server.service; then
        HY2_OK=true
        break
    fi
    if systemctl is-failed --quiet hysteria-server.service; then
        break
    fi
    sleep 1
done

if [ "$HY2_OK" = true ]; then
    echo -e "${GREEN}Hysteria 服务运行正常${NC}"
    systemctl status hysteria-server.service --no-pager | head -n 10
else
    echo -e "${RED}Hysteria 服务启动失败,最近错误日志如下:${NC}"
    journalctl -u hysteria-server.service -n 20 --no-pager
    echo -e "${RED}请根据以上错误排查,修复后执行: systemctl restart hysteria-server.service${NC}"
fi

# 14. === 选装 fail2ban,防止 SSH 端口被暴力破解 ===
read -p "是否选装 fail2ban 防 SSH 爆破? 推荐新服务器安装 [Y/n]: " INSTALL_FAIL2BAN
if [[ -z "$INSTALL_FAIL2BAN" || "$INSTALL_FAIL2BAN" =~ ^[Yy]$ ]]; then
    bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/fail2ban.sh) || {
        echo -e "${RED}fail2ban 安装失败,可稍后手动执行:${NC}"
        echo "bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/fail2ban.sh)"
    }
fi

# 15. === 安装常驻信息面板 ===
PANEL_URL=""
SUB_URL=""
install_h2_panel "$PUBLIC_IP" || true

# 16. === 显示最终信息 ===
if [ "$HY2_OK" = true ]; then
    echo -e "${GREEN}Hysteria 2 安装和配置完成！${NC}"
else
    echo -e "${RED}Hysteria 2 未成功运行,请先根据上方日志排查${NC}"
fi
echo "--------------------------------------------"
echo -e "🌐 服务器IP:  ${GREEN}$PUBLIC_IP${NC}"
echo -e "🚪 使用端口:  ${GREEN}$PORT${NC}"
echo -e "🔐 连接密码:  ${GREEN}$PASSWORD${NC}"
echo -e "📄 服务端配置:  /etc/hysteria/config.yaml"
echo -e "📄 客户端配置:  /etc/hysteria/h2.yaml"
echo -e "🔏 证书路径:  /etc/hysteria/self-signed.crt"
[ -n "$PANEL_URL" ] && echo -e "🖥️ 信息面板:  ${GREEN}$PANEL_URL${NC}"
[ -n "$SUB_URL" ] && echo -e "📥 订阅链接:  ${GREEN}$SUB_URL${NC}"
echo "--------------------------------------------"
echo "云厂商安全组请放行: UDP $PORT、TCP 443、TCP $PANEL_PORT"
echo
echo -e "${RED}请仔细阅读以下证书的客户端配置流程！${NC}"
echo -e "${GREEN}1.将下面的证书内容复制到客户端设备上，保存为 self-signed.crt 文件。${NC}"
echo -e "${GREEN}2.Windows 客户端,双击 self-signed.crt 文件 → “安装证书” → 选择“本地计算机” → 选择“将所有的证书都放入下列存储” →  存储到 “受信任的根证书颁发机构”。${NC}"
echo -e "${GREEN}3.如果不在意数据泄露,可以直接将 客户端配置文件中的\"skip-cert-verify: false\" 设置为true,将跳过证书验证${NC}"
echo "💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖"
echo -e 复制以下证书内容到电脑上保存为 self-signed.crt 文件:
cat /etc/hysteria/self-signed.crt
echo "💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖"
echo
read -p "需要显示客户端具体配置内容,请按回车 或执行 cat /etc/hysteria/h2.yaml 命令查看💕"
echo "---------------------------------------------------"
echo -e 复制以下配置内容到电脑上保存为 h2.yaml 文件然后导入客户端:
cat /etc/hysteria/h2.yaml
echo "---------------------------------------------------"
