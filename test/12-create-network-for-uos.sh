#!/bin/bash


SYSTEMD_NET_DIR=/usr/lib/systemd/network

mkdir -p ${SYSTEMD_NET_DIR}

umask 033

cat <<EOF>${SYSTEMD_NET_DIR}/50-acrn.netdev
[NetDev]
Name=acrn-br0
Kind=bridge
EOF

cat <<EOF>${SYSTEMD_NET_DIR}/50-acrn.network
[Match]
Name=e* acrn_tap*

[Network]
Bridge=acrn-br0
EOF


cat <<EOF>${SYSTEMD_NET_DIR}/50-acrn_tap0.netdev
[NetDev]
Name=acrn_tap0
Kind=tap
EOF

cat <<EOF>${SYSTEMD_NET_DIR}/50-eth.network
[Match]
Name=acrn-br0

[Network]
DHCP=ipv4
EOF


systemctl daemon-reload
systemctl restart systemd-networkd

