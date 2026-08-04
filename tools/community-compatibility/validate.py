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
FAILURE_STAGES = {
    "setup",
    "discovery",
    "authentication",
    "request",
    "submission",
    "readback",
    "final-state",
    "cleanup",
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
COMMIT_PATTERN = re.compile(r"^(?:[0-9a-fA-F]{7,40}|unknown)$")
API_NAME_PATTERN = re.compile(r"^(?:SYNO(?:\.[A-Za-z0-9_]+)+|unknown)$")
PRIVACY_SAFE_KEYS = {"rawResponseIncluded"}

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
            if key not in PRIVACY_SAFE_KEYS and PROHIBITED_KEY_PATTERN.search(key):
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
    if root["schemaVersion"] != 1 or root["testSuiteVersion"] != 2:
        raise ValidationError(
            "能力注册表 schemaVersion 必须为 1，testSuiteVersion 必须为 2 / "
            "capability registry schemaVersion must be 1 and "
            "testSuiteVersion must be 2"
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
            {
                "id",
                "module",
                "operation",
                "required",
                "introducedInTestSuiteVersion",
                "name",
            },
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
        introduced_version = capability["introducedInTestSuiteVersion"]
        if type(introduced_version) is not int or not (
            1 <= introduced_version <= root["testSuiteVersion"]
        ):
            raise ValidationError(
                f"{location}.introducedInTestSuiteVersion 必须是 1 到 "
                f"{root['testSuiteVersion']} 的整数 / must be an integer between "
                f"1 and {root['testSuiteVersion']}"
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
        {"supersedes"},
    )
    if report["$schema"] != "../../schemas/community-compatibility-report.schema.json":
        raise ValidationError(f"{source}: $schema 路径无效 / path is invalid")
    if report["schemaVersion"] != 2 or report["testSuiteVersion"] not in {1, 2}:
        raise ValidationError(
            f"{source}: schemaVersion 必须为 2，testSuiteVersion 必须为 1 或 2 / "
            "schemaVersion must be 2 and testSuiteVersion must be 1 or 2"
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
    if "supersedes" in report:
        supersedes = require_array(report["supersedes"], f"{source}.supersedes")
        if not supersedes:
            raise ValidationError(
                f"{source}.supersedes 不能为空 / cannot be empty"
            )
        target_ids: set[str] = set()
        for index, target_id in enumerate(supersedes):
            target_id = require_pattern(
                target_id,
                f"{source}.supersedes[{index}]",
                REPORT_ID_PATTERN,
            )
            if target_id in target_ids:
                raise ValidationError(
                    f"{source}.supersedes 包含重复报告 / contains a duplicate: "
                    f"{target_id}"
                )
            target_ids.add(target_id)

    app = require_object(report["app"], f"{source}.app")
    require_exact_keys(
        app,
        f"{source}.app",
        {"version", "commit", "platform", "platformVersion"},
    )
    require_string(app["version"], f"{source}.app.version", maximum=40)
    require_pattern(app["commit"], f"{source}.app.commit", COMMIT_PATTERN)
    platform = require_enum(app["platform"], f"{source}.app.platform", PLATFORMS)
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
    result_statuses: dict[str, str] = {}
    for index, raw_result in enumerate(
        require_array(report["results"], f"{source}.results")
    ):
        location = f"{source}.results[{index}]"
        result = require_object(raw_result, location)
        require_exact_keys(
            result,
            location,
            {"capabilityId", "status"},
            {"failure"},
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
        result_statuses[capability_id] = status
        has_failure = "failure" in result
        if status in {"failed", "partial"} and not has_failure:
            raise ValidationError(
                f"{location} 的 {status} 结果必须填写 failure / "
                f"a {status} result requires failure"
            )
        if status not in {"failed", "partial"} and has_failure:
            raise ValidationError(
                f"{location} 的 {status} 结果不得填写 failure / "
                f"a {status} result must not include failure"
            )
        if has_failure:
            failure = require_object(result["failure"], f"{location}.failure")
            require_exact_keys(
                failure,
                f"{location}.failure",
                {
                    "stage",
                    "errorCategory",
                    "apiName",
                    "apiVersion",
                    "httpStatus",
                    "retryPerformed",
                    "rawResponseIncluded",
                },
            )
            require_enum(
                failure["stage"],
                f"{location}.failure.stage",
                FAILURE_STAGES,
            )
            require_enum(
                failure["errorCategory"],
                f"{location}.failure.errorCategory",
                FAILURE_CATEGORIES,
            )
            require_pattern(
                failure["apiName"],
                f"{location}.failure.apiName",
                API_NAME_PATTERN,
            )
            api_version = failure["apiVersion"]
            if api_version != "unknown" and (
                type(api_version) is not int or not 1 <= api_version <= 99
            ):
                raise ValidationError(
                    f"{location}.failure.apiVersion 必须为 1 到 99 或 unknown / "
                    "must be between 1 and 99 or unknown"
                )
            http_status = failure["httpStatus"]
            if http_status is not None and (
                type(http_status) is not int or not 100 <= http_status <= 599
            ):
                raise ValidationError(
                    f"{location}.failure.httpStatus 必须为 100 到 599 或 null / "
                    "must be between 100 and 599 or null"
                )
            if type(failure["retryPerformed"]) is not bool:
                raise ValidationError(
                    f"{location}.failure.retryPerformed 必须为布尔值 / "
                    "must be a Boolean"
                )
            if failure["rawResponseIncluded"] is not False:
                raise ValidationError(
                    f"{location}.failure.rawResponseIncluded 必须为 false / "
                    "must be false"
                )

    test_suite_version = report["testSuiteVersion"]
    expected_result_ids = {
        capability_id
        for capability_id, capability in capabilities.items()
        if capability["introducedInTestSuiteVersion"] <= test_suite_version
    }
    missing_result_ids = expected_result_ids - result_ids
    unexpected_result_ids = result_ids - expected_result_ids
    if missing_result_ids:
        raise ValidationError(
            f"{source}.results 缺少 testSuiteVersion {test_suite_version} 的能力 / "
            f"is missing capabilities for testSuiteVersion {test_suite_version}: "
            f"{', '.join(sorted(missing_result_ids))}"
        )
    if unexpected_result_ids:
        raise ValidationError(
            f"{source}.results 包含不属于 testSuiteVersion {test_suite_version} 的能力 / "
            f"contains capabilities outside testSuiteVersion {test_suite_version}: "
            f"{', '.join(sorted(unexpected_result_ids))}"
        )

    if platform != "macOS":
        invalid_desktop_results = sorted(
            capability_id
            for capability_id in expected_result_ids
            if capabilities[capability_id]["module"] == "desktop-drive"
            and result_statuses[capability_id] != "not-supported"
        )
        if invalid_desktop_results:
            raise ValidationError(
                f"{source}.results 的非 macOS 桌面云盘能力必须为 not-supported / "
                "desktop-drive capabilities on non-macOS platforms must be "
                f"not-supported: {', '.join(invalid_desktop_results)}"
            )
    scan_privacy(report)
    return report


def exact_environment_key(report: dict[str, Any]) -> tuple[Any, ...]:
    """返回用于比较已审核报告的精确、稳定环境键。"""

    packages = tuple(
        sorted((package["id"], package["version"]) for package in report["packages"])
    )
    return (
        report["nas"]["model"],
        report["nas"]["architecture"],
        report["dsm"]["version"],
        report["dsm"]["build"],
        report["dsm"]["update"],
        report["app"]["platform"],
        report["app"]["platformVersion"],
        report["app"]["version"],
        report["app"]["commit"],
        packages,
        report["connectionType"],
        report["accountRole"],
        report["certificateType"],
        report["testSuiteVersion"],
    )


def result_status_map(report: dict[str, Any]) -> dict[str, str]:
    """按能力 ID 返回状态，避免数组顺序影响审计。"""

    return {
        result["capabilityId"]: result["status"] for result in report["results"]
    }


def _result_signature(report: dict[str, Any]) -> tuple[tuple[str, str], ...]:
    return tuple(sorted(result_status_map(report).items()))


def _failure_signature(result: dict[str, Any]) -> str | None:
    failure = result.get("failure")
    if failure is None:
        return None
    return json.dumps(failure, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _warning(
    code: str,
    reports: list[str] | set[str] | tuple[str, ...],
    message: str,
    capabilities: list[str] | set[str] | tuple[str, ...] = (),
) -> dict[str, Any]:
    """创建字段和排序都稳定的维护者警告。"""

    return {
        "level": "warning",
        "code": code,
        "reportIds": sorted(reports),
        "capabilityIds": sorted(capabilities),
        "message": message,
    }


def validate_supersession_graph(reports: list[dict[str, Any]]) -> None:
    """校验替换关系图；会改变生成结果的关系错误必须阻断。"""

    by_id = {report["reportId"]: report for report in reports}
    if len(by_id) != len(reports):
        duplicate_ids = sorted(
            report_id
            for report_id in by_id
            if sum(report["reportId"] == report_id for report in reports) > 1
        )
        raise ValidationError(
            "reportId 重复 / duplicated report IDs: " + ", ".join(duplicate_ids)
        )
    inbound: dict[str, list[str]] = {report_id: [] for report_id in by_id}
    edges: dict[str, list[str]] = {report_id: [] for report_id in by_id}

    for report in reports:
        source_id = report["reportId"]
        for target_id in report.get("supersedes", []):
            if target_id not in by_id:
                raise ValidationError(
                    f"{source_id}.supersedes 引用了不存在的报告 / references an "
                    f"unknown report: {target_id}"
                )
            if target_id == source_id:
                raise ValidationError(
                    f"{source_id}.supersedes 不得引用自身 / must not reference itself"
                )
            target = by_id[target_id]
            if report["submittedAt"] < target["submittedAt"]:
                raise ValidationError(
                    f"{source_id} 的提交日期早于被取代报告 {target_id} / submission "
                    "date is earlier than the superseded report"
                )
            if target["reviewStatus"] != "superseded":
                raise ValidationError(
                    f"{target_id} 被 {source_id} 取代但 reviewStatus 不是 superseded / "
                    "is superseded but reviewStatus is not superseded"
                )
            edges[source_id].append(target_id)
            inbound[target_id].append(source_id)

    for report in reports:
        report_id = report["reportId"]
        if report["reviewStatus"] == "superseded" and not inbound[report_id]:
            raise ValidationError(
                f"{report_id} 标记为 superseded 但没有报告声明 supersedes / is marked "
                "superseded without an incoming supersedes relation"
            )

    states: dict[str, int] = {report_id: 0 for report_id in by_id}

    def visit(report_id: str, path: list[str]) -> None:
        if states[report_id] == 1:
            cycle_start = path.index(report_id)
            cycle = path[cycle_start:] + [report_id]
            raise ValidationError(
                "supersedes 关系形成环 / relation contains a cycle: "
                + " -> ".join(cycle)
            )
        if states[report_id] == 2:
            return
        states[report_id] = 1
        for target_id in sorted(edges[report_id]):
            visit(target_id, path + [report_id])
        states[report_id] = 2

    for report_id in sorted(by_id):
        visit(report_id, [])


def audit_reports(reports: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """返回不阻断合并、但需要维护者复核的稳定结构化警告。"""

    warnings: list[dict[str, Any]] = []
    active_reports = [
        report for report in reports if report["reviewStatus"] != "superseded"
    ]
    grouped: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for report in active_reports:
        grouped.setdefault(exact_environment_key(report), []).append(report)

    matching_report_ids: set[str] = set()
    conflicting_report_ids: set[str] = set()
    for group in grouped.values():
        if len(group) < 2:
            continue
        by_signature: dict[
            tuple[tuple[str, str], ...], list[dict[str, Any]]
        ] = {}
        for report in group:
            by_signature.setdefault(_result_signature(report), []).append(report)
        for matching in by_signature.values():
            if len(matching) < 2:
                continue
            report_ids = {report["reportId"] for report in matching}
            matching_report_ids.update(report_ids)
            warnings.append(
                _warning(
                    "MATCHING_ENVIRONMENT_REPORTS",
                    report_ids,
                    "相同精确环境包含相符结果，请人工核对贡献者独立性 / "
                    "matching results share an exact environment; verify contributor "
                    "independence manually",
                )
            )
            if not any(
                report["reviewStatus"] in {"corroborated", "maintainer-verified"}
                for report in matching
            ):
                warnings.append(
                    _warning(
                        "MATCH_NOT_MARKED_CORROBORATED",
                        report_ids,
                        "相符报告尚未标记为 corroborated / matching reports are not "
                        "marked corroborated",
                    )
                )

        status_maps = {report["reportId"]: result_status_map(report) for report in group}
        capability_ids = sorted(next(iter(status_maps.values())))
        conflicts: set[str] = set()
        coverage: set[str] = set()
        for capability_id in capability_ids:
            statuses = {
                status_map[capability_id] for status_map in status_maps.values()
            }
            if len(statuses) < 2:
                continue
            observed = statuses - {"skipped"}
            if len(observed) > 1:
                conflicts.add(capability_id)
            if "skipped" in statuses and observed:
                coverage.add(capability_id)
        group_ids = {report["reportId"] for report in group}
        if conflicts:
            conflicting_report_ids.update(group_ids)
            warnings.append(
                _warning(
                    "CONFLICTING_ENVIRONMENT_RESULTS",
                    group_ids,
                    "相同精确环境包含冲突结果 / conflicting results share an exact "
                    "environment",
                    conflicts,
                )
            )
            not_disputed = {
                report["reportId"]
                for report in group
                if report["reviewStatus"] not in {"disputed", "maintainer-verified"}
            }
            if not_disputed:
                warnings.append(
                    _warning(
                        "CONFLICT_NOT_MARKED_DISPUTED",
                        not_disputed,
                        "冲突报告尚未标记为 disputed / conflicting reports are not "
                        "marked disputed",
                        conflicts,
                    )
                )
        if coverage:
            warnings.append(
                _warning(
                    "COVERAGE_DIVERGENCE",
                    group_ids,
                    "相同精确环境的执行覆盖范围不同 / execution coverage differs "
                    "within an exact environment",
                    coverage,
                )
            )

        for capability_id in capability_ids:
            details: dict[str, dict[str, set[str]]] = {}
            for report in group:
                result = next(
                    item
                    for item in report["results"]
                    if item["capabilityId"] == capability_id
                )
                if result["status"] not in {"failed", "partial"}:
                    continue
                signature = _failure_signature(result)
                if signature is not None:
                    details.setdefault(result["status"], {}).setdefault(
                        signature, set()
                    ).add(report["reportId"])
            diverged_statuses = {
                status: signatures
                for status, signatures in details.items()
                if len(signatures) > 1
            }
            if diverged_statuses:
                involved = {
                    report_id
                    for signatures in diverged_statuses.values()
                    for report_ids in signatures.values()
                    for report_id in report_ids
                }
                warnings.append(
                    _warning(
                        "FAILURE_DETAIL_DIVERGENCE",
                        involved,
                        "相同结果状态的失败详情不同 / failure details differ for the "
                        "same result status",
                        [capability_id],
                    )
                )

    for report in active_reports:
        report_id = report["reportId"]
        if report["reviewStatus"] == "corroborated" and report_id not in matching_report_ids:
            warnings.append(
                _warning(
                    "CORROBORATED_WITHOUT_MATCH",
                    [report_id],
                    "corroborated 报告没有相符的精确环境报告 / corroborated report "
                    "has no matching exact-environment report",
                )
            )
        if report["reviewStatus"] == "disputed" and report_id not in conflicting_report_ids:
            warnings.append(
                _warning(
                    "DISPUTED_WITHOUT_CONFLICT",
                    [report_id],
                    "disputed 报告没有检测到结构化冲突 / disputed report has no "
                    "detected structured conflict",
                )
            )

    by_id = {report["reportId"]: report for report in reports}
    successors: dict[str, list[str]] = {}
    for report in reports:
        source_id = report["reportId"]
        for target_id in report.get("supersedes", []):
            target = by_id.get(target_id)
            if target is None:
                continue
            successors.setdefault(target_id, []).append(source_id)
            if report["submittedAt"] == target["submittedAt"]:
                warnings.append(
                    _warning(
                        "SUPERSEDES_SAME_DAY",
                        [source_id, target_id],
                        "替换关系发生在同一提交日期，请人工核对顺序 / supersession "
                        "uses the same submission date; verify ordering manually",
                    )
                )
            if exact_environment_key(report) != exact_environment_key(target):
                warnings.append(
                    _warning(
                        "SUPERSEDES_KEY_MISMATCH",
                        [source_id, target_id],
                        "替换关系两端的精确环境键不同，请人工核对 / supersession "
                        "links different exact-environment keys; verify manually",
                    )
                )
    for target_id, source_ids in successors.items():
        active_source_ids = [
            source_id
            for source_id in source_ids
            if by_id[source_id]["reviewStatus"] != "superseded"
        ]
        if len(active_source_ids) > 1:
            warnings.append(
                _warning(
                    "MULTIPLE_ACTIVE_SUCCESSORS",
                    [target_id, *active_source_ids],
                    "一个旧报告存在多个有效后继，请人工确认分支 / one report has "
                    "multiple active successors; review the branch manually",
                )
            )

    return sorted(
        warnings,
        key=lambda warning: (
            warning["code"],
            tuple(warning["reportIds"]),
            tuple(warning["capabilityIds"]),
        ),
    )


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

    validate_supersession_graph(reports)
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
    warnings = audit_reports(reports)
    for warning in warnings:
        print(json.dumps(warning, ensure_ascii=False, sort_keys=True), file=sys.stderr)
    print(
        f"社区兼容性校验通过 / Community compatibility validation passed: "
        f"{len(capabilities)} 个能力 / capabilities，"
        f"{len(reports)} 份已审核报告 / reviewed reports，"
        f"{len(warnings)} 条维护者警告 / maintainer warnings"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
