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
| **Seerr** | 5055 | Request manager for movies and TV shows |
| **Jellyfin** | 8096, 7359/udp | Media server with hardware transcoding |

## Quick Start

```bash
cp example.env .env
# Edit .env to set MEDIA_PATH and GID for your system
docker compose up -d
```

## Architecture

All services use `network_mode: "service:cloudflare-warp"` which routes their traffic through the WARP VPN tunnel. Ports are exposed through the cloudflare-warp container.

```
┌─────────────────────────────────────────────────────────┐
│                    Cloudflare WARP                      │
│                    (VPN Gateway)                        │
│  Exposed Ports: 7878, 8989, 8686, 6767, 9696,           │
│                 8080, 6881, 8096, 7359, 8191, 5055      │
└──────────────────────┬──────────────────────────────────┘
                       │ network_mode: service:cloudflare-warp
    ┌──────────┼──────────┼──────────┼───────────┐
    │          │          │          │           │
┌───▼───┐  ┌───▼───┐  ┌───▼───┐  ┌───▼────┐  ┌───▼────┐
│Radarr │  │Sonarr │  │Lidarr │  │Bazarr  │  │ Seerr  │
└───────┘  └───────┘  └───────┘  └────────┘  └────────┘
    │             │             │             │
┌───▼─────┐  ┌────▼────┐  ┌─────▼─────┐  ┌────▼─────┐
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
- **Seerr**: http://localhost:5055
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

### Environment Variables

Copy `example.env` to `.env` and configure the values:

```bash
cp example.env .env
```

| Variable | Description |
|----------|-------------|
| `MEDIA_PATH` | Host path for shared media storage (bind-mounted as the `data` volume) |
| `GID` | Group ID for GPU device access (used by Jellyfin for hardware transcoding) |

**Find your GPU group ID:**

```bash
stat -c '%g' /dev/dri/renderD128
```

Set the `GID` value in your `.env` file:

```
GID=109
```

**Set your media path:**

The `MEDIA_PATH` variable defines the host directory that is bind-mounted as the shared `data` volume. Set it to the absolute path where your media and downloads reside:

```
MEDIA_PATH=/mnt/shared/media
```

This `MEDIA_PATH` is referenced by the `data` volume in `compose.yaml`. Make sure the directory exists on the host before starting the stack.

This `GID` is referenced by Jellyfin's `group_add` directive in `compose.yaml` via `${GID}`, granting the container access to `/dev/dri/renderD128` for hardware transcoding.

### Jellyfin Hardware Transcoding

Jellyfin is configured for GPU hardware transcoding using `/dev/dri/renderD128`. The device group membership is handled via the `GID` environment variable — no manual edits to `compose.yaml` are needed. If transcoding fails, verify that the `GID` in your `.env` file matches the group owning `/dev/dri/renderD128`.

### Seerr Setup

Seerr is a request management tool that allows users to request movies and TV shows. After starting the stack:

1. Access Seerr at http://localhost:5055
2. Complete the initial setup wizard
3. Connect Seerr to your Radarr and Sonarr instances using `localhost:7878` and `localhost:8989` respectively
4. Configure Jellyfin as the media server at `localhost:8096`

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

2. Check the correct GID for your GPU device:
   ```bash
   stat -c '%g' /dev/dri/renderD128
   ```

3. Update the `GID` value in your `.env` file to match, then restart:
   ```bash
   docker compose up -d jellyfin
   ```

### Services Can't Reach Each Other

All services share the WARP network. Use localhost for inter-service communication:
- Radarr → qBittorrent: `localhost:8080`
- Prowlarr → FlareSolverr: `localhost:8191`
- Seerr → Radarr: `localhost:7878`
- Seerr → Sonarr: `localhost:8989`

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
| `seerr-config` | Seerr configuration |
| `data` | Shared media and downloads (bind-mounted from `MEDIA_PATH`) |

## Notes

- WARP runs as a **non-registered (free) user**
- Registration data persists in Docker volume to avoid re-registering on restart
- All *arr services wait for WARP to be healthy before starting
- Jellyfin has read-only access to the data volume (`:ro`)
- Port 7359/UDP is for Jellyfin auto-discovery on local network
