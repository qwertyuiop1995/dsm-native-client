from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
from io import StringIO
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).parents[1] / "ensure_ui_ux_pro_max.py"
MODULE_SPEC = importlib.util.spec_from_file_location("ensure_ui_ux_pro_max", MODULE_PATH)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError("无法加载 UI UX Pro Max 引导脚本")

ensure_skill = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(ensure_skill)


class EnsureUIUXProMaxTests(unittest.TestCase):
    def run_main(self, codex_home: Path) -> int:
        output = StringIO()
        with patch.dict(os.environ, {"CODEX_HOME": str(codex_home)}):
            with redirect_stdout(output), redirect_stderr(output):
                return ensure_skill.main()

    def create_required_files(self, codex_home: Path) -> None:
        skill_directory = codex_home / "skills" / ensure_skill.SKILL_NAME
        (skill_directory / "scripts").mkdir(parents=True)
        (skill_directory / "SKILL.md").write_text("name: ui-ux-pro-max\n", encoding="utf-8")
        (skill_directory / "scripts" / "search.py").write_text("", encoding="utf-8")

    def test_existing_installation_skips_npx(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            codex_home = Path(temporary_directory)
            self.create_required_files(codex_home)
            with patch.object(ensure_skill.subprocess, "run") as run:
                self.assertEqual(self.run_main(codex_home), 0)
                run.assert_not_called()

    def test_incomplete_installation_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            codex_home = Path(temporary_directory)
            (codex_home / "skills" / ensure_skill.SKILL_NAME).mkdir(parents=True)
            self.assertEqual(self.run_main(codex_home), 2)

    def test_missing_npx_returns_actionable_error(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            codex_home = Path(temporary_directory)
            with patch.object(ensure_skill.shutil, "which", return_value=None):
                self.assertEqual(self.run_main(codex_home), 3)

    def test_missing_skill_runs_pinned_installer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            codex_home = Path(temporary_directory)

            def complete_install(command: list[str], **kwargs: object) -> None:
                self.assertIn(ensure_skill.NPM_PACKAGE, command)
                environment = kwargs.get("env")
                self.assertIsInstance(environment, dict)
                self.assertEqual(environment["CODEX_HOME"], str(codex_home))
                self.create_required_files(codex_home)

            with patch.object(ensure_skill.shutil, "which", return_value="/usr/bin/npx"):
                with patch.object(ensure_skill.subprocess, "run", side_effect=complete_install) as run:
                    self.assertEqual(self.run_main(codex_home), 0)
                    run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
