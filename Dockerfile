# syntax=docker/dockerfile:1.7
# Custom 9Router image for Render Free Plan
# Base: official published image (no rebuild of 9router from source)
FROM decolua/9router:latest

USER root

# Install litestream (continuous SQLite replication to S3/R2) + sqlite CLI (to seed empty DB)
RUN wget -qO- https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.tar.gz \
    | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/litestream \
    && apk add --no-cache sqlite


# Wrapper that restores/persists DB and mitigates memory leak
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD ["node", "custom-server.js"]
