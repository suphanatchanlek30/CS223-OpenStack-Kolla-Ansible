# 03 · คำสั่งใช้งานและ Admin OpenStack (CLI ใน VM)

ทุกอย่างในไฟล์นี้ทำใน Horizon ได้เหมือนกัน ตอน demo แนะนำโชว์ทั้ง 2 แบบ

## สลับผู้ใช้

```bash
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh    # admin (ผู้ดูแลระบบ)
source ~/demo-openrc.sh              # demo-user (ผู้ใช้ทั่วไปใน demo-project)
openstack token issue -c project_id -c user_id    # ดูว่าตอนนี้เป็นใคร
```

---

## Keystone: Project / User / Role (ต้องเป็น admin)

```bash
openstack project list
openstack user list
openstack role list
openstack role assignment list --names

# ตัวอย่างสร้างใหม่ตอน demo
openstack project create --description "live demo" demo2
openstack user create --project demo2 --password 'Demo2@12345' user2
openstack role add --project demo2 --user user2 member

# ลบทิ้ง
openstack user delete user2
openstack project delete demo2
```

## Glance: Image

```bash
openstack image list
openstack image show cirros-aarch64
# อัปโหลดเพิ่ม (ต้องเป็น image แบบ aarch64 เพราะเครื่องเป็น ARM)
openstack image create my-image --file ~/cirros-0.6.3-aarch64-disk.img \
  --disk-format qcow2 --container-format bare --property hw_firmware_type=uefi
openstack image delete my-image
```

## Nova: Flavor (ต้องเป็น admin)

```bash
openstack flavor list
openstack flavor create --vcpus 1 --ram 384 --disk 1 m1.demo
openstack flavor delete m1.demo
```

## Neutron: Network / Router / Security Group / Floating IP

```bash
openstack network list
openstack subnet list
openstack router list
openstack router show r1
openstack security group list
openstack security group rule list demo-sg
openstack floating ip list
openstack port list

# เปิดพอร์ตเพิ่ม เช่น HTTP
openstack security group rule create --proto tcp --dst-port 80 demo-sg
```

## Nova: Instance (ทำเป็น demo-user)

```bash
source ~/demo-openrc.sh

openstack server list
openstack server show demo-vm1

# วงจรชีวิตของ instance
openstack server start demo-vm1       # หลัง reboot VM ต้องสั่งอันนี้
openstack server stop demo-vm1
openstack server reboot demo-vm1
openstack server pause demo-vm1;   openstack server unpause demo-vm1
openstack server suspend demo-vm1; openstack server resume demo-vm1
openstack server event list demo-vm1  # ประวัติ action ทั้งหมด

# ดูหน้าจอ / log การบูต
openstack console log show demo-vm1 | tail -20
openstack console url show demo-vm1   # ได้ URL noVNC เปิดใน browser บน Mac ได้

# สร้างตัวใหม่สด ๆ
openstack server create demo-vm2 --image cirros-aarch64 --flavor m1.tiny \
  --network private-net --security-group demo-sg --key-name demo-key --wait
openstack floating ip create public-net                 # จด IP ที่ได้
openstack server add floating ip demo-vm2 <FLOATING_IP>
openstack server delete demo-vm2

# snapshot
openstack server image create --name demo-vm1-snap demo-vm1
```

### เข้าไปใน instance

```bash
ping -c3 172.24.4.200
ssh -i ~/demo-key.pem cirros@172.24.4.200
# ใน instance:  uname -a ; ip addr ; lsblk ; ping -c2 8.8.8.8 ; exit
```

> Floating IP (172.24.4.x) ping/SSH ได้จากใน VM host เท่านั้น ส่วนจาก Mac ให้ใช้ Console ใน Horizon แทน
> รหัสผ่าน console ของ CirrOS: user `cirros` / pass `gocubsgo`

## Cinder: Volume

```bash
openstack volume list
openstack volume create --size 1 vol2
openstack server add volume demo-vm1 vol2         # ใน instance จะเห็น /dev/vdc
openstack server remove volume demo-vm1 vol2
openstack volume delete vol2
openstack volume snapshot create --volume vol1 vol1-snap
```

## Swift: Object Store (Bonus) — ทำเป็น admin

```bash
source /etc/kolla/admin-openrc.sh
openstack object store account show
openstack container list
openstack object list demo-container
echo "hello CS223" > /tmp/a.txt
openstack object create demo-container /tmp/a.txt --name a.txt
openstack object save demo-container a.txt --file /tmp/a-download.txt && cat /tmp/a-download.txt
openstack object delete demo-container a.txt
openstack container create my-bucket
```

> demo-user ยังไม่มี container ของตัวเอง ถ้าจะสร้างให้ `source ~/demo-openrc.sh` แล้ว `openstack container create ...`

## งาน Admin อื่น ๆ

```bash
openstack quota show demo-project
openstack quota set --instances 5 --cores 4 --ram 4096 demo-project
openstack usage list
openstack server list --all-projects --long
openstack server migrate --help        # (มีเครื่องเดียว ย้ายไม่ได้ ใช้อธิบายแนวคิดได้)
```
