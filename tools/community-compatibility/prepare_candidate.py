#!/usr/bin/env python3
"""从已审核的本地草稿生成只读候选报告或待复核差异。"""

from __future__ import annotations

import argparse
import copy
import difflib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIRECTORY = Path(__file__).resolve().parent
REPORTS_DIRECTORY = (
    REPOSITORY_ROOT / "contracts/community-compatibility/reports"
)
ZH_MATRIX_PATH = (
    REPOSITORY_ROOT
    / "docs/compatibility/COMMUNITY_COMPATIBILITY_MATRIX_ZH.md"
)
EN_MATRIX_PATH = (
    REPOSITORY_ROOT
    / "docs/compatibility/COMMUNITY_COMPATIBILITY_MATRIX_EN.md"
)
REPORT_SCHEMA_REFERENCE = (
    "../../schemas/community-compatibility-report.schema.json"
)
REPORT_COPY_FIELDS = (
    "app",
    "nas",
    "dsm",
    "packages",
    "connectionType",
    "accountRole",
    "certificateType",
    "testSuiteVersion",
    "results",
    "privacyAttestation",
)


class CandidatePreparationError(ValueError):
    """表示候选报告无法安全生成。"""


def _load_module(name: str, path: Path) -> Any:
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(
            "无法加载社区兼容性工具 / unable to load compatibility tool"
        )
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


submission_validator = _load_module(
    "community_compatibility_candidate_submission_validator",
    TOOLS_DIRECTORY / "validate_submission.py",
)
report_validator = _load_module(
    "community_compatibility_candidate_report_validator",
    TOOLS_DIRECTORY / "validate.py",
)
matrix_generator = _load_module(
    "community_compatibility_candidate_generator",
    TOOLS_DIRECTORY / "generate.py",
)


def allocate_report_id(reports: Sequence[dict[str, Any]]) -> str:
    """按历史最大编号分配新 ID，不复用删除后留下的空洞。"""
    maximum = 0
    for report in reports:
        report_id = report.get("reportId")
        if (
            not isinstance(report_id, str)
            or report_validator.REPORT_ID_PATTERN.fullmatch(report_id) is None
        ):
            raise CandidatePreparationError(
                "现有报告 ID 无效 / an existing report ID is invalid"
            )
        maximum = max(maximum, int(report_id.removeprefix("cc-")))
    if maximum >= 999999:
        raise CandidatePreparationError(
            "报告 ID 已耗尽 / report ID space is exhausted"
        )
    return f"cc-{maximum + 1:06d}"


def ensure_unique_source(
    source_ref: str,
    reports: Sequence[dict[str, Any]],
) -> None:
    """拒绝把同一公开来源转换为多份正式报告。"""
    if any(report.get("sourceRef") == source_ref for report in reports):
        raise CandidatePreparationError(
            "公开来源已存在正式报告 / the public source already has a report"
        )


def build_candidate(
    submission: Any,
    submission_source: Path,
    source_ref: str,
    submitted_at: str,
    capabilities: dict[str, dict[str, Any]],
    reports: Sequence[dict[str, Any]],
) -> tuple[dict[str, Any], Path]:
    """在内存中把白名单草稿转换并复验为正式候选报告。"""
    validated_submission = submission_validator.validate_submission(
        submission,
        submission_source,
    )
    ensure_unique_source(source_ref, reports)
    report_id = allocate_report_id(reports)
    target = REPORTS_DIRECTORY / f"{report_id}.json"
    report = {
        "$schema": REPORT_SCHEMA_REFERENCE,
        "schemaVersion": 2,
        "reportId": report_id,
        "sourceRef": source_ref,
        "submittedAt": submitted_at,
        "reviewStatus": "reviewed",
        **{
            field: copy.deepcopy(validated_submission[field])
            for field in REPORT_COPY_FIELDS
        },
    }
    try:
        report_validator.validate_report(
            report,
            target,
            capabilities,
        )
    except report_validator.ValidationError as error:
        raise CandidatePreparationError(str(error)) from error
    return report, target


def render_json(report: dict[str, Any]) -> str:
    """生成稳定、便于人工复核的候选 JSON。"""
    return json.dumps(report, ensure_ascii=False, indent=2) + "\n"


def _unified_diff(
    before: str,
    after: str,
    relative_path: Path,
    *,
    new_file: bool = False,
) -> str:
    from_file = "/dev/null" if new_file else f"a/{relative_path.as_posix()}"
    to_file = f"b/{relative_path.as_posix()}"
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=from_file,
            tofile=to_file,
        )
    )


def render_diff(
    report: dict[str, Any],
    target: Path,
    reports: Sequence[dict[str, Any]],
    capabilities: dict[str, dict[str, Any]],
) -> str:
    """在内存中生成候选报告和中英文矩阵的统一差异。"""
    proposed_reports = sorted(
        [*reports, report],
        key=lambda item: item["reportId"],
    )
    outputs = [
        (
            target,
            "",
            render_json(report),
            True,
        ),
        (
            ZH_MATRIX_PATH,
            ZH_MATRIX_PATH.read_text(encoding="utf-8"),
            matrix_generator.render_document(
                proposed_reports,
                capabilities,
                "zh-Hans",
            ),
            False,
        ),
        (
            EN_MATRIX_PATH,
            EN_MATRIX_PATH.read_text(encoding="utf-8"),
            matrix_generator.render_document(
                proposed_reports,
                capabilities,
                "en",
            ),
            False,
        ),
    ]
    return "".join(
        _unified_diff(
            before,
            after,
            path.relative_to(REPOSITORY_ROOT),
            new_file=new_file,
        )
        for path, before, after, new_file in outputs
    )


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "从已完成人工隐私审核的本地草稿准备候选正式报告；"
            "命令只输出到 stdout，不写入仓库"
        )
    )
    parser.add_argument("--submission", required=True, type=Path)
    parser.add_argument("--source-ref", required=True)
    parser.add_argument("--submitted-at", required=True)
    parser.add_argument(
        "--confirm-privacy-reviewed",
        required=True,
        action="store_true",
        help="确认公开来源和草稿已完成人工隐私审核",
    )
    parser.add_argument(
        "--format",
        choices=("json", "diff"),
        default="diff",
    )
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    parser = create_parser()
    options = parser.parse_args(arguments)
    try:
        capabilities, reports = report_validator.load_and_validate_all()
        submission = submission_validator.load_json(options.submission)
        report, target = build_candidate(
            submission,
            options.submission,
            options.source_ref,
            options.submitted_at,
            capabilities,
            reports,
        )
        output = (
            render_json(report)
            if options.format == "json"
            else render_diff(report, target, reports, capabilities)
        )
    except (
        CandidatePreparationError,
        submission_validator.SubmissionValidationError,
        report_validator.ValidationError,
        OSError,
    ):
        # CLI 不回显草稿值、原始正文或路径，详细定位请单独运行本地校验器。
        print(
            "候选报告准备失败：输入或仓库数据未通过校验 / "
            "candidate preparation failed: input or repository data is invalid",
            file=sys.stderr,
        )
        return 1
    sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
