#!/usr/bin/env python3
"""校验本地导出的社区兼容性提交草稿。"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import SchemaError, ValidationError as JSONSchemaError
from referencing import Registry, Resource


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = (
    REPOSITORY_ROOT
    / "contracts/schemas/community-compatibility-submission.schema.json"
)
REPORT_SCHEMA_PATH = (
    REPOSITORY_ROOT
    / "contracts/schemas/community-compatibility-report.schema.json"
)
CAPABILITIES_PATH = (
    REPOSITORY_ROOT / "contracts/community-compatibility/capabilities.json"
)
DATE_TIME_PATTERN = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt]"
    r"[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?"
    r"(?:[Zz]|[+-][0-9]{2}:[0-9]{2})$"
)


class SubmissionValidationError(ValueError):
    """表示提交草稿未通过结构、隐私或跨能力校验。"""


def _load_report_validator():
    source = Path(__file__).with_name("validate.py")
    specification = importlib.util.spec_from_file_location(
        "community_compatibility_report_validator",
        source,
    )
    if specification is None or specification.loader is None:
        raise RuntimeError(f"无法加载报告校验器 / unable to load validator: {source}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


report_validator = _load_report_validator()


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as source:
            return json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        raise SubmissionValidationError(
            f"{path}: 无法读取 JSON / unable to read JSON: {error}"
        ) from error


def _schema_validator() -> Draft202012Validator:
    submission_schema = load_json(SCHEMA_PATH)
    report_schema = load_json(REPORT_SCHEMA_PATH)
    try:
        Draft202012Validator.check_schema(submission_schema)
        Draft202012Validator.check_schema(report_schema)
    except SchemaError as error:
        raise SubmissionValidationError(
            f"Schema 无效 / invalid schema: {error.message}"
        ) from error

    runtime_schema = copy.deepcopy(submission_schema)
    runtime_schema["$id"] = SCHEMA_PATH.as_uri()
    registry = Registry().with_resource(
        REPORT_SCHEMA_PATH.as_uri(),
        Resource.from_contents(report_schema),
    )
    return Draft202012Validator(
        runtime_schema,
        registry=registry,
        format_checker=FormatChecker(),
    )


def _json_location(error: JSONSchemaError) -> str:
    if not error.absolute_path:
        return "$"
    return "$" + "".join(
        f"[{part}]" if isinstance(part, int) else f".{part}"
        for part in error.absolute_path
    )


def _validate_generated_at(value: str, source: Path) -> None:
    if DATE_TIME_PATTERN.fullmatch(value) is None:
        raise SubmissionValidationError(
            f"{source}.generatedAt 必须是带时区的 RFC 3339 时间 / "
            "must be an RFC 3339 date-time with a timezone"
        )
    normalized = value[:-1] + "+00:00" if value[-1] in "Zz" else value
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise SubmissionValidationError(
            f"{source}.generatedAt 日期或时间无效 / has an invalid date or time"
        ) from error
    if parsed.tzinfo is None:
        raise SubmissionValidationError(
            f"{source}.generatedAt 必须包含时区 / must include a timezone"
        )


def _as_report_for_strict_checks(submission: dict[str, Any]) -> dict[str, Any]:
    """仅在内存中补齐审核字段，以复用报告 v2 的严格语义校验。"""
    report = {
        key: copy.deepcopy(value)
        for key, value in submission.items()
        if key
        not in {
            "$schema",
            "submissionSchemaVersion",
            "reportSchemaVersion",
            "generatedAt",
        }
    }
    report.update(
        {
            "$schema": "../../schemas/community-compatibility-report.schema.json",
            "schemaVersion": 2,
            "reportId": "cc-000000",
            "sourceRef": "issue-1",
            "submittedAt": submission["generatedAt"][:10],
            "reviewStatus": "submitted",
        }
    )
    return report


def validate_submission(data: Any, source: Path) -> dict[str, Any]:
    validator = _schema_validator()
    errors = sorted(
        validator.iter_errors(data),
        key=lambda error: [str(part) for part in error.absolute_path],
    )
    if errors:
        error = errors[0]
        raise SubmissionValidationError(
            f"{source}:{_json_location(error)}: {error.message}"
        )
    if not isinstance(data, dict):
        raise SubmissionValidationError(
            f"{source}: 草稿必须是对象 / submission must be an object"
        )
    _validate_generated_at(data["generatedAt"], source)

    capabilities = report_validator.validate_capabilities(
        report_validator.load_json(CAPABILITIES_PATH)
    )
    try:
        report_validator.validate_report(
            _as_report_for_strict_checks(data),
            source,
            capabilities,
            example=True,
        )
    except report_validator.ValidationError as error:
        raise SubmissionValidationError(str(error)) from error
    return data


def validate_file(path: Path) -> dict[str, Any]:
    return validate_submission(load_json(path), path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="校验社区兼容性提交草稿 / validate submission drafts"
    )
    parser.add_argument("submissions", nargs="+", type=Path)
    arguments = parser.parse_args()
    try:
        for source in arguments.submissions:
            validate_file(source)
            print(f"草稿通过 / submission passed: {source}")
    except SubmissionValidationError as error:
        print(
            f"草稿校验失败 / submission validation failed: {error}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
