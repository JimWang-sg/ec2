#!/bin/bash
# Jupyter Lab 远程部署脚本 v4.0
# 适配 Ubuntu 24.04 LTS | 默认端口 8899 | 默认密码 ju2024
# 生成日期：2025-05-23

set -eo pipefail

# 配置常量
VENV_PATH="$HOME/jupyter_venv"
CONFIG_DIR="$HOME/.jupyter"
CONFIG_JSON="$CONFIG_DIR/jupyter_server_config.json"
SERVICE_FILE="/etc/systemd/system/jupyter.service"
DEFAULT_PORT=8899
DEFAULT_PASS="ju2024"

# 颜色定义
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'

# 显示帮助信息[10](@ref)
show_help() {
    echo -e "${GREEN}使用方法：$0 [选项]"
    echo "选项："
    echo "  install          部署Jupyter Lab服务"
    echo "  uninstall        完全卸载Jupyter Lab"
    echo "  config           修改服务配置参数"
    echo "  status           查看服务状态"
    echo "  --help           显示帮助信息"
    echo "  --port=PORT      指定服务端口（默认：$DEFAULT_PORT）"
    echo "  --pass=PASSWORD  设置访问密码（默认：$DEFAULT_PASS）"
    echo -e "\n示例："
    echo "  $0 install --port=9000 --pass=mypassword"
    echo "  $0 config${NC}"
    exit 0
}

# 参数解析[9](@ref)
parse_params() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|uninstall|config|status)
                ACTION=$1
                shift
                ;;
            --port=*)
                PORT="${1#*=}"
                shift
                ;;
            --pass=*)
                PASSWORD="${1#*=}"
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                echo -e "${RED}错误：未知参数 $1${NC}"
                exit 1
        esac
    done
}

# 检测安装状态[2,3](@ref)
check_installation() {
    if [[ -d $VENV_PATH && -f $SERVICE_FILE ]]; then
        echo -e "${GREEN}检测到已安装Jupyter Lab${NC}"
        return 0
    elif [[ -d $VENV_PATH || -f $SERVICE_FILE ]]; then
        echo -e "${YELLOW}检测到不完整的安装记录，建议执行卸载后重新安装${NC}"
        return 1
    else
        echo -e "${BLUE}未检测到现有安装${NC}"
        return 1
    fi
}

# 卸载服务[6,8](@ref)
uninstall_service() {
    echo -e "${YELLOW}开始卸载Jupyter Lab...${NC}"
    sudo systemctl stop jupyter.service 2>/dev/null || true
    sudo systemctl disable jupyter.service 2>/dev/null || true
    sudo rm -f $SERVICE_FILE
    sudo firewall-cmd --permanent --remove-port=${PORT:-$DEFAULT_PORT}/tcp 2>/dev/null
    sudo firewall-cmd --reload 2>/dev/null
    rm -rf $VENV_PATH $CONFIG_DIR
    echo -e "${GREEN}卸载完成，已清除："
    echo "  - Python虚拟环境：$VENV_PATH"
    echo "  - 配置文件目录：$CONFIG_DIR"
    echo "  - 系统服务文件：$SERVICE_FILE${NC}"
}

# 生成配置文件[5,7](@ref)
generate_config() {
    local port=${PORT:-$DEFAULT_PORT}
    local password=${PASSWORD:-$DEFAULT_PASS}
    
    python - <<EOF
from jupyter_server.auth import passwd
import json

password_hash = passwd('$password', algorithm='argon2')
config = {
    "ServerApp": {
        "password": password_hash,
        "ip": "0.0.0.0",
        "port": $port,
        "open_browser": False,
        "root_dir": "$HOME/jupyter_workspace",
        "allow_remote_access": True
    },
    "KernelSpecManager": {
        "whitelist": ["python3"]
    }
}

with open("$CONFIG_JSON", "w") as f:
    json.dump(config, f, indent=4)
EOF
}

# 交互式配置[10](@ref)
interactive_config() {
    echo -e "\n${BLUE}当前配置："
    echo "端口：${PORT:-$(jq -r '.ServerApp.port' $CONFIG_JSON 2>/dev/null || echo $DEFAULT_PORT)}"
    echo -e "密码：******${NC}"
    
    read -p "是否修改端口？[y/N] " -n 1 yn
    if [[ $yn =~ [Yy] ]]; then
        read -p "输入新端口（当前：${PORT:-$DEFAULT_PORT}）：" new_port
        PORT=${new_port:-$PORT}
    fi
    
    read -p "是否修改密码？[y/N] " -n 1 yn
    if [[ $yn =~ [Yy] ]]; then
        read -sp "输入新密码：" new_pass
        PASSWORD=${new_pass:-$PASSWORD}
        echo
    fi
    
    generate_config
    sudo systemctl restart jupyter.service
    echo -e "${GREEN}配置已更新，正在重启服务...${NC}"
}

# 主执行逻辑
parse_params "$@"

case $ACTION in
    install)
        if check_installation; then
            echo -e "${RED}错误：服务已存在，请先卸载${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}开始安装Jupyter Lab...${NC}"
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y python3.12 python3.12-venv firewalld
        
        python3.12 -m venv "$VENV_PATH"
        source "$VENV_PATH/bin/activate"
        pip install --upgrade pip wheel setuptools
        pip install jupyterlab notebook jupyter-server
        
        generate_config
        mkdir -p "$HOME/jupyter_workspace"
        
        sudo tee $SERVICE_FILE > /dev/null <<EOL
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

        sudo firewall-cmd --permanent --add-port=${PORT:-$DEFAULT_PORT}/tcp
        sudo firewall-cmd --reload
        sudo systemctl daemon-reload
        sudo systemctl enable --now jupyter.service
        
        echo -e "${GREEN}部署成功！访问地址：http://$(curl -s ifconfig.me):${PORT:-$DEFAULT_PORT}${NC}"
        ;;

    uninstall)
        check_installation || exit 1
        uninstall_service
        ;;

    config)
        check_installation || exit 1
        interactive_config
        ;;

    status)
        check_installation || exit 1
        echo -e "${BLUE}服务状态："
        systemctl status jupyter.service --no-pager
        ;;

    *)
        show_help
        ;;
esac
