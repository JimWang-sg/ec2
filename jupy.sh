#!/bin/bash

# 更新系统
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3-pip


# 安装Jupyter
pip install jupyter

# 将Jupyter可执行文件路径添加到PATH
export PATH=$PATH:~/.local/bin

# 生成Jupyter配置文件
jupyter notebook --generate-config

# 添加允许任意IP访问的配置
echo "c.NotebookApp.ip = '*'" >> ~/.jupyter/jupyter_notebook_config.py

# 创建Jupyter服务文件
sudo tee /etc/systemd/system/jupyter.service > /dev/null <<EOL
[Unit]
Description=Jupyter Notebook

[Service]
Type=simple
ExecStart=/home/ubuntu/.local/bin/jupyter notebook
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOL

# 重载systemd并启动Jupyter服务
sudo systemctl daemon-reload
sudo systemctl enable jupyter.service
sudo systemctl start jupyter.service
sudo systemctl status jupyter.service

echo "Jupyter Notebook安装完成，并已配置为开机自动启动。"
