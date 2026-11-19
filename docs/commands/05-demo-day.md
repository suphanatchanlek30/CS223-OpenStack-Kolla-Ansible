# 05 · ขั้นตอนวัน Demo (17 พ.ย. 2569)

## ก่อนเข้าห้อง (30 นาทีก่อน)

```bash
# Terminal บน Mac
caffeinate -dims &
limactl start openstack-aio
```

รอ 3–4 นาที แล้ว:

```bash
limactl shell openstack-aio
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
openstack compute service list        # up ครบ
openstack network agent list          # :-) ครบ
source ~/demo-openrc.sh
openstack server start demo-vm1       # instance กลับมาเป็น SHUTOFF หลังเปิดเครื่อง
openstack server list                 # รอจน ACTIVE
```

เปิด browser → **http://192.168.64.2** → login `admin` เตรียมไว้

## Checklist

- [ ] ชาร์จ Mac / ต่อสาย
- [ ] Horizon login ได้
- [ ] `demo-vm1` = ACTIVE, ping 172.24.4.200 ได้
- [ ] เปิด Terminal ค้างไว้ 1 หน้าต่างใน VM (source ครบแล้ว)
- [ ] ปิดแอปอื่นที่กิน RAM

## ลำดับ Demo ใน Horizon (ตามหัวข้อที่อาจารย์กำหนด)

| # | หัวข้อ | โชว์อะไร | หน้าใน Horizon / คำสั่ง |
|---|---|---|---|
| 1 | แนะนำหัวข้อ + ประโยชน์ | OpenStack คือ IaaS ส่วนตัว ติดตั้งด้วย Kolla Ansible | (สไลด์) |
| 2 | สถาปัตยกรรม | Mac → Lima VM → Docker/Kolla → OpenStack → instance, 3 ชั้น virtualization | (สไลด์) + Terminal: `sudo docker ps`, `openstack service list` |
| 3 | Demo: Admin | ภาพรวมทรัพยากร hypervisor | **Admin → Compute → Hypervisors**, **Admin → System Information** |
| 3 | Demo: Identity | project/user/role | **Identity → Projects / Users** |
| 3 | Demo: Image/Flavor | image ARM64, flavor | **Admin → Compute → Images / Flavors** |
| 3 | Demo: Network | topology, router, SG | **Project → Network → Network Topology**, Security Groups |
| 3 | Demo: Instance | สร้างสด / console | **Project → Compute → Instances → Launch Instance**, คลิกชื่อ → **Console** |
| 3 | Demo: Volume | attach volume | **Project → Volumes → Volumes** |
| 3 | Demo: Swift (Bonus) | upload/download ไฟล์ | **Project → Object Store → Containers** |
| 4 | อุปสรรค | ปัญหา 13 เรื่องจริง เลือกเล่า 3 เรื่อง: ProxySQL ชนพอร์ต, Neutron DB ค้าง, NAT ทำ floating IP พัง | `docs/INSTALL_LOG.md` หัวข้อ 3 |
| 5 | การแบ่งงาน | ทำคนเดียว | – |

## เปลี่ยน project ใน Horizon

มุมซ้ายบน (dropdown ชื่อ project) → เลือก `admin` หรือ `demo-project`
- `demo-vm1`, `vol1`, `private-net`, `r1` อยู่ใน **demo-project**
- `demo-container` (Swift) อยู่ใน **admin**

## ถ้าระบบล่มระหว่าง demo

1. ใช้ screenshot / วิดีโอสำรองที่อัดไว้
2. แก้ตาม `docs/commands/04-troubleshooting.md`
