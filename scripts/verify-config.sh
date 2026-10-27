#!/usr/bin/env bash
# 在 openwrt/ 目录下、make defconfig 之后执行：校验闭源无线驱动 + 目标设备都就位
set -uo pipefail

DEVICE="${1:?用法: verify-config.sh <device-id>}"
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

check "设备 $DEVICE 已选中"        "^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE}=y" y
check "闭源无线 kmod-mt_wifi"      "^CONFIG_PACKAGE_kmod-mt_wifi=y" y
check "MTK 芯片 MT7981"            "^CONFIG_MTK_CHIP_MT7981=y" y
check "MTK 新固件 MT7981_NEW_FW"   "^CONFIG_MTK_MT7981_NEW_FW=y" y
check "WARP v2"                    "^CONFIG_MTK_WARP_V2=y" y
check "硬件 NAT kmod-mediatek_hnat" "^CONFIG_PACKAGE_kmod-mediatek_hnat=y" y
check "开源驱动 kmod-mt7915e 未启用" "^CONFIG_PACKAGE_kmod-mt7915e=y" n

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "===== 源码树里 360 相关的设备定义 ====="
  grep -nE '^(define Device/|TARGET_DEVICES \+=).*360' \
    target/linux/mediatek/image/filogic.mk || echo "（一个都没有）"
  echo
  echo "===== 当前 .config 里所有可用设备 ====="
  grep -oE 'DEVICE_mediatek_filogic_DEVICE_[A-Za-z0-9_.-]+' .config | sort -u || true
  exit 1
fi

echo "校验通过。"
