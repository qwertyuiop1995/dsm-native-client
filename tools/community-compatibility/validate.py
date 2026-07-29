#!/usr/bin/env python3
"""校验社区兼容性能力注册表和结构化报告。"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPABILITIES_PATH = (
    REPOSITORY_ROOT / "contracts/community-compatibility/capabilities.json"
)
REPORTS_DIRECTORY = (
    REPOSITORY_ROOT / "contracts/community-compatibility/reports"
)
EXAMPLES_DIRECTORY = (
    REPOSITORY_ROOT / "contracts/community-compatibility/examples"
)

PLATFORMS = {"macOS", "iPhone", "iPad", "Android", "Windows"}
ARCHITECTURES = {"x86_64", "aarch64", "armv7", "unknown"}
CONNECTION_TYPES = {
    "lan",
    "quickconnect-direct",
    "quickconnect-relay",
    "reverse-proxy",
    "unknown",
}
ACCOUNT_ROLES = {"standard", "administrator", "unknown"}
CERTIFICATE_TYPES = {"public-ca", "private-ca", "self-signed", "unknown"}
REVIEW_STATUSES = {
    "submitted",
    "reviewed",
    "corroborated",
    "maintainer-verified",
    "disputed",
    "superseded",
}
RESULT_STATUSES = {"passed", "failed", "partial", "skipped", "not-supported"}
FAILURE_CATEGORIES = {
    "permission-denied",
    "operation-failed",
    "connection-failed",
    "unexpected-result",
    "app-crashed",
    "unknown",
}
OPERATIONS = {"read", "controlled-write"}

REPORT_ID_PATTERN = re.compile(r"^cc-[0-9]{6}$")
SOURCE_REF_PATTERN = re.compile(r"^(?:issue|pull)-[1-9][0-9]*$")
MODEL_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]{1,39}$")
DSM_VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}$")
DSM_BUILD_PATTERN = re.compile(r"^[0-9]{4,8}$")
DSM_UPDATE_PATTERN = re.compile(r"^(?:[0-9]{1,3}|none|unknown)$")
STABLE_ID_PATTERN = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
PACKAGE_ID_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

PROHIBITED_KEY_PATTERN = re.compile(
    r"(?:password|passwd|otp|username|accountname|hostname|quickconnect"
    r"|serialnumber|macaddress|synotoken|cookie|sessionid|sid|did"
    r"|filepath|filename|sharename|volumename|log|response)",
    re.IGNORECASE,
)
PROHIBITED_VALUE_PATTERNS = (
    ("URL", re.compile(r"https?://", re.IGNORECASE)),
    (
        "IPv4 地址",
        re.compile(
            r"(?<![0-9])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})"
            r"(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9])"
        ),
    ),
    (
        "电子邮箱",
        re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE),
    ),
    (
        "NAS 文件路径",
        re.compile(r"(?:/volume[0-9]+/|/homes?/|\\\\\\\\[^\\s]+\\\\)", re.IGNORECASE),
    ),
    (
        "Windows 文件路径",
        re.compile(r"\b[A-Z]:\\(?:[^\\\r\n]+\\)*", re.IGNORECASE),
    ),
    (
        "疑似会话秘密",
        re.compile(
            r"(?:synotoken|cookie|session[_-]?id|sid|did|token)\s*[:=]",
            re.IGNORECASE,
        ),
    ),
)


class ValidationError(ValueError):
    """表示兼容性数据未通过校验。"""


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as source:
            return json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(
            f"{path}: 无法读取 JSON / unable to read JSON: {error}"
        ) from error


def require_object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{location} 必须是对象 / must be an object")
    return value


def require_array(value: Any, location: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationError(f"{location} 必须是数组 / must be an array")
    return value


def require_string(
    value: Any,
    location: str,
    *,
    minimum: int = 1,
    maximum: int = 200,
) -> str:
    if not isinstance(value, str) or not minimum <= len(value) <= maximum:
        raise ValidationError(
            f"{location} 必须是长度 {minimum} 到 {maximum} 的字符串 / "
            f"must be a string between {minimum} and {maximum} characters"
        )
    return value


def require_exact_keys(
    value: dict[str, Any],
    location: str,
    required: set[str],
    optional: set[str] | None = None,
) -> None:
    optional = optional or set()
    missing = required - value.keys()
    unexpected = value.keys() - required - optional
    if missing:
        raise ValidationError(
            f"{location} 缺少字段 / missing fields: {', '.join(sorted(missing))}"
        )
    if unexpected:
        raise ValidationError(
            f"{location} 包含未定义字段 / contains undefined fields: "
            f"{', '.join(sorted(unexpected))}"
        )


def require_enum(value: Any, location: str, allowed: set[str]) -> str:
    if not isinstance(value, str) or value not in allowed:
        choices = ", ".join(sorted(allowed))
        raise ValidationError(
            f"{location} 必须是以下值之一 / must be one of: {choices}"
        )
    return value


def require_pattern(value: Any, location: str, pattern: re.Pattern[str]) -> str:
    text = require_string(value, location)
    if pattern.fullmatch(text) is None:
        raise ValidationError(f"{location} 格式无效 / has an invalid format")
    return text


def require_date(value: Any, location: str) -> str:
    text = require_string(value, location, maximum=10)
    try:
        date.fromisoformat(text)
    except ValueError as error:
        raise ValidationError(
            f"{location} 必须是 YYYY-MM-DD 日期 / must be a YYYY-MM-DD date"
        ) from error
    return text


def scan_privacy(value: Any, location: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if PROHIBITED_KEY_PATTERN.search(key):
                raise ValidationError(
                    f"{location}.{key} 使用了禁止的敏感字段名 / "
                    "uses a prohibited sensitive field name"
                )
            scan_privacy(child, f"{location}.{key}")
        return
    if isinstance(value, list):
        for index, child in enumerate(value):
            scan_privacy(child, f"{location}[{index}]")
        return
    if not isinstance(value, str):
        return
    for description, pattern in PROHIBITED_VALUE_PATTERNS:
        if pattern.search(value):
            raise ValidationError(
                f"{location} 包含禁止的{description} / "
                f"contains prohibited private data ({description})"
            )


def validate_capabilities(data: Any) -> dict[str, dict[str, Any]]:
    root = require_object(data, "capabilities")
    require_exact_keys(
        root,
        "capabilities",
        {"schemaVersion", "testSuiteVersion", "capabilities"},
    )
    if root["schemaVersion"] != 1 or root["testSuiteVersion"] != 1:
        raise ValidationError(
            "能力注册表版本必须为 1 / capability registry versions must be 1"
        )

    registered: dict[str, dict[str, Any]] = {}
    for index, raw_capability in enumerate(
        require_array(root["capabilities"], "capabilities.capabilities")
    ):
        location = f"capabilities.capabilities[{index}]"
        capability = require_object(raw_capability, location)
        require_exact_keys(
            capability,
            location,
            {"id", "module", "operation", "required", "name"},
        )
        capability_id = require_pattern(
            capability["id"], f"{location}.id", STABLE_ID_PATTERN
        )
        if capability_id in registered:
            raise ValidationError(
                f"{location}.id 与已有能力重复 / duplicates a capability: "
                f"{capability_id}"
            )
        require_pattern(capability["module"], f"{location}.module", PACKAGE_ID_PATTERN)
        require_enum(capability["operation"], f"{location}.operation", OPERATIONS)
        if not isinstance(capability["required"], bool):
            raise ValidationError(
                f"{location}.required 必须是布尔值 / must be a Boolean"
            )
        names = require_object(capability["name"], f"{location}.name")
        require_exact_keys(names, f"{location}.name", {"zh-Hans", "en"})
        require_string(names["zh-Hans"], f"{location}.name.zh-Hans", maximum=100)
        require_string(names["en"], f"{location}.name.en", maximum=140)
        registered[capability_id] = capability

    if not registered:
        raise ValidationError(
            "能力注册表不能为空 / capability registry cannot be empty"
        )
    return registered


def validate_report(
    data: Any,
    source: Path,
    capabilities: dict[str, dict[str, Any]],
    *,
    example: bool = False,
) -> dict[str, Any]:
    report = require_object(data, str(source))
    require_exact_keys(
        report,
        str(source),
        {
            "$schema",
            "schemaVersion",
            "reportId",
            "sourceRef",
            "submittedAt",
            "reviewStatus",
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
        },
    )
    if report["$schema"] != "../../schemas/community-compatibility-report.schema.json":
        raise ValidationError(f"{source}: $schema 路径无效 / path is invalid")
    if report["schemaVersion"] != 1 or report["testSuiteVersion"] != 1:
        raise ValidationError(
            f"{source}: schemaVersion 和 testSuiteVersion 必须为 1 / must be 1"
        )

    report_id = require_pattern(report["reportId"], f"{source}.reportId", REPORT_ID_PATTERN)
    if not example and source.stem != report_id:
        raise ValidationError(
            f"{source}: 文件名必须与 reportId 一致 / "
            "file name must match reportId"
        )
    require_pattern(
        report["sourceRef"], f"{source}.sourceRef", SOURCE_REF_PATTERN
    )
    require_date(report["submittedAt"], f"{source}.submittedAt")
    review_status = require_enum(
        report["reviewStatus"], f"{source}.reviewStatus", REVIEW_STATUSES
    )
    if not example and review_status == "submitted":
        raise ValidationError(
            f"{source}: 未审核的 submitted 报告不能进入 reports 目录 / "
            "an unreviewed submitted report cannot enter the reports directory"
        )

    app = require_object(report["app"], f"{source}.app")
    require_exact_keys(app, f"{source}.app", {"version", "platform", "platformVersion"})
    require_string(app["version"], f"{source}.app.version", maximum=40)
    require_enum(app["platform"], f"{source}.app.platform", PLATFORMS)
    require_string(app["platformVersion"], f"{source}.app.platformVersion", maximum=40)

    nas = require_object(report["nas"], f"{source}.nas")
    require_exact_keys(nas, f"{source}.nas", {"model", "architecture"})
    require_pattern(nas["model"], f"{source}.nas.model", MODEL_PATTERN)
    require_enum(nas["architecture"], f"{source}.nas.architecture", ARCHITECTURES)

    dsm = require_object(report["dsm"], f"{source}.dsm")
    require_exact_keys(dsm, f"{source}.dsm", {"version", "build", "update"})
    require_pattern(dsm["version"], f"{source}.dsm.version", DSM_VERSION_PATTERN)
    require_pattern(dsm["build"], f"{source}.dsm.build", DSM_BUILD_PATTERN)
    require_pattern(dsm["update"], f"{source}.dsm.update", DSM_UPDATE_PATTERN)

    package_ids: set[str] = set()
    for index, raw_package in enumerate(
        require_array(report["packages"], f"{source}.packages")
    ):
        location = f"{source}.packages[{index}]"
        package = require_object(raw_package, location)
        require_exact_keys(package, location, {"id", "version"})
        package_id = require_pattern(package["id"], f"{location}.id", PACKAGE_ID_PATTERN)
        if package_id in package_ids:
            raise ValidationError(
                f"{location}.id 重复 / is duplicated: {package_id}"
            )
        package_ids.add(package_id)
        require_string(package["version"], f"{location}.version", maximum=60)

    require_enum(
        report["connectionType"], f"{source}.connectionType", CONNECTION_TYPES
    )
    require_enum(report["accountRole"], f"{source}.accountRole", ACCOUNT_ROLES)
    require_enum(
        report["certificateType"], f"{source}.certificateType", CERTIFICATE_TYPES
    )
    if report["privacyAttestation"] is not True:
        raise ValidationError(
            f"{source}.privacyAttestation 必须为 true / must be true"
        )

    result_ids: set[str] = set()
    for index, raw_result in enumerate(
        require_array(report["results"], f"{source}.results")
    ):
        location = f"{source}.results[{index}]"
        result = require_object(raw_result, location)
        require_exact_keys(
            result,
            location,
            {"capabilityId", "status"},
            {"failureCategory"},
        )
        capability_id = require_pattern(
            result["capabilityId"], f"{location}.capabilityId", STABLE_ID_PATTERN
        )
        if capability_id not in capabilities:
            raise ValidationError(
                f"{location}.capabilityId 未注册 / is not registered: "
                f"{capability_id}"
            )
        if capability_id in result_ids:
            raise ValidationError(
                f"{location}.capabilityId 重复 / is duplicated: {capability_id}"
            )
        result_ids.add(capability_id)
        status = require_enum(result["status"], f"{location}.status", RESULT_STATUSES)
        has_failure_category = "failureCategory" in result
        if status in {"failed", "partial"} and not has_failure_category:
            raise ValidationError(
                f"{location} 的 {status} 结果必须填写 failureCategory / "
                f"a {status} result requires failureCategory"
            )
        if status not in {"failed", "partial"} and has_failure_category:
            raise ValidationError(
                f"{location} 的 {status} 结果不得填写 failureCategory / "
                f"a {status} result must not include failureCategory"
            )
        if has_failure_category:
            require_enum(
                result["failureCategory"],
                f"{location}.failureCategory",
                FAILURE_CATEGORIES,
            )

    if not result_ids:
        raise ValidationError(f"{source}.results 不能为空 / cannot be empty")
    scan_privacy(report)
    return report


def load_and_validate_all(
    *,
    reports_directory: Path = REPORTS_DIRECTORY,
    examples_directory: Path = EXAMPLES_DIRECTORY,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    capabilities = validate_capabilities(load_json(CAPABILITIES_PATH))
    reports: list[dict[str, Any]] = []
    report_ids: set[str] = set()
    source_refs: set[str] = set()

    for source in sorted(reports_directory.glob("*.json")):
        report = validate_report(load_json(source), source, capabilities)
        if report["reportId"] in report_ids:
            raise ValidationError(
                f"{source}: reportId 重复 / is duplicated: {report['reportId']}"
            )
        report_ids.add(report["reportId"])
        if report["sourceRef"] in source_refs:
            raise ValidationError(
                f"{source}: sourceRef 重复 / is duplicated: {report['sourceRef']}"
            )
        source_refs.add(report["sourceRef"])
        reports.append(report)

    for source in sorted(examples_directory.glob("*.json")):
        validate_report(load_json(source), source, capabilities, example=True)

    return capabilities, reports


def main() -> int:
    parser = argparse.ArgumentParser(description="校验社区兼容性结构化数据")
    parser.parse_args()
    try:
        capabilities, reports = load_and_validate_all()
    except ValidationError as error:
        print(
            f"社区兼容性校验失败 / Community compatibility validation failed: "
            f"{error}",
            file=sys.stderr,
        )
        return 1
    print(
        f"社区兼容性校验通过 / Community compatibility validation passed: "
        f"{len(capabilities)} 个能力 / capabilities，"
        f"{len(reports)} 份已审核报告 / reviewed reports"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
