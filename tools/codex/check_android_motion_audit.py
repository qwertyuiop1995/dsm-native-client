#!/usr/bin/env python3
"""检查 Android 生产界面是否新增未经审计的显式时间动效。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
UI_ROOT = (
    ROOT
    / "android/app/src/main/java/io/github/qwertyuiop1995/dsmnativeclient/ui"
)


@dataclass(frozen=True)
class MotionFinding:
    path: str
    line: int
    source: str


TIME_MOTION_PATTERNS = (
    re.compile(r"^import android\.animation(?:\.|$)"),
    re.compile(r"^import androidx\.compose\.animation(?:\.|$)"),
    re.compile(
        r"\b(?:Animatable|AnimatedContent|AnimatedVisibility|Crossfade|"
        r"TargetBasedAnimation|animate\w*AsState|animateTo|decay|"
        r"infiniteRepeatable|keyframes|rememberInfiniteTransition|repeatable|"
        r"spring|tween|updateTransition)\s*\("
    ),
    re.compile(r"\bValueAnimator\.areAnimatorsEnabled\s*\("),
)

# 当前唯一显式时间动效是 Workspace 的预测返回取消回弹。白名单精确到源码行，
# 避免在同一文件中悄悄加入另一套未经审计的动效。
ALLOWED_SOURCES = {
    "import android.animation.ValueAnimator",
    "import androidx.compose.animation.core.Animatable",
    "import androidx.compose.animation.core.tween",
    "val predictiveBackProgress = remember { Animatable(0f) }",
    "animationsEnabled = ValueAnimator.areAnimatorsEnabled(),",
    "if (ValueAnimator.areAnimatorsEnabled()) {",
    "predictiveBackProgress.animateTo(0f, animationSpec = tween(150))",
}
ALLOWED_PATH = "WorkspaceShell.kt"


def scan_ui(ui_root: Path = UI_ROOT) -> list[MotionFinding]:
    findings: list[MotionFinding] = []
    for path in sorted(ui_root.rglob("*.kt")):
        for line_number, raw_line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            1,
        ):
            source = raw_line.strip()
            if source and any(pattern.search(source) for pattern in TIME_MOTION_PATTERNS):
                findings.append(
                    MotionFinding(
                        path=path.relative_to(ui_root).as_posix(),
                        line=line_number,
                        source=source,
                    )
                )
    return findings


def validate_findings(findings: list[MotionFinding]) -> list[str]:
    errors: list[str] = []
    actual_sources: set[str] = set()
    for finding in findings:
        if finding.path != ALLOWED_PATH or finding.source not in ALLOWED_SOURCES:
            errors.append(
                f"未经审计的显式时间动效：{finding.path}:{finding.line}: "
                f"{finding.source}"
            )
        elif finding.source in actual_sources:
            errors.append(
                f"允许的动效源码重复出现：{finding.path}:{finding.line}: "
                f"{finding.source}"
            )
        else:
            actual_sources.add(finding.source)

    missing = ALLOWED_SOURCES - actual_sources
    for source in sorted(missing):
        errors.append(f"预测返回动效审计基线缺失：{source}")

    if (
        "if (ValueAnimator.areAnimatorsEnabled()) {" not in actual_sources
        or "animationsEnabled = ValueAnimator.areAnimatorsEnabled()," not in actual_sources
    ):
        errors.append("预测返回进度与取消回弹必须同时遵守系统动画开关")
    return errors


def main() -> int:
    errors = validate_findings(scan_ui())
    if errors:
        for error in errors:
            print(f"错误：{error}")
        return 1
    print("Android 显式时间动效审计通过：仅保留遵守系统动画开关的预测返回动效。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
