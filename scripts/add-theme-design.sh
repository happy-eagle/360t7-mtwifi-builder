#!/usr/bin/env bash
# 在 openwrt/ 目录下、feeds install 之前执行：把第三方 design 主题放进 package/
#
# 来源：lgs2007m/luci-theme-design 分支 openwrt-25.12（带 ucode 模板的版本）
#   - 0x676e67 和 papagaye744 那两版只有 luasrc/*.htm，是 Lua 时代的老机制，
#     LuCI 24.10 只认 ucode/template/themes/<name>/*.ut，装上去会白屏。
#   - lgs2007m 这版有 ucode/template/themes/design/{header,footer,sysauth}.ut
#     和 htdocs/luci-static/resources/menu-design.js，是能跑的。
#
# 注意：该主题面向 OpenWrt 25.12，我们的树是 24.10，模板 API 有细微差异，
#       不保证 100% 正常。默认主题仍是 bootstrap，design 只是装进去备选。
set -euo pipefail

REPO="https://github.com/lgs2007m/luci-theme-design.git"
BRANCH="openwrt-25.12"
DEST="package/luci-theme-design"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "===== 克隆 design 主题 ($BRANCH) ====="
git clone --depth=1 --single-branch --branch "$BRANCH" "$REPO" "$TMP/src" 2>&1 | tail -3

SRC="$TMP/src/luci-theme-design"
[ -f "$SRC/Makefile" ] || { echo "克隆下来的目录结构不对，找不到 luci-theme-design/Makefile"; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/

# 校验：没有 ucode 模板就是白屏货，直接失败，别浪费 60 分钟编译
for f in ucode/template/themes/design/header.ut \
         ucode/template/themes/design/footer.ut \
         htdocs/luci-static/resources/menu-design.js; do
  [ -f "$DEST/$f" ] || { echo "缺少 $f —— 这个版本不能用在 LuCI 24.10 上"; exit 1; }
done

echo "===== design 主题就位 ====="
grep -E "PKG_VERSION|PKG_RELEASE" "$DEST/Makefile" || true
echo "  ucode 模板: $(find "$DEST/ucode" -name '*.ut' | wc -l) 个"
echo "  menu js:    $(ls "$DEST/htdocs/luci-static/resources" 2>/dev/null | tr '\n' ' ')"
