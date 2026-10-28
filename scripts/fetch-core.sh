#!/usr/bin/env bash
# 下载 mihomo(Meta) 内核并放进 openwrt/files，随固件一起打包
#
# 用法: fetch-core.sh <目标目录> [内核类型]
#   fetch-core.sh files/etc/openclash/core        # 默认 meta
#
# 为什么不用设备自动下载：raw.githubusercontent.com 国内基本不可达。
# 这里在 CI 上抓（runner 有外网），失败自动切 jsdelivr CDN。
set -euo pipefail

DEST_DIR="${1:?用法: fetch-core.sh <目标目录> [meta]}"
CORE_KIND="${2:-meta}"          # meta | smart
ARCH="linux-arm64"              # MT7981 = Cortex-A53, aarch64

BRANCH="${OPENCLASH_CORE_BRANCH:-master}"

# 允许测试时用本地文件替代
if [ -n "${CORE_URL:-}" ]; then
  URLS=("$CORE_URL")
else
  URLS=(
    "https://raw.githubusercontent.com/vernesong/OpenClash/core/${BRANCH}/${CORE_KIND}/clash-${ARCH}.tar.gz"
    "https://cdn.jsdelivr.net/gh/vernesong/OpenClash@core/${BRANCH}/${CORE_KIND}/clash-${ARCH}.tar.gz"
  )
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TGZ="$WORK/core.tar.gz"
OK=0
for u in "${URLS[@]}"; do
  echo "下载: $u"
  if curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 -m 600 -o "$TGZ" "$u"; then
    SZ=$(stat -c %s "$TGZ" 2>/dev/null || echo 0)
    if [ "$SZ" -gt 1000000 ]; then
      echo "  下载成功，$((SZ/1024/1024)) MB"
      OK=1
      break
    fi
    echo "  文件过小（$SZ 字节），换下一个源"
  else
    echo "  失败，换下一个源"
  fi
done
[ "$OK" = "1" ] || { echo "::error::所有内核下载源都失败"; exit 1; }

echo "解包..."
( cd "$WORK" && tar -xzf core.tar.gz )
BIN="$WORK/clash"
[ -f "$BIN" ] || { echo "::error::压缩包里没有 clash 文件"; ls -l "$WORK"; exit 1; }

# 校验 aarch64 ELF，防止拿到错误架构（x86 上跑不了，只能读头）
MAGIC=$(od -An -tx1 -j0 -N4 "$BIN" | tr -d ' \n')
CLASS=$(od -An -tx1 -j4 -N1 "$BIN" | tr -d ' \n')
MACH=$(od -An -tx1 -j18 -N2 "$BIN" | tr -d ' \n')
echo "ELF: magic=$MAGIC class=$CLASS machine=$MACH"
[ "$MAGIC" = "7f454c46" ] || { echo "::error::不是 ELF 文件"; exit 1; }
[ "$CLASS" = "02" ]       || { echo "::error::不是 64 位 ELF"; exit 1; }
[ "$MACH"  = "b700" ]     || { echo "::error::不是 AArch64（期望 machine=b700，实际 $MACH）"; exit 1; }
echo "架构校验通过: AArch64"

mkdir -p "$DEST_DIR"
install -m 4755 "$BIN" "$DEST_DIR/clash_meta"

BSZ=$(stat -c %s "$DEST_DIR/clash_meta")
echo "已放置: $DEST_DIR/clash_meta  $((BSZ/1024/1024)) MB  $(sha256sum "$DEST_DIR/clash_meta" | cut -c1-16)…"
[ "$BSZ" -gt 5000000 ] || { echo "::error::内核体积异常（$BSZ 字节），可能下到了错误文件"; exit 1; }
echo "内核打包准备完成（$CORE_KIND / $ARCH / $BRANCH）"
