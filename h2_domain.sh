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

# 清洗域名:去掉首尾空格、http(s) 协议和路径
sanitize_domain() {
    local d="$1"
    d="${d#"${d%%[![:space:]]*}"}"
    d="${d%"${d##*[![:space:]]}"}"
    d="${d#http://}"
    d="${d#https://}"
    d="${d%%/*}"
    printf '%s' "$d"
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

# 安装并启动常驻信息面板
# $1 对外主机名(域名或 IP)  $2 为 1 时尝试 HTTPS
install_h2_panel() {
    local host="$1"
    local want_tls="$2"
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

    # 订阅路径用的随机 token,Clash 不带密码也能拉取
    local token
    token=$(cat /proc/sys/kernel/random/uuid)

    local use_tls=0
    local cert_file=""
    local key_file=""
    if [ "$want_tls" = "1" ]; then
        cert_file=$(find /var/lib/hysteria /etc/hysteria -type f -name "${host}.crt" 2>/dev/null | head -n 1)
        if [ -n "$cert_file" ]; then
            key_file="${cert_file%.crt}.key"
            if [ -f "$key_file" ]; then
                use_tls=1
            else
                cert_file=""
                key_file=""
            fi
        fi
    fi

    cat > /etc/hysteria/panel.env << EOF
PANEL_PORT=$PANEL_PORT
PANEL_PASSWORD=$PASSWORD
SUB_TOKEN=$token
H2_YAML=/etc/hysteria/h2.yaml
SERVER_HOST=$host
SERVER_PORT=$PORT
TRAFFIC_URL=http://127.0.0.1:9999/traffic
USE_TLS=$use_tls
CERT_FILE=$cert_file
KEY_FILE=$key_file
EOF
    chmod 600 /etc/hysteria/panel.env

    ufw allow "$PANEL_PORT"/tcp >/dev/null
    systemctl daemon-reload
    systemctl enable --now h2-panel.service

    local scheme="http"
    [ "$use_tls" = "1" ] && scheme="https"
    PANEL_URL="$scheme://$host:$PANEL_PORT/"
    SUB_URL="$scheme://$host:$PANEL_PORT/$token/h2.yaml"
    echo -e "${GREEN}信息面板: ${PANEL_URL}${NC}"
    echo "浏览器打开后,用户名随意,密码为连接密码"
    echo -e "${GREEN}订阅链接: ${SUB_URL}${NC}"
    if command -v qrencode >/dev/null 2>&1; then
        echo "手机可扫描下面的二维码导入订阅:"
        qrencode -t ansiutf8 "$SUB_URL"
    fi
    if [ "$want_tls" = "1" ] && [ "$use_tls" != "1" ]; then
        echo -e "${RED}未找到 ACME 证书,面板暂用 HTTP。证书就绪后可重新运行安装或手动填写 CERT_FILE 后重启 h2-panel${NC}"
    fi
}

echo
echo -e "${GREEN}欢迎使用 hysteria2 域名模式 安装脚本${NC}"
echo -e "${RED}!!!安装之前请确认你已经解析好域名,否则会失败!!!${NC}"
echo "😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎😎"
echo

# 1. === 获取用户输入的域名,cloudflare DNS API,端口和密码 ===
read -p "请输入要使用的域名: " DOMAIN
DOMAIN=$(sanitize_domain "$DOMAIN")
if [ -z "$DOMAIN" ]; then
    echo "域名不能为空,请重新运行脚本并输入有效域名"
    exit 1
fi

read -p "请输入 cloudflare DNS API: " CLOUDFLAREAPI
if [ -z "$CLOUDFLAREAPI" ]; then
    echo "Cloudflare DNS API不能为空,请重新运行脚本并输入有效API密钥"
    exit 1
fi

while true; do
    read -p "请输入要使用的端口号(默认 443): " PORT
    PORT=${PORT:-443}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    fi
    echo -e "${RED}端口必须是 1 到 65535 的数字${NC}"
done

while true; do
    read -p "请输入连接密码(默认密码: 88888888): " PASSWORD
    PASSWORD=${PASSWORD:-88888888}
    if [ ${#PASSWORD} -lt 4 ]; then
        echo -e "${RED}密码长度至少4个字符,请重新输入${NC}"
        continue
    fi
    break
done

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
    - $(yaml_quote "$DOMAIN")
  email: admin@$DOMAIN
  type: dns
  dns:
    name: cloudflare
    config:
      cloudflare_api_token: $(yaml_quote "$CLOUDFLAREAPI")

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
# 配置含密码和 API Token,仅允许 hysteria 用户读取
chown hysteria:hysteria /etc/hysteria/config.yaml
chmod 600 /etc/hysteria/config.yaml
echo -e "${GREEN}------ 服务端配置文件创建成功! ------${NC}"

# 6. === 创建客户端配置文件 ===
cat > /etc/hysteria/h2.yaml << EOF
proxies:
  - name: $DOMAIN
    type: hysteria2
    server: $DOMAIN
    port: $PORT
    password: $(yaml_quote "$PASSWORD")
    sni: $DOMAIN
    obfs: salamander
    obfs-password: $(yaml_quote "$PASSWORD")
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
ensure_ufw
ufw allow "$PORT"
ufw allow 443/tcp
ufw allow "$PANEL_PORT"/tcp
ufw status
echo -e "${GREEN}------ 防火墙配置完成! ------${NC}"
echo "若使用云厂商安全组,请放行 UDP $PORT、TCP 443、TCP $PANEL_PORT"

# 8. === 立即启动服务,设置开机自启 ===
echo "正在启动 Hysteria 服务..."
systemctl start hysteria-server.service
systemctl enable hysteria-server.service

# 9. === 检查服务状态,域名模式申请证书可能较慢,最多等待约90秒 ===
echo "检查服务状态..."
HY2_OK=false
for i in $(seq 1 45); do
    if systemctl is-active --quiet hysteria-server.service; then
        HY2_OK=true
        break
    fi
    if systemctl is-failed --quiet hysteria-server.service; then
        break
    fi
    sleep 2
done

if [ "$HY2_OK" = true ]; then
    echo -e "${GREEN}Hysteria 服务运行正常${NC}"
    systemctl status hysteria-server.service --no-pager | head -n 10
else
    echo -e "${RED}Hysteria 服务启动失败,最近错误日志如下:${NC}"
    journalctl -u hysteria-server.service -n 20 --no-pager
    echo -e "${RED}请根据以上错误排查,修复后执行: systemctl restart hysteria-server.service${NC}"
fi

# 10. === 选装 fail2ban,防止 SSH 端口被暴力破解 ===
read -p "是否选装 fail2ban 防 SSH 爆破? 推荐新服务器安装 [Y/n]: " INSTALL_FAIL2BAN
if [[ -z "$INSTALL_FAIL2BAN" || "$INSTALL_FAIL2BAN" =~ ^[Yy]$ ]]; then
    bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/fail2ban.sh) || {
        echo -e "${RED}fail2ban 安装失败,可稍后手动执行:${NC}"
        echo "bash <(curl -fsSL https://raw.githubusercontent.com/georgetime1970/h2/main/fail2ban.sh)"
    }
fi

# 11. === 获取公网 IP ===
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me \
  || curl -s --max-time 5 https://api.ipify.org \
  || curl -s --max-time 5 https://ipinfo.io/ip \
  || curl -s --max-time 5 https://checkip.amazonaws.com)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="(未能自动获取,请自行查看)"
fi

# 12. === 安装常驻信息面板 ===
PANEL_URL=""
SUB_URL=""
install_h2_panel "$DOMAIN" 1 || true

# 13. === 显示最终信息 ===
if [ "$HY2_OK" = true ]; then
    echo -e "${GREEN}------ Hysteria 2 安装和配置完成! ------${NC}"
else
    echo -e "${RED}------ Hysteria 2 未成功运行,请先根据上方日志排查 ------${NC}"
fi
echo "--------------------------------------------"
echo -e "📇 您的域名:  ${GREEN}$DOMAIN${NC}"
echo -e "🌐 服务器IP:  ${GREEN}$PUBLIC_IP${NC}"
echo -e "🚪 使用端口:  ${GREEN}$PORT${NC}"
echo -e "🔐 连接密码:  ${GREEN}$PASSWORD${NC}"
echo -e "📄 服务端配置:  /etc/hysteria/config.yaml"
echo -e "📄 客户端配置:  /etc/hysteria/h2.yaml"
[ -n "$PANEL_URL" ] && echo -e "🖥️ 信息面板:  ${GREEN}$PANEL_URL${NC}"
[ -n "$SUB_URL" ] && echo -e "📥 订阅链接:  ${GREEN}$SUB_URL${NC}"
echo "--------------------------------------------"
echo "云厂商安全组请放行: UDP $PORT、TCP 443、TCP $PANEL_PORT"
echo
read -p "需要显示客户端具体配置内容,请按回车💕"
echo "---------------------------------------------------"
echo -e 复制以下配置内容到电脑上保存为 h2.yaml 文件然后导入客户端:
cat /etc/hysteria/h2.yaml
echo "---------------------------------------------------"
