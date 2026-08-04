"""社区兼容性报告重复、冲突与替换关系审计测试。"""

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


validator = load_module("community_report_audit_validate", TOOLS_DIRECTORY / "validate.py")
generator = load_module("community_report_audit_generate", TOOLS_DIRECTORY / "generate.py")


class CommunityReportAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.example = validator.load_json(
            REPOSITORY_ROOT
            / "contracts/community-compatibility/examples/example-report.json"
        )
        cls.capabilities = validator.validate_capabilities(
            validator.load_json(validator.CAPABILITIES_PATH)
        )

    def report(
        self,
        number: int,
        *,
        submitted_at: str = "2026-07-29",
        review_status: str = "reviewed",
    ) -> dict:
        report = copy.deepcopy(self.example)
        report["reportId"] = f"cc-{number:06d}"
        report["sourceRef"] = f"issue-{number + 1}"
        report["submittedAt"] = submitted_at
        report["reviewStatus"] = review_status
        return report

    @staticmethod
    def warning_codes(reports: list[dict]) -> set[str]:
        return {warning["code"] for warning in validator.audit_reports(reports)}

    @staticmethod
    def set_result(report: dict, capability_id: str, status: str) -> dict:
        result = next(
            item for item in report["results"] if item["capabilityId"] == capability_id
        )
        result["status"] = status
        if status in {"failed", "partial"}:
            result["failure"] = {
                "stage": "request",
                "errorCategory": "operation-failed",
                "apiName": "unknown",
                "apiVersion": "unknown",
                "httpStatus": None,
                "retryPerformed": False,
                "rawResponseIncluded": False,
            }
        else:
            result.pop("failure", None)
        return result

    def test_report_accepts_unique_supersedes_array(self) -> None:
        report = self.report(2)
        report["supersedes"] = ["cc-000001"]
        validated = validator.validate_report(
            report,
            Path("cc-000002.json"),
            self.capabilities,
        )
        self.assertEqual(["cc-000001"], validated["supersedes"])

    def test_report_rejects_duplicate_supersedes_target(self) -> None:
        report = self.report(2)
        report["supersedes"] = ["cc-000001", "cc-000001"]
        with self.assertRaisesRegex(validator.ValidationError, "重复报告"):
            validator.validate_report(
                report,
                Path("cc-000002.json"),
                self.capabilities,
            )

    def test_duplicate_source_ref_is_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            reports_directory = Path(temporary_directory)
            first = self.report(1)
            second = self.report(2)
            second["sourceRef"] = first["sourceRef"]
            for report in (first, second):
                (reports_directory / f"{report['reportId']}.json").write_text(
                    json.dumps(report, ensure_ascii=False),
                    encoding="utf-8",
                )
            with self.assertRaisesRegex(validator.ValidationError, "sourceRef 重复"):
                validator.load_and_validate_all(
                    reports_directory=reports_directory,
                    examples_directory=reports_directory / "examples",
                )

    def test_duplicate_report_id_is_blocking(self) -> None:
        first = self.report(1)
        second = self.report(1)
        second["sourceRef"] = "issue-999"
        with self.assertRaisesRegex(validator.ValidationError, "reportId 重复"):
            validator.validate_supersession_graph([first, second])

    def test_matching_environment_is_warning_and_package_order_is_normalized(self) -> None:
        first = self.report(1)
        first["packages"].append({"id": "photos", "version": "1"})
        second = self.report(2)
        second["packages"] = list(reversed(first["packages"]))
        warnings = validator.audit_reports([first, second])
        self.assertEqual(warnings, validator.audit_reports([second, first]))
        self.assertIn("MATCHING_ENVIRONMENT_REPORTS", self.warning_codes([first, second]))

    def test_different_commit_does_not_share_an_exact_environment(self) -> None:
        first = self.report(1)
        second = self.report(2)
        second["app"]["commit"] = "abcdef0"
        self.assertNotIn(
            "MATCHING_ENVIRONMENT_REPORTS",
            self.warning_codes([first, second]),
        )
        self.assertNotEqual(
            generator.environment_key(first),
            generator.environment_key(second),
        )

    def test_non_skipped_status_differences_are_conflicts(self) -> None:
        for status in ("failed", "partial", "not-supported"):
            with self.subTest(status=status):
                first = self.report(1)
                second = self.report(2)
                self.set_result(first, "connection.resolve", "passed")
                self.set_result(second, "connection.resolve", status)
                codes = self.warning_codes([first, second])
                self.assertIn("CONFLICTING_ENVIRONMENT_RESULTS", codes)
                self.assertIn("CONFLICT_NOT_MARKED_DISPUTED", codes)

    def test_failed_and_partial_are_conflicting(self) -> None:
        first = self.report(1)
        second = self.report(2)
        self.set_result(first, "connection.resolve", "failed")
        self.set_result(second, "connection.resolve", "partial")
        self.assertIn(
            "CONFLICTING_ENVIRONMENT_RESULTS",
            self.warning_codes([first, second]),
        )

    def test_skipped_difference_is_coverage_not_conflict(self) -> None:
        first = self.report(1)
        second = self.report(2)
        self.set_result(first, "connection.resolve", "passed")
        self.set_result(second, "connection.resolve", "skipped")
        codes = self.warning_codes([first, second])
        self.assertIn("COVERAGE_DIVERGENCE", codes)
        self.assertNotIn("CONFLICTING_ENVIRONMENT_RESULTS", codes)

    def test_failure_detail_difference_is_separate_warning(self) -> None:
        first = self.report(1)
        second = self.report(2)
        first_result = self.set_result(first, "connection.resolve", "failed")
        second_result = self.set_result(second, "connection.resolve", "failed")
        first_result["failure"]["stage"] = "discovery"
        second_result["failure"]["stage"] = "request"
        codes = self.warning_codes([first, second])
        self.assertIn("FAILURE_DETAIL_DIVERGENCE", codes)
        self.assertNotIn("CONFLICTING_ENVIRONMENT_RESULTS", codes)

    def test_review_status_mismatch_warnings(self) -> None:
        corroborated = self.report(1, review_status="corroborated")
        disputed = self.report(2, review_status="disputed")
        disputed["app"]["commit"] = "abcdef0"
        codes = self.warning_codes([corroborated, disputed])
        self.assertIn("CORROBORATED_WITHOUT_MATCH", codes)
        self.assertIn("DISPUTED_WITHOUT_CONFLICT", codes)

    def test_unknown_and_self_supersedes_are_blocking(self) -> None:
        unknown = self.report(1)
        unknown["supersedes"] = ["cc-999999"]
        with self.assertRaisesRegex(validator.ValidationError, "不存在的报告"):
            validator.validate_supersession_graph([unknown])

        self_reference = self.report(1, review_status="superseded")
        self_reference["supersedes"] = [self_reference["reportId"]]
        with self.assertRaisesRegex(validator.ValidationError, "不得引用自身"):
            validator.validate_supersession_graph([self_reference])

    def test_supersession_cycle_is_blocking(self) -> None:
        reports = [
            self.report(1, review_status="superseded"),
            self.report(2, review_status="superseded"),
            self.report(3, review_status="superseded"),
        ]
        reports[0]["supersedes"] = [reports[1]["reportId"]]
        reports[1]["supersedes"] = [reports[2]["reportId"]]
        reports[2]["supersedes"] = [reports[0]["reportId"]]
        with self.assertRaisesRegex(validator.ValidationError, "形成环"):
            validator.validate_supersession_graph(reports)

    def test_earlier_date_and_non_superseded_target_are_blocking(self) -> None:
        target = self.report(1, submitted_at="2026-07-30", review_status="superseded")
        successor = self.report(2, submitted_at="2026-07-29")
        successor["supersedes"] = [target["reportId"]]
        with self.assertRaisesRegex(validator.ValidationError, "日期早于"):
            validator.validate_supersession_graph([target, successor])

        target["submittedAt"] = "2026-07-28"
        target["reviewStatus"] = "reviewed"
        with self.assertRaisesRegex(validator.ValidationError, "不是 superseded"):
            validator.validate_supersession_graph([target, successor])

    def test_superseded_without_incoming_relation_is_blocking(self) -> None:
        report = self.report(1, review_status="superseded")
        with self.assertRaisesRegex(validator.ValidationError, "没有报告声明"):
            validator.validate_supersession_graph([report])

    def test_same_day_multiple_successors_and_key_mismatch_are_warnings(self) -> None:
        target = self.report(1, review_status="superseded")
        first = self.report(2)
        second = self.report(3)
        first["supersedes"] = [target["reportId"]]
        second["supersedes"] = [target["reportId"]]
        second["app"]["commit"] = "abcdef0"
        validator.validate_supersession_graph([target, first, second])
        codes = self.warning_codes([target, first, second])
        self.assertIn("SUPERSEDES_SAME_DAY", codes)
        self.assertIn("MULTIPLE_ACTIVE_SUCCESSORS", codes)
        self.assertIn("SUPERSEDES_KEY_MISMATCH", codes)

    def test_legal_chain_leaves_only_latest_report_in_coverage(self) -> None:
        oldest = self.report(1, submitted_at="2026-07-27", review_status="superseded")
        middle = self.report(2, submitted_at="2026-07-28", review_status="superseded")
        latest = self.report(3, submitted_at="2026-07-29")
        middle["supersedes"] = [oldest["reportId"]]
        latest["supersedes"] = [middle["reportId"]]
        reports = [oldest, middle, latest]
        validator.validate_supersession_graph(reports)
        coverage = generator.render_coverage(reports, self.capabilities, "en")
        self.assertEqual(1, "\n".join(coverage).count("`connection.resolve`"))


if __name__ == "__main__":
    unittest.main()
