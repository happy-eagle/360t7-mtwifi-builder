#!/usr/bin/env bash
# 在 openwrt/ 目录下执行：用仓库自带 defconfig，只保留 H3C NX30 Pro (NMBM)
set -euo pipefail

DEVICE="h3c_magic-nx30-pro-nmbm"
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

# 3. 关掉设备 DEVICE_PACKAGES 默认带来的开源 mt76 驱动。
#    filogic.mk 里 Device/h3c_magic-nx30-pro-nmbm 的 DEVICE_PACKAGES 是
#    kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware（开源方案）。
#    本固件用闭源 mt_wifi 7.6.6.1，两者不能共存，必须显式关掉。
DROP="kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-mt7996e kmod-mt7992e argon"
for sym in $DROP; do
  sed -i -E "s|^CONFIG_PACKAGE_${sym}=y$|# CONFIG_PACKAGE_${sym} is not set|" .config
  grep -qE "^# CONFIG_PACKAGE_${sym} is not set$" .config || \
    echo "# CONFIG_PACKAGE_${sym} is not set" >> .config
done

echo "===== 已请求关闭的包 ====="
for sym in $DROP; do
  grep -qE "^# CONFIG_PACKAGE_${sym} is not set$" .config && echo "  - ${sym}"
done

# 4. 追加 UPnP。
#    24.10 / firewall4 / nftables → 必须用 miniupnpd-nftables，
#    iptables 变体与之 CONFLICTS。不加任何主题（保持 defconfig 的 bootstrap-mod 默认）。
ADD="luci-app-upnp miniupnpd-nftables luci-i18n-upnp-zh-cn"

for sym in $ADD; do
  if grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config; then
    continue
  fi
  sed -i -E "s|^# CONFIG_PACKAGE_${sym} is not set$|CONFIG_PACKAGE_${sym}=y|" .config
  grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config || echo "CONFIG_PACKAGE_${sym}=y" >> .config
done

echo "===== 已追加的包 ====="
for sym in $ADD; do
  grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config && echo "  + ${sym}"
done
