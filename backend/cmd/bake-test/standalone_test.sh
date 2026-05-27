#!/usr/bin/env bash
# Quick standalone test of the FFmpeg + libass pipeline using synthetic
# input — no Postgres / R2 required. Generates a 10s color bar with
# 3 fake chat lines burned in as ASS subtitles. Run from this folder:
#   bash standalone_test.sh
# Then play ./standalone_out.mp4 to verify Vietnamese rendering works.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ASS="$HERE/standalone.ass"
OUT="$HERE/standalone_out.mp4"

cat > "$ASS" <<'EOF'
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: ChatBox,Arial,32,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,3,2,0,1,40,40,40,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:09.00,ChatBox,,0,0,180,,{\1c&H0000D7FF\b1}Trợ lý AI:{\b0\1c&H00FFFFFF} Cảnh chua tôm 75.000đ — flash sale hôm nay 🎉
Dialogue: 0,0:00:03.00,0:00:09.00,ChatBox,,0,0,240,,{\1c&H00FFFFFF\b1}Nguyễn Văn B:{\b0\1c&H00FFFFFF} Shop ơi có giảm giá thêm không ạ?
Dialogue: 0,0:00:05.00,0:00:09.00,ChatBox,,0,0,300,,{\1c&H00FF80C0\b1}Bot:{\b0\1c&H00FFFFFF} Dạ tối nay 20h có thêm mã giảm 30k ạ.
EOF

# On Windows, FFmpeg filters parse `:` as an option separator; an
# absolute path like C:/... gets cut at the colon. Two workarounds:
# (1) cd into the dir + pass basename; (2) escape and quote. We use (1).
ASS_DIR=$(dirname "$ASS")
ASS_BASENAME=$(basename "$ASS")
cd "$ASS_DIR"

# Generate 10s blue color bar at 1080x1920 + silent audio, burn subtitles.
ffmpeg -y \
  -f lavfi -i color=c=0x1e3a5f:s=1080x1920:d=10 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -t 10 \
  -vf "subtitles=$ASS_BASENAME" \
  -c:v libx264 -preset veryfast -crf 23 \
  -c:a aac -shortest \
  -movflags +faststart \
  "$OUT" 2>&1 | tail -20

echo "---"
echo "Output: $OUT"
ls -la "$OUT"
