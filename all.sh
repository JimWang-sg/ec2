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

# 安装 Nginx
sudo apt install -y nginx

# 提示用户输入自定义域名
read -p "请输入您的自定义域名（例如，example.com）: " custom_domain

# 配置 Nginx 将自定义域名解析到 Jupyter Notebook 运行的端口
sudo bash -c 'cat > /etc/nginx/sites-available/jupyter' <<EOF
server {
    listen 80;
    server_name $custom_domain;

    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOF

# 创建符号链接
sudo ln -s /etc/nginx/sites-available/jupyter /etc/nginx/sites-enabled

# 重启 Nginx 以应用更改
sudo systemctl restart nginx


#安装v2ray
echo "安装v2ray"
sudo -i <<EOF
echo 1 | bash <(curl -s -L https://raw.githubusercontent.com/JimWang-sg/v2ray/master/install.sh)
EOF

#安装模块
pip install pandas akshare matplotlib requests mplfinance websockets jupyterlab-language-pack-zh-CN python-okx jupyter_ai openai

echo "脚本执行完毕。查询v2ray请输入：sudo v2ray url"

