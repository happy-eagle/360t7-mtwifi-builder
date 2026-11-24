#!/usr/bin/env bash
# 在 make defconfig 之后执行，校验 360T7 5.4 闭源方案的关键开关。
set -uo pipefail

DEVICE="mt7981-360-t7-108M"
FAIL=0

check() {
  local desc="$1" pat="$2" want="$3"
  if [ "$want" = "y" ]; then
    if grep -qE "$pat" .config; then echo "[ OK ] $desc"
    else echo "[FAIL] $desc"; FAIL=1; fi
  else
    if grep -qE "$pat" .config; then echo "[FAIL] $desc（不该启用）"; FAIL=1
    else echo "[ OK ] $desc"; fi
  fi
}

PREFIX="CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_"

check "mediatek/mt7981 目标"          "^CONFIG_TARGET_mediatek_mt7981=y" y
check "360T7 108M 变体已选中"         "^${PREFIX}${DEVICE}=y" y
check "36M 变体未选中"                "^${PREFIX}mt7981-360-t7=y" n

N=$(grep -cE "^${PREFIX}.+=y$" .config || true)
echo "  实际选中设备数: $N"
if [ "$N" -ne 1 ]; then
  echo "[FAIL] 期望 1 台，实际 $N 台 —— 会编出一堆用不到的镜像"
  FAIL=1
fi

check "闭源驱动 kmod-mt_wifi"         "^CONFIG_PACKAGE_kmod-mt_wifi=y" y
check "MT7981 芯片"                   "^CONFIG_MTK_CHIP_MT7981=y" y
check "MT7981 第一接口"               "^CONFIG_MTK_FIRST_IF_MT7981=y" y
check "WARP v2"                       "^CONFIG_MTK_WARP_V2=y" y
check "硬件 NAT"                      "^CONFIG_PACKAGE_kmod-mediatek_hnat=y" y
check "开源 mt76 未启用"              "^CONFIG_PACKAGE_kmod-mt7915e=y" n

check "UPnP: miniupnpd"               "^CONFIG_PACKAGE_miniupnpd=y" y
check "UPnP: luci-app-upnp"           "^CONFIG_PACKAGE_luci-app-upnp=y" y
check "UPnP: 中文语言包"              "^CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" y
check "UPnP: nftables 变体未启用"     "^CONFIG_PACKAGE_miniupnpd-nftables=y" n

check "默认主题 bootstrap 已启用"     "^CONFIG_PACKAGE_luci-theme-bootstrap=y" y
check "argon 主题未启用"              "^CONFIG_PACKAGE_luci-theme-argon=y" n

echo "----- 驱动版本 -----"
if grep -qE '^CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y$' .config; then
  echo "  mt_wifi 7.6.7.3-mt7981（hanwckf 21.02 defconfig 默认）"
elif grep -qE '^CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7661=y$' .config; then
  echo "  mt_wifi 7.6.6.1-mt7981"
else
  echo "[FAIL] 没找到 mt_wifi 驱动版本开关"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "===== 源码树里 360T7 相关定义 ====="
  grep -nE '^(define Device/|TARGET_DEVICES \+=).*360-t7' \
    target/linux/mediatek/image/mt7981.mk || echo "（一个都没有）"
  exit 1
fi

echo "校验通过。"
