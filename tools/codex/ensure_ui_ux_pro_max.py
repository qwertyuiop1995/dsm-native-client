#!/usr/bin/env python3

"""确保当前用户已安装项目要求的 UI UX Pro Max Skill。"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


SKILL_VERSION = "2.11.0"
SKILL_NAME = "ui-ux-pro-max"
NPM_PACKAGE = f"ui-ux-pro-max-cli@{SKILL_VERSION}"


def codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".codex"


def required_files(skill_directory: Path) -> tuple[Path, Path]:
    return (
        skill_directory / "SKILL.md",
        skill_directory / "scripts" / "search.py",
    )


def install_command(npx_path: str) -> list[str]:
    arguments = [
        npx_path,
        "--yes",
        NPM_PACKAGE,
        "init",
        "--ai",
        "codex",
        "--global",
    ]
    if os.name == "nt":
        return ["cmd", "/d", "/s", "/c", *arguments]
    return arguments


def main() -> int:
    home = codex_home()
    skill_directory = home / "skills" / SKILL_NAME
    manifest, search_script = required_files(skill_directory)

    if manifest.is_file() and search_script.is_file():
        print(f"UI UX Pro Max 已安装：{skill_directory}")
        return 0

    if skill_directory.exists():
        print(
            f"检测到不完整的 Skill 目录，已拒绝自动覆盖：{skill_directory}",
            file=sys.stderr,
        )
        print("请人工检查或移除残缺目录后重试。", file=sys.stderr)
        return 2

    npx_path = shutil.which("npx")
    if npx_path is None:
        print(
            "未找到 npx。请先由用户安装 Node.js，再重新执行 UI/UX 任务。",
            file=sys.stderr,
        )
        return 3

    print(f"未检测到 UI UX Pro Max，正在安装固定版本 {SKILL_VERSION}…")
    environment = os.environ.copy()
    environment["CODEX_HOME"] = str(home)

    try:
        subprocess.run(
            install_command(npx_path),
            check=True,
            env=environment,
        )
    except subprocess.CalledProcessError as error:
        print(
            f"UI UX Pro Max 自动安装失败，退出码：{error.returncode}",
            file=sys.stderr,
        )
        return error.returncode or 4

    if not manifest.is_file() or not search_script.is_file():
        print(
            f"安装器执行成功，但缺少必要文件：{skill_directory}",
            file=sys.stderr,
        )
        return 5

    print(f"UI UX Pro Max {SKILL_VERSION} 已安装：{skill_directory}")
    print("后续 UI/UX 任务必须读取该 Skill 后再继续。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
