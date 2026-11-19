#!/usr/bin/env bash
# Step 2: install Kolla Ansible (OpenStack 2026.1), prepare Cinder LVM, write globals.yml
set -euxo pipefail
RELEASE=2026.1
MGMT_IP=$(ip -4 -br addr show lima0 | awk '{print $3}' | cut -d/ -f1)

# --- Kolla Ansible in a Python venv (official quickstart) ---
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate
pip install -U pip
pip install "git+https://opendev.org/openstack/kolla-ansible@stable/${RELEASE}"
sudo mkdir -p /etc/kolla && sudo chown "$USER:$USER" /etc/kolla
cp -n -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp -n ~/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one ~/all-in-one
kolla-ansible install-deps
kolla-genpwd

cat > ~/ansible.cfg <<'A'
[defaults]
host_key_checking=False
pipelining=True
forks=10
A

# --- Cinder LVM backend on a 40 GB sparse loopback file ---
if ! sudo vgs cinder-volumes >/dev/null 2>&1; then
  sudo truncate -s 40G /var/lib/cinder-volumes.img
  LOOP=$(sudo losetup -f --show /var/lib/cinder-volumes.img)
  sudo pvcreate "$LOOP" && sudo vgcreate cinder-volumes "$LOOP"
fi
sudo tee /etc/systemd/system/cinder-loop.service >/dev/null <<'U'
[Unit]
Description=Attach loopback disk for Cinder LVM (cinder-volumes)
DefaultDependencies=no
After=local-fs.target
Before=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'losetup -j /var/lib/cinder-volumes.img | grep -q loop || losetup -f /var/lib/cinder-volumes.img; vgscan --mknodes; vgchange -ay cinder-volumes'
[Install]
WantedBy=multi-user.target
U
sudo systemctl daemon-reload && sudo systemctl enable cinder-loop.service

# --- globals.yml (only the lines we change; everything else = Kolla defaults) ---
cat >> /etc/kolla/globals.yml <<G

######## CS223 project settings ########
kolla_base_distro: "ubuntu"
openstack_release: "${RELEASE}"
openstack_tag_suffix: "-aarch64"          # ARM64 images on quay.io
network_interface: "lima0"                # management/API network
neutron_external_interface: "veth-ovs"    # external (provider) network for floating IPs
kolla_internal_vip_address: "${MGMT_IP}"  # single node: VIP = host IP
enable_haproxy: "no"                      # no load balancer/keepalived needed for 1 node
enable_proxysql: "no"                     # else ProxySQL grabs port 3306 on the host IP (problem #6)
nova_compute_virt_type: "kvm"             # /dev/kvm exists (nested virtualization on M5)
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
enable_cinder_backup: "no"                # no backup backend configured
enable_heat: "no"
G
grep -v '^#' /etc/kolla/globals.yml | grep -v '^$'
