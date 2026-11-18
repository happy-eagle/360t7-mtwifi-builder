#!/usr/bin/env bash
# 在 hanwckf/immortalwrt-mt798x @ openwrt-21.02 源码树根目录执行。
# 基于仓库自带 defconfig，只保留目标设备，确保闭源 mt_wifi + UPnP 选中。
set -euo pipefail

DEVICE="${1:-h3c_nx30pro}"
DEFCONFIG="defconfig/mt7981-ax3000.config"

[ -f "$DEFCONFIG" ] || { echo "找不到 $DEFCONFIG"; exit 1; }
cp -f "$DEFCONFIG" .config

# 5.4 树的目标符号是 mediatek_mt7981（不是 24.10 的 mediatek_filogic）
PREFIX="CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_"

# 1. 关掉 defconfig 里默认全选的 52 个设备
sed -i -E "s|^${PREFIX}(.+)=y\$|# ${PREFIX}\1 is not set|" .config

# 2. 只打开目标设备
if grep -q "^# ${PREFIX}${DEVICE} is not set$" .config; then
  sed -i "s|^# ${PREFIX}${DEVICE} is not set$|${PREFIX}${DEVICE}=y|" .config
elif ! grep -q "^${PREFIX}${DEVICE}=y$" .config; then
  echo "${PREFIX}${DEVICE}=y" >> .config
fi

echo "===== 目标设备 ====="
grep -E "^${PREFIX}.*=y$" .config || { echo "没有选中任何设备"; exit 1; }

# 3. 必须有的包（defconfig 已带，这里做幂等确保）
#    5.4 是 firewall3/iptables，UPnP 只能用 miniupnpd，不存在 nftables 变体
ADD="kmod-mt_wifi kmod-warp kmod-mediatek_hnat wifi-dats mtwifi-cfg \
     luci-app-mtwifi-cfg luci-i18n-mtwifi-cfg-zh-cn \
     miniupnpd luci-app-upnp luci-i18n-upnp-zh-cn"
for sym in $ADD; do
  if grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config; then
    continue
  fi
  sed -i -E "s|^# CONFIG_PACKAGE_${sym} is not set$|CONFIG_PACKAGE_${sym}=y|" .config
  grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config || echo "CONFIG_PACKAGE_${sym}=y" >> .config
done

# 4. 开源 mt76 驱动与闭源 mt_wifi 冲突，明确关掉
DROP="kmod-mt7915e kmod-mt7916e kmod-mt7996e miniupnpd-nftables"
for sym in $DROP; do
  sed -i -E "s|^CONFIG_PACKAGE_${sym}=y$|# CONFIG_PACKAGE_${sym} is not set|" .config
  grep -qE "^# CONFIG_PACKAGE_${sym} is not set$" .config || \
    echo "# CONFIG_PACKAGE_${sym} is not set" >> .config
done

echo "===== 关键包 ====="
for sym in kmod-mt_wifi kmod-warp kmod-mediatek_hnat miniupnpd luci-app-upnp luci-i18n-upnp-zh-cn; do
  grep -qE "^CONFIG_PACKAGE_${sym}=y$" .config && echo "  + ${sym}" || echo "  ! ${sym}（将校验）"
done
