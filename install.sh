#!/bin/bash
# Dressmaker 繁體中文化補丁（macOS / Apple Silicon）
#   安裝：curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash
#   還原：curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash -s restore
#   檢查：curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash -s check
set -euo pipefail
REPO="${DRESSMAKER_ZHTW_REPO:-linyunchieh/dressmaker-zhtw-mac}"
BASE="${DRESSMAKER_ZHTW_BASE:-https://github.com/$REPO/releases/latest/download}"
CMD="${1:-install}"
case "$CMD" in install|restore|check) ;; *) echo "用法：bash install.sh [install|restore|check] [--game <資料夾>]"; exit 2;; esac

if [ "$(uname -m)" != arm64 ]; then
    echo "這個補丁只支援 Apple Silicon（M 系列晶片）的 Mac。" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "下載補丁工具…"
curl -fsSL "$BASE/zhtw-patcher-arm64" -o "$TMP/zhtw-patcher"
curl -fsSL "$BASE/SHA256SUMS.txt" -o "$TMP/SHA256SUMS.txt"
expected="$(awk '$2=="zhtw-patcher-arm64"{print $1}' "$TMP/SHA256SUMS.txt")"
actual="$(shasum -a 256 "$TMP/zhtw-patcher" | awk '{print $1}')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "下載的檔案校驗失敗，請稍後再試。" >&2
    exit 1
fi
chmod +x "$TMP/zhtw-patcher"
"$TMP/zhtw-patcher" "$CMD" "${@:2}"
