#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def prepare(source, lock, managed):
    if managed:
        if not source.exists():
            source.parent.mkdir(parents=True, exist_ok=True)
            git("clone", lock["repository"], str(source))
        if not (source / ".git").exists():
            raise SystemExit("Engine cache is not a Git checkout; inspect it before retrying.")
        if git("status", "--porcelain", "--untracked-files=no", "--ignore-submodules=all", cwd=source):
            raise SystemExit("Engine cache has tracked modifications; refusing to overwrite them.")
        git("submodule", "foreach", "--recursive", "git diff --quiet && git diff --cached --quiet", cwd=source)
        git("checkout", "--detach", lock["commit"], cwd=source)
        git("submodule", "update", "--init", "--recursive", cwd=source)
    if git("rev-parse", "HEAD", cwd=source) != lock["commit"]:
        raise SystemExit("Engine HEAD differs from engine.lock.json; no files were modified.")
    if git("status", "--porcelain", "--untracked-files=no", cwd=source):
        raise SystemExit("Engine has tracked modifications; use a clean pinned checkout.")
    for name, commit in lock["submodules"].items():
        if not (source / name / ".git").exists() or git("rev-parse", "HEAD", cwd=source / name) != commit:
            raise SystemExit(f"Submodule {name} is missing or differs from the lockfile.")


def main():
    parser = argparse.ArgumentParser(description="Fetch or verify the pinned engine without modifying the PC checkout.")
    parser.add_argument("--local", type=Path, help="Verify an existing local engine instead of fetching")
    args = parser.parse_args()
    lock = json.loads((ROOT / "engine.lock.json").read_text())
    source = args.local.resolve() if args.local else ROOT / ".cache" / "engine"
    prepare(source, lock, managed=not args.local)
    print(f"Verified engine: {source}")
    print("Engine integration is pending; this checkout is not linked into the iOS host yet.")


if __name__ == "__main__":
    main()
