#!/usr/bin/env python3
"""
一键发布：建仓库 -> 推代码 -> 触发 Actions -> 打印运行链接

用法（在 360t7-mtwifi-builder 目录下）：
    GITHUB_TOKEN=ghp_xxx python publish.py
    GITHUB_TOKEN=ghp_xxx python publish.py --repo my-360t7 --private

Token 需要权限（fine-grained）：Administration=write, Contents=write, Actions=write, Workflows=write
或者直接用 classic token，勾 repo + workflow 两项。

脚本不会把 token 写进 .git/config，也不会写进任何文件。
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"


def die(msg: str, code: int = 1):
    print(f"\n[失败] {msg}", file=sys.stderr)
    sys.exit(code)


def api(method: str, path: str, token: str, payload=None, ok=(200, 201, 204)):
    url = path if path.startswith("http") else API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body.strip() else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if e.code in ok:
            return e.code, (json.loads(body) if body.strip() else {})
        return e.code, {"message": body[:500]}


def run(cmd, cwd, extra_header=None):
    args = ["git"] + (["-c", extra_header] if extra_header else []) + cmd
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        die(f"git {' '.join(cmd)} 失败:\n{p.stdout}\n{p.stderr}")
    return p.stdout.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="360t7-mtwifi-builder", help="仓库名")
    ap.add_argument("--private", action="store_true", help="建私有仓库（默认公开，公开仓库 Actions 不限时长）")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--device", default="qihoo_360t7", help="传给 workflow 的设备 id")
    ap.add_argument("--no-build", action="store_true", help="只推送，不触发编译")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        die("没找到 GITHUB_TOKEN 环境变量。\n  用法: GITHUB_TOKEN=ghp_xxx python publish.py")

    root = os.path.dirname(os.path.abspath(__file__))
    if not os.path.isdir(os.path.join(root, ".github", "workflows")):
        die(f"{root} 下没有 .github/workflows，请在项目根目录运行")

    # 1. 身份
    code, me = api("GET", "/user", token)
    if code != 200:
        die(f"token 无效或权限不足 (HTTP {code}): {me.get('message')}")
    login = me["login"]
    print(f"[1/5] 已认证: {login}")

    # 2. 建仓库
    code, repo = api("POST", "/user/repos", token, {
        "name": args.repo,
        "private": args.private,
        "description": "ImmortalWrt 24.10 + mt_wifi 闭源驱动，360T7 自动编译",
        "has_issues": False,
        "has_wiki": False,
        "auto_init": False,
    }, ok=(201, 422))
    if code == 422:
        print(f"[2/5] 仓库 {login}/{args.repo} 已存在，直接复用")
        code, repo = api("GET", f"/repos/{login}/{args.repo}", token)
        if code != 200:
            die(f"无法访问已有仓库 (HTTP {code}): {repo.get('message')}")
    else:
        print(f"[2/5] 已创建仓库: {repo['html_url']}")

    # 3. 提交并推送
    remote = f"https://github.com/{login}/{args.repo}.git"
    if not os.path.isdir(os.path.join(root, ".git")):
        run(["init"], root)
    run(["checkout", "-B", args.branch], root)
    run(["add", "-A"], root)
    staged = subprocess.run(["git", "diff", "--cached", "--name-only"],
                            cwd=root, capture_output=True, text=True).stdout.strip()
    if staged:
        run(["-c", "user.name=" + login,
             "-c", "user.email=" + f"{login}@users.noreply.github.com",
             "commit", "-m", "feat: 360T7 闭源驱动编译流水线"], root)
    run(["remote", "remove", "origin"], root) if "origin" in run(["remote"], root) else None
    run(["remote", "add", "origin", remote], root)

    b64 = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    run(["push", "-f", "-u", "origin", args.branch],
        root, extra_header=f"http.https://github.com/.extraheader=AUTHORIZATION: basic {b64}")
    print(f"[3/5] 已推送: {remote} ({args.branch})")

    # 4. 放开 Actions 写权限（release 步骤需要）
    code, _ = api("PUT", f"/repos/{login}/{args.repo}/actions/permissions/workflow", token,
                  {"default_workflow_permissions": "write", "can_approve_pull_request_reviews": False})
    print(f"[4/5] Actions 默认权限设为 write: {'OK' if code in (200, 204) else f'跳过 (HTTP {code})'}")

    if args.no_build:
        print("[5/5] --no-build，未触发编译")
        return

    # 5. 触发 workflow
    # push 事件本身也会触发一次（workflow 里配了 push 触发），
    # 所以先看这次 push 有没有已经在跑的 run，避免同一次提交编两遍。
    wf = "build-360t7.yml"
    head_sha = run(["rev-parse", "HEAD"], root)

    run_url = None
    for _ in range(8):
        time.sleep(3)
        code, runs = api("GET",
                         f"/repos/{login}/{args.repo}/actions/workflows/{wf}/runs?per_page=10",
                         token)
        if code != 200:
            continue
        for r in runs.get("workflow_runs", []):
            if r.get("head_sha") == head_sha and r["status"] in ("queued", "in_progress"):
                run_url = r["html_url"]
                print(f"[5/5] 本次 push 已自动触发编译，跳过手动 dispatch（避免重复编译）")
                break
        if run_url:
            break

    if not run_url:
        code, res = api("POST", f"/repos/{login}/{args.repo}/actions/workflows/{wf}/dispatches", token,
                        {"ref": args.branch, "inputs": {"device": args.device}}, ok=(204,))
        if code != 204:
            die(f"触发失败 (HTTP {code}): {res.get('message')}\n"
                f"  检查 .github/workflows/{wf} 是否已在 {args.branch} 分支上")
        print(f"[5/5] 已触发编译，等待 runner 接单…")

        for _ in range(30):
            time.sleep(6)
            code, runs = api("GET",
                             f"/repos/{login}/{args.repo}/actions/workflows/{wf}/runs?per_page=1",
                             token)
            if code == 200 and runs.get("workflow_runs"):
                r = runs["workflow_runs"][0]
                if r["status"] in ("queued", "in_progress", "completed"):
                    run_url = r["html_url"]
                    break

    print()
    print("=" * 68)
    print(f"仓库:   https://github.com/{login}/{args.repo}")
    print(f"运行:   {run_url or 'https://github.com/' + login + '/' + args.repo + '/actions'}")
    print("=" * 68)
    print("编译约 50-90 分钟。完成后固件在 Actions 的 Artifact 和 Releases 里。")


if __name__ == "__main__":
    main()
