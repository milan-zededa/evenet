#!/usr/bin/env bash

# Run http server.
# Usage: http.sh <server-name> <port> [ip] [interface]

srv_name=${1}
port=${2}
ip=${3:-}
interface=${4:-}

mkdir -p /www
echo "${srv_name}-data=" > /www/rand-${srv_name}.data
dd bs=1024 count=10240 < /dev/urandom > /www/urand-${srv_name}.data
base64 /www/urand-${srv_name}.data >> /www/rand-${srv_name}.data
echo -ne "HTTP/1.0 200 OK\r\nContent-Length: $(wc -c </www/rand-${srv_name}.data)\r\n\r\n" > /www/index-${srv_name}.html
cat /www/rand-${srv_name}.data >> /www/index-${srv_name}.html

while true
do
  if [ -n "${interface}" ]; then
    /usr/bin/setnif.sh ${interface} nc -l ${ip} ${port} < /www/index-${srv_name}.html
  else
    nc -l ${ip} ${port} < /www/index-${srv_name}.html
  fi
done