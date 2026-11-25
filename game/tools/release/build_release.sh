#!/usr/bin/env bash
# 一键打包发布物（仓库根目录运行）：bash game/tools/release/build_release.sh
#   dist/ShenShu-<版本>-Setup.exe    Windows 安装包（含游戏运行时，玩家不需要另装 Godot）
#   dist/ShenShu-<版本>-win64.zip    免安装版（解压即玩）
#   dist/ShenShu-<版本>-web.zip      网页版文件（任意静态服务器可托管；deploy/web/public 同时更新，供 Railway 部署）
# 首次使用：python game/tools/release/fetch_templates.py（导出模板），winget install JRSoftware.InnoSetup
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
REL="$ROOT/game/tools/release"
GODOT="$ROOT/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
ISCC="${ISCC:-$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe}"
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/game/project.godot")"
DIST="$ROOT/dist"
WIN="$DIST/win"
WEB="$ROOT/deploy/web/public"
echo "== 神树 v$VER"
# exe 的图标与版本号由导出预设里的 application/* 写入（Godot 内置，不需要 rcedit）；改版本号时记得同步 export_presets.cfg 的 file_version / product_version
rm -f "$WIN"/ShenShu.* "$DIST"/ShenShu-*
mkdir -p "$WIN" "$WEB"
rm -f "$WEB"/index.*

echo "== 导出 Windows"
"$GODOT" --headless --path "$ROOT/game" --export-release Windows "$WIN/ShenShu.exe" < /dev/null > /dev/null
rm -f "$WIN"/*.console.exe

echo "== 导出网页"
"$GODOT" --headless --path "$ROOT/game" --export-release Web "$WEB/index.html" < /dev/null > /dev/null

echo "== 打包"
( cd "$WIN" && powershell -NoProfile -Command "Compress-Archive -Path ShenShu.exe,ShenShu.pck -DestinationPath '$(cygpath -w "$DIST/ShenShu-$VER-win64.zip")' -Force" )
( cd "$WEB" && powershell -NoProfile -Command "Compress-Archive -Path * -DestinationPath '$(cygpath -w "$DIST/ShenShu-$VER-web.zip")' -Force" )
( cd "$REL" && MSYS_NO_PATHCONV=1 "$ISCC" /Q "/DAppVersion=$VER" "/DSrcDir=$(cygpath -w "$WIN")" "/DOutDir=$(cygpath -w "$DIST")" installer.iss )
ls -la "$DIST"
