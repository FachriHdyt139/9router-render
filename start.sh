#!/bin/sh

DATA_DIR="${DATA_DIR:-/app/data}"
DB_PATH="$DATA_DIR/db/data.sqlite"
mkdir -p "$DATA_DIR/db"

# ---------- Optional persistence via S3-compatible storage (Supabase) ----------
if [ -n "$R2_BUCKET" ] && [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ]; then
    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

    # Supabase S3 endpoint (strip https:// for endpoint param)
    SUPABASE_ENDPOINT="nlqndotojfongwivgeyj.supabase.co/storage/v1/s3"
    if [ -n "$R2_ENDPOINT" ]; then
        SUPABASE_ENDPOINT=$(echo "$R2_ENDPOINT" | sed 's|https://||')
    fi

    S3_URL="s3://$R2_BUCKET/9router/data.sqlite?endpoint=$SUPABASE_ENDPOINT"

    echo "[9router] S3_URL: $S3_URL"

    # Restore DB from Supabase if local DB missing
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Restoring DB from Supabase..."
        litestream restore -if-replica-exists -o "$DB_PATH" "$S3_URL" 2>&1 || echo "[9router] Restore failed or no backup yet"
    fi

    # Seed an empty valid SQLite DB if still missing
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Seeding empty DB..."
        sqlite3 "$DB_PATH" "VACUUM;" 2>/dev/null || touch "$DB_PATH"
    fi
    chown node:node "$DB_PATH" 2>/dev/null || true
    # Fix permissions for 9router (needs write access to /app/data)
    chown -R node:node /app/data 2>/dev/null || true
    mkdir -p /app/data/db/backups 2>/dev/null || true
    chown -R node:node /app/data/db/backups 2>/dev/null || true

    echo "[9router] Starting Litestream replication to Supabase with exec..."
    # Run Litestream as PID 1, executing 9router as child process
    # This ensures Litestream errors are captured in stdout
    exec litestream replicate -exec "su-exec node node custom-server.js" "$DB_PATH" "$S3_URL"
else
    echo "[9router] No S3 credentials, running without persistence"
    chown -R node:node /app/data /app/data-home 2>/dev/null || true
    exec su-exec node node custom-server.js
fi