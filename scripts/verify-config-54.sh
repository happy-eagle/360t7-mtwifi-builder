#!/usr/bin/env bash
# 在 make defconfig 之后执行，校验 5.4 闭源方案的关键开关。
set -uo pipefail

DEVICE="${1:-h3c_nx30pro}"
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

check "mediatek/mt7981 目标"        "^CONFIG_TARGET_mediatek_mt7981=y" y
check "设备 ${DEVICE} 已选中"       "^${PREFIX}${DEVICE}=y" y
check "只选中一台设备"              "^${PREFIX}.+=y$" y

# 数一下选中设备数量
N=$(grep -cE "^${PREFIX}.+=y$" .config || true)
echo "  实际选中设备数: $N"
if [ "$N" -ne 1 ]; then
  echo "[FAIL] 期望 1 台，实际 $N 台 —— 会编出一堆用不到的镜像"
  FAIL=1
fi

check "闭源驱动 kmod-mt_wifi"       "^CONFIG_PACKAGE_kmod-mt_wifi=y" y
check "MT7981 芯片"                 "^CONFIG_MTK_CHIP_MT7981=y" y
check "MT7981 第一接口"             "^CONFIG_MTK_FIRST_IF_MT7981=y" y
check "WARP v2"                     "^CONFIG_MTK_WARP_V2=y" y
check "硬件 NAT"                    "^CONFIG_PACKAGE_kmod-mediatek_hnat=y" y
check "开源 mt76 未启用"            "^CONFIG_PACKAGE_kmod-mt7915e=y" n

check "UPnP: miniupnpd"             "^CONFIG_PACKAGE_miniupnpd=y" y
check "UPnP: luci-app-upnp"         "^CONFIG_PACKAGE_luci-app-upnp=y" y
check "UPnP: 中文语言包"            "^CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" y

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
  echo "===== 源码树里 NX30 相关定义 ====="
  grep -nE '^(define Device/|TARGET_DEVICES \+=).*nx30' \
    target/linux/mediatek/image/mt7981.mk || echo "（一个都没有）"
  exit 1
fi

echo "校验通过。"
