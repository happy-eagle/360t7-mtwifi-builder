# 360T7 闭源无线固件编译器（ImmortalWrt 24.10 + mt_wifi 7.6.6.1）

用 GitHub Actions 编译 **360T7** 的 ImmortalWrt 固件，无线走 MTK 原厂闭源驱动。

## 事实依据

| 项 | 值 | 出处 |
|---|---|---|
| 源码 | `padavanonly/immortalwrt-mt798x-24.10` 分支 `openwrt-24.10-6.6` | 仓库 |
| 内核 | 6.6.133 | 分支提交记录 |
| 无线驱动 | `mt_wifi` **7.6.6.1-mt7981** | `package/mtk/drivers/mt_wifi/Makefile` 的 `PKG_VERSION` |
| 设备 id | **`qihoo_360t7`** | `filogic.mk:1861` `define Device/qihoo_360t7` |
| 加速 | `kmod-mediatek_hnat` + WARP v2 + `MTK_MT7981_NEW_FW` | 同一 defconfig |

**关键结论：不需要改 dts。** 这个 fork 自带的 mt7981 defconfig 里 `kmod-mt_wifi=y`、没有 `kmod-mt7915e`，`qihoo_360t7` 的 dts（`mt7981b-qihoo-360t7`）本身就是 108M ubi 布局。这套流水线做的事是：把它单独拎出来编译，省掉其余十几个机型的时间；**并补上源码里缺失的 factory 镜像定义**（见下节）。

> ⚠️ 仓库 `defconfig/mt7981-ax3000.config` 里原本写的是 `CONFIG_TARGET_DEVICE_..._mt7981-360-t7-108M`，这是**过期符号**（沿袭 hanwckf 21.02 的命名），当前 `openwrt-24.10-6.6` 分支源码树里不存在。`make defconfig` 会静默丢弃它，必须改成 `qihoo_360t7`。这个问题已在第一次实跑时被校验脚本拦下（run 40462376449）。

## 为什么原来源码不产出 factory.bin

源码里 `Device/qihoo_360t7` 只有一行镜像定义：

```makefile
define Device/qihoo_360t7
  ...
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
```

没有 `IMAGES += factory.bin`，也没有 `IMAGE/factory.bin`，所以 `bin/targets/` 里只会出现一个 `sysupgrade.bin`。

而且这个 `sysupgrade.bin` 是 `sysupgrade-tar` 产物——**它是个 tar 归档，不是可烧写的 UBI 镜像**。实测头部：

```
00000000: 7379 7375 7067 7261 6465 2d71 6968 6f6f  sysupgrade-qihoo
00000010: 5f33 3630 7437 2f                        _360t7/
```

这种 tar 只能被系统内的 `sysupgrade` 命令消费，uboot 恢复页刷不了。

更麻烦的是同一个段落还缺 `KERNEL_IN_UBI`，而 dts 里没有独立的 `kernel` mtd 分区（只有 `bl2 / u-boot-env / Factory / fip / ubi / config / factory / log`）。没有 kernel 落点，`nand_do_upgrade` 升级时找不到该往哪写内核。

**根因一句话：这个设备定义是从别处抄过来没补全的半成品。**

## 补丁做了什么

`scripts/patch-filogic-mk.py` 在编译前按同 fork 内 `abt_asr3000`、`cetron_ct3003`、`cmcc_a10-stock` 的既有写法补齐：

```makefile
  UBINIZE_OPTS := -E 5
  KERNEL_IN_UBI := 1
  IMAGE_SIZE := 110592k
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
```

`110592k` = 108 MiB，等于 dts 里 ubi 分区 `0x6c00000`。脚本是幂等的（已补过就跳过），设备名对不上会打印源码树里所有可用设备后退出。

产物里的 `factory.bin` 是 UBI 格式，头部 magic 为 `UBI#`（`55424923`）。工作流在收集产物阶段会校验这一点，格式不对或超过 113246208 字节直接红叉。

## 怎么用

### 方式 A：一条命令全自动（推荐）

```bash
# 在 360t7-mtwifi-builder 目录下
GITHUB_TOKEN=ghp_xxxxxxxx python publish.py
GITHUB_TOKEN=ghp_xxxxxxxx python publish.py --variant openclash   # 带 OpenClash
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
   - 想换设备就在 `device` 输入框里改（比如 `xiaomi_mi-router-ax3000t-mtkuboot`）。
4. 等 50~90 分钟。编译完成会同时产出：
   - **Artifact**：`immortalwrt-24.10-mtwifi-qihoo_360t7`
   - **Release**：`build-YYYYMMDD-<run号>`，带 sha256sums

产物形如：

```
immortalwrt-mediatek-filogic-qihoo_360t7-squashfs-sysupgrade.bin
immortalwrt-mediatek-filogic-qihoo_360t7-squashfs-factory.bin
sha256sums
*.manifest
```

以 `bin/targets/mediatek/filogic/` 里实际产物为准（workflow 会把所有含 `360` 的文件都收走）。

## 两种变体

`variant` 参数控制是否带 OpenClash，其余配置完全一致：

| 变体 | 内容 | 额外依赖 | 编译时长 |
|---|---|---|---|
| `plain`（默认） | 纯净版，只有 mt_wifi + HNAT + WARP + LuCI | — | ~40 分钟 |
| `openclash` | 在上面基础上加 `luci-app-openclash` 0.48.002 + **内置 AArch64 内核** | `dnsmasq-full`、`ruby`、`kmod-tun`、`kmod-inet-diag`、`kmod-nft-tproxy`、`luci-compat`、`ip-full`、`unzip` | ~90 分钟 |

`openclash` 变体做的事（`scripts/add-openclash.sh`）：

1. 往 `feeds.conf.default` 加 `src-git openclash https://github.com/vernesong/OpenClash.git;master`
2. `feeds update/install` 之后，往 `.config` 追加 `luci-app-openclash=y` 及其依赖
3. **显式把 `CONFIG_PACKAGE_dnsmasq` 关掉**——`dnsmasq-full` 与 `dnsmasq` 冲突，只靠 kconfig 的 CONFLICTS 推导不可靠
4. `make defconfig` 之后由工作流逐项校验 8 个符号，缺一个就红叉

两个变体可以同时跑（各自独立的 run），Release tag 带变体后缀，不会互相覆盖。

### 内核直接打进固件

`luci-app-openclash` 是 `PKGARCH:=all` 的纯脚本包，**不含内核二进制**（`root/etc/openclash/` 下只有 `custom/`、`overwrite/`、`rule_provider/`、`Country.mmdb`）。官方设计是首次启动时从 `raw.githubusercontent.com` 下载——国内基本下不动。

所以 `openclash` 变体在编译时就把内核塞进去：

```
openwrt/files/etc/openclash/core/clash_meta     # 权限 4755，AArch64
```

由 `scripts/fetch-core.sh` 完成：

1. 从 `https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz` 下载，失败自动切 jsdelivr CDN
2. 解包取 `clash`，校验 ELF 头：`7f454c46` / 64 位 / `machine=b700`（AArch64）
3. 装到 `files/etc/openclash/core/clash_meta`，权限 4755
4. 工作流在 `Verify config` 阶段再独立复核一次架构，不对就红叉

刷完机 OpenClash 直接可用，不需要碰命令行。代价是固件大约多 8~10 MB（squashfs 压缩后）。

**注意**：内核版本固定在编译那一刻。想换内核版本，重跑一次编译即可（`fetch-core.sh` 拉的是 `core` 分支的当前产物）。

## 刷机流程

`qihoo_360t7` = **108M ubi 分区**布局，对应 dts 里 `ubi` 从 `0x580000` 起、长度 `0x6c00000`。

**原厂 uboot 起不来这个固件。** 顺序如下：

1. 刷支持 108M 分区的改版 uboot（hanwckf 的 `bl-mt798x` 或同类 7981 multi-layout uboot），用 TTL / 编程器 / 原厂漏洞。
2. 进 uboot web 恢复页（通常按住 reset 上电，访问 `192.168.1.1`）。
3. 上传 **`factory.bin`**（UBI 镜像），写进 ubi 分区。
4. 重启进系统，之后升级用 `sysupgrade.bin`。

`initramfs-kernel.bin` 可以先在内存里试跑，不动闪存——不确定无线是否正常时，先用它验证再落地。

不想动 bootloader 就别用这个，去用 hanwckf 21.02 线的 36M 版本。

## 三个脚本分工

| 脚本 | 阶段 | 作用 |
|---|---|---|
| `patch-filogic-mk.py` | 拉源码后 | 给 `Device/qihoo_360t7` 补 `KERNEL_IN_UBI` / `IMAGE_SIZE` / `UBINIZE_OPTS` / `factory.bin` |
| `prepare-config.sh` | 配 config | 复制仓库 defconfig，关掉其余十几个机型，只留目标设备 |
| `verify-config.sh` | 编译前 | 校验 7 项开关，不对就红叉 |

`scripts/verify-config.sh` 在 `make defconfig` 之后强制检查 7 项，任一项不对就红叉退出，并在日志里打印源码树中所有含 `360` 的设备定义和 `.config` 里所有可用设备。这是防 defconfig 里的设备符号跟源码树对不上（符号失效时 `make defconfig` 会静默丢弃，最后编译出一堆空产物）。

检查项：

- `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_qihoo_360t7=y`
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
