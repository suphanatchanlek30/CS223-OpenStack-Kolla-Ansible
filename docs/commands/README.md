# คู่มือคำสั่ง OpenStack All-in-One (CS223)

| ไฟล์ | ใช้เมื่อ |
|---|---|
| [01-vm-lima.md](01-vm-lima.md) | เปิด/ปิด/เข้า VM, ดูสเปก VM (Terminal บน Mac) |
| [02-check-status.md](02-check-status.md) | เช็คว่าทุก service ทำงานไหม |
| [03-admin-operations.md](03-admin-operations.md) | ใช้งาน/Admin: project, user, image, flavor, network, instance, volume, Swift |
| [04-troubleshooting.md](04-troubleshooting.md) | ดู log, restart, อาการและวิธีแก้ |
| [05-demo-day.md](05-demo-day.md) | ขั้นตอนเตรียมและลำดับ demo วันที่ 17 พ.ย. |

## สรุป 30 วินาที

```bash
# Mac
limactl start openstack-aio          # เปิด
limactl shell openstack-aio          # เข้า VM
limactl stop openstack-aio           # ปิด

# ใน VM
source ~/kolla-venv/bin/activate && source /etc/kolla/admin-openrc.sh
openstack service list
sudo docker ps
```

- Horizon: http://192.168.64.2 (Domain `Default`)
- admin password: `grep keystone_admin_password /etc/kolla/passwords.yml` (ใน VM)
- demo-user / `Demo@12345`

ดูประวัติการติดตั้งและปัญหาที่เจอได้ที่ [../INSTALL_LOG.md](../INSTALL_LOG.md)
