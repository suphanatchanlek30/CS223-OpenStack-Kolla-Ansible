# 02 · คำสั่งเช็คสถานะ OpenStack (รันใน VM)

เตรียมก่อนทุกครั้ง:

```bash
limactl shell openstack-aio
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

## 1. Container ของ Kolla (ทุก service รันเป็น Docker container)

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}"     # ทั้งหมด ต้องเป็น Up / healthy
sudo docker ps -q | wc -l                                   # นับจำนวน (~38)
sudo docker ps --format "{{.Names}} {{.Status}}" | grep -v healthy   # ดูตัวที่ไม่มี (healthy)
```

> ตัวที่ไม่มีคำว่า `(healthy)` แต่เป็น `Up` ถือว่าปกติ เพราะบางตัวไม่มี healthcheck เช่น `cron`, `fluentd`, `kolla_toolbox`, `iscsid`, `tgtd`, `neutron_metadata_agent`

## 2. ภาพรวม service (ใช้ demo / แคปใส่เล่ม)

```bash
openstack service list            # keystone, glance, nova, placement, neutron, cinder, swift
openstack endpoint list           # URL ของแต่ละ service (public/internal/admin)
openstack catalog list            # service catalog ที่ Keystone แจกให้ client
```

## 3. แยกตาม service

```bash
# Nova (Compute)
openstack compute service list    # nova-scheduler, nova-conductor, nova-compute = up
openstack hypervisor list         # lima-openstack-aio, State up
openstack hypervisor show lima-openstack-aio

# Neutron (Network)
openstack network agent list      # DHCP, Open vSwitch, Metadata, L3 = :-) UP

# Cinder (Block Storage)
openstack volume service list     # cinder-scheduler, cinder-volume = up

# Keystone (Identity)
openstack token issue             # ได้ token = Keystone ทำงาน

# Glance (Image)
openstack image list

# Swift (Object Storage)
curl http://192.168.64.2:8080/healthcheck        # ต้องได้ OK
systemctl is-active swift-proxy swift-account swift-container swift-object
```

## 4. เช็คว่าใช้ KVM จริง (คำถามยอดนิยมของอาจารย์)

```bash
ls -l /dev/kvm
sudo grep virt_type /etc/kolla/nova-compute/nova.conf      # virt_type = kvm
```

## 5. ทรัพยากรที่ใช้อยู่

```bash
openstack server list --all-projects        # instance ทุก project
openstack quota show demo-project           # โควตาของ project
openstack usage list                        # การใช้ vCPU/RAM/disk ตามช่วงเวลา
free -h; df -h /                            # RAM/ดิสก์ของ VM host
sudo vgs cinder-volumes                     # พื้นที่ LVM ที่ Cinder ใช้
df -h /srv/node/d1                          # พื้นที่ดิสก์ของ Swift
```

## 6. เช็คจาก Mac (ไม่ต้องเข้า VM)

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.64.2/auth/login/    # 200 = Horizon พร้อม
curl http://192.168.64.2:8080/healthcheck                                  # OK = Swift พร้อม
```
