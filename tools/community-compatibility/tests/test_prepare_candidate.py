"""社区兼容性候选报告只读辅助命令测试。"""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


candidate = load_module(
    "community_compatibility_prepare_candidate_test",
    TOOLS_DIRECTORY / "prepare_candidate.py",
)


class CommunityCompatibilityCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.capabilities, cls.repository_reports = (
            candidate.report_validator.load_and_validate_all()
        )
        example = candidate.report_validator.load_json(
            REPOSITORY_ROOT
            / "contracts/community-compatibility/examples/example-report.json"
        )
        cls.submission = {
            "$schema": "community-compatibility-submission.schema.json",
            "submissionSchemaVersion": 1,
            "reportSchemaVersion": 2,
            "generatedAt": "2026-08-04T12:34:56Z",
            **{
                key: copy.deepcopy(example[key])
                for key in candidate.REPORT_COPY_FIELDS
            },
        }

    def reviewed_report(
        self,
        report_id: str,
        source_ref: str,
    ) -> dict:
        report, _ = candidate.build_candidate(
            copy.deepcopy(self.submission),
            Path("synthetic-submission.json"),
            source_ref,
            "2026-08-04",
            self.capabilities,
            [],
        )
        report["reportId"] = report_id
        return report

    def build(
        self,
        *,
        submission: dict | None = None,
        source_ref: str = "issue-123",
        submitted_at: str = "2026-08-04",
        reports: list[dict] | None = None,
    ) -> tuple[dict, Path]:
        return candidate.build_candidate(
            copy.deepcopy(submission or self.submission),
            Path("synthetic-submission.json"),
            source_ref,
            submitted_at,
            self.capabilities,
            reports or [],
        )

    def test_allocates_first_id_for_empty_repository(self) -> None:
        self.assertEqual("cc-000001", candidate.allocate_report_id([]))

    def test_allocates_after_maximum_without_reusing_gap(self) -> None:
        reports = [
            {"reportId": "cc-000001"},
            {"reportId": "cc-000004"},
            {"reportId": "cc-000002"},
        ]
        self.assertEqual("cc-000005", candidate.allocate_report_id(reports))

    def test_rejects_exhausted_or_invalid_existing_id(self) -> None:
        cases = ([{"reportId": "cc-999999"}], [{"reportId": "unsafe"}])
        for reports in cases:
            with self.subTest(reports=reports):
                with self.assertRaises(candidate.CandidatePreparationError):
                    candidate.allocate_report_id(reports)

    def test_rejects_duplicate_public_source(self) -> None:
        reports = [self.reviewed_report("cc-000007", "issue-123")]
        with self.assertRaisesRegex(
            candidate.CandidatePreparationError,
            "公开来源已存在",
        ):
            self.build(reports=reports)

    def test_converts_only_allowlisted_submission_fields(self) -> None:
        report, target = self.build()
        self.assertEqual("cc-000001", report["reportId"])
        self.assertEqual("issue-123", report["sourceRef"])
        self.assertEqual("2026-08-04", report["submittedAt"])
        self.assertEqual("reviewed", report["reviewStatus"])
        self.assertEqual(2, report["schemaVersion"])
        self.assertNotIn("generatedAt", report)
        self.assertNotIn("submissionSchemaVersion", report)
        self.assertNotIn("reportSchemaVersion", report)
        self.assertEqual("cc-000001.json", target.name)

    def test_rejects_invalid_source_and_explicit_date(self) -> None:
        for source_ref, submitted_at in (
            ("issue-0", "2026-08-04"),
            ("issue-123", "2026-02-30"),
        ):
            with self.subTest(source_ref=source_ref, submitted_at=submitted_at):
                with self.assertRaises(candidate.CandidatePreparationError):
                    self.build(
                        source_ref=source_ref,
                        submitted_at=submitted_at,
                    )

    def test_preserves_version_one_and_structured_failure_semantics(self) -> None:
        version_one = copy.deepcopy(self.submission)
        version_one["testSuiteVersion"] = 1
        version_one["results"] = version_one["results"][:14]
        report, _ = self.build(submission=version_one)
        self.assertEqual(14, len(report["results"]))
        failed = next(
            result for result in report["results"] if result["status"] == "failed"
        )
        self.assertFalse(failed["failure"]["rawResponseIncluded"])

    def test_rejects_non_macos_invalid_desktop_drive_status(self) -> None:
        submission = copy.deepcopy(self.submission)
        submission["app"]["platform"] = "Android"
        with self.assertRaises(
            candidate.submission_validator.SubmissionValidationError
        ):
            self.build(submission=submission)

    def test_json_output_is_stable_and_ends_with_newline(self) -> None:
        report, _ = self.build()
        rendered = candidate.render_json(report)
        self.assertTrue(rendered.endswith("\n"))
        self.assertEqual(report, json.loads(rendered))
        self.assertEqual(rendered, candidate.render_json(report))

    def test_diff_contains_report_and_bilingual_matrix_changes(self) -> None:
        report, target = self.build(reports=self.repository_reports)
        rendered = candidate.render_diff(
            report,
            target,
            self.repository_reports,
            self.capabilities,
        )
        self.assertIn("/dev/null", rendered)
        self.assertIn(
            "contracts/community-compatibility/reports/cc-000001.json",
            rendered,
        )
        self.assertIn("COMMUNITY_COMPATIBILITY_MATRIX_ZH.md", rendered)
        self.assertIn("COMMUNITY_COMPATIBILITY_MATRIX_EN.md", rendered)
        self.assertIn("issue-123", rendered)

    def test_cli_requires_privacy_confirmation(self) -> None:
        with self.assertRaises(SystemExit) as raised, redirect_stderr(io.StringIO()):
            candidate.main(
                [
                    "--submission",
                    "draft.json",
                    "--source-ref",
                    "issue-123",
                    "--submitted-at",
                    "2026-08-04",
                ]
            )
        self.assertEqual(2, raised.exception.code)

    def test_cli_json_mode_does_not_write_repository(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "submission.json"
            source.write_text(
                json.dumps(self.submission, ensure_ascii=False),
                encoding="utf-8",
            )
            standard_output = io.StringIO()
            standard_error = io.StringIO()
            with (
                mock.patch.object(Path, "write_text") as write_text,
                redirect_stdout(standard_output),
                redirect_stderr(standard_error),
            ):
                result = candidate.main(
                    [
                        "--submission",
                        str(source),
                        "--source-ref",
                        "issue-123",
                        "--submitted-at",
                        "2026-08-04",
                        "--confirm-privacy-reviewed",
                        "--format",
                        "json",
                    ]
                )
            self.assertEqual(0, result)
            write_text.assert_not_called()
            self.assertEqual("", standard_error.getvalue())
            self.assertEqual(
                "reviewed",
                json.loads(standard_output.getvalue())["reviewStatus"],
            )

    def test_cli_defaults_to_complete_diff_without_writing_repository(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "submission.json"
            source.write_text(json.dumps(self.submission), encoding="utf-8")
            standard_output = io.StringIO()
            with (
                mock.patch.object(Path, "write_text") as write_text,
                redirect_stdout(standard_output),
                redirect_stderr(io.StringIO()),
            ):
                result = candidate.main(
                    [
                        "--submission",
                        str(source),
                        "--source-ref",
                        "pull-456",
                        "--submitted-at",
                        "2026-08-04",
                        "--confirm-privacy-reviewed",
                    ]
                )
            rendered = standard_output.getvalue()
            self.assertEqual(0, result)
            write_text.assert_not_called()
            self.assertIn("cc-000001.json", rendered)
            self.assertIn("COMMUNITY_COMPATIBILITY_MATRIX_ZH.md", rendered)
            self.assertIn("COMMUNITY_COMPATIBILITY_MATRIX_EN.md", rendered)

    def test_cli_error_does_not_echo_sensitive_value(self) -> None:
        sensitive_value = "token=do-not-repeat-this-value"
        submission = copy.deepcopy(self.submission)
        submission["connectionType"] = sensitive_value
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "submission.json"
            source.write_text(json.dumps(submission), encoding="utf-8")
            standard_error = io.StringIO()
            with redirect_stdout(io.StringIO()), redirect_stderr(standard_error):
                result = candidate.main(
                    [
                        "--submission",
                        str(source),
                        "--source-ref",
                        "issue-123",
                        "--submitted-at",
                        "2026-08-04",
                        "--confirm-privacy-reviewed",
                        "--format",
                        "json",
                    ]
                )
        self.assertEqual(1, result)
        self.assertNotIn(sensitive_value, standard_error.getvalue())
        self.assertNotIn(str(source), standard_error.getvalue())


if __name__ == "__main__":
    unittest.main()
