# راهنمای GUCCI 3X-UI روی Railway

این مخزن، سورس کامل نسخه رسمی **MHSanaei/3x-ui** را نگه می‌دارد و لایه Railway/GUCCI را بدون تغییر دادن منطق اصلی پنل روی آن قرار می‌دهد.

## مسیرها

- `/` — صفحه معرفی GUCCI
- `/gucci/` — پنل اصلی 3X-UI
- `/sub/{subId}` — لینک سابسکریپشن اصلی و Native پنل سنایی
- `/json/{subId}` و `/clash/{subId}` — خروجی‌های Native در صورت فعال‌سازی
- `/healthz` — Health Check

## اطلاعات اولیه

- Username: `gucci`
- Password: `gucci`

در استقرار فعلی `XUI_FORCE_INITIAL_CREDENTIALS=false` است؛ بنابراین نام کاربری و رمز `gucci` پس از هر Restart هم اعمال می‌شوند. تمام کاربران، inboundها و سایر تنظیمات روی Volume باقی می‌مانند.

## Volume

**Mount Path را دقیقاً `/data` قرار دهید.**

Entrypoint پوشه‌های زیر را داخل همان Volume نگه می‌دارد:

- `/data/x-ui` — دیتابیس SQLite، کاربران، inboundها و تمام تنظیمات
- `/data/cert` — گواهی‌ها
- `/data/acme` — وضعیت تمدید گواهی
- `/data/log` — لاگ‌های پنل

در نتیجه Redeploy، Restart و ارتقای نسخه اطلاعات پنل را پاک نمی‌کند.

## متغیرهای Railway

```env
PORT=8080
XUI_INTERNAL_PORT=2053
XUI_WEB_BASE_PATH=/gucci/
XUI_INITIAL_USERNAME=gucci
XUI_INITIAL_PASSWORD=gucci
XUI_DATA_ROOT=/data
XUI_FORCE_INITIAL_CREDENTIALS=false
XUI_ENABLE_FAIL2BAN=true
XRAY_VMESS_AEAD_FORCED=false
```

## به‌روزرسانی خودکار

Workflow زمان‌بندی‌شده هر روز آخرین Release پایدار `MHSanaei/3x-ui` را بررسی می‌کند. در صورت انتشار نسخه جدید:

1. سورس کامل upstream همگام می‌شود.
2. Image پایه به نسخه جدید تغییر می‌کند.
3. Commit جدید ساخته می‌شود.
4. Railway به‌صورت خودکار Deploy می‌کند.
5. Volume `/data` تمام اطلاعات قبلی را حفظ می‌کند.

اگر Health Check نسخه جدید شکست بخورد، Railway نسخه سالم قبلی را نگه می‌دارد.

## محدودیت Railway

دامنه HTTP پنل و تمام لینک‌های سابسکریپشن کار می‌کنند. Railway برای هر Service فقط یک TCP Proxy عمومی و ورودی UDP محدودی دارد؛ بنابراین برای عمومی‌کردن تعداد زیادی inbound با پورت‌های مستقل، باید از fallback روی یک پورت، Relayهای جدا یا VPS استفاده شود. این محدودیت خود Railway است و قابلیت‌های UI اصلی 3X-UI حذف نشده‌اند.

## تنظیم خودکار شبکه GUCCI

Workflow `railway-ensure.yml` در هر Push این وضعیت را enforce می‌کند:

- دامنه عمومی روی Application Port `1`
- دقیقاً یک TCP Proxy روی Application Port `1234` و حذف Proxyهای پورت دیگر
- Inbound بومی VLESS Reality روی `1234`
- فقط `play.google.com` به‌عنوان Reality SNI/target
- Host override همه کاربران روی endpoint همان TCP Proxy
- IP-limit UI فعال (3X-UI v3.6.0 از Online Stats API استفاده می‌کند)
- Region فقط EU West آمستردام/هلند
