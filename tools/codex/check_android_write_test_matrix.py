#!/usr/bin/env python3
"""校验 Android 生产写入口与写操作测试矩阵没有漂移。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
VIEW_MODEL = ROOT / "android/app/src/main/java/io/github/qwertyuiop1995/dsmnativeclient/AppViewModel.kt"
MATRIX = ROOT / "docs/development/ANDROID_WRITE_MUTATION_TEST_MATRIX_ZH.md"
TEST_ROOT = ROOT / "android/app/src/test/java"

CALL_PATTERN = re.compile(
    r"\b(?:repo|repository|claim\.repository)\.([A-Za-z0-9_]+Result)\s*\("
)
ROW_PATTERN = re.compile(r"<!-- WRITE-MUTATION (?P<body>.*?) -->")
FIELD_PATTERN = re.compile(r"(?P<key>[a-z]+)=(?P<value>[^;]*)(?:;|$)")
REQUIRED_OPEN_SCENARIOS = ("pre", "success", "disconnect", "readback", "cancel")
VALID_STATES = {"open", "closed", "readonly", "pending"}


@dataclass(frozen=True)
class MatrixRow:
    methods: tuple[str, ...]
    state: str
    multi: bool
    fields: dict[str, str]


def production_result_calls(source: str | None = None) -> set[str]:
    text = VIEW_MODEL.read_text(encoding="utf-8") if source is None else source
    return set(CALL_PATTERN.findall(text))


def parse_rows(text: str | None = None) -> list[MatrixRow]:
    source = MATRIX.read_text(encoding="utf-8") if text is None else text
    rows: list[MatrixRow] = []
    for match in ROW_PATTERN.finditer(source):
        fields = {
            field.group("key"): field.group("value").strip()
            for field in FIELD_PATTERN.finditer(match.group("body"))
        }
        methods = tuple(filter(None, fields.get("methods", "").split(",")))
        rows.append(
            MatrixRow(
                methods=methods,
                state=fields.get("state", ""),
                multi=fields.get("multi") == "yes",
                fields=fields,
            )
        )
    return rows


def _validate_evidence(reference: str) -> str | None:
    if reference in {"na", "gap", ""}:
        return None
    if "::" not in reference:
        return f"证据格式错误（应为相对路径::测试名片段）：{reference}"
    relative_path, test_name = reference.split("::", 1)
    path = TEST_ROOT / relative_path
    if "/" not in relative_path:
        matches = list(TEST_ROOT.rglob(relative_path))
        if len(matches) != 1:
            return f"测试证据文件必须唯一存在：{relative_path}（当前 {len(matches)} 个）"
        path = matches[0]
    if not path.is_file():
        return f"测试证据文件不存在：{relative_path}"
    if test_name not in path.read_text(encoding="utf-8"):
        return f"测试证据名称不存在：{relative_path}::{test_name}"
    return None


def validate(
    calls: set[str] | None = None,
    rows: list[MatrixRow] | None = None,
) -> list[str]:
    actual_calls = production_result_calls() if calls is None else calls
    actual_rows = parse_rows() if rows is None else rows
    errors: list[str] = []
    represented: dict[str, int] = {}

    for index, row in enumerate(actual_rows, 1):
        if not row.methods:
            errors.append(f"第 {index} 行缺少 methods")
            continue
        if row.state not in VALID_STATES:
            errors.append(f"第 {index} 行 state 无效：{row.state or '<空>'}")
        for method in row.methods:
            represented[method] = represented.get(method, 0) + 1

        required = ("zero",) if row.state == "closed" else ()
        if row.state == "open":
            required = REQUIRED_OPEN_SCENARIOS + (("partial",) if row.multi else ())
        elif row.state == "readonly":
            required = ("success", "readback", "cancel")

        for scenario in required:
            reference = row.fields.get(scenario, "")
            if reference in {"", "gap", "na"}:
                errors.append(
                    f"{','.join(row.methods)} 的 {scenario} 场景没有有效测试证据"
                )
                continue
            evidence_error = _validate_evidence(reference)
            if evidence_error:
                errors.append(evidence_error)

        if row.state == "pending":
            gaps = [
                scenario
                for scenario in REQUIRED_OPEN_SCENARIOS
                + (("partial",) if row.multi else ())
                if row.fields.get(scenario, "") == "gap"
            ]
            if not gaps:
                errors.append(f"pending 行未声明 gap：{','.join(row.methods)}")
            else:
                errors.append(
                    f"待补测试：{','.join(row.methods)} -> {','.join(gaps)}"
                )

        # 对已经填写的证据也做路径和测试名校验，避免 pending 行留下失效链接。
        for scenario in ("pre", "success", "disconnect", "readback", "cancel", "partial", "zero"):
            reference = row.fields.get(scenario, "")
            if reference not in {"", "gap", "na"}:
                evidence_error = _validate_evidence(reference)
                if evidence_error and evidence_error not in errors:
                    errors.append(evidence_error)

    missing = actual_calls - represented.keys()
    extra = represented.keys() - actual_calls
    for method in sorted(missing):
        errors.append(f"生产写入口未进入矩阵：{method}")
    for method in sorted(extra):
        errors.append(f"矩阵记录了不存在的生产调用：{method}")
    for method, count in sorted(represented.items()):
        if count != 1:
            errors.append(f"生产写入口必须且只能记录一次：{method}（当前 {count} 次）")
    return errors


def main() -> int:
    errors = validate()
    if errors:
        for error in errors:
            print(f"错误：{error}")
        return 1
    print("Android 写操作测试矩阵通过：生产入口、适用场景与测试证据均完整。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
