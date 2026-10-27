#!/usr/bin/env bash
# 在 openwrt/ 目录下执行：用仓库自带 defconfig，只保留目标设备
set -euo pipefail

DEVICE="${1:?用法: prepare-config.sh <device-id>}"
DEFCONFIG="defconfig/mt7981-ax3000.config"

[ -f "$DEFCONFIG" ] || { echo "找不到 $DEFCONFIG"; exit 1; }

cp -f "$DEFCONFIG" .config

# 1. 先把所有已选中的设备关掉（只动 =y 的行，不动 DEVICE_PACKAGES 的 ="" 行）
sed -i -E \
  's|^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_(.+)=y$|# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_\1 is not set|' \
  .config

# 2. 打开目标设备
if grep -q "^# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE} is not set$" .config; then
  sed -i "s|^# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE} is not set$|CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE}=y|" .config
else
  echo "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${DEVICE}=y" >> .config
fi

echo "===== 目标设备: ${DEVICE} ====="
grep -E "^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_.*=y$" .config || echo "（没有选中任何设备）"
