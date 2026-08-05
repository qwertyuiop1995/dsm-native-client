#!/usr/bin/env python3
"""检查 Android 自定义点击目标是否保持至少 48dp 的可审计尺寸。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
UI_ROOT = ROOT / "android/app/src/main/java/io/github/qwertyuiop1995/dsmnativeclient/ui"

INTERACTION_PATTERN = re.compile(
    r"\.(?P<kind>clickable|combinedClickable|toggleable|selectable)\s*(?:\(|\{)"
)
GESTURE_TAP_PATTERN = re.compile(r"\b(?:pointerInput|detectTapGestures)\s*\(")
HEIGHT_PATTERN = re.compile(
    r"\.(?:height|heightIn)\s*\(\s*(?:min\s*=\s*)?(?P<value>\d+(?:\.\d+)?)\.dp"
)
WIDTH_PATTERN = re.compile(
    r"\.(?:width|widthIn)\s*\(\s*(?:min\s*=\s*)?(?P<value>\d+(?:\.\d+)?)\.dp"
)
SIZE_PATTERN = re.compile(r"\.size\s*\(\s*(?P<value>\d+(?:\.\d+)?)\.dp")
SIZE_IN_MIN_WIDTH_PATTERN = re.compile(
    r"\.sizeIn\s*\([^)]*minWidth\s*=\s*(?P<value>\d+(?:\.\d+)?)\.dp",
    re.DOTALL,
)
SIZE_IN_MIN_HEIGHT_PATTERN = re.compile(
    r"\.sizeIn\s*\([^)]*minHeight\s*=\s*(?P<value>\d+(?:\.\d+)?)\.dp",
    re.DOTALL,
)


@dataclass(frozen=True)
class TouchTargetFinding:
    path: str
    line: int
    kind: str
    modifier_source: str


def _modifier_source(lines: list[str], interaction_index: int) -> str:
    """截取当前交互调用所属 Modifier 链，避免借用上一组件的尺寸。"""
    lower_bound = max(0, interaction_index - 16)
    start = interaction_index
    for index in range(interaction_index, lower_bound - 1, -1):
        # 变量 modifier 是审计边界：不可继续向上借用其他
        # 组件的 Modifier 根和尺寸。调用方应将尺寸约束显式写在当前链。
        if index < interaction_index and re.search(r"\bmodifier\s*=", lines[index]):
            if not re.search(r"\bModifier\b", lines[index]):
                return "\n".join(lines[index: interaction_index + 1])
        if re.search(r"\bModifier\b", lines[index]):
            start = index
            break
    return "\n".join(lines[start : interaction_index + 1])


def scan_ui(ui_root: Path = UI_ROOT) -> tuple[list[TouchTargetFinding], list[str]]:
    findings: list[TouchTargetFinding] = []
    gesture_errors: list[str] = []
    for path in sorted(ui_root.rglob("*.kt")):
        lines = path.read_text(encoding="utf-8").splitlines()
        relative_path = path.relative_to(ui_root).as_posix()
        for index, source in enumerate(lines):
            for match in INTERACTION_PATTERN.finditer(source):
                findings.append(
                    TouchTargetFinding(
                        path=relative_path,
                        line=index + 1,
                        kind=match.group("kind"),
                        modifier_source=_modifier_source(lines, index),
                    )
                )
            if GESTURE_TAP_PATTERN.search(source):
                gesture_errors.append(
                    f"需人工审计的手势点击区域：{relative_path}:{index + 1}: {source.strip()}"
                )
    return findings, gesture_errors


def _at_least_48(match: re.Match[str] | None) -> bool:
    return match is not None and float(match.group("value")) >= 48.0


def validate_findings(
    findings: list[TouchTargetFinding],
    gesture_errors: list[str],
) -> list[str]:
    errors = list(gesture_errors)
    for finding in findings:
        source = finding.modifier_source
        native_minimum = ".minimumInteractiveComponentSize()" in source
        height_ok = (
            native_minimum
            or _at_least_48(HEIGHT_PATTERN.search(source))
            or _at_least_48(SIZE_PATTERN.search(source))
            or _at_least_48(SIZE_IN_MIN_HEIGHT_PATTERN.search(source))
        )
        width_ok = (
            native_minimum
            or ".fillMaxWidth(" in source
            or ".weight(" in source
            or _at_least_48(WIDTH_PATTERN.search(source))
            or _at_least_48(SIZE_PATTERN.search(source))
            or _at_least_48(SIZE_IN_MIN_WIDTH_PATTERN.search(source))
        )
        location = f"{finding.path}:{finding.line} ({finding.kind})"
        if not height_ok:
            errors.append(f"自定义点击目标缺少至少 48dp 的高度合约：{location}")
        if not width_ok:
            errors.append(f"自定义点击目标缺少至少 48dp 的宽度合约：{location}")
        if "indication = null" in source:
            errors.append(f"自定义点击目标禁用了原生按压反馈：{location}")
    return errors


def main() -> int:
    findings, gesture_errors = scan_ui()
    errors = validate_findings(findings, gesture_errors)
    if errors:
        for error in errors:
            print(f"错误：{error}")
        return 1
    print(
        "Android 点击目标审计通过："
        f"{len(findings)} 处自定义交互均具备至少 48dp 双向尺寸与原生按压反馈。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
