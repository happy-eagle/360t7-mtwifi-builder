#!/usr/bin/env python3
"""
给 filogic.mk 里的目标设备补齐 UBI 工厂镜像所需字段。

背景：padavanonly fork 的 Device/qihoo_360t7 只定义了
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
缺少 KERNEL_IN_UBI / IMAGE_SIZE / UBINIZE_OPTS / factory.bin，
后果有两个：
  1) 不产出 factory.bin，uboot 恢复页没东西可刷；
  2) 生成的 sysupgrade.bin 是 tar 包，而 dts 里没有 kernel 分区，
     nand_do_upgrade 找不到 kernel 落点。

本脚本按同 fork 内 abt_asr3000 / cetron_ct3003 / cmcc_a10-stock 的
既有写法补齐，不引入新语法。

用法: patch-filogic-mk.py <filogic.mk 路径> <device id> [ubi 分区 MiB]
"""
import re
import sys


def main():
    if len(sys.argv) < 3:
        print("用法: patch-filogic-mk.py <filogic.mk> <device> [ubi_mib]", file=sys.stderr)
        return 2

    path, dev = sys.argv[1], sys.argv[2]
    ubi_mib = int(sys.argv[3]) if len(sys.argv) > 3 else 108

    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    # 定位 define Device/<dev> ... endef
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == f"define Device/{dev}":
            start = i
            break
    if start is None:
        names = [l.strip()[len("define Device/"):] for l in lines if l.strip().startswith("define Device/")]
        print(f"[FAIL] 找不到 define Device/{dev}", file=sys.stderr)
        print("       源码树里可用的设备：" + ", ".join(names), file=sys.stderr)
        return 1

    end = None
    for i in range(start + 1, len(lines)):
        if lines[i].strip() == "endef":
            end = i
            break
    if end is None:
        print(f"[FAIL] Device/{dev} 段落没有 endef", file=sys.stderr)
        return 1

    block = lines[start:end + 1]
    body = "\n".join(block)

    if "KERNEL_IN_UBI" in body and "IMAGE/factory.bin" in body:
        print(f"[SKIP] Device/{dev} 已有 KERNEL_IN_UBI + factory.bin，不重复补")
        return 0

    # 找插入点：block 内第一处 IMAGE/sysupgrade 行
    anchor = None
    for i in range(start + 1, end):
        if "IMAGE/sysupgrade" in lines[i]:
            anchor = i
            break
    if anchor is None:
        print(f"[FAIL] Device/{dev} 里找不到 IMAGE/sysupgrade 行，无法定位插入点", file=sys.stderr)
        return 1

    # 已有则保留，缺则补，避免覆盖设备自定义值
    have = set()
    for ln in block:
        key = ln.strip().split(":=")[0].strip() if ":=" in ln else ""
        if key:
            have.add(key)

    inject = []
    if "UBINIZE_OPTS" not in have:
        inject.append("  UBINIZE_OPTS := -E 5")
    if "KERNEL_IN_UBI" not in have:
        inject.append("  KERNEL_IN_UBI := 1")
    if "IMAGE_SIZE" not in have:
        inject.append(f"  IMAGE_SIZE := {ubi_mib * 1024}k")
    if "IMAGES" not in have:
        inject.append("  IMAGES += factory.bin")
    if "IMAGE/factory.bin" not in have:
        inject.append("  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)")

    lines[anchor:anchor] = inject

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    # 回读校验
    with open(path, encoding="utf-8") as f:
        new = f.read()
    s = new.index(f"define Device/{dev}\n")
    e = new.index("\nendef", s)
    patched = new[s:e]

    required = ["UBINIZE_OPTS", "KERNEL_IN_UBI", "IMAGE_SIZE", "IMAGES += factory.bin", "IMAGE/factory.bin"]
    missing = [r for r in required if r not in patched]
    if missing:
        print(f"[FAIL] 补丁后仍缺: {missing}", file=sys.stderr)
        return 1

    print(f"[ OK ] Device/{dev} 已补齐 {len(inject)} 行，UBI 分区按 {ubi_mib} MiB")
    print("------ 补丁后的设备定义 ------")
    print(patched + "\nendef")
    return 0


if __name__ == "__main__":
    sys.exit(main())
