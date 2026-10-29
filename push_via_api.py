#!/usr/bin/env python3
"""用 GitHub Git Data API 推送当前目录到远端分支。

为什么不用 git push：本机代理对 github.com 的 HTTPS 极不稳定，
实测连续 5 次 502 / TLS handshake failure。Git Data API 走 api.github.com，
同样一次 HTTPS 但请求体小、可重试，成功率明显更高。

用法：
    GITHUB_TOKEN=ghp_xxx python push_via_api.py --repo happy-eagle/360t7-mtwifi-builder
    GITHUB_TOKEN=ghp_xxx python push_via_api.py --repo o/r --dispatch openclash
    python push_via_api.py --repo o/r --dry-run          # 只看会改哪些文件，不需要 token

只上传内容有变化的文件（按 git blob sha1 比对），不会把整个仓库重传一遍。
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
SKIP_DIRS = {".git", "__pycache__", "out", "build"}


def api(method, path, token, payload=None, ok=(200, 201)):
    url = API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "push-via-api")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {"message": body}
        if e.code not in ok:
            print(f"HTTP {e.code} {method} {path}: {parsed.get('message')}", file=sys.stderr)
        return e.code, parsed


def blob_sha(path):
    """git 计算 blob id 的方式：sha1('blob <size>\\0' + content)"""
    with open(path, "rb") as f:
        data = f.read()
    h = hashlib.sha1()
    h.update(b"blob %d\x00" % len(data))
    h.update(data)
    return h.hexdigest(), data


def collect(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            out[rel] = full
    # .github 被上面的 startswith(".") 过滤掉了，单独补回来
    gh = os.path.join(root, ".github")
    for dirpath, _, filenames in os.walk(gh):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            out[rel] = full
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/name")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--message", default=None)
    ap.add_argument("--dir", default=os.getcwd(), help="要推送的目录，默认当前目录")
    ap.add_argument("--dispatch", default=None,
                    help="推送后触发 workflow，值为 variant（plain/openclash）")
    ap.add_argument("--device", default="qihoo_360t7")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "")
    root = os.path.abspath(args.dir)
    files = collect(root)

    # 1. 取远端当前分支的 tree，算出差集
    # 公开仓库匿名也能读，所以 --dry-run 不带 token 也能拿到真实差异
    base_sha = None
    remote = {}
    code, ref = api("GET", f"/repos/{args.repo}/git/ref/heads/{args.branch}", token, ok=(200, 404))
    if code == 200:
        base_sha = ref["object"]["sha"]
        code, tree = api("GET", f"/repos/{args.repo}/git/trees/{base_sha}?recursive=1", token)
        if code != 200:
            sys.exit("取远端 tree 失败")
        remote = {e["path"]: e["sha"] for e in tree.get("tree", []) if e["type"] == "blob"}

    changed, added, deleted = [], [], []
    local_shas = {}
    for rel, full in sorted(files.items()):
        sha, _ = blob_sha(full)
        local_shas[rel] = sha
        if rel not in remote:
            added.append(rel)
        elif remote[rel] != sha:
            changed.append(rel)
    if remote:
        deleted = sorted(set(remote) - set(files))

    print(f"仓库 {args.repo}@{args.branch}  本地 {len(files)} 个文件")
    for rel in added:
        print("  + " + rel)
    for rel in changed:
        print("  M " + rel)
    for rel in deleted:
        print("  - " + rel)
    if not (added or changed or deleted):
        print("远端已是最新，无需推送")
        return

    if args.dry_run:
        print("\n--dry-run，不推送")
        return
    if not token:
        sys.exit("缺少 GITHUB_TOKEN")

    # 2. 逐个上传 blob（只传有变化的）
    entries = []
    for rel in added + changed:
        sha, data = blob_sha(files[rel])
        code, res = api("POST", f"/repos/{args.repo}/git/blobs", token,
                        {"content": base64.b64encode(data).decode(), "encoding": "base64"})
        if code not in (200, 201):
            sys.exit(f"上传 blob 失败: {rel}")
        entries.append({"path": rel, "mode": "100755" if rel.endswith(".sh") else "100644",
                        "type": "blob", "sha": res["sha"]})
        print(f"  blob {rel} -> {res['sha'][:8]}")
    for rel in deleted:
        entries.append({"path": rel, "mode": "100644", "type": "blob", "sha": None})

    # 3. tree
    payload = {"tree": entries}
    if base_sha:
        payload["base_tree"] = base_sha
    code, tree = api("POST", f"/repos/{args.repo}/git/trees", token, payload)
    if code not in (200, 201):
        sys.exit("创建 tree 失败")

    # 4. commit
    msg = args.message or "chore: 同步 %s" % time.strftime("%Y-%m-%d %H:%M")
    commit_payload = {"message": msg, "tree": tree["sha"]}
    if base_sha:
        commit_payload["parents"] = [base_sha]
    code, commit = api("POST", f"/repos/{args.repo}/git/commits", token, commit_payload)
    if code not in (200, 201):
        sys.exit("创建 commit 失败")
    print(f"commit {commit['sha'][:8]}  {msg.splitlines()[0]}")

    # 5. 更新 ref
    if base_sha:
        code, _ = api("PATCH", f"/repos/{args.repo}/git/refs/heads/{args.branch}", token,
                      {"sha": commit["sha"], "force": False}, ok=(200, 422))
        if code == 422:
            sys.exit("更新 ref 失败：远端有别人提交，先拉再推")
    else:
        code, _ = api("POST", f"/repos/{args.repo}/git/refs", token,
                      {"ref": f"refs/heads/{args.branch}", "sha": commit["sha"]})
        if code not in (200, 201):
            sys.exit("创建 ref 失败")
    print(f"已推送 {args.repo}@{args.branch} -> {commit['sha'][:8]}")

    # 6. 可选触发 workflow
    if args.dispatch:
        wf = "build-360t7.yml"
        code, _ = api("POST", f"/repos/{args.repo}/actions/workflows/{wf}/dispatches", token,
                      {"ref": args.branch,
                       "inputs": {"device": args.device, "variant": args.dispatch}}, ok=(204,))
        if code != 204:
            sys.exit(f"触发失败 HTTP {code}")
        print(f"已触发 {wf}  variant={args.dispatch}")
        print(f"https://github.com/{args.repo}/actions/workflows/{wf}")


if __name__ == "__main__":
    main()
