#!/bin/bash

read -p "MYSQL Root Password: " -s MYSQL_ROOT_PASSWORD

install_dir="/var/www/html/interview.fireapps.io"
domain="interview.fireapps.io"
sudo mkdir -p $install_dir

if [ -z $MYSQL_ROOT_PASSWORD ]
then
exit 1
fi

sudo apt-get install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo add-apt-repository ppa:certbot/certbot -y
sudo apt update -y 
sudo apt install nginx -y 
sudo systemctl enable --now nginx.service
sudo apt-get install mariadb-server mariadb-client -y 
sudo systemctl enable --now mysql.service
sudo apt-get install python-certbot-nginx -y
sudo apt install php7.2-fpm php7.2-common php7.2-mysql php7.2-gmp php7.2-curl php7.2-intl php7.2-mbstring php7.2-xmlrpc php7.2-gd php7.2-xml php7.2-cli php7.2-zip -y
sudo apt install wget -y
sudo apt install unzip -y


mysql -u root <<-EOF
UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN \('localhost', '127.0.0.1', '::1'\);
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF


wget https://wordpress.org/latest.zip
unzip latest.zip
sudo cp -a wordpress/* $install_dir
sudo cp $install_dir/wp-config-sample.php $install_dir/wp-config.php
sudo chown -R www-data:www-data $install_dir/
sudo chmod -R 755 $install_dir/

sudo sed -i "s/database_name_here/wordpress/" $install_dir/wp-config.php
sudo sed -i "s/username_here/wordpressuser/" $install_dir/wp-config.php
sudo sed -i "s/password_here/password/" $install_dir/wp-config.php

sudo cat > /tmp/$domain << EOF
server {
    listen 80;
    listen [::]:80;

    server_name  $domain www.$domain;
    root   /var/www/html/$domain;
    index  index.php;
    
    include snippets/well-known;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    client_max_body_size 100M;
  
    autoindex off;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ .php$ {
         include snippets/fastcgi-php.conf;
         fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;
         fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
         include fastcgi_params;
    }
}
EOF

sudo ufw allow 'Nginx Full'

sudo cp /tmp/$domain /etc/nginx/sites-available/$domain 
sudo touch /var/log/nginx/$domain.access.log
sudo touch /var/log/nginx/$domain.error.log
sudo chown -R www-data:www-data /var/log/nginx/$domain.*

sudo mkdir -p /var/lib/letsencrypt/.well-known
sudo chgrp www-data /var/lib/letsencrypt
sudo chmod g+s /var/lib/letsencrypt

sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
sudo systemctl restart nginx.service

#cat > /tmp/certbotnginx << EOF
#  location ^~ /.well-known/acme-challenge/ {
#  allow all;
#  root /var/lib/letsencrypt/;
#  default_type "text/plain";
#  try_files $uri =404;
#}
#EOF
#
#
#sudo cp /tmp/certbotnginx /etc/nginx/snippets/well-known


cat > /tmp/https$domain << EOF

server {
    listen 80;
    server_name www.$domain $domain;
    include snippets/well-known;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name $domain www.$domain;
    root /var/www/html/$domain;
    index index.html;

    if (\$host != "$domain") {
           return 301 https://$domain\$request_uri;
       }
    
    include snippets/well-known;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;
    ssl_dhparam /etc/ssl/certs/dhparam.pem;
    
    sl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
    ssl_prefer_server_ciphers on;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 30s;
    
    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    client_max_body_size 100M;
  
    autoindex off;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ .php$ {
         include snippets/fastcgi-php.conf;
         fastcgi_pass unix:/var/run/php/php7.2-fpm.sock;
         fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
         include fastcgi_params;
    }
}
EOF

crontab -e << 'EOF'
0 1 * * * /usr/bin/certbot renew & > /dev/null
EOF
