#!/usr/bin/env bash
# Step 6 (Bonus): OpenStack Swift object storage, installed from Ubuntu packages
# (Kolla Ansible removed its Swift role after 2024.1 and publishes no ARM64 Swift images),
# then integrated with the Kolla-deployed Keystone so Horizon shows "Object Store".
set -euo pipefail
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
set -x                                   # (enabled after sourcing so passwords are not logged)
IP=$(ip -4 -br addr show lima0 | awk '{print $3}' | cut -d/ -f1)
PORT=8080
SWIFT_PASS=$(openssl rand -hex 12)
sudo ss -ltnp | grep ":$PORT " | grep -vq swift-proxy && { echo "port $PORT used by another service"; exit 1; } || true

# 1) Packages
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y swift swift-proxy swift-account swift-container \
     swift-object python3-swiftclient python3-keystonemiddleware xfsprogs

# 2) Storage device: 10 GB sparse file, XFS, mounted at /srv/node/d1
sudo mkdir -p /srv/node/d1 /var/cache/swift /etc/swift
[ -f /srv/swift-disk.img ] || { sudo truncate -s 10G /srv/swift-disk.img; sudo mkfs.xfs -q /srv/swift-disk.img; }
grep -q swift-disk /etc/fstab || echo '/srv/swift-disk.img /srv/node/d1 xfs loop,noatime 0 0' | sudo tee -a /etc/fstab
mountpoint -q /srv/node/d1 || sudo mount /srv/node/d1
sudo chown -R swift:swift /srv/node /var/cache/swift

# 3) Cluster-wide config
sudo test -f /etc/swift/swift.conf || sudo tee /etc/swift/swift.conf >/dev/null <<C
[swift-hash]
swift_hash_path_suffix = $(openssl rand -hex 8)
swift_hash_path_prefix = $(openssl rand -hex 8)
[storage-policy:0]
name = Policy-0
default = yes
C

# 4) Account / container / object servers (listen on localhost only)
for s in account:6202 container:6201 object:6200; do
  n=${s%%:*}; p=${s##*:}
  sudo tee /etc/swift/$n-server.conf >/dev/null <<C
[DEFAULT]
bind_ip = 127.0.0.1
bind_port = $p
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = true
[pipeline:main]
pipeline = healthcheck recon $n-server
[app:$n-server]
use = egg:swift#$n
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
[${n}-replicator]
[${n}-auditor]
C
done
sudo tee -a /etc/swift/container-server.conf >/dev/null <<C
[container-updater]
[container-sync]
C
sudo tee -a /etc/swift/object-server.conf >/dev/null <<C
[object-updater]
C

# 5) Rings (1 replica, single device)
for r in account:6202 container:6201 object:6200; do
  n=${r%%:*}; p=${r##*:}
  sudo test -f /etc/swift/$n.ring.gz && continue
  sudo swift-ring-builder /etc/swift/$n.builder create 10 1 1
  sudo swift-ring-builder /etc/swift/$n.builder add --region 1 --zone 1 --ip 127.0.0.1 --port $p --device d1 --weight 100
  sudo swift-ring-builder /etc/swift/$n.builder rebalance
done
sudo chown -R swift:swift /etc/swift

# 6) Keystone: user, service, endpoints
openstack user show swift >/dev/null 2>&1 || openstack user create --domain default --password "$SWIFT_PASS" swift
openstack user set --password "$SWIFT_PASS" swift
openstack role add --project service --user swift admin
openstack service show object-store >/dev/null 2>&1 || openstack service create --name swift --description "OpenStack Object Storage" object-store
for i in public internal admin; do
  openstack endpoint list --service object-store --interface $i -f value | grep -q . || \
    openstack endpoint create --region RegionOne object-store $i "http://$IP:$PORT/v1/AUTH_%(project_id)s"
done

# 7) Proxy server with Keystone auth
sudo tee /etc/swift/proxy-server.conf >/dev/null <<C
[DEFAULT]
bind_ip = $IP
bind_port = $PORT
user = swift
swift_dir = /etc/swift
[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache listing_formats bulk ratelimit authtoken keystoneauth copy slo dlo versioned_writes symlink proxy-logging proxy-server
[app:proxy-server]
use = egg:swift#proxy
account_autocreate = true
[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
www_authenticate_uri = http://$IP:5000
auth_url = http://$IP:5000
memcached_servers = $IP:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = $SWIFT_PASS
delay_auth_decision = True
service_token_roles_required = True
[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin,member
reseller_admin_role = ResellerAdmin
[filter:catch_errors]
use = egg:swift#catch_errors
[filter:gatekeeper]
use = egg:swift#gatekeeper
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:proxy-logging]
use = egg:swift#proxy_logging
[filter:cache]
use = egg:swift#memcache
memcache_servers = $IP:11211
[filter:listing_formats]
use = egg:swift#listing_formats
[filter:bulk]
use = egg:swift#bulk
[filter:ratelimit]
use = egg:swift#ratelimit
[filter:copy]
use = egg:swift#copy
[filter:slo]
use = egg:swift#slo
[filter:dlo]
use = egg:swift#dlo
[filter:versioned_writes]
use = egg:swift#versioned_writes
allow_versioned_writes = true
[filter:symlink]
use = egg:swift#symlink
C
sudo chown swift:swift /etc/swift/proxy-server.conf && sudo chmod 640 /etc/swift/proxy-server.conf

# 8) Start services
sudo swift-init all stop 2>/dev/null || true          # stop any copies not managed by systemd
sudo systemctl daemon-reload
sudo systemctl enable swift-account swift-container swift-object swift-proxy
sudo systemctl restart swift-account swift-container swift-object swift-proxy
sleep 3
curl -s http://$IP:$PORT/healthcheck; echo

# 9) Test with the admin user
openstack object store account show
openstack container show demo-container >/dev/null 2>&1 || openstack container create demo-container
echo "Hello from Swift on OpenStack (CS223)" > /tmp/hello.txt
openstack object create demo-container /tmp/hello.txt --name hello.txt
openstack object list demo-container
