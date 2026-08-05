"""校验 VMM 删除镜像的回读策略。"""

from __future__ import annotations

import json
from pathlib import Path
import unittest


FIXTURE_PATH = (
    Path(__file__).resolve().parents[3]
    / "contracts/request-fixtures/vmm/delete-image/synthetic-image/request.json"
)


class VmmDeleteImageReadbackPolicyTests(unittest.TestCase):
    def test_delete_image_requires_image_list_readback(self) -> None:
        fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

        self.assertEqual(
            fixture["policy"]["readbackPolicy"],
            "required",
        )


if __name__ == "__main__":
    unittest.main()
