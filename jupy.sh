#!/bin/bash
# Python 常用库一键安装脚本
# 版本：v1.2
# 最后更新：2024-05-23

set -eo pipefail

# 定义颜色代码
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# 库列表（按功能分类）
BASE_PACKAGES=(
    # 核心数据处理
    pandas
    numpy
    scipy
    
    # 金融数据
    akshare
    mplfinance
    ta-lib
    pandas-datareader
    
    # 可视化
    matplotlib
    seaborn
    plotly
    bokeh
    
    # 网络请求
    requests
    httpx
    websockets
    aiohttp
    
    # 异步编程
    asyncio
    uvloop
    
    # Jupyter
    jupyterlab
    jupyterlab-language-pack-zh-CN  # 中文语言包
    ipython
    pyzmq
    
    # 数据库
    sqlalchemy
    psycopg2-binary
    pymysql
    
    # 机器学习
    scikit-learn
    xgboost
    lightgbm
    catboost
    tensorflow
    pytorch
    torchvision
    
    # 文档处理
    openpyxl
    xlrd
    python-docx
    pdfplumber
    
    # 其他实用工具
    tqdm
    loguru
    python-dotenv
    beautifulsoup4
    pillow
    pytest
    flake8
    autopep8
)

# 安装函数
install_packages() {
    echo -e "${GREEN}开始安装 Python 常用库...${NC}"
    
    for package in "${BASE_PACKAGES[@]}"; do
        echo -e "${YELLOW}正在安装: ${package}${NC}"
        if python -m pip install -U "${package}"; then
            echo -e "${GREEN}✓ 成功安装: ${package}${NC}"
        else
            echo -e "${RED}✗ 安装失败: ${package}${NC}" >&2
        fi
    done
    
    echo -e "${GREEN}\n所有库安装完成！${NC}"
}

# 生成 requirements.txt
generate_requirements() {
    echo -e "${GREEN}生成 requirements.txt...${NC}"
    printf "%s\n" "${BASE_PACKAGES[@]}" > requirements.txt
    echo -e "${GREEN}已生成 requirements.txt 文件${NC}"
}

# 显示菜单
show_menu() {
    echo -e "${GREEN}请选择操作："
    echo "1) 立即安装所有库"
    echo "2) 生成 requirements.txt"
    echo "3) 从 requirements.txt 安装"
    echo "0) 退出"
    echo -n "请输入选项数字: ${NC}"
}

main() {
    case $1 in
        "1") install_packages ;;
        "2") generate_requirements ;;
        "3") python -m pip install -r requirements.txt ;;
        *) 
            while true; do
                show_menu
                read choice
                case $choice in
                    1) install_packages; break ;;
                    2) generate_requirements; break ;;
                    3) python -m pip install -r requirements.txt; break ;;
                    0) exit 0 ;;
                    *) echo -e "${RED}无效选项，请重新输入${NC}" ;;
                esac
            done
            ;;
    esac
}

# 执行主程序
main "$@"
