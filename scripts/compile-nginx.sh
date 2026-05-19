#!/bin/bash
# Optional: Compile latest nginx from source (advanced users only)
# For most cases, use the official Docker image instead.

NGINX_VERSION="1.27.4"   # Update as needed

apt update && apt install -y build-essential libpcre3-dev zlib1g-dev libssl-dev

wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz
 tar -xzf nginx-$NGINX_VERSION.tar.gz
cd nginx-$NGINX_VERSION

./configure \
    --prefix=/usr/local/nginx \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module

make -j$(nproc)
make install

echo "Nginx $NGINX_VERSION compiled and installed to /usr/local/nginx"
