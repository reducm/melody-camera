#!/usr/bin/env python3
"""本机扫描拟发布历史与工作区；不读取钥匙串，不输出密钥或原始命中行。"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gitleaks", default="gitleaks", help="Gitleaks 可执行文件路径")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    binary = shutil.which(args.gitleaks)
    if not binary:
        print("未找到 Gitleaks，请按 docs/GitHub发布检查.md 安装或传入 --gitleaks 路径。")
        return 2
    binary = str(Path(binary).resolve())
    env = {k: v for k, v in os.environ.items() if not k.startswith("GITLEAKS_")}
    config = root / ".gitleaks.toml"
    files = sorted(set(filter(None, git(root, "ls-files", "-co", "--exclude-standard", "-z").split(b"\0"))))
    tracked_ignored = git(root, "ls-files", "-ci", "--exclude-standard", "-z").split(b"\0")
    failed = False
    tracked_ignored = [os.fsdecode(p) for p in tracked_ignored if p]
    if tracked_ignored:
        failed = True
        print(json.dumps({"已跟踪但应忽略": tracked_ignored}, ensure_ascii=False))
    with tempfile.TemporaryDirectory(prefix="melody-secret-audit-") as temporary:
        temporary = Path(temporary)
        snapshot = temporary / "worktree"
        snapshot.mkdir()
        index = temporary / "index"
        index.mkdir()
        for entry in git(root, "ls-files", "--stage", "-z").split(b"\0"):
            if not entry:
                continue
            metadata, raw_name = entry.split(b"\t", 1)
            mode, oid, stage = metadata.decode().split()
            name = os.fsdecode(raw_name)
            if stage != "0" or mode not in ("100644", "100755"):
                print(json.dumps({"需人工核对索引条目": name, "模式": mode, "阶段": stage}, ensure_ascii=False))
                failed = True
                continue
            path = index / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(git(root, "cat-file", "blob", oid))
        history = temporary / "history"
        history.mkdir()
        object_names = {}
        for entry in git(root, "rev-list", "--objects", "--all").decode().splitlines():
            oid, _, name = entry.partition(" ")
            kind = git(root, "cat-file", "-t", oid).decode().strip()
            if kind not in ("blob", "commit", "tag"):
                continue
            path = history / (oid + ".txt")
            path.write_bytes(git(root, "cat-file", kind, oid))
            object_names[path.name] = {"文件": name or "Git " + kind + " 元数据", "对象": oid[:12]}
        copied = 0
        for raw in files:
            name = os.fsdecode(raw)
            source = root / name
            if source.is_symlink():
                # 不跟随链接读取仓库外私人文件；要求发布前人工确认。
                print(json.dumps({"需人工核对符号链接": name}, ensure_ascii=False))
                failed = True
                continue
            if not source.is_file():
                continue  # 已删除文件仍由历史扫描覆盖。
            destination = snapshot / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            copied += 1
        for label, command in [
            ("全部分支与标签历史", ["git", str(root), "--log-opts=--all --full-history"]),
            ("历史对象全文与提交说明", ["dir", str(history)]),
            ("暂存区文件快照", ["dir", str(index)]),
            ("当前已跟踪与未忽略文件", ["dir", str(snapshot)]),
        ]:
            report = temporary / "report.json"
            report.unlink(missing_ok=True)
            result = subprocess.run([
                binary, *command, "--config", str(config), "--redact=100",
                "--ignore-gitleaks-allow", "--gitleaks-ignore-path", str(temporary),
                "--max-decode-depth=2", "--report-format=json", "--report-path", str(report),
                "--no-banner", "--log-level=error",
            ], cwd=root, env=env, capture_output=True)
            if result.returncode not in (0, 1) or not report.exists():
                print(json.dumps({"检查": label, "工具错误退出码": result.returncode}, ensure_ascii=False))
                failed = True
                continue
            findings = json.loads(report.read_text()) or []
            locations = []
            for finding in findings:
                name = finding.get("File", "")
                if name.startswith(str(snapshot) + os.sep):
                    name = name[len(str(snapshot)) + 1:]
                if name.startswith(str(index) + os.sep):
                    name = name[len(str(index)) + 1:]
                location = {"文件": name, "行": finding.get("StartLine"),
                            "规则": finding.get("RuleID"), "提交": finding.get("Commit", "")[:12]}
                if label == "历史对象全文与提交说明":
                    location.update(object_names.get(Path(name).name, {}))
                locations.append(location)
            print(json.dumps({"检查": label, "命中数": len(findings), "位置": locations}, ensure_ascii=False))
            failed |= bool(findings) or result.returncode != 0
    print(json.dumps({"可达提交数": int(git(root, "rev-list", "--all", "--count")),
                      "历史全文对象数": len(object_names), "工作区扫描文件数": copied,
                      "通过": not failed}, ensure_ascii=False))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
