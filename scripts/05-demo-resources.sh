#!/usr/bin/env bash
# Step 5: create the basic cloud resources used in the demo (run inside the VM)
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
set -x                                   # (enabled after sourcing so passwords are not logged)

# --- Keystone: project / user / role ---
openstack project show demo-project >/dev/null 2>&1 || openstack project create --description "CS223 demo" demo-project
openstack user show demo-user >/dev/null 2>&1 || openstack user create --project demo-project --password 'Demo@12345' demo-user
openstack role add --project demo-project --user demo-user member
openstack role add --project demo-project --user admin admin

# --- Glance: CirrOS for ARM64 (aarch64) ---
cd ~
[ -f cirros-0.6.3-aarch64-disk.img ] || wget -q https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-aarch64-disk.img
openstack image show cirros-aarch64 >/dev/null 2>&1 || openstack image create cirros-aarch64 \
  --file cirros-0.6.3-aarch64-disk.img --disk-format qcow2 --container-format bare --public \
  --property hw_firmware_type=uefi --property os_distro=cirros --property hw_architecture=aarch64

# --- Nova: flavors ---
openstack flavor show m1.tiny  >/dev/null 2>&1 || openstack flavor create --vcpus 1 --ram 256 --disk 1 m1.tiny
openstack flavor show m1.small >/dev/null 2>&1 || openstack flavor create --vcpus 1 --ram 512 --disk 2 m1.small

# --- Neutron: external (provider) network on physnet1 = veth-ovs -> br-ex ---
openstack network show public-net >/dev/null 2>&1 || openstack network create --external --share \
  --provider-network-type flat --provider-physical-network physnet1 public-net
openstack subnet show public-subnet >/dev/null 2>&1 || openstack subnet create public-subnet --network public-net \
  --no-dhcp --subnet-range 172.24.4.0/24 --gateway 172.24.4.1 \
  --allocation-pool start=172.24.4.100,end=172.24.4.200

# ===== From here on act as the normal user demo-user (project demo-project) =====
cat > ~/demo-openrc.sh <<RC
export OS_AUTH_URL=$OS_AUTH_URL
export OS_PROJECT_NAME=demo-project
export OS_USERNAME=demo-user
export OS_PASSWORD='Demo@12345'
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_IDENTITY_API_VERSION=3
export OS_INTERFACE=internal
RC
unset OS_PROJECT_ID OS_TENANT_NAME OS_TENANT_ID OS_SYSTEM_SCOPE || true
set +x; source ~/demo-openrc.sh; set -x

# --- Neutron: tenant network + router ---
openstack network show private-net >/dev/null 2>&1 || openstack network create private-net
openstack subnet show private-subnet >/dev/null 2>&1 || openstack subnet create private-subnet \
  --network private-net --subnet-range 10.10.10.0/24 --dns-nameserver 8.8.8.8
openstack router show r1 >/dev/null 2>&1 || {
  openstack router create r1
  openstack router set r1 --external-gateway public-net
  openstack router add subnet r1 private-subnet; }

# --- Security group: allow ping + SSH ---
openstack security group show demo-sg >/dev/null 2>&1 || {
  openstack security group create demo-sg --description "allow ICMP and SSH"
  openstack security group rule create --proto icmp demo-sg
  openstack security group rule create --proto tcp --dst-port 22 demo-sg; }

# --- Keypair ---
openstack keypair show demo-key >/dev/null 2>&1 || { openstack keypair create demo-key > ~/demo-key.pem; chmod 600 ~/demo-key.pem; }

# --- Instance + floating IP ---
openstack server show demo-vm1 >/dev/null 2>&1 || openstack server create demo-vm1 --image cirros-aarch64 \
  --flavor m1.small --network private-net --security-group demo-sg --key-name demo-key --wait
FIP=$(openstack floating ip list -f value -c "Floating IP Address" -c "Fixed IP Address" | awk '$2!="None"{print $1}' | head -1)
if [ -z "$FIP" ]; then
  FIP=$(openstack floating ip create public-net -f value -c floating_ip_address)
  openstack server add floating ip demo-vm1 "$FIP"
fi

# --- Cinder: 1 GB volume attached to the instance ---
openstack volume show vol1 >/dev/null 2>&1 || { openstack volume create --size 1 vol1; sleep 8; }
openstack server volume list demo-vm1 -f value | grep -q . || openstack server add volume demo-vm1 vol1

openstack server list
echo "Floating IP: $FIP   (test: ping -c3 $FIP ; ssh -i ~/demo-key.pem cirros@$FIP)"
