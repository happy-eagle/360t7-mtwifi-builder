#!/usr/bin/env bash
# 在 openwrt/ 目录下、make defconfig 之前执行：追加 OpenClash 及其依赖
#
# 包来源：immortalwrt/luci 的 openwrt-24.10 分支自带 applications/luci-app-openclash，
# PKG_VERSION 0.47.156。不需要额外加 vernesong 上游 feed —— 同名包会被 luci feed 覆盖。
# 依赖清单取自该 Makefile 的 DEPENDS：
#   +luci-compat +dnsmasq-full +bash +curl +ca-bundle +ip-full +ruby
#   +ruby-yaml +kmod-inet-diag +kmod-nft-tproxy +kmod-tun +unzip
set -euo pipefail

[ -f .config ] || { echo "找不到 .config，先跑 prepare-config.sh"; exit 1; }

OC_MK="package/feeds/luci/luci-app-openclash/Makefile"
[ -f "$OC_MK" ] || {
  echo "错误: 找不到 $OC_MK —— feeds install 没把 luci-app-openclash 装进来"
  exit 1
}
echo "[INFO] luci-app-openclash $(grep -m1 '^PKG_VERSION:=' "$OC_MK" | cut -d= -f2 | tr -d ' ') <- $OC_MK"

if grep -q '^CONFIG_PACKAGE_luci-app-openclash=y$' .config; then
  echo "[SKIP] .config 里已有 OpenClash，不重复追加"
  exit 0
fi

# dnsmasq-full 与 dnsmasq 冲突，必须显式关掉后者，不能只靠 kconfig 的 CONFLICTS 推导
sed -i -E 's|^CONFIG_PACKAGE_dnsmasq=y$|# CONFIG_PACKAGE_dnsmasq is not set|' .config

cat >> .config <<'EOF'

# ===== OpenClash =====
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-inet-diag=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_ruby=y
CONFIG_PACKAGE_ruby-yaml=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
EOF

echo "===== 已追加 OpenClash 配置 ====="
grep -E '^CONFIG_PACKAGE_(luci-app-openclash|dnsmasq-full|kmod-tun|kmod-nft-tproxy|luci-compat|ruby)=' .config || true
grep -E '^# CONFIG_PACKAGE_dnsmasq is not set' .config || echo "警告: dnsmasq 未显式关闭"
