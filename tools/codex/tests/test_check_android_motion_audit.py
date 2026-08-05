from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "check_android_motion_audit.py"
MODULE_SPEC = importlib.util.spec_from_file_location("check_android_motion_audit", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError("无法加载 Android 动效审计脚本")

motion_audit = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = motion_audit
MODULE_SPEC.loader.exec_module(motion_audit)


class AndroidMotionAuditTests(unittest.TestCase):
    def write_ui(self, root: Path, relative_path: str, source: str) -> None:
        target = root / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source, encoding="utf-8")

    def allowed_workspace_source(self) -> str:
        return "\n".join(sorted(motion_audit.ALLOWED_SOURCES))

    def test_current_workspace_baseline_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.write_ui(root, "WorkspaceShell.kt", self.allowed_workspace_source())

            self.assertEqual(
                motion_audit.validate_findings(motion_audit.scan_ui(root)),
                [],
            )

    def test_unreviewed_time_animation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.write_ui(root, "WorkspaceShell.kt", self.allowed_workspace_source())
            self.write_ui(
                root,
                "photos/AnimatedPhoto.kt",
                "val alpha by animateFloatAsState(1f)",
            )

            errors = motion_audit.validate_findings(motion_audit.scan_ui(root))

            self.assertTrue(any("AnimatedPhoto.kt" in error for error in errors))

    def test_missing_system_animation_gate_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = self.allowed_workspace_source().replace(
                "if (ValueAnimator.areAnimatorsEnabled()) {\n",
                "",
            )
            self.write_ui(root, "WorkspaceShell.kt", source)

            errors = motion_audit.validate_findings(motion_audit.scan_ui(root))

            self.assertTrue(any("审计基线缺失" in error for error in errors))
            self.assertTrue(any("系统动画开关" in error for error in errors))

    def test_gesture_graphics_layer_is_not_treated_as_time_animation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            self.write_ui(root, "WorkspaceShell.kt", self.allowed_workspace_source())
            self.write_ui(
                root,
                "FilePreviewDialog.kt",
                "Modifier.graphicsLayer { translationX = gestureOffset }",
            )

            self.assertEqual(
                motion_audit.validate_findings(motion_audit.scan_ui(root)),
                [],
            )


if __name__ == "__main__":
    unittest.main()
