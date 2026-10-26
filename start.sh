#!/bin/sh
set -e

DATA_DIR="${DATA_DIR:-/app/data}"
DB_PATH="$DATA_DIR/db/data.sqlite"
mkdir -p "$DATA_DIR/db"

# ---------- Optional persistence via S3-compatible storage (Supabase) ----------
if [ -n "$R2_BUCKET" ] && [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ]; then
    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"

    # Supabase S3 endpoint (path-style, no https:// in endpoint param)
    SUPABASE_ENDPOINT="nlqndotojfongwivgeyj.supabase.co/storage/v1/s3"
    if [ -n "$R2_ENDPOINT" ]; then
        # Extract host+path from R2_ENDPOINT (strip https://)
        SUPABASE_ENDPOINT=$(echo "$R2_ENDPOINT" | sed 's|https://||')
    fi

    S3_URL="s3://$R2_BUCKET/9router/data.sqlite?endpoint=$SUPABASE_ENDPOINT"

    # Restore DB from Supabase if local DB missing
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Restoring DB from Supabase..."
        litestream restore -if-replica-exists -o "$DB_PATH" "$S3_URL" 2>/dev/null || true
    fi

    # Seed an empty valid SQLite DB if still missing
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Seeding empty DB..."
        sqlite3 "$DB_PATH" "VACUUM;" 2>/dev/null || touch "$DB_PATH"
    fi
    chown node:node "$DB_PATH" 2>/dev/null || true

    # Start continuous replication in background
    (
        while [ ! -f "$DB_PATH" ]; do sleep 1; done
        sleep 3
        echo "[9router] Starting Litestream replication to Supabase..."
        litestream replicate "$DB_PATH" "$S3_URL" >/tmp/litestream.log 2>&1
    ) &
fi

# ---------- Memory-leak watchdog (Render free = 512MB) ----------
(
    while true; do
        sleep 300
        NODE_PID=$(pgrep -f "custom-server.js" 2>/dev/null | head -n1)
        if [ -n "$NODE_PID" ]; then
            RSS=$(ps -o rss= -p "$NODE_PID" 2>/dev/null | tr -d ' ')
            if [ -n "$RSS" ] && [ "$RSS" -gt 400000 ]; then
                echo "[9router] RSS ${RSS}KB > 400MB, killing node to trigger Render restart"
                kill "$NODE_PID" 2>/dev/null
            fi
        fi
    done
) &

# ---------- Fix permissions & run 9router ----------
chown -R node:node /app/data /app/data-home 2>/dev/null || true
exec su-exec node node custom-server.js
