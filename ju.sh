#!/bin/bash
# Jupyter Lab 远程部署脚本 v3.1
# 适配 Ubuntu 24.04 LTS | 端口 8899 | 密码 Jupyter@2024
# 生成日期：2025-05-23

set -eo pipefail

# 系统初始化
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3.12 python3.12-venv firewalld

# 创建虚拟环境
VENV_PATH="$HOME/jupyter_venv"
python3.12 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

# 安装核心组件（网页1][网页3][网页8）
pip install --upgrade pip wheel setuptools
pip install jupyterlab notebook jupyter-server

# 生成配置文件（网页5][网页7）
CONFIG_DIR="$HOME/.jupyter"
CONFIG_JSON="$CONFIG_DIR/jupyter_server_config.json"
mkdir -p "$CONFIG_DIR"

# 生成密码配置（网页2][网页9）
python - <<EOF
from jupyter_server.auth import passwd
import json

password_hash = passwd('ju2024', algorithm='argon2')
config = {
    "ServerApp": {
        "password": password_hash,
        "ip": "0.0.0.0",    # 允许所有IP访问[6](@ref)
        "port": 8899,       # 用户指定端口[8](@ref)
        "open_browser": False,
        "root_dir": "$HOME/jupyter_workspace",
        "allow_remote_access": True
    },
    "KernelSpecManager": {
        "whitelist": ["python3"]  # 内核白名单[7](@ref)
    }
}

with open("$CONFIG_JSON", "w") as f:
    json.dump(config, f, indent=4)
EOF

# 创建工作目录（网页4]
mkdir -p "$HOME/jupyter_workspace"

# 创建系统服务（网页6]
sudo tee /etc/systemd/system/jupyter.service > /dev/null <<EOL
[Unit]
Description=Jupyter Lab Service
After=network.target

[Service]
Type=exec
User=$USER
Group=$USER
WorkingDirectory=$HOME
Environment="PATH=$VENV_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=$VENV_PATH/bin/jupyter lab --config=$CONFIG_JSON
Restart=always
RestartSec=15s
KillMode=process

[Install]
WantedBy=multi-user.target
EOL

# 防火墙配置（网页3][网页5]
sudo firewall-cmd --permanent --add-port=8899/tcp
sudo firewall-cmd --reload

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now jupyter.service

# 验证部署
echo -e "\n\033[32m[部署验证]\033[0m"
echo -e "配置文件生成：$(ls -l $CONFIG_JSON)"
echo -e "服务状态：$(systemctl is-active jupyter.service)"
echo -e "\n\033[36m访问地址：http://$(curl -s ifconfig.me):8899"
echo "登录密码：ju2024"
