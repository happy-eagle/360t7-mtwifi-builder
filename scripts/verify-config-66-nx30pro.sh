#!/usr/bin/env bash
# 在 openwrt/ 目录下、make defconfig 之后执行：校验闭源驱动 + NX30 Pro 设备 + UPnP
set -uo pipefail

DEVICE="h3c_magic-nx30-pro-nmbm"
FAIL=0

check() {
  local desc="$1" pat="$2" want="$3"
  if [ "$want" = "y" ]; then
    if grep -qE "$pat" .config; then
      echo "[ OK ] $desc"
    else
      echo "[FAIL] $desc"
      FAIL=1
    fi
  else
    if grep -qE "$pat" .config; then
      echo "[FAIL] $desc（不该启用）"
      FAIL=1
    else
      echo "[ OK ] $desc"
    fi
  fi
}

check "设备 ${DEVICE} 已选中"        "^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE}=y" y
check "只选中一台设备"               "^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.+=y$" y
check "闭源无线 kmod-mt_wifi"        "^CONFIG_PACKAGE_kmod-mt_wifi=y" y
check "MTK 芯片 MT7981"              "^CONFIG_MTK_CHIP_MT7981=y" y
check "MTK 新固件 MT7981_NEW_FW"     "^CONFIG_MTK_MT7981_NEW_FW=y" y
check "WARP v2"                      "^CONFIG_MTK_WARP_V2=y" y
check "硬件 NAT kmod-mediatek_hnat"  "^CONFIG_PACKAGE_kmod-mediatek_hnat=y" y
check "开源驱动 kmod-mt7915e 未启用" "^CONFIG_PACKAGE_kmod-mt7915e=y" n
check "开源固件 kmod-mt7981-firmware 未启用" "^CONFIG_PACKAGE_kmod-mt7981-firmware=y" n
check "UPnP: miniupnpd-nftables"     "^CONFIG_PACKAGE_miniupnpd-nftables=y" y
check "UPnP: luci-app-upnp"          "^CONFIG_PACKAGE_luci-app-upnp=y" y
check "UPnP: 中文语言包"             "^CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" y
check "UPnP: iptables 变体未启用"    "^CONFIG_PACKAGE_miniupnpd-iptables=y" n
check "argon 主题未启用"             "^CONFIG_PACKAGE_luci-theme-argon=y" n

# "只选中一台设备" 上面那条只是存在性检查，这里做真实计数
N=$(grep -cE "^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.+=y$" .config || true)
echo "  实际选中设备数: $N"
if [ "$N" -ne 1 ]; then
  echo "[FAIL] 期望只选中 1 台设备，实际 $N 台"
  FAIL=1
fi

echo "----- 驱动版本（24.10 默认 7.6.6.1） -----"
if grep -qE '^CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7661=y' .config; then
  echo "  mt_wifi 7.6.6.1-mt7981（正确）"
elif grep -qE '^CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y' .config; then
  echo "  mt_wifi 7.6.7.3-mt7981（注意：非本分支默认）"
else
  echo "[WARN] 未找到明确的驱动版本开关，以 manifest 为准"
fi

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "===== 源码树里 NX30 相关的设备定义 ====="
  grep -nE '^(define Device/|TARGET_DEVICES \+=).*nx30' \
    target/linux/mediatek/image/filogic.mk || echo "（一个都没有）"
  echo
  echo "===== 当前 .config 里所有可用设备 ====="
  grep -oE 'DEVICE_mediatek_filogic_DEVICE_[A-Za-z0-9_.-]+' .config | sort -u || true
  exit 1
fi

echo "校验通过。"
