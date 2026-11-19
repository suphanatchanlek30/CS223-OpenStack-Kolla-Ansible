#!/usr/bin/env bash
# Step 1: prepare the Ubuntu 24.04 ARM64 VM to be a Kolla-Ansible All-in-One host.
set -euxo pipefail

MGMT_IF=lima0                       # NIC reachable from the Mac (API/Horizon)
MGMT_IP=$(ip -4 -br addr show "$MGMT_IF" | awk '{print $3}' | cut -d/ -f1)

# 1) OS packages needed by Kolla Ansible (per Kolla Ansible quickstart)
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git python3-dev libffi-dev gcc libssl-dev \
     libdbus-glib-1-dev python3-venv lvm2 thin-provisioning-tools iptables

# 2) Hostname must resolve to the management IP
grep -q "$(hostname)" /etc/hosts && sudo sed -i "/[[:space:]]$(hostname)\$/d" /etc/hosts
echo "$MGMT_IP $(hostname)" | sudo tee -a /etc/hosts

# 3) Swap (protects the deploy from OOM on a 10 GB VM)
if [ ! -f /swapfile ]; then
  sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# 4) Virtual "external" NIC for Neutron: a veth pair.
#    veth-ovs  -> given to Neutron (neutron_external_interface, plugged into br-ex)
#    veth-ex   -> host side, acts as the gateway 172.24.4.1 of the floating-IP network
sudo tee /etc/systemd/network/25-veth-ex.netdev >/dev/null <<'N'
[NetDev]
Name=veth-ex
Kind=veth
[Peer]
Name=veth-ovs
N
sudo tee /etc/systemd/network/25-veth-ex.network >/dev/null <<'N'
[Match]
Name=veth-ex
[Network]
Address=172.24.4.1/24
ConfigureWithoutCarrier=yes
N
sudo tee /etc/systemd/network/25-veth-ovs.network >/dev/null <<'N'
[Match]
Name=veth-ovs
[Network]
LinkLocalAddressing=no
ConfigureWithoutCarrier=yes
N
sudo systemctl restart systemd-networkd
sleep 2

# 5) Let instances reach the Internet: NAT floating network out through the VM
sudo tee /usr/local/sbin/openstack-ext-nat.sh >/dev/null <<'N'
#!/bin/sh
sysctl -w net.ipv4.ip_forward=1
# NAT only traffic that really leaves the VM (lima0/eth0). A broader rule also matches
# packets crossing Neutron's qbr bridges (bridge-nf-call-iptables=1) and breaks floating IPs.
iptables -t nat -D POSTROUTING -s 172.24.4.0/24 ! -d 172.24.4.0/24 -j MASQUERADE 2>/dev/null || true
for o in lima0 eth0; do
  iptables -t nat -C POSTROUTING -s 172.24.4.0/24 -o $o -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 172.24.4.0/24 -o $o -j MASQUERADE
done
iptables -C FORWARD -s 172.24.4.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD -s 172.24.4.0/24 -j ACCEPT
iptables -C FORWARD -d 172.24.4.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD -d 172.24.4.0/24 -j ACCEPT
N
sudo chmod +x /usr/local/sbin/openstack-ext-nat.sh
sudo tee /etc/systemd/system/openstack-ext-nat.service >/dev/null <<'N'
[Unit]
Description=NAT for OpenStack floating IP network (172.24.4.0/24)
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/openstack-ext-nat.sh
[Install]
WantedBy=multi-user.target
N
sudo systemctl daemon-reload && sudo systemctl enable --now openstack-ext-nat.service

ip -br a
echo "MGMT_IP=$MGMT_IP"
