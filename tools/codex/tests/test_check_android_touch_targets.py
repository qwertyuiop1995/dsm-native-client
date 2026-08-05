from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "check_android_touch_targets.py"
MODULE_SPEC = importlib.util.spec_from_file_location("check_android_touch_targets", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError("无法加载 Android 点击目标审计脚本")

touch_audit = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = touch_audit
MODULE_SPEC.loader.exec_module(touch_audit)


class AndroidTouchTargetAuditTests(unittest.TestCase):
    def scan(self, source: str) -> list[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "Example.kt").write_text(source, encoding="utf-8")
            return touch_audit.validate_findings(*touch_audit.scan_ui(root))

    def test_explicit_48dp_target_is_accepted(self) -> None:
        source = """
Row(
    Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(
        value = enabled,
        onValueChange = onChange,
    ),
)
"""
        self.assertEqual(self.scan(source), [])

    def test_native_minimum_interactive_size_is_accepted(self) -> None:
        source = """
Box(
    Modifier.minimumInteractiveComponentSize().clickable(onClick = onClick),
)
"""
        self.assertEqual(self.scan(source), [])

    def test_missing_height_is_rejected(self) -> None:
        errors = self.scan("Modifier.fillMaxWidth().clickable(onClick = onClick)")
        self.assertTrue(any("高度合约" in error for error in errors))

    def test_missing_width_is_rejected(self) -> None:
        errors = self.scan("Modifier.heightIn(min = 48.dp).clickable(onClick = onClick)")
        self.assertTrue(any("宽度合约" in error for error in errors))

    def test_sub_48dp_target_is_rejected(self) -> None:
        errors = self.scan(
            "Modifier.width(47.dp).height(47.dp).selectable(selected = false, onClick = {})"
        )
        self.assertTrue(any("高度合约" in error for error in errors))
        self.assertTrue(any("宽度合约" in error for error in errors))

    def test_unreviewed_pointer_gesture_is_rejected(self) -> None:
        errors = self.scan("Modifier.pointerInput(Unit) { detectTapGestures { onClick() } }")
        self.assertTrue(any("手势点击区域" in error for error in errors))

    def test_disabled_press_feedback_is_rejected(self) -> None:
        errors = self.scan(
            "Modifier.size(48.dp).clickable(indication = null, onClick = onClick)"
        )
        self.assertTrue(any("按压反馈" in error for error in errors))

    def test_multiple_interactions_on_one_line_are_all_audited(self) -> None:
        errors = self.scan(
            "Modifier.size(48.dp).clickable(onClick = {}).selectable(selected = false, onClick = {})"
        )
        self.assertEqual(errors, [])

    def test_variable_modifier_does_not_borrow_previous_component_size(self) -> None:
        errors = self.scan(
            """
Box(modifier = Modifier.size(48.dp))
Box(
    modifier = compactModifier
        .clickable(onClick = onClick),
)
"""
        )
        self.assertTrue(any("高度合约" in error for error in errors))
        self.assertTrue(any("宽度合约" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
