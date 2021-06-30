#!/usr/bin/env bash

# Run http server.
# Usage: http.sh <server-name> <port> [ip]

srv_name=${1}
port=${2}
ip=${3:-}

mkdir -p /www
echo "${srv_name}-data=" > /www/rand.data
dd bs=1024 count=10240 < /dev/urandom > /www/urand.data
base64 /www/urand.data >> /www/rand.data
echo -ne "HTTP/1.0 200 OK\r\nContent-Length: $(wc -c </www/rand.data)\r\n\r\n" > /www/index.html
cat /www/rand.data >> /www/index.html
while true; do nc -l ${ip} ${port} < /www/index.html; done