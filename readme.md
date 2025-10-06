# Extreme WireGuard VPN Auto Selector 🚀

**نسخه:** 01  
**زبان:** Bash  

اسکریپتی برای انتخاب خودکار سریع‌ترین کانفیگ WireGuard و اتصال امن VPN.  
این ابزار کانفیگ‌ها را تست کرده و بهترین گزینه را بر اساس سرعت و پینگ انتخاب می‌کند.

---

## ویژگی‌ها ✨

- تست سرعت دیتاسنترها و انتخاب سریع‌ترین
- تست سرعت و پینگ هر کانفیگ WireGuard
- انتخاب بهترین کانفیگ با محاسبه **Score = سرعت / (1 + پینگ / P0)**
- سازگار با اکثر توزیع‌های لینوکس (نیازمند `wg`, `curl`, `jq`, `bc`)
- حالت Silent برای اجرای بی‌صدا

---

## نصب و آماده‌سازی ⚙️

1. کپی کانفیگ‌ها در مسیر:

```bash
sudo mkdir -p /etc/wireguard/extreme_configs
sudo cp your-configs/*.conf /etc/wireguard/extreme_configs/
sudo chmod 700 /etc/wireguard/extreme_configs


اجازه اجرای اسکریپت:

chmod +x extreme_vpn.sh

اجرا ▶️
sudo ./extreme_vpn.sh


گزینه‌ها:

--silent : اجرای بی‌صدا

--help : نمایش راهنما

مسیرهای مهم 🗂️
آیتم	مسیر
کانفیگ‌ها	/etc/wireguard/extreme_configs
فایل لاگ	/var/log/extreme_vpn.log
فایل تست سرعت	/tmp/speedtest.tmp
اینترفیس VPN	wg-extreme
نکات مهم ⚠️

کانفیگ‌ها باید با فرمت .conf باشند

اسکریپت مقادیر جدول (Table = off) را خودکار اضافه می‌کند

اجرای اسکریپت نیازمند دسترسی sudo است
