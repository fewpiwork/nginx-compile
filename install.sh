#!/bin/bash

# 安装依赖
if [ -e "/usr/bin/yum" ]; then
  yum update -y
  yum install git gawk vim curl wget ntpdate psmisc python-dev python-pip  libxml2 libxml2-devel libxslt-devel gd-devel gperftools libuuid-devel libblkid-devel libudev-devel fuse-devel libedit-devel libatomic_ops-devel gcc-c++ openssl openssl-devel -y
fi
if [ -e "/usr/bin/apt-get" ]; then
  apt-get update -y
  apt-get install git gawk vim curl wget ntpdate psmisc python-dev python-pip libxslt1-dev libxml2-dev libgd-dev google-perftools uuid-dev libblkid-dev libudev-dev libfuse-dev libedit-dev libatomic-ops-dev build-essential libssl-dev openssl -y
fi

# 时间
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo asia/shanghai > /etc/timezone && ntpdate 0.cn.pool.ntp.org && iptables -P INPUT ACCEPT && iptables -P OUTPUT ACCEPT

pip install logger requests
# 准备
rm -rf /usr/src/
mkdir -p /usr/src/
mkdir -p /var/log/nginx/
useradd -s /sbin/nologin -M www-data
iptables -P INPUT ACCEPT   
iptables -P OUTPUT ACCEPT  

# 下载 nginx
cd /usr/src/
nginx_v='1.16.1'
wget https://nginx.org/download/nginx-${nginx_v}.tar.gz
tar zxvf ./nginx-${nginx_v}.tar.gz 
mv nginx-${nginx_v} nginx


# 关闭 nginx 的 debug 模式
sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' /usr/src/nginx/auto/cc/gcc

# 编译安装 nginx
cd /usr/src/nginx
./configure \
--user=www-data --group=www-data \
--prefix=/usr/local/nginx \
--sbin-path=/usr/sbin/nginx \
--with-stream \
--with-compat --with-file-aio --with-threads \
--with-select_module \
--with-poll_module \
--with-threads
--conf-path=/usr/local/nginx/conf/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--pid-path=/var/run/nginx.pid

make -j2 && make install


cat > "/root/ssr_upstream.conf" << UUU
    upstream server_upstreams {
        server 8.8.8.8:443;
    }
    server {
        listen 8080;
        listen 8080 udp;
        proxy_pass server_upstreams;
    }
UUU

# 创建 nginx 全局配置
cat > "/usr/local/nginx/conf/nginx.conf" << OOO
user root root;
pid /var/run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 65535;

events {
  use epoll;
  multi_accept on;
  worker_connections 65535;
}
stream {
    include /root/ssr_upstream.conf;
}
http {
  charset utf-8;
  sendfile on;
  aio threads;
  directio 512k;
  tcp_nopush on;
  tcp_nodelay on;
  server_tokens off;
  log_not_found off;
  types_hash_max_size 2048;
  client_max_body_size 16M;

  # MIME
  include mime.types;
  default_type application/octet-stream;

  # Logging
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log warn;
  server {
        listen       59120 default_server; 
        root         /root/web; 
        location / {
        }
        error_page 404 /404.html;
            location = /40x.html {
        }  

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }
}
OOO

# 创建 nginx 服务进程
mkdir -p /usr/lib/systemd/system/ 
cat > /usr/lib/systemd/system/nginx.service <<EOF
[Unit]
Description=nginx - high performance web server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPost=/bin/sleep 0.1
ExecStartPre=/usr/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
ExecStart=/usr/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/usr/sbin/nginx -s stop

[Install]
WantedBy=multi-user.target
EOF

# 创建 nginx 日志规则 (自动分割)
cat > /etc/logrotate.d/nginx << EOF
/var/log/nginx/*.log {
  daily
  missingok
  rotate 52
  delaycompress
  notifempty
  create 640 www-data www-data
  sharedscripts
  postrotate
  if [ -f /var/run/nginx.pid ]; then
    kill -USR1 \`cat /var/run/nginx.pid\`
  fi
  endscript
}
EOF
ldconfig

# # 配置站点目录权限
mkdir -p /root/web/d87c
cp -r /usr/local/nginx/html/*.* /root/web/d87c
# chown -R www-data:www-data /root/web/
# find /root/web/ -type d -exec chmod 755 {} \;
# find /root/web/ -type f -exec chmod 644 {} \;

# 开启 nginx 服务进程
systemctl unmask nginx.service
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

