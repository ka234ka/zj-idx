#!/bin/bash

# ✅ 参数配置（请修改）
CF_TUNNEL_DOMAIN="ffff001.cckkvv.eu.org"        # 固定域名
CF_TUNNEL_TOKEN="eyJhIjoiZTQyZTJiODdmZmQwNjYyZTMyNzZiNTExODA2YzlhNjEiLCJ0IjoiYzU4OWI3YTYtZDU1Mi00NjAwLThmNzUtZDQ2YTdmMzc5NzU2IiwicyI6Ik5EQXpPRGs1WTJNdFlUUmhOeTAwT1ROaExUbGlOelF0TURBMk5tWTBPV00zTXpkbSJ9"              # 或 JSON 文件路径
UUID="aca4e9de-9705-428c-a8f2-3c34938dc62c" # VMess UUID
PORT=9002                                   # sing-box 监听端口
SUB_PORT=8080                               # 订阅服务端口

# ✅ 安装依赖
apt-get update && apt-get install -y curl unzip python3

# ✅ 创建工作目录
mkdir -p ~/.cache && cd ~/.cache

# ✅ 下载 sing-box
curl -L https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64 -o web
chmod +x web

# ✅ 下载 cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared

# ✅ 写入 config.json
cat > config.json <<EOF
{
  "inbounds": [
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        { "uuid": "$UUID" }
      ],
      "transport": {
        "type": "ws",
        "path": "/vmess-argo"
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

# ✅ 启动 sing-box
nohup ./web run -c config.json > web.log 2>&1 &

# ✅ 启动 cloudflared 隧道
nohup ./cloudflared tunnel --url http://localhost:$PORT --no-autoupdate --hostname $CF_TUNNEL_DOMAIN --token $CF_TUNNEL_TOKEN > cloudflared.log 2>&1 &

# ✅ 启动订阅服务
cat > sub.py <<EOF
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, base64

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        node = {
            "v": "2",
            "ps": "vmess-argo",
            "add": "$CF_TUNNEL_DOMAIN",
            "port": "443",
            "id": "$UUID",
            "aid": "0",
            "net": "ws",
            "type": "none",
            "host": "$CF_TUNNEL_DOMAIN",
            "path": "/vmess-argo",
            "tls": "tls"
        }
        vmess = "vmess://" + base64.b64encode(json.dumps(node).encode()).decode()
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(vmess.encode())

HTTPServer(("", $SUB_PORT), Handler).serve_forever()
EOF
nohup python3 sub.py > sub.log 2>&1 &

# ✅ 输出订阅链接
echo "订阅链接：http://localhost:$SUB_PORT"
