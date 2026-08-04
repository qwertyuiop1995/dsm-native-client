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

    def report_for_suite(self, version: int) -> dict:
        report = copy.deepcopy(self.example)
        report["testSuiteVersion"] = version
        expected_ids = {
            capability_id
            for capability_id, capability in self.capabilities.items()
            if capability["introducedInTestSuiteVersion"] <= version
        }
        report["results"] = [
            result
            for result in report["results"]
            if result["capabilityId"] in expected_ids
        ]
        return report

    def test_repository_data_passes_validation(self) -> None:
        capabilities, reports = validator.load_and_validate_all()
        registry = validator.load_json(validator.CAPABILITIES_PATH)
        self.assertEqual(2, registry["testSuiteVersion"])
        self.assertEqual(19, len(capabilities))
        self.assertEqual(
            14,
            sum(
                capability["introducedInTestSuiteVersion"] == 1
                for capability in capabilities.values()
            ),
        )
        self.assertEqual(
            5,
            sum(
                capability["introducedInTestSuiteVersion"] == 2
                for capability in capabilities.values()
            ),
        )
        self.assertIsInstance(reports, list)

    def test_example_report_passes_validation(self) -> None:
        validated = self.validate_example(copy.deepcopy(self.example))
        self.assertEqual("cc-000000", validated["reportId"])
        self.assertEqual(2, validated["schemaVersion"])
        self.assertEqual("unknown", validated["app"]["commit"])

    def test_commit_accepts_short_and_full_hexadecimal_values(self) -> None:
        for commit in ("1a2b3c4", "a" * 40):
            with self.subTest(commit=commit):
                report = copy.deepcopy(self.example)
                report["app"]["commit"] = commit
                self.validate_example(report)

    def test_rejects_invalid_commit(self) -> None:
        for commit in ("abcdef", "g123456", "a" * 41):
            with self.subTest(commit=commit):
                report = copy.deepcopy(self.example)
                report["app"]["commit"] = commit
                with self.assertRaisesRegex(validator.ValidationError, "commit"):
                    self.validate_example(report)

    def test_rejects_legacy_report_schema_version(self) -> None:
        report = copy.deepcopy(self.example)
        report["schemaVersion"] = 1
        with self.assertRaisesRegex(validator.ValidationError, "schemaVersion 必须为 2"):
            self.validate_example(report)

    def test_rejects_capability_introduced_after_current_suite(self) -> None:
        registry = validator.load_json(validator.CAPABILITIES_PATH)
        registry["capabilities"][0]["introducedInTestSuiteVersion"] = 3
        with self.assertRaisesRegex(
            validator.ValidationError,
            "introducedInTestSuiteVersion",
        ):
            validator.validate_capabilities(registry)

    def test_rejects_unregistered_capability(self) -> None:
        report = copy.deepcopy(self.example)
        report["results"][0]["capabilityId"] = "files.not-registered"
        with self.assertRaisesRegex(validator.ValidationError, "未注册"):
            self.validate_example(report)

    def test_rejects_missing_capability_for_suite(self) -> None:
        report = copy.deepcopy(self.example)
        report["results"] = report["results"][:-1]
        with self.assertRaisesRegex(validator.ValidationError, "缺少"):
            self.validate_example(report)

    def test_rejects_duplicate_capability(self) -> None:
        report = copy.deepcopy(self.example)
        report["results"].append(copy.deepcopy(report["results"][0]))
        with self.assertRaisesRegex(validator.ValidationError, "重复"):
            self.validate_example(report)

    def test_complete_version_one_report_passes(self) -> None:
        report = self.report_for_suite(1)
        validated = self.validate_example(report)
        self.assertEqual(14, len(validated["results"]))

    def test_version_one_rejects_version_two_capability(self) -> None:
        report = self.report_for_suite(1)
        report["results"].append(
            {"capabilityId": "desktop-drive.mount", "status": "skipped"}
        )
        with self.assertRaisesRegex(validator.ValidationError, "不属于"):
            self.validate_example(report)

    def test_macos_may_skip_desktop_drive_capabilities(self) -> None:
        validated = self.validate_example(copy.deepcopy(self.example))
        desktop_results = [
            result
            for result in validated["results"]
            if result["capabilityId"].startswith("desktop-drive.")
        ]
        self.assertEqual(5, len(desktop_results))
        self.assertTrue(
            all(result["status"] == "skipped" for result in desktop_results)
        )

    def test_non_macos_requires_not_supported_for_desktop_drive(self) -> None:
        report = copy.deepcopy(self.example)
        report["app"]["platform"] = "Windows"
        for result in report["results"]:
            if result["capabilityId"].startswith("desktop-drive."):
                result["status"] = "not-supported"
        validated = self.validate_example(report)
        self.assertEqual("Windows", validated["app"]["platform"])

    def test_non_macos_rejects_skipped_desktop_drive_capability(self) -> None:
        report = copy.deepcopy(self.example)
        report["app"]["platform"] = "Android"
        for result in report["results"]:
            if result["capabilityId"].startswith("desktop-drive."):
                result["status"] = "not-supported"
        desktop_result = next(
            result
            for result in report["results"]
            if result["capabilityId"] == "desktop-drive.mount"
        )
        desktop_result["status"] = "skipped"
        with self.assertRaisesRegex(validator.ValidationError, "not-supported"):
            self.validate_example(report)

    def test_failed_result_requires_structured_failure(self) -> None:
        report = copy.deepcopy(self.example)
        failed_result = next(
            result for result in report["results"] if result["status"] == "failed"
        )
        failed_result.pop("failure")
        with self.assertRaisesRegex(validator.ValidationError, "failure"):
            self.validate_example(report)

    def test_partial_result_requires_structured_failure(self) -> None:
        report = copy.deepcopy(self.example)
        result = report["results"][0]
        result["status"] = "partial"
        with self.assertRaisesRegex(validator.ValidationError, "failure"):
            self.validate_example(report)

    def test_partial_result_accepts_structured_failure(self) -> None:
        report = copy.deepcopy(self.example)
        failure = next(
            result["failure"]
            for result in report["results"]
            if result["status"] == "failed"
        )
        result = report["results"][0]
        result["status"] = "partial"
        result["failure"] = copy.deepcopy(failure)
        self.validate_example(report)

    def test_non_failure_result_rejects_failure(self) -> None:
        report = copy.deepcopy(self.example)
        failed_result = next(
            result for result in report["results"] if result["status"] == "failed"
        )
        failure = failed_result.pop("failure")
        failed_result["status"] = "passed"
        failed_result["failure"] = failure
        with self.assertRaisesRegex(validator.ValidationError, "不得填写 failure"):
            self.validate_example(report)

    def test_legacy_failure_category_is_rejected(self) -> None:
        report = copy.deepcopy(self.example)
        failed_result = next(
            result for result in report["results"] if result["status"] == "failed"
        )
        failed_result.pop("failure")
        failed_result["failureCategory"] = "operation-failed"
        with self.assertRaisesRegex(validator.ValidationError, "未定义字段"):
            self.validate_example(report)

    def test_failure_accepts_unknown_api_without_raw_response(self) -> None:
        report = copy.deepcopy(self.example)
        failure = next(
            result["failure"]
            for result in report["results"]
            if result["status"] == "failed"
        )
        failure["apiName"] = "unknown"
        failure["apiVersion"] = "unknown"
        failure["httpStatus"] = None
        self.validate_example(report)

    def test_failure_rejects_missing_or_extra_fields(self) -> None:
        for mutation in ("missing", "extra"):
            with self.subTest(mutation=mutation):
                report = copy.deepcopy(self.example)
                failure = next(
                    result["failure"]
                    for result in report["results"]
                    if result["status"] == "failed"
                )
                if mutation == "missing":
                    failure.pop("stage")
                else:
                    failure["message"] = "not allowed"
                with self.assertRaisesRegex(
                    validator.ValidationError,
                    "缺少字段|未定义字段",
                ):
                    self.validate_example(report)

    def test_failure_rejects_invalid_structured_values(self) -> None:
        cases = {
            "stage": "transport",
            "errorCategory": "raw-error",
            "apiName": "SYNO..Unsafe",
            "apiVersion": 100,
            "httpStatus": 99,
            "retryPerformed": "false",
            "rawResponseIncluded": True,
        }
        for key, value in cases.items():
            with self.subTest(key=key):
                report = copy.deepcopy(self.example)
                failure = next(
                    result["failure"]
                    for result in report["results"]
                    if result["status"] == "failed"
                )
                failure[key] = value
                with self.assertRaisesRegex(validator.ValidationError, key):
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
        self.assertIn("测试套件 v2", chinese)
        self.assertIn("Test suite v2", english)
        self.assertNotIn("operation-failed", chinese)
        self.assertNotIn("operation-failed", english)

    def test_different_test_suite_versions_are_not_aggregated(self) -> None:
        version_two = copy.deepcopy(self.example)
        version_two["reviewStatus"] = "reviewed"
        version_one = copy.deepcopy(version_two)
        version_one["reportId"] = "cc-000001"
        version_one["sourceRef"] = "issue-2"
        version_one["testSuiteVersion"] = 1
        version_one["results"] = [
            result
            for result in version_one["results"]
            if not result["capabilityId"].startswith("desktop-drive.")
        ]

        chinese = generator.render_document(
            [version_one, version_two],
            self.capabilities,
            "zh-Hans",
        )

        self.assertEqual(2, chinese.count("`connection.resolve`"))
        self.assertIn("测试套件 v1", chinese)
        self.assertIn("测试套件 v2", chinese)


if __name__ == "__main__":
    unittest.main()
