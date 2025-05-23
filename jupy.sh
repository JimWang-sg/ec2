#!/bin/bash
# Jupyter Lab 远程部署脚本 v5.0
# 适配 Ubuntu 24.04 LTS | 交互式配置版
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

# 输入验证
get_valid_input() {
    local prompt=$1
    local default=$2
    local validator=$3
    local value
    
    while true; do
        read -p "$prompt (默认：$default) " value
        value=${value:-$default}
        if $validator "$value"; then
            break
        fi
    done
    echo "$value"
}

# 端口验证
validate_port() {
    if [[ $1 =~ ^[0-9]+$ ]] && [ $1 -ge 1 ] && [ $1 -le 65535 ]; then
        return 0
    else
        echo -e "${RED}错误：端口号必须为1-65535之间的数字${NC}"
        return 1
    fi
}

# 密码验证
validate_pass() {
    if [ -z "$1" ]; then
        echo -e "${RED}错误：密码不能为空${NC}"
        return 1
    elif [ ${#1} -lt 4 ]; then
        echo -e "${RED}警告：密码建议至少4位字符${NC}"
    fi
    return 0
}

# 生成配置文件
generate_config() {
    local port=$1
    local password=$2
    
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

# 安装流程
install_jupyter() {
    echo -e "\n${GREEN}>>> 开始安装流程${NC}"
    
    # 获取用户输入
    local port=$(get_valid_input "请输入监听端口" $DEFAULT_PORT validate_port)
    local pass=$(get_valid_input "设置访问密码" $DEFAULT_PASS validate_pass)
    
    # 系统更新
    echo -e "${BLUE}正在更新系统包...${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3.12 python3.12-venv firewalld
    
    # 创建虚拟环境
    echo -e "${BLUE}创建Python虚拟环境...${NC}"
    python3.12 -m venv "$VENV_PATH"
    source "$VENV_PATH/bin/activate"
    
    # 安装依赖
    echo -e "${BLUE}安装核心组件...${NC}"
    pip install --upgrade pip wheel setuptools
    pip install jupyterlab notebook jupyter-server
    
    # 生成配置
    echo -e "${BLUE}生成配置文件...${NC}"
    mkdir -p "$CONFIG_DIR"
    generate_config $port $pass
    mkdir -p "$HOME/jupyter_workspace"
    
    # 配置系统服务
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

    # 防火墙配置
    echo -e "${BLUE}配置防火墙...${NC}"
    sudo firewall-cmd --permanent --add-port=$port/tcp
    sudo firewall-cmd --reload
    
    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable --now jupyter.service
    
    echo -e "\n${GREEN}✔ 安装完成！${NC}"
    show_access_info
}

# 卸载流程
uninstall_jupyter() {
    echo -e "\n${YELLOW}>>> 开始卸载流程${NC}"
    
    # 获取当前端口
    local current_port=$DEFAULT_PORT
    if [ -f $CONFIG_JSON ]; then
        current_port=$(jq -r '.ServerApp.port' $CONFIG_JSON)
    fi
    
    # 确认提示
    read -p "确定要完全卸载吗？[y/N] " -n 1 confirm
    echo
    [[ $confirm =~ [yY] ]] || return
    
    # 停止服务
    echo -e "${BLUE}停止运行中的服务...${NC}"
    sudo systemctl stop jupyter.service 2>/dev/null || true
    sudo systemctl disable jupyter.service 2>/dev/null || true
    
    # 清除文件
    echo -e "${BLUE}删除相关文件...${NC}"
    sudo rm -f $SERVICE_FILE
    sudo firewall-cmd --permanent --remove-port=${current_port}/tcp
    sudo firewall-cmd --reload
    rm -rf $VENV_PATH $CONFIG_DIR
    
    echo -e "${GREEN}✔ 卸载完成${NC}"
}

# 修改配置
modify_config() {
    echo -e "\n${GREEN}>>> 修改配置参数${NC}"
    
    # 获取当前配置
    if [ ! -f $CONFIG_JSON ]; then
        echo -e "${RED}错误：未找到配置文件${NC}"
        return
    fi
    
    local current_port=$(jq -r '.ServerApp.port' $CONFIG_JSON)
    local new_port=$(get_valid_input "输入新端口" $current_port validate_port)
    
    # 密码修改需要二次确认
    read -p "是否修改密码？[y/N] " -n 1 yn
    echo
    if [[ $yn =~ [yY] ]]; then
        local new_pass=$(get_valid_input "设置新密码" "" validate_pass)
        generate_config $new_port $new_pass
    else
        generate_config $new_port $DEFAULT_PASS
    fi
    
    # 更新防火墙
    if [ $new_port -ne $current_port ]; then
        sudo firewall-cmd --permanent --remove-port=$current_port/tcp
        sudo firewall-cmd --permanent --add-port=$new_port/tcp
        sudo firewall-cmd --reload
    fi
    
    sudo systemctl restart jupyter.service
    echo -e "${GREEN}✔ 配置已更新${NC}"
}

# 状态查看
show_status() {
    echo -e "\n${BLUE}>>> 服务状态${NC}"
    systemctl status jupyter.service --no-pager || echo -e "${RED}服务未运行${NC}"
}

# 访问信息
show_access_info() {
    if [ -f $CONFIG_JSON ]; then
        local port=$(jq -r '.ServerApp.port' $CONFIG_JSON)
        local public_ip=$(curl -s ifconfig.me)
        echo -e "\n${GREEN}访问信息："
        echo "URL: http://${public_ip}:${port}"
        echo -e "密码: $(jq -r '.ServerApp.password' $CONFIG_JSON | awk -F: '{print $1}')${NC}"
    else
        echo -e "${RED}未找到配置信息${NC}"
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
