# 01 · คำสั่งจัดการ VM (รันใน Terminal บน Mac)

VM ชื่อ `openstack-aio` สร้างด้วย Lima (Apple Virtualization)
OpenStack ทั้งหมดรันอยู่ข้างใน VM นี้

## ดูสถานะ

```bash
limactl list                         # ดูว่า VM Running หรือ Stopped, ดู CPU/RAM/Disk
```

## เปิด / ปิด / รีสตาร์ท

```bash
limactl start openstack-aio          # เปิด VM (รอ ~1 นาที แล้วรอ container ขึ้นอีก 2–3 นาที)
limactl stop openstack-aio           # ปิด VM แบบปกติ (OpenStack ปิดตามไปด้วย)
limactl stop -f openstack-aio        # บังคับปิด (ใช้เมื่อ VM ค้างเท่านั้น)
limactl restart openstack-aio        # ปิดแล้วเปิดใหม่
```

> หลังเปิด VM ใหม่ instance ใน OpenStack จะเป็น `SHUTOFF` ต้องสั่ง start เอง (ดูไฟล์ 03)

## เข้าไปใน VM

```bash
limactl shell openstack-aio          # เข้า shell ของ VM (พิมพ์ exit เพื่อออก)
limactl shell openstack-aio -- uptime   # รันคำสั่งเดียวโดยไม่ต้องเข้า shell
```

ทุกครั้งที่เข้า VM แล้วจะใช้คำสั่ง `openstack` ต้องรัน 2 บรรทัดนี้ก่อน:

```bash
source ~/kolla-venv/bin/activate     # เปิด Python venv ที่มี kolla-ansible และ openstack client
source /etc/kolla/admin-openrc.sh    # login เป็น admin (หรือ source ~/demo-openrc.sh = demo-user)
```

## ดูสเปกของ VM (ใช้แคปใส่เล่ม)

ใน VM:

```bash
uname -m                 # aarch64
nproc                    # 6
free -h                  # RAM ~10 GB + swap 8 GB
df -h /                  # ดิสก์ 100 GB
ls -l /dev/kvm           # มีไฟล์นี้ = nested virtualization ใช้ได้
ip -br a                 # lima0 = 192.168.64.2, veth-ex = 172.24.4.1
lsb_release -ds          # Ubuntu 24.04
```

## กัน Mac หลับระหว่างใช้งาน

```bash
caffeinate -dims         # ค้างไว้ใน Terminal 1 หน้าต่าง, กด Ctrl+C เมื่อเลิกใช้
```

## ไฟล์ตั้งค่า VM

`lima/openstack-aio.yaml` (6 vCPU, 10 GiB, 100 GiB, `nestedVirtualization: true`, `vzNAT`)
