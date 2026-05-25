#!/usr/bin/env bash
set -e

mkdir -p www

# Copy index.html to www/
cp index.html www/index.html

# opencv.js: use local cache if present, otherwise download from GitHub Releases
if [ -f opencv.js ]; then
  echo "Copying local opencv.js to www/"
  cp opencv.js www/opencv.js
else
  echo "Downloading opencv.js from GitHub Releases..."
  LATEST=$(curl -s https://api.github.com/repos/opencv/opencv/releases/latest \
    | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  echo "Latest OpenCV release: $LATEST"
  curl -L -o /tmp/opencv-docs.zip \
    "https://github.com/opencv/opencv/releases/download/${LATEST}/opencv-${LATEST}-docs.zip"
  unzip -j /tmp/opencv-docs.zip "js/bin/opencv.js" -d www/
  rm /tmp/opencv-docs.zip
fi

echo "www/ build complete."
ls -lh www/
