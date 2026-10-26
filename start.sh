#!/bin/sh

DATA_DIR="${DATA_DIR:-/app/data}"
DB_PATH="$DATA_DIR/db/data.sqlite"
LITESTREAM_CONFIG="/etc/litestream.yml"
mkdir -p "$DATA_DIR/db"

# ---------- Optional persistence via S3-compatible storage (Filebase) ----------
if [ -n "$R2_BUCKET" ] && [ -n "$R2_ACCESS_KEY_ID" ] && [ -n "$R2_SECRET_ACCESS_KEY" ]; then

    # Strip https:// from R2_ENDPOINT for the config's endpoint field
    ENDPOINT_HOST=$(echo "${R2_ENDPOINT:-https://s3.filebase.io}" | sed 's|https://||')

    echo "[9router] Persistence config: bucket=$R2_BUCKET endpoint=$ENDPOINT_HOST"

    # Write explicit Litestream config (config-file mode = full control,
    # no provider auto-detection quirks, no bucket-region lookup against AWS)
    cat > "$LITESTREAM_CONFIG" <<EOF
dbs:
  - path: $DB_PATH
    replicas:
      - type: s3
        bucket: $R2_BUCKET
        path: 9router/data.sqlite
        endpoint: $ENDPOINT_HOST
        region: us-east-1
        force-path-style: true
        access-key-id: $R2_ACCESS_KEY_ID
        secret-access-key: $R2_SECRET_ACCESS_KEY
EOF

    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
    export LITESTREAM_CONFIG="$LITESTREAM_CONFIG"

    # Restore DB from replica if local DB missing (new Render instance / after restart)
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Restoring DB from replica (if exists)..."
        litestream restore -if-replica-exists -config "$LITESTREAM_CONFIG" "$DB_PATH" 2>&1 || echo "[9router] Restore skipped (no backup yet)"
    fi

    # Seed an empty valid SQLite DB if still missing (so litestream + 9router can start)
    if [ ! -f "$DB_PATH" ]; then
        echo "[9router] Seeding empty DB..."
        sqlite3 "$DB_PATH" "VACUUM;" 2>/dev/null || touch "$DB_PATH"
    fi
    chown node:node "$DB_PATH" 2>/dev/null || true
    chown -R node:node /app/data 2>/dev/null || true
    mkdir -p /app/data/db/backups 2>/dev/null || true
    chown -R node:node /app/data/db/backups 2>/dev/null || true

    echo "[9router] Starting Litestream replication (config-file mode, exec 9router)..."
    exec litestream replicate -config "$LITESTREAM_CONFIG" -exec "su-exec node node custom-server.js"
else
    echo "[9router] No S3 credentials, running without persistence"
    chown -R node:node /app/data 2>/dev/null || true
    exec su-exec node node custom-server.js
fi
