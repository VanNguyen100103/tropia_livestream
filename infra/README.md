# Tropia Live - Infrastructure

Docker Compose stack for local development.

## Services

| Service | Port | Purpose |
|---|---|---|
| Postgres | 5432 | Main DB |
| Redis | 6379 | Chat pub/sub, session cache |
| SRS | 1935 (RTMP), 8080 (HLS), 1985 (HTTP API + WHIP), 8000/udp (WebRTC), 10080/udp (SRT) | Media server |

## Start

```bash
cd infra
docker compose up -d
```

## Check status

```bash
docker compose ps
docker compose logs -f srs
```

## SRS endpoints

- **Push RTMP**: `rtmp://localhost:1935/live/{stream_key}`
- **Push SRT**: `srt://localhost:10080?streamid=#!::r=live/{stream_key},m=publish`
- **WHIP (WebRTC publish)**: `http://localhost:1985/rtc/v1/whip/?app=live&stream={stream_key}`
- **HLS playback**: `http://localhost:8080/live/{stream_key}.m3u8`
- **WHEP (WebRTC playback)**: `http://localhost:1985/rtc/v1/whep/?app=live&stream={stream_key}`
- **SRS HTTP API**: `http://localhost:1985/api/v1/`

## Test stream (with ffmpeg)

Push a test video file to SRS:

```bash
ffmpeg -re -stream_loop -1 -i test.mp4 -c copy -f flv rtmp://localhost:1935/live/test
```

Then open: `http://localhost:8080/live/test.m3u8` in VLC or browser.

## Reset everything

```bash
docker compose down -v   # -v removes volumes (DB data, recordings)
```
