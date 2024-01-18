#!/bin/bash
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
