# บันทึกการติดตั้ง OpenStack All-in-One ด้วย Kolla Ansible บน MacBook Air M5

> โครงงาน CS223: ติดตั้งและ Admin ระบบ OpenStack 1 [Implementation]
> ผู้ทำ: 6709616897 นาย ศุภณัฐ จันทร์เลข
> เริ่มติดตั้ง: 15 พ.ย. 2569
> สถานะล่าสุด (15 พ.ย. 2569 23:10): **✅ ติดตั้งสำเร็จครบ** — OpenStack 2026.1 All-in-One + Cinder + Swift (Bonus) ใช้งานได้, Horizon เข้าจาก Mac ได้, instance ACTIVE ping/SSH ผ่าน floating IP ได้, ทดสอบ reboot VM แล้วระบบกลับมาครบ

เอกสารนี้บันทึกสิ่งที่ทำจริง คำสั่งที่ใช้ ผลลัพธ์ และปัญหาที่พบ เพื่อใช้เป็นวัตถุดิบเขียนเล่มรายงาน (บทที่ 3–7) และใช้ทำซ้ำได้

---

## 1. สถาปัตยกรรมของระบบ

```
ชั้น 0  MacBook Air M5 (macOS 27.2.1, RAM 16 GB, SSD 512 GB)
  │      Hypervisor: Lima 2.3.0 (vmType: vz = Apple Virtualization.framework)
  └─ ชั้น 1  VM "openstack-aio": Ubuntu 24.04.5 LTS ARM64
       │      6 vCPU / 10 GB RAM (+ swap 8 GB) / ดิสก์ 100 GB / nested virtualization
       │      Docker + Kolla Ansible (stable/2026.1)
       └─ OpenStack 2026.1 All-in-One (1 controller = control + network + compute + storage)
            Keystone · Glance · Nova · Placement · Neutron (OVS) · Cinder (LVM) · Horizon
            + Swift (Bonus, ติดตั้งแยกจาก Ubuntu packages)
            └─ ชั้น 2  Instance CirrOS 0.6.3 aarch64 (รันด้วย KVM)
```

### เครือข่าย

| Interface ใน VM | IP | หน้าที่ |
|---|---|---|
| `eth0` | 192.168.5.15 | เครือข่ายภายในของ Lima (ใช้ `limactl shell`) |
| `lima0` | **192.168.64.2** | Management/API network, Mac เข้าถึงได้ → Horizon ที่ `http://192.168.64.2` |
| `veth-ex` | 172.24.4.1/24 | ฝั่ง host ของสาย veth ทำหน้าที่ gateway ของ floating IP |
| `veth-ovs` | (ไม่มี IP) | อีกปลายของ veth ให้ Neutron ใช้เป็น `neutron_external_interface` (ต่อเข้า `br-ex`) |

- Floating IP: `172.24.4.100–200`
- Tenant network ของ demo: `10.10.10.0/24`
- Instance ออกอินเทอร์เน็ตผ่าน NAT (iptables MASQUERADE) ใน VM

### เหตุผลของการตัดสินใจหลัก

| เรื่อง | เลือก | เหตุผล |
|---|---|---|
| Hypervisor | Lima (vz) แทน UTM GUI | ใช้ Apple Virtualization เหมือน UTM แต่สั่งผ่าน command line ได้ทั้งหมด ทำซ้ำได้ด้วยไฟล์ YAML ไฟล์เดียว และรองรับ nested virtualization บน M3 ขึ้นไป |
| OS ใน VM | Ubuntu 24.04 ARM64 | Kolla มี image `2026.1-ubuntu-noble-aarch64` บน quay.io (ตรวจจาก Quay API แล้ว) |
| OpenStack release | 2026.1 | ตรวจแล้วว่ามี image ARM64 ครบทุก service ที่ใช้ |
| Load balancer | ปิด (`enable_haproxy: no`) | มีเครื่องเดียว ไม่ต้องใช้ HAProxy/keepalived ให้ VIP = IP ของเครื่อง ลดจุดเสีย |
| External NIC | veth pair | ไม่ต้องพึ่งการ์ดใบที่ 2 จาก hypervisor ผลลัพธ์แน่นอนกว่า |
| Compute | KVM | VM มี `/dev/kvm` (nested virtualization ทำงาน) |
| Block storage | Cinder LVM บนไฟล์ loopback 40 GB | ไม่ต้องมีดิสก์จริงเพิ่ม |
| Object storage (Bonus) | Swift จาก apt ผูกกับ Keystone | Kolla Ansible **ตัด Swift role ออกตั้งแต่หลัง 2024.1** และ quay.io **ไม่มี Swift image ARM64** (ตรวจแล้ว มีแค่ `master-ubuntu-noble` ของ x86) |

---

## 2. ขั้นตอนที่ทำแล้ว

### ขั้น 0: ตรวจเครื่อง Mac

```bash
sysctl -n machdep.cpu.brand_string   # Apple M5
sysctl -n hw.memsize                 # 17179869184 (16 GB)
sysctl -n hw.ncpu                    # 10
sysctl kern.hv_support               # 1 = รองรับ Hypervisor.framework
sw_vers                              # macOS 27.2.1
```

### ขั้น 1: ติดตั้ง Lima และสร้าง VM ✅

```bash
brew install lima                    # limactl 2.3.0
limactl create --name=openstack-aio lima/openstack-aio.yaml
limactl start openstack-aio
```

ไฟล์ตั้งค่า VM: [`lima/openstack-aio.yaml`](../lima/openstack-aio.yaml) มีค่าที่สำคัญคือ:

```yaml
vmType: vz
nestedVirtualization: true
cpus: 6
memory: 10GiB
disk: 100GiB
networks:
  - vzNAT: true
```

ตรวจผล (`limactl shell openstack-aio`):

```
uname -m        → aarch64
nproc           → 6
free -h         → Mem 9.7Gi
df -h /         → 96G
ls -l /dev/kvm  → crw-rw---- 1 root kvm 10, 232   ✅ nested virtualization ใช้ได้
lsb_release -ds → Ubuntu 24.04.5 LTS
```

> **ความหมาย:** `/dev/kvm` มีอยู่ แปลว่า VM ชั้น 1 ใช้ hardware virtualization ของ M5 สร้าง VM ชั้น 2 ได้โดยตรง
> ถ้าไม่มี Nova ต้องใช้ QEMU จำลอง CPU ด้วยซอฟต์แวร์ (TCG) ซึ่งช้ากว่ามาก

### ขั้น 2: เตรียม host ✅ ([`scripts/01-prepare-host.sh`](../scripts/01-prepare-host.sh))

1. ติดตั้งแพ็กเกจ: `git python3-dev libffi-dev gcc libssl-dev libdbus-glib-1-dev python3-venv lvm2 thin-provisioning-tools iptables`
2. ให้ hostname resolve ไปที่ IP ของ `lima0` ใน `/etc/hosts`
3. สร้าง swap 8 GB (`/swapfile`) กัน RAM หมดตอน deploy
4. สร้าง veth pair `veth-ex` ↔ `veth-ovs` ถาวรด้วย systemd-networkd (ไฟล์ `/etc/systemd/network/25-veth-*.netdev/.network`)
5. สร้าง service `openstack-ext-nat.service` เปิด `ip_forward` และ NAT ให้ 172.24.4.0/24 ออกอินเทอร์เน็ตได้

### ขั้น 3: ติดตั้ง Kolla Ansible และตั้งค่า ✅ ([`scripts/02-install-kolla.sh`](../scripts/02-install-kolla.sh))

```bash
python3 -m venv ~/kolla-venv && source ~/kolla-venv/bin/activate
pip install -U pip
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2026.1
sudo mkdir -p /etc/kolla && sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp ~/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one ~/
kolla-ansible install-deps
kolla-genpwd                        # สร้างรหัสผ่านทุก service ใน /etc/kolla/passwords.yml
```

เตรียมดิสก์ให้ Cinder:

```bash
sudo truncate -s 40G /var/lib/cinder-volumes.img
LOOP=$(sudo losetup -f --show /var/lib/cinder-volumes.img)
sudo pvcreate $LOOP && sudo vgcreate cinder-volumes $LOOP
# + cinder-loop.service ให้ loop device กลับมาหลัง reboot
```

ค่าที่เพิ่มใน `/etc/kolla/globals.yml`:

```yaml
kolla_base_distro: "ubuntu"
openstack_release: "2026.1"
openstack_tag_suffix: "-aarch64"
network_interface: "lima0"
neutron_external_interface: "veth-ovs"
kolla_internal_vip_address: "192.168.64.2"
enable_haproxy: "no"
enable_proxysql: "no"        # เพิ่มภายหลัง (ดูปัญหา #6)
nova_compute_virt_type: "kvm"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
enable_heat: "no"
```

### ขั้น 4: Bootstrap และ Prechecks ✅

```bash
kolla-ansible bootstrap-servers -i ~/all-in-one              # ติดตั้ง Docker ฯลฯ → failed=0
pip install docker dbus-python                               # แก้ปัญหา #1
kolla-ansible prechecks -i ~/all-in-one --use-test-images    # → ok=102 failed=0
```

Log: `evidence/03-bootstrap-prechecks.log`, `03b-prechecks.log`, `03c-prechecks.log`

### ขั้น 5: Pull images + Deploy ✅

```bash
kolla-ansible pull -i ~/all-in-one          # failed=0 (ไม่รับ --use-test-images ดูปัญหา #3)
kolla-ansible deploy -i ~/all-in-one        # ล้ม 3 รอบ (ปัญหา #6, #7, #8) รอบที่ 4 ได้ ok=322 failed=0
```

Log: `evidence/04-pull-deploy.log`, `05a/05b/05c-*.log` (รอบที่ล้ม), `05-deploy.log` (รอบที่สำเร็จ)

### ขั้น 6: Post-deploy และตรวจสอบสถานะ ✅

```bash
kolla-ansible post-deploy -i ~/all-in-one   # สร้าง /etc/kolla/admin-openrc.sh
pip install python-openstackclient python-cinderclient -c https://releases.openstack.org/constraints/upper/2026.1
source /etc/kolla/admin-openrc.sh
openstack service list           # keystone, glance, nova, placement, neutron, cinder
openstack compute service list   # nova-scheduler, nova-conductor, nova-compute = up
openstack network agent list     # DHCP, Open vSwitch, Metadata, L3 = :-) UP
openstack volume service list    # cinder-scheduler, cinder-volume = up
openstack hypervisor list        # lima-openstack-aio, QEMU (libvirt), 192.168.64.2, up
```

- Container ทั้งหมด 35 ตัว สถานะ Up/healthy (log: `evidence/06-verify.log`)
- `nova.conf` ของ nova-compute มี `virt_type = kvm`
- "Hypervisor Type = QEMU" เป็นชื่อ driver ของ libvirt แม้จะใช้ KVM เร่งความเร็วอยู่ก็แสดงแบบนี้

### ขั้น 7: สร้างทรัพยากร demo ✅ ([`scripts/05-demo-resources.sh`](../scripts/05-demo-resources.sh))

| สิ่งที่สร้าง | ใครสร้าง | รายละเอียด |
|---|---|---|
| `demo-project`, `demo-user` (role member) | admin | Keystone |
| image `cirros-aarch64` (public) | admin | CirrOS 0.6.3 aarch64, `hw_firmware_type=uefi` |
| flavor `m1.tiny` (1 vCPU/256 MB/1 GB), `m1.small` (1 vCPU/512 MB/2 GB) | admin | Nova |
| `public-net` (external, flat, physnet1) + `public-subnet` 172.24.4.0/24 | admin | ไม่มี DHCP, pool .100–.200 |
| `private-net` + `private-subnet` 10.10.10.0/24 | demo-user | tenant network |
| router `r1` (gateway → public-net) | demo-user | SNAT + floating IP |
| security group `demo-sg` (ICMP + TCP 22) | demo-user | |
| keypair `demo-key` | demo-user | ไฟล์ `~/demo-key.pem` ใน VM |
| instance `demo-vm1` (m1.small) + floating IP **172.24.4.200** | demo-user | ACTIVE |
| volume `vol1` 1 GB ต่อเข้า `demo-vm1` เป็น `/dev/vdb` | demo-user | Cinder LVM |

ผลทดสอบ (log: `evidence/08-instance-test.log`):

- console log บูตถึง `demo-vm1 login:` ใน ~24 วินาที (KVM ทำงาน)
- ได้ IP 10.10.10.214 จาก DHCP
- `ping 172.24.4.200` จาก host: 0% loss (หลังแก้ปัญหา #9)
- SSH `cirros@172.24.4.200` ได้
- ใน instance: `lsblk` เห็น `vdb 1G`, `ping 8.8.8.8` ได้ (ออกอินเทอร์เน็ตผ่าน router + NAT)

### ขั้น 8 (Bonus): OpenStack Swift ✅ ([`scripts/06-swift.sh`](../scripts/06-swift.sh))

- ติดตั้ง Swift 2.33.0 จาก Ubuntu packages (`swift swift-proxy swift-account swift-container swift-object`)
- ดิสก์: ไฟล์ 10 GB ฟอร์แมต XFS mount ที่ `/srv/node/d1` (อยู่ใน `/etc/fstab`)
- Ring: account/container/object แบบ part power 10, 1 replica, device เดียว
- account/container/object server ฟังที่ 127.0.0.1:6202/6201/6200
- proxy ฟังที่ `192.168.64.2:8080` ใช้ `authtoken` + `keystoneauth` ยืนยันตัวตนกับ Keystone ของ Kolla, ใช้ memcached ของ Kolla
- ลงทะเบียนใน Keystone: user `swift` (role admin ใน project service), service `object-store`, endpoint public/internal/admin `http://192.168.64.2:8080/v1/AUTH_%(project_id)s`
- ทดสอบ: `openstack container create demo-container`, `openstack object create demo-container hello.txt` สำเร็จ, `curl http://192.168.64.2:8080/healthcheck` = `OK`
- Horizon มีเมนู **Project → Object Store → Containers** (log: `evidence/09-swift.log`, `09b-swift.log`)

### ขั้น 9: ทดสอบ reboot ✅

`limactl stop` / `limactl start` แล้วตรวจ:

- IP `lima0` ยังเป็น 192.168.64.2
- veth, Cinder VG, Swift mount และ NAT กลับมาเอง
- container 38 ตัว Up
- service ทุกตัว up
- Swift healthcheck OK
- instance กลับมาเป็น **SHUTOFF** (พฤติกรรมปกติของ Nova) ต้อง `openstack server start demo-vm1`

ตัด `cinder-backup` ออก (`enable_cinder_backup: "no"` + `cinder-manage service remove`) เพราะไม่ได้ตั้ง backup backend ไว้ ทำให้แสดง down

---

## 3. ปัญหาที่พบและวิธีแก้

| # | ขั้น | อาการ / Error จริง | สาเหตุ | วิธีแก้ | บทเรียน |
|---|---|---|---|---|---|
| 1 | prechecks | `ModuleNotFoundError: No module named 'docker'` | Kolla ใช้ Python ใน venv คุม Docker แต่ venv ยังไม่มี library `docker` | `pip install docker dbus-python` ใน venv | เมื่อติดตั้งใน virtualenv ต้องมี dependency ฝั่ง Python ครบ |
| 2 | prechecks | `Kolla images from quay.io/openstack.kolla namespace are meant only for testing purposes ... use --use-test-images` | Kolla รุ่นใหม่ถือว่า image สาธารณะบน quay.io เป็น image ทดสอบ (production ควร build เองหรือใช้ registry ของตัวเอง) | เพิ่ม `--use-test-images` (เหมาะกับงานแล็บ) | เข้าใจความต่างของ image ทดสอบกับ production |
| 3 | pull | `kolla-ansible pull: error: unrecognized arguments: --use-test-images` | คำสั่ง `pull` ไม่รับ option นี้ | ใส่ option เฉพาะ `prechecks` และ `deploy` | อ่าน `--help` ของแต่ละคำสั่ง |
| 5 | deploy | `kolla-ansible deploy: error: unrecognized arguments: --use-test-images` | option นี้มีเฉพาะ `prechecks` (ตรวจ registry เฉพาะตอน precheck) | รัน `deploy` โดยไม่ใส่ option | option เดียวกันใช้ไม่ได้กับทุก sub-command |
| 6 | deploy (MariaDB) | `Timeout when waiting for search string MariaDB in 192.168.64.2:3306` และใน `mariadb.log`: `Bind on TCP/IP port. Got error: 98: Address already in use` | Kolla 2026.1 มี `enable_proxysql` (ค่า default = เปิดเมื่อใช้ MariaDB) ซึ่งทำให้ load balancer (haproxy + proxysql) ถูก deploy ด้วยแม้ตั้ง `enable_haproxy: no` แล้ว ProxySQL จับพอร์ต 3306 บน IP ของ host ก่อน MariaDB | เพิ่ม `enable_proxysql: "no"` ใน globals.yml, ลบ container/volume `proxysql`, `haproxy`, `mariadb` แล้ว deploy ใหม่ (log เดิม: `evidence/05a-deploy-failed-mariadb.log`) | ตัวเลือก "ปิด load balancer" ต้องปิดทุกตัวที่เกี่ยวข้อง และ All-in-One ที่ VIP = IP ของเครื่องจะชนพอร์ตกัน |
| 7 | deploy (MariaDB รอบ 2) | `Timeout when waiting for search string MariaDB` อีกครั้ง แต่ `docker ps` แสดง `mariadb ... (healthy)` และ log บอก `ready for connections` | Kolla เช็คพอร์ตตอนที่ MariaDB กำลัง restart (จังหวะเวลา) | รัน `deploy` ซ้ำ (idempotent) (log: `evidence/05b-deploy-mariadb-timing.log`) | Kolla ทำงานแบบ idempotent สั่งซ้ำได้อย่างปลอดภัย |
| 8 | deploy (Neutron) | `pymysql.err.OperationalError: (1050, "Table 'address_groups' already exists")` ตอน `neutron-db-manage upgrade head` | ฐานข้อมูล neutron ถูก migrate ไปครึ่งทางจากรอบก่อน: ตาราง `alembic_version` ยังค้างที่ `fd6107509ccd` แต่ตารางรุ่นถัดไปถูกสร้างแล้ว (MySQL DDL ไม่เป็น transaction จึง rollback ไม่ได้) | ระบบใหม่ยังไม่มีข้อมูล จึง `DROP DATABASE neutron; CREATE DATABASE neutron;` (สิทธิ์ของ user neutron ยังอยู่) แล้ว deploy ใหม่ (log: `evidence/05c-deploy-neutron-db.log`) | อ่าน traceback หาตารางที่ชน แล้วตรวจ `alembic_version` เพื่อยืนยันว่า migration ค้าง |
| 9 | ทดสอบ floating IP | instance เป็น ACTIVE บูตถึง `login:` และ SSH จาก router namespace ได้ แต่ `ping 172.24.4.200` จาก host ได้ 100% packet loss | `tcpdump` พบว่า router DNAT ถูกต้อง แต่ที่ tap ของ instance ต้นทางกลายเป็น 192.168.5.15 เพราะ Neutron ใช้ `OVSHybridIptablesFirewallDriver` (มี bridge `qbr` และ `bridge-nf-call-iptables=1`) ทำให้ packet ผ่าน iptables ของ host และโดนกฎ NAT ของเราเอง `MASQUERADE -s 172.24.4.0/24 ! -d 172.24.4.0/24` ที่กว้างเกินไป | แก้กฎเป็น NAT เฉพาะขาออก `-o lima0` และ `-o eth0` | ใช้ `tcpdump` ไล่ทีละจุด (host → qrouter → tap) เพื่อหาว่า packet หายตรงไหน |
| 10 | Swift | `cd: /etc/swift: Permission denied` | package สร้าง `/etc/swift` ให้ user swift เท่านั้น | เรียก `swift-ring-builder` ด้วย `sudo` และ path เต็ม | – |
| 11 | Swift | `Could not bind to 127.0.0.1:6202 after trying for 30 seconds` | `systemctl enable --now` เปิด service ไปแล้ว ตามด้วย `swift-init main restart` เปิดซ้ำอีกชุด จึงชนพอร์ต | ใช้ systemd อย่างเดียว (`systemctl restart swift-*`) | อย่าใช้ตัวจัดการ service 2 แบบพร้อมกัน |
| 12 | เก็บหลักฐาน | `set -x` พิมพ์ `OS_PASSWORD` และ `--password` ลงไฟล์ log | bash trace แสดงทุกคำสั่งรวมตัวแปรรหัสผ่าน | เปิด `set -x` หลัง `source` ไฟล์ openrc และปิดรหัสใน log ที่มีอยู่ (`<REDACTED>`) | ตรวจ log ก่อนแนบในเล่มเสมอ |
| 13 | หลัง reboot | `cinder-backup` แสดง `down` | Kolla เปิด cinder-backup ตามค่า default แต่ไม่มี backup backend | `enable_cinder_backup: "no"`, ลบ container และ `cinder-manage service remove` | – |
| 4 | วางแผน Bonus | ไม่มี `swift` role ใน kolla-ansible 2025.1+ และไม่มี Swift image `-aarch64` บน quay.io | Kolla ตัดการรองรับ Swift ออกหลัง 2024.1 | ติดตั้ง Swift จาก Ubuntu package แล้วผูกกับ Keystone ของ Kolla | ตรวจ support matrix ของเวอร์ชันจริงก่อนวางแผน |

---

## 4. วิธีเปิดระบบและเข้าใช้งาน (ใช้วัน demo)

### เปิดระบบ (Terminal บน Mac)

```bash
caffeinate -dims &                     # กัน Mac หลับ
limactl start openstack-aio            # รอ ~1 นาที แล้วรออีก 2-3 นาทีให้ container ขึ้นครบ
limactl shell openstack-aio            # เข้า VM
```

ใน VM:

```bash
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
openstack compute service list         # ต้อง up ทั้งหมด
source ~/demo-openrc.sh                # สลับเป็น demo-user (เจ้าของ instance)
openstack server start demo-vm1        # instance กลับมาเป็น SHUTOFF หลัง reboot
source /etc/kolla/admin-openrc.sh      # กลับเป็น admin
```

### เข้า Horizon

- URL: **http://192.168.64.2** (เปิดจาก browser บน Mac)
- Admin:
  - Domain `Default`, User `admin`
  - Password: ดูได้ในเครื่อง VM ด้วย `grep keystone_admin_password /etc/kolla/passwords.yml`
- User ธรรมดา: Domain `Default`, User `demo-user`, Password `Demo@12345`

### ปิดระบบ

```bash
limactl stop openstack-aio
```

---

## 4.1 ขั้นตอนเดิมที่วางไว้ (ทำเสร็จแล้วทั้งหมด)

| ขั้น | งาน | สคริปต์ |
|---|---|---|
| 6 | `kolla-ansible post-deploy`, ติดตั้ง `python-openstackclient`, ตรวจ `openstack service list`, `compute service list`, `network agent list`, `volume service list` | – |
| 7 | สร้างทรัพยากรสำหรับ demo (รายการด้านล่าง) | [`scripts/05-demo-resources.sh`](../scripts/05-demo-resources.sh) |
| 8 | Bonus Swift (รายการด้านล่าง) | [`scripts/06-swift.sh`](../scripts/06-swift.sh) |
| 9 | ทดสอบ Horizon จาก Mac: `http://192.168.64.2` (user `admin`, รหัสจาก `grep keystone_admin_password /etc/kolla/passwords.yml`) | – |
| 10 | เตรียมสไลด์ + สคริปต์ demo วันที่ 17 พ.ย. | – |

สิ่งที่ขั้น 7 จะสร้าง:

- `demo-project`, `demo-user`
- image `cirros-aarch64`
- flavor `m1.tiny` และ `m1.small`
- `public-net` (flat, physnet1) และ `private-net` (10.10.10.0/24)
- router `r1` และ security group `demo-sg` (ICMP + SSH)
- keypair `demo-key`
- instance `demo-vm1` + floating IP
- volume `vol1` ต่อเข้า instance

สิ่งที่ขั้น 8 จะทำ:

- ติดตั้ง Swift 2.33 จาก apt บนดิสก์ XFS loopback 10 GB
- สร้าง ring 1 replica
- ลงทะเบียน service `object-store` ใน Keystone
- เปิด proxy ที่พอร์ต 8080
- ผลคือ Horizon จะมีเมนู Object Store → Containers

---

## 5. คำสั่งที่ใช้บ่อย

```bash
# บน Mac
limactl list                         # ดูสถานะ VM
limactl start openstack-aio          # เปิด VM
limactl stop openstack-aio           # ปิด VM
limactl shell openstack-aio          # เข้า shell ของ VM

# ใน VM
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh    # สิทธิ์ admin สำหรับคำสั่ง openstack
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
openstack service list
```

## 6. ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | เนื้อหา |
|---|---|
| `lima/openstack-aio.yaml` | นิยาม VM |
| `scripts/01-prepare-host.sh` | เตรียม host (swap, veth, NAT) |
| `scripts/02-install-kolla.sh` | ติดตั้ง Kolla Ansible + Cinder LVM + globals.yml |
| `scripts/05-demo-resources.sh` | สร้างทรัพยากร demo |
| `scripts/06-swift.sh` | Bonus Swift |
| `evidence/*.log` | log จริงของทุกขั้น (ใช้อ้างอิงในเล่ม) |
| `docs/PLAN_OpenStack_AllInOne.md` | แผนเดิม (5 พ.ย.) |

> ห้ามแนบ `/etc/kolla/passwords.yml` ในเล่ม เพราะมีรหัสผ่านจริง

## 7. แหล่งอ้างอิงที่ใช้ตรวจสอบ (เข้าถึง 15 พ.ย. 2569)

- Kolla Ansible Quick Start (2026.1): https://docs.openstack.org/kolla-ansible/2026.1/user/quickstart.html
- Kolla Ansible source (ตรวจ role/branch): https://opendev.org/openstack/kolla-ansible
- Kolla images (ตรวจ tag aarch64): https://quay.io/organization/openstack.kolla
- Lima (vz, nestedVirtualization): https://lima-vm.io และ https://github.com/lima-vm/lima
- Ubuntu cloud images (noble arm64): https://cloud-images.ubuntu.com/releases/noble/
- CirrOS: https://download.cirros-cloud.net
- OpenStack Swift install guide: https://docs.openstack.org/swift/latest/install/
- ผู้ช่วย AI: Claude (Anthropic) ช่วยวางแผน ตรวจสอบเอกสาร และรันคำสั่ง (ระบุตามนโยบายวิชา)
