"""社区兼容性提交草稿契约测试。"""

from __future__ import annotations

import copy
import importlib.util
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


validator = load_module(
    "community_compatibility_submission_test",
    TOOLS_DIRECTORY / "validate_submission.py",
)


class CommunityCompatibilitySubmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        report = validator.load_json(
            REPOSITORY_ROOT
            / "contracts/community-compatibility/examples/example-report.json"
        )
        cls.source = Path("synthetic-submission.json")
        cls.submission = {
            "$schema": "community-compatibility-submission.schema.json",
            "submissionSchemaVersion": 1,
            "reportSchemaVersion": 2,
            "generatedAt": "2026-08-04T12:34:56Z",
            **{
                key: copy.deepcopy(report[key])
                for key in (
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
            },
        }

    def validate(self, submission: dict) -> dict:
        return validator.validate_submission(submission, self.source)

    def test_complete_version_two_submission_passes(self) -> None:
        validated = self.validate(copy.deepcopy(self.submission))
        self.assertEqual(19, len(validated["results"]))
        self.assertNotIn("reportId", validated)
        self.assertNotIn("reviewStatus", validated)

    def test_complete_version_one_submission_passes(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["testSuiteVersion"] = 1
        submission["results"] = [
            result
            for result in submission["results"]
            if not result["capabilityId"].startswith("desktop-drive.")
        ]
        validated = self.validate(submission)
        self.assertEqual(14, len(validated["results"]))

    def test_rejects_review_metadata_and_extra_fields(self) -> None:
        cases = {
            "reportId": "cc-000000",
            "sourceRef": "issue-1",
            "reviewStatus": "submitted",
            "unexpected": True,
        }
        for key, value in cases.items():
            with self.subTest(key=key):
                submission = copy.deepcopy(self.submission)
                submission[key] = value
                with self.assertRaisesRegex(
                    validator.SubmissionValidationError,
                    "Additional properties",
                ):
                    self.validate(submission)

    def test_rejects_invalid_generated_at_format(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["generatedAt"] = "2026-02-30T12:00:00Z"
        with self.assertRaisesRegex(
            validator.SubmissionValidationError,
            "generatedAt|date-time",
        ):
            self.validate(submission)

    def test_rejects_missing_capability_for_suite(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["results"] = submission["results"][:-1]
        with self.assertRaisesRegex(
            validator.SubmissionValidationError,
            "results|19|缺少",
        ):
            self.validate(submission)

    def test_non_macos_requires_desktop_drive_not_supported(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["app"]["platform"] = "Android"
        with self.assertRaisesRegex(
            validator.SubmissionValidationError,
            "not-supported",
        ):
            self.validate(submission)

    def test_rejects_private_data(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["app"]["platformVersion"] = "10.0.0.8"
        with self.assertRaisesRegex(
            validator.SubmissionValidationError,
            "IPv4",
        ):
            self.validate(submission)

    def test_failure_requires_complete_report_v2_structure(self) -> None:
        submission = copy.deepcopy(self.submission)
        failed = next(
            result for result in submission["results"] if result["status"] == "failed"
        )
        failed.pop("failure")
        with self.assertRaisesRegex(
            validator.SubmissionValidationError,
            "failure",
        ):
            self.validate(submission)


if __name__ == "__main__":
    unittest.main()
