#!/bin/bash

# Create domain name helper
#NGINX_DOMAIN="domain.com"
read -p "Domain: " NGINX_DOMAIN

sudo apt update

# install nginx and certbot
sudo apt install -y nginx certbot python3-certbot-dns-cloudflare python3-certbot-nginx

# Request lets encrypt cert for domain and www subdomain
sudo certbot certonly --dry-run --nginx --email admin@$NGINX_DOMAIN -d $NGINX_DOMAIN -d www.$NGINX_DOMAIN && sudo certbot certonly --nginx --email admin@$NGINX_DOMAIN -d $NGINX_DOMAIN -d sub.$NGINX_DOMAIN


# Create certbot deploy renewal hook
echo '#!/bin/bash

/usr/bin/systemctl reload nginx
' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/nginx.sh > /dev/null

sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx.sh

## Alternate: New cert chain and cert type
# sudo apt-get remove -y certbot
# sudo snap install --classic certbot
# sudo ln -s /snap/bin/certbot /usr/bin/certbot
# certbot --version
# certbot 2.5.0
# sudo certbot --force-renewal --preferred-chain  "ISRG Root X1" renew  --key-type ecdsa

# Verify certs
sudo certbot certificates

# Generate domain Diffie-Hellman parameter for DHE ciphersuites
sudo mkdir -p /etc/nginx/ssldhparam/$NGINX_DOMAIN
sudo openssl dhparam -out /etc/nginx/ssldhparam/$NGINX_DOMAIN/dhparam.pem 2048

# Increase www-data user open file limits
echo '
www-data         soft    nofile           8192
www-data         hard    nofile           8192
' | sudo tee /etc/security/limits.d/www-data.conf > /dev/null

sudo su www-data -s /bin/bash -c 'ulimit -Sn'

# Create backup nginx.conf
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.default

# Increase nginx open file and connections limits
sudo sed -i '3iworker_rlimit_nofile 8192;' /etc/nginx/nginx.conf
sudo sed -i 's/worker_connections 768/worker_connections 8192/g' /etc/nginx/nginx.conf

# Create bash cron task to update cloudflare ip helper to fix and replace Cloudflare IP Address by real user IP Address
cd /opt && sudo git clone https://github.com/exploitfate/cfip.git
sudo chmod +x /opt/cfip/update.sh
sudo /opt/cfip/update.sh

echo '# /etc/cron.d/cfip: crontab entries to update Cloudflare IPs for nginx config
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin

0 0 * * * /opt/cfip/update.sh
' | sudo tee /etc/cron.d/cfip > /dev/null

# Increase server names hashes
echo '
server_names_hash_max_size 1024;
server_names_hash_bucket_size 128;
' | sudo tee /etc/nginx/conf.d/names_hash.conf > /dev/null

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

## Set upstream backends
echo '
upstream backend {
    server ip-172-31-40-1.us-east-2.compute.internal;
    server ip-172-31-44-2.us-east-2.compute.internal;
    server ip-172-31-35-3.us-east-2.compute.internal;
    server ip-172-31-38-4.us-east-2.compute.internal;
}

' | sudo tee /etc/nginx/conf.d/api.conf > /dev/null



# Turn off auth_basic for listed locations
echo '
location /.well-known {
        auth_basic off;
        try_files $uri $uri/;
}
' | sudo tee /etc/nginx/noauth.conf > /dev/null

# Create auth_basic password file
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD;
echo printf "${USERNAME}:$(openssl passwd -crypt ${PASSWORD})\n" | sudo tee /etc/nginx/passwords > /dev/null

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

## Create load balancer domain config
echo '
# HTTP
server {
        server_name '$NGINX_DOMAIN' www.'$NGINX_DOMAIN';
        listen 80;

        root          /var/www/html;

        # auth_basic "Protected";
        # auth_basic_user_file passwords;
        # include noauth.conf;

        # access_log    /var/log/nginx/access.log combined buffer=64k;
        access_log    off;
        error_log     /var/log/nginx/error.log notice;

        include protect-system-files.conf;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            # Set real user IP Address to X-Real-IP header
            proxy_set_header X-Real-IP $remote_addr;
        }
}

# HTTP to HTTPS and www to non-www redirect
#server {
#        server_name '$NGINX_DOMAIN' www.'$NGINX_DOMAIN';
#        listen 80;
#        return 301 https://'$NGINX_DOMAIN'$request_uri;
#}

# HTTPS www to non-www redirect 443
#server {
#        server_name www.'$NGINX_DOMAIN';
#        listen 443 ssl http2;
#        ssl_certificate /etc/letsencrypt/live/'$NGINX_DOMAIN'/fullchain.pem;
#        ssl_certificate_key /etc/letsencrypt/live/'$NGINX_DOMAIN'/privkey.pem;
#        ssl_dhparam /etc/nginx/ssldhparam/'$NGINX_DOMAIN'/dhparam.pem;
#        # enable ocsp stapling (mechanism by which a site can convey certificate revocation information to visitors in a privacy-preserving, scalable manner)
#        # http://blog.mozilla.org/security/2013/07/29/ocsp-stapling-in-firefox/
#        resolver 8.8.8.8 8.8.4.4;
#        ssl_stapling on;
#        ssl_stapling_verify on;
#        return 301 https://'$NGINX_DOMAIN'$request_uri;
#}

# HTTPS
server {
        server_name '$NGINX_DOMAIN';
        listen 443 ssl http2;

        ssl_certificate /etc/letsencrypt/live/'$NGINX_DOMAIN'/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/'$NGINX_DOMAIN'/privkey.pem;

        # Diffie-Hellman parameter for DHE ciphersuites, recommended 2048 bits
        ssl_dhparam /etc/nginx/ssldhparam/'$NGINX_DOMAIN'/dhparam.pem;

        # enables server-side protection from BEAST attacks
        # http://blog.ivanristic.com/2013/09/is-beast-still-a-threat.html
        # ssl_prefer_server_ciphers on;
        # disable SSLv3(enabled by default since nginx 0.8.19) since it is less secure then TLS http://en.wikipedia.org/wiki/Secure_Sockets_Layer#SSL_3.0
        # ssl_protocols TLSv1.1 TLSv1.2;
        # ciphers chosen for forward secrecy and compatibility
        # https://www.nginx.com/blog/pci-dss-best-practices-with-nginx-plus/
        # ssl_ciphers ECDHE-ECDSA-CHACHA20-POLY1305:ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:!AES256-GCM-SHA256:!AES256-GCM-SHA128:!aNULL:!MD5;

        # enable ocsp stapling (mechanism by which a site can convey certificate revocation information to visitors in a privacy-preserving, scalable manner)
        # http://blog.mozilla.org/security/2013/07/29/ocsp-stapling-in-firefox/
        resolver 8.8.8.8 8.8.4.4;
        ssl_stapling on;
        ssl_stapling_verify on;
        # config to enable HSTS(HTTP Strict Transport Security) https://developer.mozilla.org/en-US/docs/Security/HTTP_Strict_Transport_Security
        # to avoid ssl stripping https://en.wikipedia.org/wiki/SSL_stripping#SSL_stripping
        # also https://hstspreload.org/
#        add_header Strict-Transport-Security "max-age=31536000";

        root          /var/www/html;

        # auth_basic "Protected";
        # auth_basic_user_file passwords;
        # include noauth.conf;

        # access_log    /var/log/nginx/access.log combined buffer=64k;
        access_log    off;
        error_log     /var/log/nginx/error.log notice;

        include protect-system-files.conf;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            # Set real user IP Address to X-Real-IP header
            proxy_set_header X-Real-IP $remote_addr;
        }
}
' | sudo tee /etc/nginx/sites-available/$NGINX_DOMAIN.conf > /dev/null

# Enable load balancer domain config
cd /etc/nginx/sites-enabled/

sudo ln -s ../sites-available/$NGINX_DOMAIN.conf .

sudo nginx -t
sudo service nginx restart

