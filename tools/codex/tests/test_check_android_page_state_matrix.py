from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "check_android_page_state_matrix.py"
MODULE_SPEC = importlib.util.spec_from_file_location("check_android_page_state_matrix", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError("无法加载 Android 页面五态矩阵检查器")

page_state_matrix = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = page_state_matrix
MODULE_SPEC.loader.exec_module(page_state_matrix)


class AndroidPageStateMatrixTests(unittest.TestCase):
    def write_fixture(self, root: Path, state: str = "覆盖", automation: str = "完整") -> None:
        (root / "ExampleScreen.kt").write_text("@Composable fun ExampleScreen() = Unit", encoding="utf-8")
        (root / "matrix.md").write_text(
            "| 文件 | 页面 | 加载 | 空内容 | 筛选空 | 错误 | 正常 | 自动化 | 依据 |\n"
            "|---|---|---|---|---|---|---|---|---|\n"
            f"| `ExampleScreen.kt` | 示例 | {state} | 不适用 | 不适用 | 覆盖 | 覆盖 | {automation} | 测试 |\n",
            encoding="utf-8",
        )
        (root / "plan.md").write_text(
            "- [ ] 每页覆盖加载、空内容、筛选后为空、错误和正常内容五种状态；建立页面—状态覆盖矩阵后再勾选。\n",
            encoding="utf-8",
        )

    def validate_fixture(self, checked: bool = False, state: str = "覆盖", automation: str = "完整"):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.write_fixture(root, state, automation)
            if checked:
                (root / "plan.md").write_text(
                    "- [x] 每页覆盖加载、空内容、筛选后为空、错误和正常内容五种状态；建立页面—状态覆盖矩阵后再勾选。\n",
                    encoding="utf-8",
                )
            original = page_state_matrix.EXPECTED_FILES
            page_state_matrix.EXPECTED_FILES = {"ExampleScreen.kt"}
            try:
                return page_state_matrix.validate(root, root / "matrix.md", root / "plan.md")
            finally:
                page_state_matrix.EXPECTED_FILES = original

    def test_complete_matrix_is_accepted(self) -> None:
        errors, gaps, automation_gaps = self.validate_fixture()
        self.assertEqual(errors, [])
        self.assertEqual((gaps, automation_gaps), (0, 0))

    def test_declared_gap_is_counted_without_failing_open_target(self) -> None:
        errors, gaps, _ = self.validate_fixture(state="缺口")
        self.assertEqual(errors, [])
        self.assertEqual(gaps, 1)

    def test_checked_target_with_gap_is_rejected(self) -> None:
        errors, _, _ = self.validate_fixture(checked=True, state="缺口")
        self.assertTrue(any("已勾选" in error for error in errors))

    def test_checked_target_with_partial_automation_is_rejected(self) -> None:
        errors, _, automation_gaps = self.validate_fixture(checked=True, automation="局部")
        self.assertEqual(automation_gaps, 1)
        self.assertTrue(any("已勾选" in error for error in errors))

    def test_unknown_state_value_is_rejected(self) -> None:
        errors, _, _ = self.validate_fixture(state="也许")
        self.assertTrue(any("非法状态值" in error for error in errors))

    def test_new_surface_file_requires_audit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.write_fixture(root)
            (root / "NewDialog.kt").write_text("@Composable fun NewDialog() = Unit", encoding="utf-8")
            original = page_state_matrix.EXPECTED_FILES
            page_state_matrix.EXPECTED_FILES = {"ExampleScreen.kt"}
            try:
                errors, _, _ = page_state_matrix.validate(root, root / "matrix.md", root / "plan.md")
            finally:
                page_state_matrix.EXPECTED_FILES = original
            self.assertTrue(any("遗漏生产页面" in error for error in errors))
            self.assertTrue(any("页面文件清单已变化" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
