# 9Router on Render Free Plan - Complete Setup Guide

## Jawaban: BISA, dengan workaround persistence + anti-sleep + anti-OOM

Render Free Plan punya 3 masalah utama buat 9Router:
1. **Sleep 15 menit idle** -> Uptime Robot (ping tiap 5 menit)
2. **Tidak ada persistent disk** -> Litestream + Cloudflare R2 (backup SQLite tiap detik)
3. **Memory leak -> OOM di 512MB** -> Watchdog auto-kill node saat RSS > 400MB (Render auto-restart)

## Arsitektur

```
[Uptime Robot] --ping 5min--> [Render Free Web Service]
                                    |
                                    v
                            [Custom Docker Image]
                            decolua/9router + litestream + sqlite
                                    |
                                    v
                            [Cloudflare R2]  (SQLite backup, free 10GB)
```

## Step 1: Siapkan Cloudflare R2 (gratis, persistence)

1. Daftar/login Cloudflare (gratis): https://dash.cloudflare.com
2. Menu kiri -> **R2 Object Storage** -> Create bucket
   - Nama bucket: `9router-backup`
   - Location: Automatic
3. Buat API token: R2 -> Manage R2 API Tokens -> Create API Token
   - Permission: **Object Read & Write**
   - Scope: bucket `9router-backup`
   - Copy: **Access Key ID**, **Secret Access Key**
4. Catat **Account ID** (di URL dashboard: dash.cloudflare.com/<ACCOUNT_ID>/r2)
5. Endpoint R2: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`

## Step 2: Push file ke GitHub

Buat repo baru (misal `9router-render`), push 3 file ini:
- `Dockerfile`
- `start.sh`
- `render.yaml`

```bash
git init
git add .
git commit -m "9router render free"
git remote add origin https://github.com/<user>/9router-render.git
git push -u origin main
```

## Step 3: Deploy di Render (Free)

1. Login Render: https://dashboard.render.com
2. **New** -> **Blueprint** -> connect repo `9router-render`
3. Render baca `render.yaml`, auto-create Web Service (Free)
4. Isi env vars (yang `sync: false`):
   - `R2_BUCKET` = `9router-backup`
   - `R2_ACCESS_KEY_ID` = (dari step 1)
   - `R2_SECRET_ACCESS_KEY` = (dari step 1)
   - `R2_ENDPOINT` = `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
5. **Apply** -> Render build image (3-5 menit) -> deploy
6. Catat URL service: `https://9router-xxxx.onrender.com`

Catatan: Render Free inject `PORT=10000` otomatis. 9Router baca `PORT` env var -> listen di 10000. OK.

## Step 4: Uptime Robot (anti-sleep)

1. Daftar: https://uptimerobot.com (gratis, 50 monitors)
2. **Add New Monitor**
   - Type: HTTP(s)
   - Friendly Name: 9router
   - URL: `https://9router-xxxx.onrender.com/api/health`
   - Monitoring Interval: **5 minutes**
3. Create Monitor

Sekarang Render tidak akan sleep karena ada ping tiap 5 menit.

## Step 5: Akses Dashboard 9Router

- URL: `https://9router-xxxx.onrender.com`
- Login default password: `123456` (ganti segera di Settings)
- Tambah provider (Kiro free, OpenCode free, dll)

## Step 6: Point CLI Tool ke 9Router

Di Claude Code / Cursor / Cline:
- Base URL: `https://9router-xxxx.onrender.com/v1`
- API Key: (dari dashboard 9Router -> API Keys)

## Cara Kerja Persistence

1. Render instance baru start -> `start.sh` restore DB dari R2 (jika ada)
2. 9Router jalan, Litestream replicate DB ke R2 tiap perubahan
3. Render restart (OOM/crash/maintenance) -> instance baru -> restore dari R2
4. Config, API keys, provider settings **tetap aman** di R2

## Memory Leak Mitigation

- Watchdog cek RSS node tiap 5 menit
- Jika RSS > 400MB -> kill node -> Render auto-restart service
- Render restart -> Litestream restore DB dari R2 -> data aman
- Downtime ~1 menit per restart (acceptable untuk hobby)

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Build gagal (OOM) | Render free build limit 512MB; image base 187MB + layer kecil, biasanya OK. Kalau gagal, push image ke Docker Hub dulu lalu pakai "Existing Image" |
| Service tidak bisa diakses | Cek Render logs: Dashboard -> service -> Logs |
| Data hilang setelah restart | Pastikan R2 env vars terisi & bucket benar. Cek Litestream log: `cat /tmp/litestream.log` (butuh shell, tidak ada di free). Cek R2 bucket ada file `9router/data.sqlite` |
| 401 Unauthorized | Login default password `123456`, ganti di Settings |
| Sleep masih terjadi | Pastikan Uptime Robot monitor status "Up" (hijau) |
| Memory crash terlalu sering | Kurangi provider/fitur yang dipakai; atau upgrade ke Render paid ($7/mo, 512MB+ no sleep) |

## Alternatif: Push image ke Docker Hub (jika build di Render gagal)

```bash
# di mesin lokal yang punya Docker
docker build -t <dockerhub-user>/9router-render:latest .
docker push <dockerhub-user>/9router-render:latest
```
Lalu di Render: New -> Web Service -> Existing Image -> `<dockerhub-user>/9router-render:latest`

## Catatan Penting

- Render Free **tidak cocok production** (sleep, restart, no persistent disk). Ini solusi **hobby/testing**.
- Untuk penggunaan serius, pertimbangkan: Oracle Cloud Free Tier (VM 1GB, selamanya gratis) atau VPS $5/mo (Hetzner/Contabo).
- Memory leak 9Router (issue #1245) belum fixed; watchdog adalah workaround.
- R2 free tier: 10GB storage, cukup untuk DB 9Router yang kecil (<100MB).

## File yang Dibutuhkan

- `Dockerfile` - custom image
- `start.sh` - wrapper (restore/replicate/watchdog/run)
- `render.yaml` - Render blueprint
