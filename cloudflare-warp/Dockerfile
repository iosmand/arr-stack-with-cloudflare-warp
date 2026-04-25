FROM debian:bookworm-slim

LABEL maintainer="Cloudflare WARP Docker"
LABEL description="Cloudflare WARP client running as non-registered (free) user"

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    ca-certificates \
    iproute2 \
    dbus \
    && rm -rf /var/lib/apt/lists/*

# Add Cloudflare GPG key and repository
RUN curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" > /etc/apt/sources.list.d/cloudflare-client.list

# Install Cloudflare WARP
RUN apt-get update && apt-get install -y \
    cloudflare-warp \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /var/lib/cloudflare-warp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose SOCKS5 proxy port (optional, for proxy mode)
# EXPOSE 40000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD warp-cli --accept-tos status | grep -q "Connected" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
