#!/bin/bash

if [[ -z "${QEMU_TAP}" ]]; then
  echo "TAP interface for qemu not defined, will do nothing"
  sleep infinity
else
  until ifconfig ${QEMU_TAP} 2>/dev/null;
  do
    echo "Waiting for ${QEMU_TAP} interface to appear"
    sleep 5
  done
  qemu-system-x86_64 \
    -kernel /cirros-0.5.2-x86_64-vmlinuz \
    -append "root=/dev/hda console=ttyS0 dslist=nocloud instance-id=${APP_NAME:-app}" \
    -initrd /cirros-0.5.2-x86_64-initrd \
    -hda /cirros-0.5.2-x86_64-blank.img \
    -enable-kvm -nographic \
    -serial chardev:char0 -chardev socket,id=char0,port=7777,host=localhost,server,nodelay,nowait,telnet,logfile=/var/log/app-qemu.log \
    -netdev tap,id=eth0,ifname=${QEMU_TAP},script=no,downscript=no -device virtio-net-pci,netdev=eth0
fi