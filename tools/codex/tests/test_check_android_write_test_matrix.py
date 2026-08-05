import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check_android_write_test_matrix.py"
SPEC = importlib.util.spec_from_file_location("check_android_write_test_matrix", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class AndroidWriteTestMatrixCheckTest(unittest.TestCase):
    def row(self, methods, state="open", multi=False, **fields):
        values = {
            "methods": methods,
            "state": state,
            "multi": "yes" if multi else "no",
            **fields,
        }
        return MODULE.MatrixRow(
            methods=tuple(methods.split(",")),
            state=state,
            multi=multi,
            fields=values,
        )

    def test_extracts_unique_production_result_calls(self):
        source = "repo.saveResult(); repository.deleteResult(1); repo.saveResult()"
        self.assertEqual(
            MODULE.production_result_calls(source),
            {"saveResult", "deleteResult"},
        )

    def test_rejects_unlisted_and_duplicate_calls(self):
        rows = [
            self.row("saveResult", state="closed", zero="gap"),
            self.row("saveResult", state="closed", zero="gap"),
        ]
        errors = MODULE.validate({"saveResult", "deleteResult"}, rows)
        self.assertTrue(any("deleteResult" in error for error in errors))
        self.assertTrue(any("当前 2 次" in error for error in errors))

    def test_open_multi_operation_requires_partial_success(self):
        row = self.row(
            "saveResult",
            multi=True,
            pre="gap",
            success="gap",
            disconnect="gap",
            readback="gap",
            cancel="gap",
            partial="gap",
        )
        errors = MODULE.validate({"saveResult"}, [row])
        self.assertTrue(any("partial" in error for error in errors))

    def test_pending_row_reports_exact_missing_scenarios(self):
        row = self.row(
            "saveResult",
            state="pending",
            pre="gap",
            success="na",
            disconnect="gap",
            readback="na",
            cancel="gap",
        )
        errors = MODULE.validate({"saveResult"}, [row])
        self.assertIn(
            "待补测试：saveResult -> pre,disconnect,cancel",
            errors,
        )

    def test_evidence_must_point_to_existing_test_name(self):
        with tempfile.TemporaryDirectory() as directory:
            original = MODULE.TEST_ROOT
            try:
                MODULE.TEST_ROOT = Path(directory)
                path = Path(directory) / "SampleTest.kt"
                path.write_text("fun `可复验场景`() {}", encoding="utf-8")
                self.assertIsNone(MODULE._validate_evidence("SampleTest.kt::可复验场景"))
                self.assertIn(
                    "测试证据名称不存在",
                    MODULE._validate_evidence("SampleTest.kt::不存在"),
                )
            finally:
                MODULE.TEST_ROOT = original


if __name__ == "__main__":
    unittest.main()
