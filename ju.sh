#!/bin/bash
# Jupyter Lab 安全部署脚本 v5.5
# 功能：全自动端口跟踪 | 防火墙规则自清洁
# 适配：Ubuntu 24.04 LTS
# 最后更新：2025-05-25

set -eo pipefail

# 配置区
readonly VENV_PATH="$HOME/.jupyter_venv"
readonly CONFIG_DIR="$HOME/.jupyter"
readonly CONFIG_JSON="$CONFIG_DIR/server_config.json"
readonly PASS_FILE="$CONFIG_DIR/.passkey"
readonly PORT_RECORD="$CONFIG_DIR/firewall_ports.log"  # 端口变更追踪文件
readonly SERVICE_FILE="/etc/systemd/system/jupyter-lab.service"
readonly DEFAULT_PORT=8899
readonly DEFAULT_PASS="jupyter24$RANDOM"  # 动态生成默认密码

# 颜色定义
readonly RED='\033[31m'; readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'; readonly BLUE='\033[34m'
readonly NC='\033[0m'

# 初始化日志文件
init_port_record() {
    mkdir -p "$CONFIG_DIR"
    touch "$PORT_RECORD"
    chmod 600 "$PORT_RECORD"
}

# 防火墙管理核心
firewall_manager() {
    local action=$1
    local port=$2

    case $action in
        add)
            echo "Adding port $port"
            sudo firewall-cmd --permanent --add-port="$port/tcp"
            grep -qxF "$port" "$PORT_RECORD" || echo "$port" >> "$PORT_RECORD"
            ;;
        remove)
            echo "Removing port $port"
            sudo firewall-cmd --permanent --remove-port="$port/tcp"
            sed -i "/^$port$/d" "$PORT_RECORD"
            ;;
        cleanup)
            echo "Cleaning all recorded ports"
            while read -r p; do
                sudo firewall-cmd --permanent --remove-port="${p}/tcp"
            done < "$PORT_RECORD"
            rm -f "$PORT_RECORD"
            ;;
        *)
            echo "Invalid firewall action"
            return 1
            ;;
    esac

    sudo firewall-cmd --reload
}

# 密码验证增强
validate_password() {
    local pass=$1
    [[ ${#pass} -ge 8 ]] || {
        echo -e "${RED}密码必须至少8个字符${NC}" >&2
        return 1
    }
    return 0
}

# 配置生成器
generate_jupyter_config() {
    local port=$1
    local password=$2

    # 添加参数验证
    [[ -n "$port" && "$port" =~ ^[0-9]+$ ]] || {
        echo -e "${RED}错误：端口号无效${NC}" >&2
        return 1
    }
    [[ -n "$password" ]] || {
        echo -e "${RED}错误：密码不能为空${NC}" >&2
        return 1
    }

    python3 - <<EOF
from jupyter_server.auth import passwd
import json

try:
    # 生成密码哈希
    hashed_pass = passwd('$password', algorithm='sha256')
    
    # 构建配置字典
    config = {
        "ServerApp": {
            "password": hashed_pass,
            "ip": "0.0.0.0",
            "port": $port,  # 确保端口是整数
            "root_dir": "$HOME/jupyter_workspace",
            "allow_root": True
        },
        "KernelSpecManager": {
            "whitelist": ["python3"]
        }
    }

    # 写入配置文件
    with open("$CONFIG_JSON", "w") as f:
        json.dump(config, f, indent=4)
        
except Exception as e:
    print(f"配置生成错误: {str(e)}")
    exit(1)
EOF
}

# 服务安装流程
install_service() {
    echo -e "${GREEN}>>> 开始安装 Jupyter Lab${NC}"

    # 用户输入
    local port=$(get_valid_input "监听端口" $DEFAULT_PORT 'validate_port')
    local pass=$(get_valid_input "访问密码" $DEFAULT_PASS 'validate_password' true)

    # 系统准备
    echo -e "${BLUE}更新系统包...${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3.12 python3.12-venv firewalld

    # 虚拟环境
    echo -e "${BLUE}配置Python环境...${NC}"
    python3.12 -m venv "$VENV_PATH"
    source "$VENV_PATH/bin/activate"
    pip install --upgrade pip wheel
    pip install jupyterlab jupyter-server

    # 配置文件
    echo -e "${BLUE}生成安全配置...${NC}"
    mkdir -p "$CONFIG_DIR"
    generate_jupyter_config "$port" "$pass"
    echo "$pass" > "$PASS_FILE"
    chmod 400 "$PASS_FILE"

    # 防火墙规则
    init_port_record
    firewall_manager add "$port"

    # 系统服务
    echo -e "${BLUE}创建系统服务...${NC}"
    sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Jupyter Lab Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME
Environment="PATH=$VENV_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=$VENV_PATH/bin/jupyter lab --config=$CONFIG_JSON
Restart=always
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable --now jupyter-lab.service

    echo -e "${GREEN}✔ 安装成功！访问端口：${port}${NC}"
}

# 完全卸载流程
uninstall_service() {
    echo -e "${YELLOW}>>> 开始卸载 Jupyter Lab${NC}"

    # 二次确认
    read -p "确定要完全卸载吗？[y/N] " -n 1 confirm
    [[ $confirm =~ [yY] ]] || return

    # 停止服务
    echo -e "${BLUE}停止服务...${NC}"
    sudo systemctl stop jupyter-lab.service 2>/dev/null || true
    sudo systemctl disable jupyter-lab.service 2>/dev/null || true

    # 清理防火墙
    firewall_manager cleanup

    # 删除文件
    echo -e "${BLUE}删除配置文件...${NC}"
    sudo rm -f "$SERVICE_FILE"
    rm -rf "$VENV_PATH" "$CONFIG_DIR"

    echo -e "${GREEN}✔ 卸载完成，所有相关配置已清除${NC}"
}

# 配置修改（关键改进）
modify_config() {
    echo -e "${GREEN}>>> 修改服务配置${NC}"

    # 获取当前配置
    local current_port=$(jq -r '.ServerApp.port' "$CONFIG_JSON")
    local current_pass=$(cat "$PASS_FILE")

    # 用户输入
    local new_port=$(get_valid_input "新端口" "$current_port" 'validate_port')
    local new_pass=$(get_valid_input "新密码" "$current_pass" 'validate_password' true)

    # 更新防火墙
    if [[ "$new_port" != "$current_port" ]]; then
        firewall_manager remove "$current_port"
        firewall_manager add "$new_port"
    fi

    # 生成新配置
    generate_jupyter_config "$new_port" "$new_pass"
    echo "$new_pass" > "$PASS_FILE"

    # 重启服务
    sudo systemctl restart jupyter-lab.service
    echo -e "${GREEN}✔ 配置更新成功！新端口：${new_port}${NC}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}Jupyter Lab 管理菜单${NC}"
    echo "--------------------------------"
    echo "1. 安全安装"
    echo "2. 完全卸载"
    echo "3. 修改配置"
    echo "4. 服务状态"
    echo "5. 访问信息"
    echo "0. 退出"
    echo "--------------------------------"
}

# 入口函数
main() {
    while true; do
        show_menu
        read -p "请选择操作: " choice
        case $choice in
            1) install_service ;;
            2) uninstall_service ;;
            3) modify_config ;;
            4) systemctl status jupyter-lab.service ;;
            5) show_access_info ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 执行入口
main "$@"
