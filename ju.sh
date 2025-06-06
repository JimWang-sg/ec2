#!/bin/bash
# Jupyter Lab 远程部署脚本 v5.4.1修改版
# 移除所有防火墙配置操作 | 发布日期：2025-05-24

set -eo pipefail

# 配置常量
VENV_PATH="$HOME/jupyter_venv"
CONFIG_DIR="$HOME/.jupyter"
CONFIG_JSON="$CONFIG_DIR/jupyter_server_config.json"
PASSWORD_FILE="$CONFIG_DIR/password.txt"
SERVICE_FILE="/etc/systemd/system/jupyter.service"
DEFAULT_PORT=8899
DEFAULT_PASS="jupyter24"

# 颜色定义
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'
BLUE='\033[34m'; NC='\033[0m'

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}Jupyter Lab 管理菜单${NC}"
    echo "--------------------------------"
    echo "1. 安装并配置 Jupyter Lab"
    echo "2. 完全卸载 Jupyter Lab"
    echo "3. 修改服务配置"
    echo "4. 查看服务状态"
    echo "5. 显示访问信息"
    echo "0. 退出脚本"
    echo "--------------------------------"
}

# 输入验证（修复版）
get_valid_input() {
    local prompt=$1
    local default=$2
    local validator=$3
    local is_password=$4
    local value=""
    
    while true; do
        if [ "$is_password" = "true" ]; then
            read -sp "${prompt} (默认：${default//?/*}) " value
            echo
        else
            read -p "${prompt} (默认：${default}) " value
        fi
        
        if [ -z "$value" ]; then
            value="$default"
            if [ "$is_password" = "true" ]; then
                echo -e "${BLUE}使用默认密码：${default//?/*}${NC}" >&2
            else
                echo -e "${BLUE}使用默认值：${default}${NC}" >&2
            fi
        fi
        
        if $validator "$value"; then
            break
        else
            echo -e "${RED}输入无效，请重新输入${NC}" >&2
        fi
    done
    echo "$value"
}

# 端口验证
validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ $1 -ge 1 -a $1 -le 65535 ] && return 0
    echo -e "${RED}错误：端口必须为1-65535之间的数字${NC}" >&2
    return 1
}

# 密码验证（增强版）
validate_pass() {
    if [ -z "$1" ]; then
        echo -e "${RED}错误：密码不能为空${NC}" >&2
        return 1
    elif [ ${#1} -lt 8 ]; then
        echo -e "${RED}错误：密码长度至少8位（当前：${#1}位）${NC}" >&2
        return 1
    fi
    return 0
}

# 生成配置文件
generate_config() {
    local port=$1
    local password=$2
    
    python3 - <<EOF
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

# 安装流程（移除了防火墙配置）
install_jupyter() {
    echo -e "\n${GREEN}>>> 开始安装流程${NC}"
    
    local port=$(get_valid_input "请输入监听端口" $DEFAULT_PORT validate_port false)
    local pass=$(get_valid_input "设置访问密码" $DEFAULT_PASS validate_pass true)
    
    echo -e "${BLUE}正在更新系统包...${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3.12 python3.12-venv  # 移除了firewalld安装
    
    echo -e "${BLUE}创建Python虚拟环境...${NC}"
    python3.12 -m venv "$VENV_PATH"
    source "$VENV_PATH/bin/activate"
    
    echo -e "${BLUE}安装核心组件...${NC}"
    pip install --upgrade pip wheel setuptools
    pip install jupyterlab notebook jupyter-server
    
    echo -e "${BLUE}生成配置文件...${NC}"
    mkdir -p "$CONFIG_DIR"
    generate_config $port $pass
    
    echo "$pass" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    mkdir -p "$HOME/jupyter_workspace"
    
    echo -e "${BLUE}创建系统服务...${NC}"
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

    sudo systemctl daemon-reload
    sudo systemctl enable --now jupyter.service
    
    echo -e "\n${GREEN}✔ 安装完成！${NC}"
    show_access_info
}

# 卸载流程（移除了防火墙清理）
uninstall_jupyter() {
    echo -e "\n${YELLOW}>>> 开始卸载流程${NC}"
    
    read -p "确定要完全卸载吗？[y/N] " -n 1 confirm
    echo
    [[ $confirm =~ [yY] ]] || return
    
    echo -e "${BLUE}停止运行中的服务...${NC}"
    sudo systemctl stop jupyter.service 2>/dev/null || true
    sudo systemctl disable jupyter.service 2>/dev/null || true
    
    echo -e "${BLUE}删除相关文件...${NC}"
    sudo rm -f $SERVICE_FILE
    rm -rf $VENV_PATH $CONFIG_DIR "$PASSWORD_FILE"
    
    echo -e "${GREEN}✔ 卸载完成${NC}"
}

# 修改配置（移除了防火墙更新）
modify_config() {
    echo -e "\n${GREEN}>>> 修改配置参数${NC}"
    source "$VENV_PATH/bin/activate"
    
    if [ ! -f $CONFIG_JSON ]; then
        echo -e "${RED}错误：未找到配置文件${NC}"
        return 1
    fi
    
    local current_port=$(jq -r '.ServerApp.port' $CONFIG_JSON)
    local new_port=$(get_valid_input "输入新端口" $current_port validate_port false)
    
    # 密码处理
    local current_pass=$(cat "$PASSWORD_FILE")
    read -p "是否修改密码？[y/N] " -n 1 yn
    echo
    if [[ $yn =~ [yY] ]]; then
        local new_pass=$(get_valid_input "设置新密码" "$current_pass" validate_pass true)
        echo "$new_pass" > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
    else
        local new_pass="$current_pass"
    fi
    
    generate_config $new_port $new_pass
    
    sudo systemctl restart jupyter.service
    echo -e "${BLUE}等待服务重启..." && sleep 3
    
    systemctl is-active jupyter.service | grep -q "active" || {
        echo -e "${RED}服务启动失败，请检查日志："
        journalctl -u jupyter.service -n 50 --no-pager
        exit 1
    }
    
    echo -e "${GREEN}✔ 配置已更新${NC}"
}

show_status() {
    echo -e "\n${BLUE}>>> 服务状态${NC}"
    systemctl status jupyter.service --no-pager || echo -e "${RED}服务未运行${NC}"
}

show_access_info() {
    if [ -f "$CONFIG_JSON" ] && [ -f "$PASSWORD_FILE" ]; then
        local port=$(jq -r '.ServerApp.port' $CONFIG_JSON)
        local public_ip=$(curl -s ifconfig.me)
        local password=$(cat "$PASSWORD_FILE")
        
        echo -e "\n${GREEN}访问信息："
        echo "URL: http://${public_ip}:${port}"
        echo -e "密码: ${GREEN}${password}${NC}"
    else
        echo -e "${RED}配置信息不完整，请重新安装${NC}"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请输入操作编号 (0-5): " choice
    case $choice in
        1) install_jupyter ;;
        2) uninstall_jupyter ;;
        3) modify_config ;;
        4) show_status ;;
        5) show_access_info ;;
        0) echo -e "${GREEN}已退出脚本${NC}"; exit 0 ;;
        *) echo -e "${RED}无效的选项，请重新输入${NC}" ;;
    esac
    read -n 1 -s -r -p "按任意键返回菜单..."
done
