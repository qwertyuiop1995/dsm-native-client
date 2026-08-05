#!/usr/bin/env python3
"""校验 Android 页面五态矩阵覆盖完整且不把已知缺口标成完成。"""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
UI_ROOT = ROOT / "android/app/src/main/java/io/github/qwertyuiop1995/dsmnativeclient/ui"
MATRIX_PATH = ROOT / "docs/development/ANDROID_PAGE_STATE_AUDIT_MATRIX_ZH.md"
PLAN_PATH = ROOT / "docs/development/ANDROID_CLIENT_COMPLETION_PLAN_ZH.md"

STATE_VALUES = {"覆盖", "不适用", "缺口"}
EXPECTED_FILES = {
    "ChatScreen.kt",
    "DownloadDestinationDialog.kt",
    "DownloadSettingsDialog.kt",
    "FileBrowserScreen.kt",
    "FileCopyMoveDialog.kt",
    "FilePreviewDialog.kt",
    "PhotoMoveDialog.kt",
    "PhotosScreen.kt",
    "downloads/DownloadDiscoveryDialog.kt",
    "downloads/DownloadTaskDetailsDialog.kt",
    "downloads/DownloadsScreen.kt",
    "login/LoginScreen.kt",
    "nas/DdnsSettingsDialog.kt",
    "nas/EthernetSettingsDialog.kt",
    "nas/NasConnectionScreen.kt",
    "nas/NasDirectoryManagementScreen.kt",
    "nas/NasHardwareSettingsScreen.kt",
    "nas/NasPackageManagementScreen.kt",
    "nas/NasPerformanceScreen.kt",
    "nas/NasRegionSettingsScreen.kt",
    "nas/NasRemoteAccessSettingsScreen.kt",
    "nas/NasSecuritySettingsScreen.kt",
    "nas/NasServiceSettingsScreen.kt",
    "nas/NasSettingsScreen.kt",
    "nas/NasStorageScreen.kt",
    "services/ServiceScreens.kt",
    "services/VirtualMachineCreationDialog.kt",
    "services/VirtualMachineImageImportDialog.kt",
    "settings/SettingsScreen.kt",
    "transfers/TransfersScreen.kt",
}


def discover_surface_files(ui_root: Path = UI_ROOT) -> set[str]:
    discovered = {
        path.relative_to(ui_root).as_posix()
        for path in ui_root.rglob("*.kt")
        if path.name.endswith("Screen.kt") or path.name.endswith("Dialog.kt")
    }
    # 该文件同时承载 Container、Registry 和 VMM 三个生产页面/弹窗。
    service_screens = ui_root / "services/ServiceScreens.kt"
    if service_screens.exists():
        discovered.add("services/ServiceScreens.kt")
    return discovered


def parse_matrix(path: Path = MATRIX_PATH) -> tuple[dict[str, list[str]], list[str]]:
    rows: dict[str, list[str]] = {}
    errors: list[str] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| `"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 9:
            errors.append(f"矩阵第 {line_number} 行必须有 9 列，实际为 {len(cells)} 列")
            continue
        source = cells[0].strip("`")
        if source in rows:
            errors.append(f"矩阵重复记录页面文件：{source}")
            continue
        states = cells[2:7]
        invalid = [value for value in states if value not in STATE_VALUES]
        if invalid:
            errors.append(f"{source} 使用了非法状态值：{', '.join(invalid)}")
        if cells[7] not in {"完整", "局部", "缺失"}:
            errors.append(f"{source} 使用了非法自动化等级：{cells[7]}")
        rows[source] = states + [cells[7], cells[8]]
    return rows, errors


def validate(
    ui_root: Path = UI_ROOT,
    matrix_path: Path = MATRIX_PATH,
    plan_path: Path = PLAN_PATH,
) -> tuple[list[str], int, int]:
    rows, errors = parse_matrix(matrix_path)
    discovered = discover_surface_files(ui_root)
    missing_inventory = sorted(discovered - set(rows))
    stale_inventory = sorted(set(rows) - discovered)
    if missing_inventory:
        errors.append("矩阵遗漏生产页面/弹窗文件：" + ", ".join(missing_inventory))
    if stale_inventory:
        errors.append("矩阵包含不存在的页面/弹窗文件：" + ", ".join(stale_inventory))
    if discovered != EXPECTED_FILES:
        errors.append(
            "生产页面文件清单已变化，请先人工审计再更新 EXPECTED_FILES："
            f"新增={sorted(discovered - EXPECTED_FILES)}，移除={sorted(EXPECTED_FILES - discovered)}"
        )

    gap_count = sum(value == "缺口" for row in rows.values() for value in row[:5])
    automation_gap_count = sum(row[5] != "完整" for row in rows.values())
    plan = plan_path.read_text(encoding="utf-8")
    leaf_pattern = re.compile(
        r"- \[(?P<checked>[ x])\] 每页覆盖加载、空内容、筛选后为空、错误和正常内容五种状态；"
    )
    match = leaf_pattern.search(plan)
    if match is None:
        errors.append("未找到 Android 计划中的页面五态叶子目标")
    elif match.group("checked") == "x" and (gap_count or automation_gap_count):
        errors.append(
            "页面五态目标已勾选，但矩阵仍有"
            f" {gap_count} 个生产状态缺口、{automation_gap_count} 个自动化未闭环页面"
        )
    return errors, gap_count, automation_gap_count


def main() -> int:
    errors, gap_count, automation_gap_count = validate()
    if errors:
        for error in errors:
            print(f"错误：{error}")
        return 1
    print(
        "Android 页面五态矩阵结构通过："
        f"{len(EXPECTED_FILES)} 个生产页面/弹窗文件，"
        f"{gap_count} 个生产状态缺口，{automation_gap_count} 个自动化未闭环页面。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
