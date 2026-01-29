# ARR Media Stack with Cloudflare WARP

A complete media automation stack running through Cloudflare WARP VPN. All *arr services and downloads are routed through WARP for privacy.

## Stack Overview

| Service | Port | Description |
|---------|------|-------------|
| **Cloudflare WARP** | - | VPN gateway for all services |
| **Radarr** | 7878 | Movie collection manager |
| **Sonarr** | 8989 | TV show collection manager |
| **Lidarr** | 8686 | Music collection manager |
| **Bazarr** | 6767 | Subtitle manager |
| **Prowlarr** | 9696 | Indexer manager |
| **qBittorrent** | 8080, 6881 | Torrent client |
| **FlareSolverr** | 8191 | Cloudflare bypass proxy |
| **Jellyfin** | 8096, 7359/udp | Media server with hardware transcoding |

## Quick Start

```bash
docker compose up -d
```

## Architecture

All services use `network_mode: "service:cloudflare-warp"` which routes their traffic through the WARP VPN tunnel. Ports are exposed through the cloudflare-warp container.

```
┌─────────────────────────────────────────────────────────┐
│                    Cloudflare WARP                      │
│                    (VPN Gateway)                        │
│  Exposed Ports: 7878, 8989, 8686, 6767, 9696,          │
│                 8080, 6881, 8096, 7359, 8191           │
└──────────────────────┬──────────────────────────────────┘
                       │ network_mode: service:cloudflare-warp
    ┌──────────────────┼──────────────────┐
    │                  │                  │
┌───▼───┐  ┌───▼───┐  ┌───▼───┐  ┌───▼────┐
│Radarr │  │Sonarr │  │Lidarr │  │Bazarr  │
└───────┘  └───────┘  └───────┘  └────────┘
    │                  │
┌───▼─────┐  ┌────▼────┐  ┌───────────┐  ┌──────────┐
│Prowlarr │  │qBittor. │  │FlareSolvrr│  │ Jellyfin │
└─────────┘  └─────────┘  └───────────┘  └──────────┘
```

## Service URLs

After deployment, access services at:

- **Radarr**: http://localhost:7878
- **Sonarr**: http://localhost:8989
- **Lidarr**: http://localhost:8686
- **Bazarr**: http://localhost:6767
- **Prowlarr**: http://localhost:9696
- **qBittorrent**: http://localhost:8080
- **FlareSolverr**: http://localhost:8191
- **Jellyfin**: http://localhost:8096

## Configuration

### Data Volume Structure

All services share a common `/data` volume. Recommended structure:

```
/data
├── torrents/
│   ├── movies/
│   ├── tv/
│   └── music/
└── media/
    ├── movies/
    ├── tv/
    └── music/
```

### Jellyfin Hardware Transcoding

Jellyfin is configured for GPU hardware transcoding using `/dev/dri/renderD128`.

**Find your GPU group ID:**

```bash
stat -c '%g' /dev/dri/renderD128
```

The compose file uses `group_add: video` which works for most systems. If transcoding fails, update the group ID:

```yaml
group_add:
  - "YOUR_GID_HERE"  # e.g., "44" or "109"
```

### Timezone

All services use `Europe/Istanbul` timezone. Change in the common environment:

```yaml
x-common-keys: &common-keys
  environment: &common-env
    TZ: Your/Timezone
```

## WARP Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WARP_MODE` | `warp` | Operation mode (see below) |
| `WARP_LISTEN_PORT` | `40000` | SOCKS5 proxy port (proxy mode only) |

### WARP Modes

- `warp` - Full VPN tunnel (default)
- `doh` - DNS over HTTPS only
- `warp+doh` - WARP tunnel + DNS over HTTPS
- `dot` - DNS over TLS only
- `warp+dot` - WARP tunnel + DNS over TLS
- `proxy` - SOCKS5 proxy mode

## Health & Status

### Check WARP Status

```bash
# Connection status
docker exec cloudflare-warp warp-cli --accept-tos status

# Verify IP is changed
docker exec cloudflare-warp curl -s https://cloudflare.com/cdn-cgi/trace

# Check health
docker inspect --format='{{.State.Health.Status}}' cloudflare-warp
```

### View Logs

```bash
# WARP logs
docker logs cloudflare-warp

# Any service logs
docker logs radarr
docker logs sonarr
docker logs qbittorrent
```

## Troubleshooting

### WARP Container Fails to Start

Ensure TUN device support:

```bash
ls -la /dev/net/tun
```

### WARP Connection Issues

```bash
# Reconnect
docker exec cloudflare-warp warp-cli --accept-tos disconnect
docker exec cloudflare-warp warp-cli --accept-tos connect

# Reset registration
docker exec cloudflare-warp warp-cli --accept-tos registration delete
docker exec cloudflare-warp warp-cli --accept-tos registration new
```

### Jellyfin Transcoding Not Working

1. Verify GPU access:
   ```bash
   docker exec jellyfin ls -la /dev/dri/
   ```

2. Check group membership:
   ```bash
   stat -c '%g' /dev/dri/renderD128
   ```

3. Update `group_add` with the correct GID

### Services Can't Reach Each Other

All services share the WARP network. Use localhost for inter-service communication:
- Radarr → qBittorrent: `localhost:8080`
- Prowlarr → FlareSolverr: `localhost:8191`

## Volumes

| Volume | Purpose |
|--------|---------|
| `warp-data` | WARP registration data |
| `radarr-config` | Radarr configuration |
| `sonarr-config` | Sonarr configuration |
| `lidarr-config` | Lidarr configuration |
| `bazarr-config` | Bazarr configuration |
| `prowlarr-config` | Prowlarr configuration |
| `qbittorrent-config` | qBittorrent configuration |
| `jellyfin-config` | Jellyfin configuration |
| `data` | Shared media and downloads |

## Notes

- WARP runs as a **non-registered (free) user**
- Registration data persists in Docker volume to avoid re-registering on restart
- All *arr services wait for WARP to be healthy before starting
- Jellyfin has read-only access to the data volume (`:ro`)
- Port 7359/UDP is for Jellyfin auto-discovery on local network
