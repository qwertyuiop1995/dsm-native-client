"""Fixture 脱敏工具测试。"""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]


def load_module():
    specification = importlib.util.spec_from_file_location(
        "fixture_sanitizer_test",
        TOOLS_DIRECTORY / "sanitize.py",
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("无法加载 Fixture 脱敏工具")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


sanitizer = load_module()


class FixtureSanitizationTests(unittest.TestCase):
    def test_replaces_secrets_identities_paths_and_names(self) -> None:
        registry = sanitizer.TokenRegistry()
        result = sanitizer.sanitize(
            {
                "sid": "secret-session",
                "owner": {"user": "real-user"},
                "path": "/volume1/private/report.pdf",
                "name": "report.pdf",
            },
            registry,
        )

        self.assertEqual("<redacted:secret-1>", result["sid"])
        self.assertEqual("<redacted:identity-1>", result["owner"])
        self.assertEqual("/fixture/share-1/item-1.bin", result["path"])
        self.assertEqual("item-1.bin", result["name"])
        self.assertEqual({"secret", "identity", "path", "name"}, registry.redacted_fields)

    def test_reuses_stable_token_for_repeated_value(self) -> None:
        registry = sanitizer.TokenRegistry()
        result = sanitizer.sanitize(
            {"first": "https://nas.example.test/path", "second": "https://nas.example.test/path"},
            registry,
        )

        self.assertEqual(result["first"], result["second"])
        self.assertNotIn("nas.example.test", result["first"])

    def test_keeps_non_sensitive_structure_and_types(self) -> None:
        registry = sanitizer.TokenRegistry()
        result = sanitizer.sanitize(
            {"success": True, "data": {"total": "2", "values": [None, 3]}},
            registry,
        )

        self.assertEqual(
            {"success": True, "data": {"total": "2", "values": [None, 3]}},
            result,
        )
        self.assertEqual(set(), registry.redacted_fields)


if __name__ == "__main__":
    unittest.main()
