
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
echo -e "${GREEN}欢迎使用 hysteria2 域名模式 安装脚本${NC}"
echo -e "${RED}!!!安装之前请确认你已经解析好域名,否则会失败!!!${NC}"
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

# 校验连接密码: 以0开头的纯数字会被 YAML 解析为八进制数字,导致服务启动失败
while true; do
    read -p "请输入连接密码(默认密码: 88888888): " PASSWORD
    PASSWORD=${PASSWORD:-88888888}
    if [[ "$PASSWORD" =~ ^0[0-9]+$ ]]; then
        echo -e "${RED}密码不能以0开头的纯数字,请使用字母数字混合密码,例如 pass${PASSWORD} 或 ${PASSWORD}x${NC}"
        continue
    fi
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

trafficStats:
  listen: :9999
  secret: $PASSWORD

obfs:
  type: salamander
  salamander:
    password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://ruanyifeng.com/
    rewriteHost: true
  listenHTTPS: :443
  forceHTTPS: true
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
    obfs: salamander
    obfs-password: $PASSWORD
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
ufw allow 9999
ufw status
echo -e "${GREEN}------ 防火墙配置完成! ------${NC}"

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
  || curl -s --max-time 5 https://checkip.amazonaws.com) \
  || echo "请自行查看你主机的IP"

# 12. === 显示最终信息 ===
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
# 临时开启订阅链接,可填入 Clash Verge / ClashMeta,或用浏览器下载
read -p "是否开启订阅链接? 可填入 Clash Verge 等客户端 [Y/n]: " DOWNLOAD_H2
if [[ -z "$DOWNLOAD_H2" || "$DOWNLOAD_H2" =~ ^[Yy]$ ]]; then
    # 精简镜像可能没有 python3 / qrencode,没有则用 apt 安装
    NEED_PKGS=()
    command -v python3 >/dev/null 2>&1 || NEED_PKGS+=(python3)
    command -v qrencode >/dev/null 2>&1 || NEED_PKGS+=(qrencode)
    if [ ${#NEED_PKGS[@]} -gt 0 ]; then
        echo "正在安装: ${NEED_PKGS[*]}"
        apt update
        apt install -y "${NEED_PKGS[@]}" || {
            echo -e "${RED}依赖安装失败,请按回车查看配置并手动复制${NC}"
        }
    fi
    if command -v python3 >/dev/null 2>&1; then
        DOWNLOAD_PORT=18080
        DOWNLOAD_ROOT="/tmp/h2-dl"
        mkdir -p "$DOWNLOAD_ROOT"
        cp /etc/hysteria/H2.yaml "$DOWNLOAD_ROOT/H2.yaml"
        ufw allow "$DOWNLOAD_PORT"/tcp >/dev/null
        python3 -m http.server "$DOWNLOAD_PORT" --directory "$DOWNLOAD_ROOT" --bind 0.0.0.0 >/dev/null 2>&1 &
        DOWNLOAD_PID=$!
        SUB_URL="http://$DOMAIN:$DOWNLOAD_PORT/H2.yaml"
        echo
        echo -e "${GREEN}订阅链接(可直接填入 Clash Verge、ClashMeta 等客户端):${NC}"
        echo -e "  ${GREEN}$SUB_URL${NC}"
        echo "手机可扫描下面的二维码导入:"
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t ansiutf8 "$SUB_URL"
        else
            echo -e "${RED}二维码生成失败,请手动复制上面的订阅链接${NC}"
        fi
        echo "也可在浏览器打开该链接下载,文件一般在:"
        echo -e "  Windows: ${GREEN}C:\\Users\\你的用户名\\Downloads\\H2.yaml${NC}"
        echo -e "  安卓: 文件管理器里的「下载」文件夹"
        echo -e "${RED}关闭后订阅链接将无法继续在线更新,请先导入客户端${NC}"
        read -p "导入或下载完成后请按回车,将关闭临时订阅服务: "
        kill "$DOWNLOAD_PID" 2>/dev/null
        wait "$DOWNLOAD_PID" 2>/dev/null
        ufw --force delete allow "$DOWNLOAD_PORT"/tcp >/dev/null 2>&1
        rm -rf "$DOWNLOAD_ROOT"
        echo -e "${GREEN}临时订阅服务已关闭${NC}"
    fi
fi
echo
read -p "需要显示客户端具体配置内容,请按回车💕"
echo "---------------------------------------------------"
echo -e 复制以下配置内容到电脑上保存为 H2.yaml 文件然后导入客户端:
cat /etc/hysteria/H2.yaml
echo "---------------------------------------------------"