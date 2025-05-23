#!/bin/bash
# Ubuntu Jupyter 安全部署脚本 v3.0
# 适配 Jupyter Notebook ≥7.0 版本

set -eo pipefail

# 系统初始化
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3.12 python3.12-venv firewalld

# 创建虚拟环境
VENV_PATH="$HOME/jupyter_venv"
python3.12 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

# 安装核心组件
pip install --upgrade pip wheel setuptools
pip install jupyterlab notebook jupyter-server

# 生成配置文件
CONFIG_DIR="$HOME/.jupyter"
CONFIG_FILE="$CONFIG_DIR/jupyter_server_config.json"
mkdir -p "$CONFIG_DIR"

# 生成密码（使用jupyter_server模块）
python - <<EOF
from jupyter_server.auth import passwd
import json
import os

password_hash = passwd('ju2024')  # 设置您的密码
config = {
    "ServerApp": {
        "password": password_hash,
        "ip": "*",
        "port": 8899,
        "open_browser": False,
        "root_dir": "$HOME/jupyter_workspace",
        "allow_remote_access": True
    }
}

with open("$CONFIG_FILE", "w") as f:
    json.dump(config, f, indent=4)
EOF

# 创建工作目录
mkdir -p "$HOME/jupyter_workspace"

# 创建系统服务
sudo tee /etc/systemd/system/jupyter.service > /dev/null <<EOL
[Unit]
Description=Jupyter Notebook Service
After=network.target

[Service]
Type=exec
User=$USER
Group=$USER
WorkingDirectory=$HOME
Environment="PATH=$VENV_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=$VENV_PATH/bin/jupyter lab --config=$CONFIG_FILE
Restart=always
RestartSec=15s
KillMode=process

[Install]
WantedBy=multi-user.target
EOL

# 防火墙配置
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --reload

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now jupyter.service

# 输出状态
echo -e "\n\033[32m部署完成！服务状态：\033[0m"
sudo systemctl status jupyter.service --no-pager
echo -e "\n访问地址：http://$(curl -s ifconfig.me):8899"
echo "登录密码：ju2024"
