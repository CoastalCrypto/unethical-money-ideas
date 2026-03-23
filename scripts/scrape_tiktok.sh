#!/bin/bash
CHANNEL="dirtydollars1"
OUTPUT_DIR="/home/ren/projects/unethical-money-ideas/data"
mkdir -p "$OUTPUT_DIR"

echo "Scraping ALL videos for @$CHANNEL..."
# Remove limit, use --match-filter to only pull videos if necessary
yt-dlp -x --audio-format mp3 --output "$OUTPUT_DIR/%(title)s.%(ext)s" "https://tiktok.com/@$CHANNEL"
echo "Download complete."
