#!/usr/bin/env bash
# 导出网页版并部署到 Railway。
# 用法（仓库根目录）：bash game/tools/release/deploy.sh            # 导出 + 上传
#                     bash game/tools/release/deploy.sh --no-upload # 只导出到 deploy/web/public
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="$ROOT/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
OUT="$ROOT/deploy/web/public"
mkdir -p "$OUT"
rm -f "$OUT"/index.*
"$GODOT" --headless --path "$ROOT/game" --export-release Web "$OUT/index.html" < /dev/null > /dev/null
ls -la "$OUT"
if [[ "${1:-}" != "--no-upload" ]]; then
  cd "$ROOT/deploy/web"
  railway up --detach
fi
