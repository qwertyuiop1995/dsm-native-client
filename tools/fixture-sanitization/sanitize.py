#!/usr/bin/env python3
"""生成可供人工复核的 DSM 响应脱敏候选样本。"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SECRET_KEYS = {
    "_sid",
    "sid",
    "synotoken",
    "cookie",
    "did",
    "password",
    "passwd",
    "otp",
    "otp_code",
    "device_id",
    "device_token",
    "token",
    "access_token",
    "refresh_token",
}
IDENTITY_KEYS = {
    "account",
    "username",
    "user",
    "owner",
    "hostname",
    "host",
    "server_name",
    "serial",
    "serial_number",
    "mac",
    "mac_address",
    "quickconnect_id",
    "certificate",
    "fingerprint",
}
PATH_KEYS = {
    "path",
    "real_path",
    "folder_path",
    "file_path",
    "destination",
    "volume_path",
}
NAME_KEYS = {
    "name",
    "filename",
    "file_name",
    "share_name",
    "volume_name",
}

URL_PATTERN = re.compile(r"https?://[^\s\"']+", re.IGNORECASE)
IPV4_PATTERN = re.compile(
    r"(?<![0-9])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})"
    r"(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9])"
)
MAC_PATTERN = re.compile(r"\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b", re.IGNORECASE)
EMAIL_PATTERN = re.compile(
    r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b",
    re.IGNORECASE,
)


class TokenRegistry:
    """在同一份响应内为敏感值分配稳定占位符。"""

    def __init__(self) -> None:
        self._tokens: dict[tuple[str, str], str] = {}
        self.redacted_fields: set[str] = set()

    def token(self, category: str, value: Any) -> str:
        original = json.dumps(value, ensure_ascii=False, sort_keys=True)
        key = (category, original)
        if key not in self._tokens:
            index = 1 + sum(existing[0] == category for existing in self._tokens)
            self._tokens[key] = f"<redacted:{category}-{index}>"
        self.redacted_fields.add(category)
        return self._tokens[key]

    def path(self, value: Any) -> str:
        token = self.token("path", value)
        index = token.rsplit("-", 1)[-1].rstrip(">")
        return f"/fixture/share-{index}/item-{index}.bin"

    def name(self, value: Any) -> str:
        token = self.token("name", value)
        index = token.rsplit("-", 1)[-1].rstrip(">")
        return f"item-{index}.bin"


def sanitize_string(value: str, registry: TokenRegistry) -> str:
    replacements = (
        ("url", URL_PATTERN),
        ("ipv4", IPV4_PATTERN),
        ("mac", MAC_PATTERN),
        ("email", EMAIL_PATTERN),
    )
    sanitized = value
    for category, pattern in replacements:
        if pattern.search(sanitized):
            sanitized = pattern.sub(registry.token(category, sanitized), sanitized)
    return sanitized


def sanitize(value: Any, registry: TokenRegistry, key: str | None = None) -> Any:
    normalized_key = key.lower() if key else None
    if normalized_key in SECRET_KEYS:
        return registry.token("secret", value)
    if normalized_key in IDENTITY_KEYS:
        return registry.token("identity", value)
    if normalized_key in PATH_KEYS:
        return registry.path(value)
    if normalized_key in NAME_KEYS:
        return registry.name(value)
    if isinstance(value, dict):
        return {
            child_key: sanitize(child, registry, child_key)
            for child_key, child in value.items()
        }
    if isinstance(value, list):
        return [sanitize(child, registry, key) for child in value]
    if isinstance(value, str):
        return sanitize_string(value, registry)
    return value


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="生成 DSM JSON 响应的脱敏候选文件；输出仍须通过严格校验和人工复核。",
    )
    parser.add_argument("source", type=Path, help="仅保存在本机的原始 JSON 文件")
    parser.add_argument("destination", type=Path, help="脱敏候选输出文件")
    parser.add_argument(
        "--redactions",
        type=Path,
        help="另行输出已处理字段类别的 JSON 文件",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        source = json.loads(arguments.source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"无法读取原始 JSON：{error}", file=sys.stderr)
        return 1

    registry = TokenRegistry()
    result = sanitize(source, registry)
    arguments.destination.parent.mkdir(parents=True, exist_ok=True)
    arguments.destination.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if arguments.redactions:
        arguments.redactions.parent.mkdir(parents=True, exist_ok=True)
        arguments.redactions.write_text(
            json.dumps(sorted(registry.redacted_fields), ensure_ascii=False, indent=2)
            + "\n",
            encoding="utf-8",
        )
    print("已生成脱敏候选文件；提交前仍须运行严格校验并人工复核。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
