#!/bin/bash

# Create domain name helper
#NGINX_DOMAIN="domain.com"
read -p "Domain: " NGINX_DOMAIN

sudo apt update

# install nginx and php
sudo apt install -y nginx memcached php-fpm php-cli php-curl php-xml php-mbstring php-intl php-zip

sudo apt install -y nginx php-fpm php-cli memcached

# Increase www-data user open file limits
echo '
www-data         soft    nofile           2048
www-data         hard    nofile           2048
' | sudo tee /etc/security/limits.d/www-data.conf > /dev/null
sudo su www-data -s /bin/bash -c 'ulimit -Sn'

# Create backup nginx.conf
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.default

# Increase nginx open file and connections limits
sudo sed -i '3iworker_rlimit_nofile 2048;' /etc/nginx/nginx.conf
sudo sed -i 's/worker_connections 768/worker_connections 2048/g' /etc/nginx/nginx.conf


# Tune php-fpm workers children
CPU_COUNT=$(nproc)
MIN_SPARE_SERVERS=$CPU_COUNT
MAX_SPARE_SERVERS=$(($CPU_COUNT*3))
START_SERVERS=$((($MIN_SPARE_SERVERS+$MAX_SPARE_SERVERS)/2))
MAX_CHILDREN=$(($CPU_COUNT*3*2))
for PHP_VERSION in $(ls /etc/php/) ; do   sudo cp /etc/php/$PHP_VERSION/fpm/pool.d/www.conf /etc/php/$PHP_VERSION/fpm/pool.d/www.conf.default ;   sudo sed -i "s/^pm.max_children.*/pm.max_children = $MAX_CHILDREN/g" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf ;   sudo sed -i "s/^pm.start_servers.*/pm.start_servers = $START_SERVERS/g" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf ;   sudo sed -i "s/^pm.min_spare_servers.*/pm.min_spare_servers = $MIN_SPARE_SERVERS/g" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf ;   sudo sed -i "s/^pm.max_spare_servers.*/pm.max_spare_servers = $MAX_SPARE_SERVERS/g" /etc/php/$PHP_VERSION/fpm/pool.d/www.conf ;   sudo php-fpm$PHP_VERSION -t && sudo service php$PHP_VERSION-fpm reload; done;

# php tune
echo '
cgi.fix_pathinfo= 0
expose_php = Off
' | sudo tee /etc/php/7.4/mods-available/nginx.ini && sudo phpenmod nginx
echo '
memory_limit = 512M
post_max_size = 128M
upload_max_filesize = 128M
' | sudo tee /etc/php/7.4/mods-available/php-override.ini && sudo phpenmod php-override


# Set charset
echo '
#Specify a charset
charset utf-8;

client_max_body_size 128M;
#server_tokens off;

merge_slashes off;

fastcgi_buffer_size 64k;
fastcgi_buffers 8 64k;
' | sudo tee /etc/nginx/conf.d/charset.conf > /dev/null


# Tune gzip
echo '
# Gzip Settings
#gzip on;               # enabled by default
#gzip_disable "msie6";  # enabled by default
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_buffers 16 8k;
gzip_types
    application/atom+xml
    application/javascript
    application/x-javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rss+xml
    application/vnd.geo+json
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/opentype
    image/bmp
    image/svg+xml
    image/x-icon
    text/cache-manifest
    text/css
    text/plain
    text/vcard
    text/vnd.rim.location.xloc
    text/vtt
    text/x-component
    text/x-cross-domain-policy;

' | sudo tee /etc/nginx/conf.d/gzip.conf > /dev/null

# Increase server names hashes
echo '
server_names_hash_max_size 1024;
server_names_hash_bucket_size 128;
' | sudo tee /etc/nginx/conf.d/names_hash.conf > /dev/null

# Increase server names hashes
echo '
server_names_hash_max_size 1024;
server_names_hash_bucket_size 128;
' | sudo tee /etc/nginx/conf.d/names_hash.conf > /dev/null


# Increase server names hashes
echo '
# nginx load balancer IP Address
# # Fix and replace load balancer IP Address by real user IP Address from X-Real-IP header

# Load balancer private IP Address
set_real_ip_from 172.31.35.1;

real_ip_header X-Real-IP;
' | sudo tee /etc/nginx/conf.d/lb.conf > /dev/null

# Create auth_basic password file
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD;
echo printf "${USERNAME}:$(openssl passwd -crypt ${PASSWORD})\n" | sudo tee /etc/nginx/passwords > /dev/null


# Turn off auth_basic for listed locations
echo '
location /.well-known {
        auth_basic off;
        try_files $uri $uri/;
}
' | sudo tee /etc/nginx/noauth.conf > /dev/null

# Deny access for files with listed extensions
echo '
# Prevent clients from accessing hidden files (starting with a dot)
# This is particularly important if you store .htpasswd files in the site hierarchy

# Let’s Encrypt validation requests
location ~ /.well-known {
    allow all;
}

# Prevent clients from accessing to backup/config/source files
location ~* (?:\.(?:bak|config|sql|fla|psd|ini|log|sh|inc|swp|dist|md)|~)$ {
    deny all;
}

# Prevent clients from accessing to backup/config/source files
location ~* (?:\.(?:bak|config|sql|fla|psd|ini|log|sh|inc|swp|dist|md)|~)$ {
    deny all;
}
' | sudo tee /etc/nginx/protect-system-files.conf > /dev/null

# Tune webfont cache
echo '
# Cross domain webfont access
location ~* \.(?:ttf|ttc|otf|eot|woff|woff2)$ {
    # Also, set cache rules for webfonts.
    #
    # See http://wiki.nginx.org/HttpCoreModule#location
    # And https://github.com/h5bp/server-configs/issues/85
    # And https://github.com/h5bp/server-configs/issues/86
    expires 1M;
    access_log off;
    add_header Cache-Control "public";
}
' | sudo tee /etc/nginx/cross-domain-fonts.conf > /dev/null

# Tune static content cache
echo '
# Expire rules for static content

# No default expire rule. This config mirrors that of apache as outlined in the
# html5-boilerplate .htaccess file. However, nginx applies rules by location,
# the apache rules are defined by type. A consequence of this difference is that
# if you use no file extension in the url and serve html, with apache you get an
# expire time of 0s, with nginx you would get an expire header of one month in the
# future (if the default expire rule is 1 month). Therefore, do not use a
# default expire rule with nginx unless your site is completely static

# cache.appcache, your document html and data
location ~* \.(?:manifest|appcache|html?|xml|json)$ {
  expires -1;
  #access_log logs/static.log;
}

# Feed
location ~* \.(?:rss|atom)$ {
  expires 1h;
  add_header Cache-Control "public";
}

# Media: images, icons, video, audio, HTC
location ~* \.(?:jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm|htc|webp|mp3)$ {
  expires 1M;
  access_log off;
  add_header Cache-Control "public";
}

# CSS and Javascript
location ~* \.(?:css|js)$ {
  expires 1y;
  access_log off;
  add_header Cache-Control "public";
}
# favicon disable logs
location = /favicon.ico {
  access_log off;
  log_not_found off;
}
' | sudo tee /etc/nginx/expires.conf > /dev/null

# Create php-fpm handler
echo '
set           $bootstrap  index.php;
index         $bootstrap;

location / {
        proxy_set_header Host $host;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Origin $http_origin;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type";
        add_header Access-Control-Allow-Credentials true;
        if ($request_method = OPTIONS) {
                add_header Content-Length 0;
                add_header Content-Type text/plain;
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
                add_header Access-Control-Allow-Origin $http_origin;
                add_header Access-Control-Allow-Headers "Authorization, Content-Type";
                add_header Access-Control-Allow-Credentials true;
                return 200;
        }
        try_files $uri $uri/ /$bootstrap$is_args$args;
}
location ~ \.php$ {
        try_files $uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index               $bootstrap;

        fastcgi_pass unix:/var/run/php/php-fpm.sock;

        fastcgi_connect_timeout     30s;
        fastcgi_read_timeout        30s;
        fastcgi_send_timeout        60s;
        fastcgi_ignore_client_abort on;
        fastcgi_pass_header         "X-Accel-Expires";

        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        fastcgi_param  PATH_INFO        $fastcgi_path_info;
        fastcgi_param  HTTP_REFERER     $http_referer;
        include fastcgi_params;
}
' | sudo tee /etc/nginx/php-fpm-bootstrap.conf

# Create upstream php backend config
echo '
# upstream php backend
server {
        server_name default_server;

        listen 80;

        root          /var/www/html;

        # auth_basic "Protected";
        # auth_basic_user_file passwords;
        # include noauth.conf;

        access_log    /var/log/nginx/access.log combined buffer=1024k;
        error_log     /var/log/nginx/error.log notice;

        include cross-domain-fonts.conf;
        include protect-system-files.conf;
        include expires.conf;

        include php-fpm-bootstrap.conf;

}
' | sudo tee /etc/nginx/sites-available/$NGINX_DOMAIN.conf > /dev/null

# Enable upstream php backend config
cd /etc/nginx/sites-enabled/

sudo ln -s ../sites-available/$NGINX_DOMAIN.conf .

# Remove default nginx config
sudo rm /etc/nginx/sites-enabled/default

sudo nginx -t
sudo service nginx restart
