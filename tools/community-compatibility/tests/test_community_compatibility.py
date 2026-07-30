"""社区兼容性数据工具测试。"""

from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


validator = load_module("community_compatibility_validate_test", TOOLS_DIRECTORY / "validate.py")
generator = load_module("community_compatibility_generate_test", TOOLS_DIRECTORY / "generate.py")


class CommunityCompatibilityValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.capabilities = validator.validate_capabilities(
            validator.load_json(
                REPOSITORY_ROOT
                / "contracts/community-compatibility/capabilities.json"
            )
        )
        cls.example_path = (
            REPOSITORY_ROOT
            / "contracts/community-compatibility/examples/example-report.json"
        )
        cls.example = validator.load_json(cls.example_path)

    def validate_example(self, report: dict) -> dict:
        return validator.validate_report(
            report,
            self.example_path,
            self.capabilities,
            example=True,
        )

    def test_repository_data_passes_validation(self) -> None:
        capabilities, reports = validator.load_and_validate_all()
        registry = validator.load_json(validator.CAPABILITIES_PATH)
        self.assertEqual(2, registry["testSuiteVersion"])
        self.assertGreaterEqual(len(capabilities), 1)
        self.assertIsInstance(reports, list)

    def test_example_report_passes_validation(self) -> None:
        validated = self.validate_example(copy.deepcopy(self.example))
        self.assertEqual("cc-000000", validated["reportId"])

    def test_rejects_unregistered_capability(self) -> None:
        report = copy.deepcopy(self.example)
        report["results"][0]["capabilityId"] = "files.not-registered"
        with self.assertRaisesRegex(validator.ValidationError, "未注册"):
            self.validate_example(report)

    def test_failed_result_requires_failure_category(self) -> None:
        report = copy.deepcopy(self.example)
        failed_result = next(
            result for result in report["results"] if result["status"] == "failed"
        )
        failed_result.pop("failureCategory")
        with self.assertRaisesRegex(validator.ValidationError, "failureCategory"):
            self.validate_example(report)

    def test_rejects_private_ipv4_address(self) -> None:
        report = copy.deepcopy(self.example)
        report["app"]["platformVersion"] = "10.0.0.8"
        with self.assertRaisesRegex(validator.ValidationError, "IPv4"):
            self.validate_example(report)

    def test_rejects_sensitive_field_name(self) -> None:
        report = copy.deepcopy(self.example)
        report["nas"]["serialNumber"] = "example"
        with self.assertRaisesRegex(validator.ValidationError, "未定义字段"):
            self.validate_example(report)

    def test_reports_directory_rejects_unreviewed_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = Path(temporary_directory) / "cc-000000.json"
            source.write_text(
                json.dumps(self.example, ensure_ascii=False),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(validator.ValidationError, "未审核"):
                validator.validate_report(
                    validator.load_json(source),
                    source,
                    self.capabilities,
                )


class CommunityCompatibilityGenerationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.capabilities = validator.validate_capabilities(
            validator.load_json(validator.CAPABILITIES_PATH)
        )
        cls.example = validator.load_json(
            REPOSITORY_ROOT
            / "contracts/community-compatibility/examples/example-report.json"
        )

    def test_empty_matrix_has_bilingual_empty_state(self) -> None:
        chinese = generator.render_document([], self.capabilities, "zh-Hans")
        english = generator.render_document([], self.capabilities, "en")
        self.assertIn("暂无已审核社区报告", chinese)
        self.assertIn("No reviewed community reports", english)

    def test_report_is_rendered_without_failure_details(self) -> None:
        report = copy.deepcopy(self.example)
        report["reviewStatus"] = "reviewed"
        chinese = generator.render_document(
            [report], self.capabilities, "zh-Hans"
        )
        english = generator.render_document([report], self.capabilities, "en")
        self.assertIn("cc-000000", chinese)
        self.assertIn("DS000+", english)
        self.assertNotIn("operation-failed", chinese)
        self.assertNotIn("operation-failed", english)


if __name__ == "__main__":
    unittest.main()
