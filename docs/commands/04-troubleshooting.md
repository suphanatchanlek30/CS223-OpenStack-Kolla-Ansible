# 04 · แก้ปัญหาและดู Log (รันใน VM)

## ดู Log

log ของ Kolla อยู่ที่ `/var/log/kolla/<service>/` (ต้องใช้ `sudo`)

```bash
sudo ls /var/log/kolla/
sudo tail -50 /var/log/kolla/nova/nova-compute.log
sudo tail -50 /var/log/kolla/neutron/neutron-server.log
sudo tail -50 /var/log/kolla/keystone/keystone.log
sudo tail -50 /var/log/kolla/cinder/cinder-volume.log
sudo tail -50 /var/log/kolla/horizon/horizon-uwsgi.log
sudo grep -i error /var/log/kolla/nova/*.log | tail -20

sudo docker logs --tail 50 nova_compute       # log ฝั่ง container (ตอน start)
sudo journalctl -u swift-proxy -n 50          # log ของ Swift
```

## Restart service

```bash
sudo docker restart nova_compute               # restart container ตัวเดียว
sudo docker restart horizon
sudo systemctl restart swift-proxy             # Swift ไม่ได้เป็น container
```

## อาการและวิธีแก้

| อาการ | ตรวจด้วย | แก้ |
|---|---|---|
| เปิด http://192.168.64.2 ไม่ได้ | `limactl list` (VM รันไหม), `sudo docker ps \| grep horizon` | `limactl start openstack-aio` แล้วรอ 3–4 นาที, หรือ `sudo docker restart horizon` |
| Login Horizon ไม่ได้ | `grep keystone_admin_password /etc/kolla/passwords.yml` | ใช้รหัสจากไฟล์นี้, Domain = `Default` |
| instance เป็น SHUTOFF | `openstack server list` | `source ~/demo-openrc.sh; openstack server start demo-vm1` |
| instance เป็น ERROR | `openstack server show demo-vm1 -c fault` | ลบแล้วสร้างใหม่, ดู `nova-compute.log` |
| ping floating IP ไม่ได้ | `systemctl status openstack-ext-nat`, `sudo iptables -t nat -S POSTROUTING` | `sudo systemctl restart openstack-ext-nat`, รอ instance บูตเสร็จ (~1 นาที) |
| SSH ขึ้น `Connection refused` | instance เพิ่งเปิด | รอ 30–60 วินาทีแล้วลองใหม่ |
| volume สร้างไม่ได้ | `openstack volume service list`, `sudo vgs cinder-volumes` | `sudo systemctl restart cinder-loop; sudo docker restart cinder_volume` |
| Swift error | `curl http://192.168.64.2:8080/healthcheck`, `mountpoint /srv/node/d1` | `sudo mount /srv/node/d1; sudo systemctl restart swift-*` |
| service ขึ้น down | `openstack compute service list` | `sudo docker restart <ชื่อ container>` รอ 1 นาที |

## ไม้ตายสุดท้าย: ให้ Kolla ตั้งค่าใหม่ทั้งหมด

ใช้เมื่อ restart แล้วยังไม่หาย (ใช้เวลา ~15 นาที, ข้อมูลไม่หาย)

```bash
source ~/kolla-venv/bin/activate
kolla-ansible deploy -i ~/all-in-one
```

## ไฟล์สำคัญ

| ไฟล์ | คือ |
|---|---|
| `/etc/kolla/globals.yml` | ค่าตั้งของ Kolla ที่เราแก้ |
| `/etc/kolla/passwords.yml` | รหัสผ่านทุก service **ห้ามแคป/แนบในเล่ม** |
| `/etc/kolla/admin-openrc.sh` | credential ของ admin |
| `~/demo-openrc.sh` | credential ของ demo-user |
| `~/demo-key.pem` | private key สำหรับ SSH เข้า instance |
| `~/all-in-one` | inventory ของ Ansible |
| `/etc/swift/*.conf`, `/etc/swift/*.ring.gz` | config และ ring ของ Swift |
