#!/usr/bin/env python3
"""按 Android 计划的叶子目标口径复算开发进度。"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "docs/development/ANDROID_CLIENT_COMPLETION_PLAN_ZH.md"
STAGE_HEADING = re.compile(r"^## \d+\. A([0-8])：")
CHECKBOX = re.compile(r"^(?P<indent>\s*)- \[(?P<state>[ xX])] (?P<label>.+)$")


@dataclass(frozen=True)
class Goal:
    line: int
    indent: int
    completed: bool
    stage: str
    label: str


def read_goals() -> list[Goal]:
    goals: list[Goal] = []
    stage: str | None = None
    for line_number, line in enumerate(PLAN.read_text(encoding="utf-8").splitlines(), 1):
        heading = STAGE_HEADING.match(line)
        if heading:
            stage = f"A{heading.group(1)}"
            continue
        if line.startswith("## "):
            stage = None
            continue
        match = CHECKBOX.match(line)
        if stage is not None and match:
            goals.append(
                Goal(
                    line=line_number,
                    indent=len(match.group("indent")),
                    completed=match.group("state").lower() == "x",
                    stage=stage,
                    label=match.group("label"),
                )
            )
    return goals


def leaf_goals(goals: list[Goal]) -> list[Goal]:
    result: list[Goal] = []
    for index, goal in enumerate(goals):
        next_goal = goals[index + 1] if index + 1 < len(goals) else None
        if next_goal is None or next_goal.indent <= goal.indent:
            result.append(goal)
    return result


def main() -> None:
    leaves = leaf_goals(read_goals())
    completed = sum(goal.completed for goal in leaves)
    remaining = len(leaves) - completed
    percent = completed / len(leaves) * 100 if leaves else 0.0
    print(
        f"Android A0–A8 叶子开发目标：{completed}/{len(leaves)}，"
        f"完成度 {percent:.1f}%，剩余 {remaining} 项。"
    )
    for goal in leaves:
        if not goal.completed:
            print(f"- {goal.stage} L{goal.line}: {goal.label}")


if __name__ == "__main__":
    main()
