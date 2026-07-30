"""脱敏 Fixture 严格校验测试。"""

from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def load_module():
    specification = importlib.util.spec_from_file_location(
        "fixture_validator_test",
        TOOLS_DIRECTORY / "validate_fixtures.py",
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("无法加载 Fixture 校验工具")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


validator = load_module()


class FixtureValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture_directory = (
            REPOSITORY_ROOT
            / "contracts/fixtures-redacted/file-station/list-folder"
            / "synthetic-string-numbers"
        )
        cls.metadata = validator.load_json(cls.fixture_directory / "metadata.json")
        cls.response = validator.load_json(cls.fixture_directory / "response.json")

    def test_repository_fixtures_pass_validation(self) -> None:
        directories = validator.validate_all()
        self.assertGreaterEqual(len(directories), 3)

    def test_rejects_real_fixture_without_stable_lab_alias(self) -> None:
        metadata = copy.deepcopy(self.metadata)
        metadata["sourceKind"] = "real-redacted"
        metadata["environment"]["alias"] = "my-nas"
        with self.assertRaisesRegex(validator.ValidationError, "稳定环境别名"):
            validator.validate_metadata(metadata, self.fixture_directory / "metadata.json")

    def test_rejects_unredacted_session_field(self) -> None:
        response = copy.deepcopy(self.response)
        response["sid"] = "real-session"
        with self.assertRaisesRegex(validator.ValidationError, "脱敏占位符"):
            validator.scan_privacy(response)

    def test_rejects_private_values(self) -> None:
        for value in (
            "https://nas.example.test/webapi",
            "192.168.1.20",
            "00:11:22:33:44:55",
            "user@example.test",
            "/volume1/private/a.txt",
        ):
            with self.subTest(value=value):
                with self.assertRaises(validator.ValidationError):
                    validator.scan_privacy({"value": value})

    def test_rejects_orphan_response(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            orphan = root / "module/endpoint/orphan"
            orphan.mkdir(parents=True)
            (orphan / "response.json").write_text(
                json.dumps({"success": True}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(validator.ValidationError, "metadata"):
                validator.validate_all(root)


if __name__ == "__main__":
    unittest.main()
