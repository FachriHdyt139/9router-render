# 9Router on Render Free Plan (with persistence)

Custom Docker image running [9Router](https://github.com/decolua/9router) on Render Free with **persistent SQLite data** via Litestream -> Filebase S3-compatible storage.

## Architecture

    [9Router node app] -- (better-sqlite3) --> /app/data/db/data.sqlite
            |
    Litestream v0.5.17 (PID 1, config-file mode)
            |  replicate every ~1s (WAL checkpoints .ltx)
            v
    Filebase bucket: 9router-backup @ https://s3.filebase.io
            |
            ^ restore on boot (container starts empty -> DB reconstructed)

- Litestream runs as PID 1 and launches 9Router via `-exec`; errors are visible in Render logs.
- Config generated at boot: `/etc/litestream.yml` (explicit endpoint + region + force-path-style).
- Memory leak mitigation (upstream issue #1245) not included in watchdog form anymore; Render restarts the free instance on OOM automatically.

## Critical notes (learned the hard way)

1. **Filebase S3 endpoint is now `s3.filebase.io`** — the legacy `s3.filebase.com` gateway still authenticates keys but returns an EMPTY bucket registry. Use the `.io` endpoint.
2. **Litestream >= v0.5.17 required** — v0.3.x performs a bucket-region lookup against AWS for command-line replicas, which fails with `InvalidAccessKeyId` on S3-compatible providers.
3. **Use config-file mode** (`/etc/litestream.yml`) — command-line mode cannot handle providers that are not auto-detected (`s3.filebase.io` is not in the auto-detect list).
4. Filebase free plan = 1 bucket, no credit card.

## Required Render env vars

| Key | Example / description |
|---|---|
| `PORT` | `10000` |
| `HOSTNAME` | `0.0.0.0` |
| `NODE_ENV` | `production` |
| `DATA_DIR` | `/app/data` |
| `JWT_SECRET` | random 44-char base64 (CVE-2026-49352 mitigation) |
| `INITIAL_PASSWORD` | dashboard login password |
| `R2_BUCKET` | Filebase bucket name (e.g. `9router-backup`) |
| `R2_ACCESS_KEY_ID` | Filebase S3 Access Key ID |
| `R2_SECRET_ACCESS_KEY` | Filebase S3 Secret Access Key |
| `R2_ENDPOINT` | `https://s3.filebase.io` |

## Deploy

1. Fork/push this repo to GitHub.
2. On Render: New -> Web Service -> connect repo (Docker runtime, free plan).
3. Set the env vars above. Boot sequence does the rest.

## Verify persistence works

Boot logs should show:

    [9router] Persistence config: bucket=9router-backup endpoint=s3.filebase.io
    [9router] Restoring DB from replica (if exists)...
    replicating to type=s3 bucket=9router-backup path=9router/data.sqlite region=us-east-1 endpoint=s3.filebase.io
    detected database behind replica ... replica_txid=000000000000000N

Add data in the dashboard, then check the Filebase bucket grows (apps like aws cli, or the Filebase console object count).

## Serving agents behind Cloudflare WAF

Use a dedicated custom domain with DNS-only (grey cloud) CNAME to the Render URL. Proxying an on-render.com domain through Cloudflare triggers WAF 403s for coding agents.

## License

Same as upstream 9Router project.