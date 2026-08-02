#!/usr/bin/env python3
"""校验请求 Fixture 和统一写操作结果示例。"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REQUEST_ROOT = REPOSITORY_ROOT / "contracts/request-fixtures"
MUTATION_ROOT = REPOSITORY_ROOT / "contracts/mutation-results/examples"

IDENTIFIER_PATTERN = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
MODULE_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
OPERATION_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:[A-Z][a-z0-9]*)*$")
API_PATTERN = re.compile(r"^SYNO\.[A-Za-z0-9_.]+$")
METHOD_PATTERN = re.compile(r"^[a-z][a-z0-9_]{0,79}$")
PATH_PATTERN = re.compile(r"^(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.cgi$")
PARAMETER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,79}$")
SAFE_TAG_PATTERN = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")

SENSITIVE_PARAMETER_PATTERN = re.compile(
    r"^(?:_?sid|synotoken|cookie|did|password(?:_confirm)?|passwd|otp(?:_code)?|"
    r"device_(?:id|token)|access_token|refresh_token|token|account|username|"
    r"hostname|server_name|quickconnect_id)$",
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
    ("电子邮箱", re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)),
    (
        "真实或绝对路径",
        re.compile(
            r"(?:^|[\"'\\s\\[])/(?!/)[^\\s\"']+|[A-Za-z]:\\|\\\\[^\\s]+\\",
            re.IGNORECASE,
        ),
    ),
)

REQUEST_REQUIRED_KEYS = {
    "schemaVersion",
    "fixtureId",
    "module",
    "operation",
    "api",
    "transport",
    "parameters",
    "authentication",
    "policy",
    "source",
}
MUTATION_REQUIRED_KEYS = {
    "schemaVersion",
    "status",
    "operation",
    "submitted",
    "requiresRefresh",
    "counts",
}
MUTATION_OPTIONAL_KEYS = {"errorCategory", "localizationKey", "diagnosticTag"}
MUTATION_STATUSES = {
    "confirmedSuccess",
    "confirmedFailure",
    "submittedButUnverified",
    "partialSuccess",
    "cancelledBeforeSubmission",
    "cancellationRequestedAfterSubmission",
    "permissionDenied",
    "unsupported",
}
ERROR_CATEGORIES = {
    "validation",
    "authentication",
    "permission",
    "conflict",
    "network",
    "server",
    "unsupported",
    "unknown",
}


class ValidationError(ValueError):
    """表示契约文件不满足提交要求。"""


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"{path}: 无法读取 JSON：{error}") from error


def require_object_keys(
    value: Any,
    location: str,
    required: set[str],
    optional: set[str] | None = None,
) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{location} 必须是对象")
    optional = optional or set()
    missing = required - value.keys()
    unexpected = value.keys() - required - optional
    if missing:
        raise ValidationError(f"{location} 缺少字段：{', '.join(sorted(missing))}")
    if unexpected:
        raise ValidationError(f"{location} 包含未定义字段：{', '.join(sorted(unexpected))}")
    return value


def require_string(
    value: Any,
    location: str,
    pattern: re.Pattern[str] | None = None,
) -> str:
    if not isinstance(value, str) or not value:
        raise ValidationError(f"{location} 必须是非空字符串")
    if pattern and pattern.fullmatch(value) is None:
        raise ValidationError(f"{location} 格式无效")
    return value


def require_enum(value: Any, location: str, choices: set[str]) -> str:
    if not isinstance(value, str) or value not in choices:
        raise ValidationError(f"{location} 必须是以下值之一：{', '.join(sorted(choices))}")
    return value


def require_boolean(value: Any, location: str) -> bool:
    if not isinstance(value, bool):
        raise ValidationError(f"{location} 必须是布尔值")
    return value


def require_nonnegative_integer(value: Any, location: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValidationError(f"{location} 必须是非负整数")
    return value


def scan_privacy(value: Any, location: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SENSITIVE_PARAMETER_PATTERN.fullmatch(key):
                raise ValidationError(f"{location}.{key} 不得保存敏感字段")
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
            raise ValidationError(f"{location} 包含禁止的{description}")


def validate_request_fixture(value: Any, path: Path) -> dict[str, Any]:
    request = require_object_keys(value, str(path), REQUEST_REQUIRED_KEYS)
    if request["schemaVersion"] != 1:
        raise ValidationError(f"{path}.schemaVersion 必须为 1")
    require_string(request["fixtureId"], f"{path}.fixtureId", IDENTIFIER_PATTERN)
    require_string(request["module"], f"{path}.module", MODULE_PATTERN)
    require_string(request["operation"], f"{path}.operation", OPERATION_PATTERN)

    api = require_object_keys(
        request["api"],
        f"{path}.api",
        {"name", "method", "preferredVersion", "resolvedVersion", "resolvedPath"},
    )
    require_string(api["name"], f"{path}.api.name", API_PATTERN)
    require_string(api["method"], f"{path}.api.method", METHOD_PATTERN)
    for key in ("preferredVersion", "resolvedVersion"):
        if isinstance(api[key], bool) or not isinstance(api[key], int) or api[key] < 1:
            raise ValidationError(f"{path}.api.{key} 必须是正整数")
    require_string(api["resolvedPath"], f"{path}.api.resolvedPath", PATH_PATTERN)

    transport = require_object_keys(
        request["transport"],
        f"{path}.transport",
        {"httpMethod", "requestFormat"},
    )
    require_enum(transport["httpMethod"], f"{path}.transport.httpMethod", {"GET", "POST"})
    require_enum(
        transport["requestFormat"],
        f"{path}.transport.requestFormat",
        {"form", "json", "multipart"},
    )

    parameters = request["parameters"]
    if not isinstance(parameters, list):
        raise ValidationError(f"{path}.parameters 必须是数组")
    names: list[str] = []
    for index, raw_parameter in enumerate(parameters):
        location = f"{path}.parameters[{index}]"
        parameter = require_object_keys(
            raw_parameter,
            location,
            {"name", "valueType"},
            {"encodedValue", "redacted"},
        )
        name = require_string(parameter["name"], f"{location}.name", PARAMETER_PATTERN)
        is_sensitive = SENSITIVE_PARAMETER_PATTERN.fullmatch(name) is not None
        is_redacted = parameter.get("redacted") is True
        has_encoded_value = "encodedValue" in parameter
        if is_sensitive and (not is_redacted or has_encoded_value):
            raise ValidationError(f"{location}.name 敏感参数只能标记为已脱敏")
        if not is_sensitive and is_redacted:
            raise ValidationError(f"{location}.redacted 只允许用于已知敏感参数")
        if has_encoded_value == is_redacted:
            raise ValidationError(
                f"{location} 必须且只能提供 encodedValue 或 redacted"
            )
        names.append(name)
        require_enum(
            parameter["valueType"],
            f"{location}.valueType",
            {
                "string",
                "integer",
                "boolean",
                "binary",
                "stringArray",
                "integerArray",
                "object",
                "objectArray",
            },
        )
        if has_encoded_value:
            encoded = require_string(
                parameter["encodedValue"],
                f"{location}.encodedValue",
            )
            if len(encoded) > 1024:
                raise ValidationError(f"{location}.encodedValue 不能超过 1024 个字符")
    if len(names) != len(set(names)):
        raise ValidationError(f"{path}.parameters 参数名不得重复")

    authentication = require_object_keys(
        request["authentication"],
        f"{path}.authentication",
        {"required", "synoTokenRequired", "sessionLocations", "synoTokenLocations"},
    )
    require_boolean(authentication["required"], f"{path}.authentication.required")
    require_boolean(
        authentication["synoTokenRequired"],
        f"{path}.authentication.synoTokenRequired",
    )
    for key, choices in (
        ("sessionLocations", {"cookie", "query", "form", "json", "multipart"}),
        ("synoTokenLocations", {"header", "query", "form", "json", "multipart"}),
    ):
        locations = authentication[key]
        if not isinstance(locations, list) or any(item not in choices for item in locations):
            raise ValidationError(f"{path}.authentication.{key} 包含无效位置")
        if len(locations) != len(set(locations)):
            raise ValidationError(f"{path}.authentication.{key} 不得重复")

    policy = require_object_keys(
        request["policy"],
        f"{path}.policy",
        {"retryPolicy", "risk", "readbackPolicy"},
    )
    retry_policy = require_enum(
        policy["retryPolicy"],
        f"{path}.policy.retryPolicy",
        {"never", "readOnlyAutomatic", "queryStateBeforeDecision"},
    )
    risk = require_enum(
        policy["risk"],
        f"{path}.policy.risk",
        {"read", "standardWrite", "highRisk", "destructive"},
    )
    readback_policy = require_enum(
        policy["readbackPolicy"],
        f"{path}.policy.readbackPolicy",
        {"none", "required", "taskPoll", "unavailable"},
    )
    if risk != "read" and retry_policy == "readOnlyAutomatic":
        raise ValidationError(f"{path}: 写操作不得启用只读自动重试")
    if risk in {"highRisk", "destructive"} and readback_policy == "none":
        raise ValidationError(f"{path}: 高风险或破坏性操作必须复查最终状态")
    if readback_policy == "unavailable":
        if risk not in {"highRisk", "destructive"}:
            raise ValidationError(f"{path}: 只有高风险或破坏性操作可标记为无法回读")
        if retry_policy != "never":
            raise ValidationError(f"{path}: 无法回读的危险写操作必须禁止重试")

    source = require_object_keys(
        request["source"],
        f"{path}.source",
        {"kind", "evidence"},
    )
    require_enum(source["kind"], f"{path}.source.kind", {"synthetic"})
    require_enum(
        source["evidence"],
        f"{path}.source.evidence",
        {"publicDocumentation", "sourceReviewed", "redactedDiscoveryRecord"},
    )
    scan_privacy(request)
    return request


def validate_mutation_result(value: Any, path: Path) -> dict[str, Any]:
    result = require_object_keys(
        value,
        str(path),
        MUTATION_REQUIRED_KEYS,
        MUTATION_OPTIONAL_KEYS,
    )
    if result["schemaVersion"] != 1:
        raise ValidationError(f"{path}.schemaVersion 必须为 1")
    status = require_enum(result["status"], f"{path}.status", MUTATION_STATUSES)
    require_string(result["operation"], f"{path}.operation", OPERATION_PATTERN)
    submitted = require_boolean(result["submitted"], f"{path}.submitted")
    requires_refresh = require_boolean(
        result["requiresRefresh"],
        f"{path}.requiresRefresh",
    )
    counts = require_object_keys(
        result["counts"],
        f"{path}.counts",
        {"succeeded", "failed", "unknown"},
    )
    succeeded = require_nonnegative_integer(counts["succeeded"], f"{path}.counts.succeeded")
    failed = require_nonnegative_integer(counts["failed"], f"{path}.counts.failed")
    unknown = require_nonnegative_integer(counts["unknown"], f"{path}.counts.unknown")

    if status == "confirmedSuccess" and (
        not submitted or failed != 0 or unknown != 0
    ):
        raise ValidationError(f"{path}: confirmedSuccess 的提交和数量不一致")
    if status == "cancelledBeforeSubmission" and (
        submitted or requires_refresh or succeeded != 0 or failed != 0 or unknown != 0
    ):
        raise ValidationError(f"{path}: cancelledBeforeSubmission 的状态不一致")
    if status in {
        "submittedButUnverified",
        "cancellationRequestedAfterSubmission",
    } and (not submitted or not requires_refresh):
        raise ValidationError(f"{path}: 已提交但未确认的结果必须要求刷新")
    if status == "partialSuccess" and (
        not submitted or succeeded < 1 or failed + unknown < 1
    ):
        raise ValidationError(f"{path}: partialSuccess 必须同时包含成功和未成功项目")

    if "errorCategory" in result:
        require_enum(result["errorCategory"], f"{path}.errorCategory", ERROR_CATEGORIES)
    for key in ("localizationKey", "diagnosticTag"):
        if key in result:
            require_string(result[key], f"{path}.{key}", SAFE_TAG_PATTERN)
    scan_privacy(result)
    return result


def validate_request_directories(root: Path = REQUEST_ROOT) -> list[Path]:
    files = sorted(root.rglob("request.json"))
    if not files:
        raise ValidationError(f"{root}: 至少需要一个请求 Fixture")
    for path in files:
        unexpected = {
            child.name
            for child in path.parent.iterdir()
            if child.is_file() and child.name != "request.json"
        }
        if unexpected:
            raise ValidationError(f"{path.parent}: 包含未定义文件：{', '.join(sorted(unexpected))}")
        validate_request_fixture(load_json(path), path)
    orphan_json = {
        path
        for path in root.rglob("*.json")
        if path.name != "request.json"
    }
    if orphan_json:
        raise ValidationError(f"{root}: 请求样本目录只能包含 request.json")
    return files


def validate_mutation_examples(root: Path = MUTATION_ROOT) -> list[Path]:
    files = sorted(root.glob("*.json"))
    if not files:
        raise ValidationError(f"{root}: 至少需要一个写操作结果示例")
    for path in files:
        validate_mutation_result(load_json(path), path)
    return files


def main() -> int:
    try:
        request_files = validate_request_directories()
        mutation_files = validate_mutation_examples()
    except ValidationError as error:
        print(f"契约校验失败：{error}", file=sys.stderr)
        return 1
    print(
        f"契约校验通过：{len(request_files)} 个请求 Fixture，"
        f"{len(mutation_files)} 个写操作结果示例。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
