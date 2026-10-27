# 360T7 闭源无线固件编译器（ImmortalWrt 24.10 + mt_wifi 7.6.6.1）

用 GitHub Actions 编译 **360T7** 的 ImmortalWrt 固件，无线走 MTK 原厂闭源驱动。

## 事实依据

| 项 | 值 | 出处 |
|---|---|---|
| 源码 | `padavanonly/immortalwrt-mt798x-24.10` 分支 `openwrt-24.10-6.6` | 仓库 |
| 内核 | 6.6.133 | 分支提交记录 |
| 无线驱动 | `mt_wifi` **7.6.6.1-mt7981** | `package/mtk/drivers/mt_wifi/Makefile` 的 `PKG_VERSION` |
| 设备 id | **`mt7981-360-t7-108M`** | 仓库 `defconfig/mt7981-ax3000.config` 里已默认选中 |
| 加速 | `kmod-mediatek_hnat` + WARP v2 + `MTK_MT7981_NEW_FW` | 同一 defconfig |

**关键结论：不需要改 dts，不需要自己写设备定义。** 这个 fork 自带的 mt7981 defconfig 里，360T7 的闭源版本（108M 分区）本来就是选中的，`kmod-mt_wifi=y`、没有 `kmod-mt7915e`。这套流水线做的事就是把它单独拎出来编译，省掉其余十几个机型的编译时间。

## 怎么用

### 方式 A：一条命令全自动（推荐）

```bash
# 在 360t7-mtwifi-builder 目录下
GITHUB_TOKEN=ghp_xxxxxxxx python publish.py
```

脚本会依次：建仓库 → 提交推送 → 放开 Actions 写权限 → 触发编译 → 打印运行链接。token 只存在于环境变量里，不写入 `.git/config`，不落地任何文件。

Token 权限（fine-grained）：`Administration=write`、`Contents=write`、`Actions=write`、`Workflows=write`；或直接 classic token 勾 `repo` + `workflow`。

可选参数：`--repo 名字`、`--private`、`--device mt7981-clt-r30b1-112M`、`--no-build`。

### 方式 B：手动推

1. 在 GitHub 新建一个空仓库（public 的 Actions 时长不限，推荐）。
2. 把本目录下 `.github/` 和 `scripts/` 原样推上去：

   ```bash
   git init
   git add .github scripts README.md
   git commit -m "init"
   git branch -M main
   git remote add origin git@github.com:<你的用户名>/<仓库名>.git
   git push -u origin main
   ```

3. 进仓库 **Actions** → 左侧 `build-360t7` → **Run workflow** → 直接点绿色的 Run。
   - 想换设备就在 `device` 输入框里改（比如 `mt7981-clt-r30b1-112M`）。
4. 等 50~90 分钟。编译完成会同时产出：
   - **Artifact**：`immortalwrt-24.10-mtwifi-mt7981-360-t7-108M`
   - **Release**：`build-YYYYMMDD-<run号>`，带 sha256sums

产物形如：

```
immortalwrt-mediatek-filogic-mt7981-360-t7-108M-squashfs-sysupgrade.bin
immortalwrt-mediatek-filogic-mt7981-360-t7-108M-squashfs-factory.bin
sha256sums
*.manifest
```

以 `bin/targets/mediatek/filogic/` 里实际产物为准（workflow 会把所有含 `360` 的文件都收走）。

## 刷机前提

`mt7981-360-t7-108M` = **108M ubi 分区**布局，对应 dts 里 `ubi` 从 `0x580000` 起、长度 `0x6c00000`。

**原厂 uboot 起不来这个固件。** 必须先刷支持 108M 分区的改版 uboot（hanwckf 的 `bl-mt798x` 或同类的 7981 multi-layout uboot），再从 uboot 的 web 恢复页刷 `factory.bin`，之后升级走 `sysupgrade.bin`。

不想动 bootloader 就别用这个，去用 hanwckf 21.02 线的 36M 版本。

## 校验脚本干了什么

`scripts/verify-config.sh` 在 `make defconfig` 之后强制检查 7 项，任一项不对就红叉退出，并在日志里打印源码树中所有含 `360` 的设备定义和 `.config` 里所有可用设备。这是防 defconfig 里的设备符号跟源码树对不上（符号失效时 `make defconfig` 会静默丢弃，最后编译出一堆空产物）。

检查项：

- `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_mt7981-360-t7-108M=y`
- `CONFIG_PACKAGE_kmod-mt_wifi=y`
- `CONFIG_MTK_CHIP_MT7981=y`
- `CONFIG_MTK_MT7981_NEW_FW=y`
- `CONFIG_MTK_WARP_V2=y`
- `CONFIG_PACKAGE_kmod-mediatek_hnat=y`
- `CONFIG_PACKAGE_kmod-mt7915e` **不存在**

## 已知风险

1. **360T7 + mt_wifi 没有官方验证记录。** 这个 fork 里 360T7 的闭源设备定义存在，但我没找到别人实测报告。最大的不确定点是 eeprom：360T7 的 dts 用 `mediatek,mtd-eeprom = <&factory 0x0>`（mt76 的写法），而 rax3000m 的闭源变体 dts 里 `&wifi` 是空的、由驱动自己找 Factory 分区。如果刷完 WiFi 起不来，先在串口里 `cat /proc/mtd` 确认 Factory 分区名，再决定要不要改 dts。
2. **`kmod-mt7915e` 绝对不能和 `mt_wifi` 共存**，两个驱动抢同一块硬件。脚本已经拦了。
3. **每次上游更新都会重新拉源码**，行为可能变。第一次跑成功之后，把成功的 commit hash 记下来；上游改动导致翻车时用它复现（workflow 里 `git log -1` 会打印）。
4. 编译超过 6 小时会被 GitHub 掐断。`timeout-minutes: 350` 是保险，正常用不到。

## 想加插件

改 `scripts/prepare-config.sh`，在最后追加：

```bash
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-theme-argon=y
EOF
```

加完跑一次 Actions，如果 `make defconfig` 阶段报依赖缺失，去 `feeds.conf.default` 里补源。别在 defconfig 里加仓库没有的包，会直接卡在 `make download`。
