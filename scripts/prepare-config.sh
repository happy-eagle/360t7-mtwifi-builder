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

# 3. 裁掉闭源驱动方案里用不上的包（能省约 1.7MB flash）
#    wpad/hostapd：闭源 mt_wifi 自己接管 AP，根本不走 hostapd。
#                  装了只会让 /etc/init.d/wpad 开机报错刷日志。
#    kmod-usb-xhci-mtk：360T7 没有 USB 口。
# 注意：如果这些包是被别的包 DEPENDS 硬拉进来的，make defconfig 会自动把它们
# 加回来，这里不报错——verify-config.sh 会用 warning 提示，不影响编译。
TRIM="wpad-openssl wpad-basic-mbedtls wpad-mbedtls hostapd hostapd-common kmod-usb-xhci-mtk"
for sym in $TRIM; do
  sed -i -E "s|^CONFIG_PACKAGE_${sym}=y$|# CONFIG_PACKAGE_${sym} is not set|" .config
  grep -qE "^# CONFIG_PACKAGE_${sym} is not set$" .config || \
    echo "# CONFIG_PACKAGE_${sym} is not set" >> .config
done

echo "===== 已请求裁掉的包 ====="
for sym in $TRIM; do
  grep -E "^# CONFIG_PACKAGE_${sym} is not set$" .config >/dev/null && echo "  - ${sym}"
done

# 4. 追加 UPnP + 主题
#    miniupnpd-nftables：本固件用 firewall4/nftables，必须选 nftables 变体，
#                         iptables 变体与之 CONFLICTS。
#    luci-theme-argon：ImmortalWrt 官方 24.10 维护，带 ucode 模板，保证可用。
#    luci-theme-design：第三方，靠 add-theme-design.sh 克隆进来，可能不渲染（见 README）。
ADD="luci-app-upnp miniupnpd-nftables luci-i18n-upnp-zh-cn \
     luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn \
     luci-theme-design"

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
