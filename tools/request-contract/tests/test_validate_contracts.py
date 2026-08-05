"""请求 Fixture 与写操作结果校验测试。"""

from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path


TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def load_module():
    specification = importlib.util.spec_from_file_location(
        "request_contract_validator_test",
        TOOLS_DIRECTORY / "validate_contracts.py",
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("无法加载请求契约校验工具")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


validator = load_module()


class RequestContractValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.request_path = (
            REPOSITORY_ROOT
            / "contracts/request-fixtures/file-station/delete/synthetic-task/request.json"
        )
        cls.request = validator.load_json(cls.request_path)
        cls.mutation_path = (
            REPOSITORY_ROOT
            / "contracts/mutation-results/examples/submitted-but-unverified.json"
        )
        cls.mutation = validator.load_json(cls.mutation_path)

    def test_repository_contracts_pass_validation(self) -> None:
        self.assertGreaterEqual(len(validator.validate_request_directories()), 1)
        self.assertGreaterEqual(len(validator.validate_mutation_examples()), 1)

    def test_rejects_sensitive_parameter(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"].append(
            {"name": "_sid", "valueType": "string", "encodedValue": "secret"}
        )
        with self.assertRaisesRegex(validator.ValidationError, "敏感参数"):
            validator.validate_request_fixture(request, self.request_path)

    def test_accepts_redacted_sensitive_parameter_without_value(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"].append(
            {"name": "password", "valueType": "string", "redacted": True}
        )

        validator.validate_request_fixture(request, self.request_path)

    def test_accepts_request_without_business_parameters(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"] = []

        validator.validate_request_fixture(request, self.request_path)

    def test_accepts_official_lower_camel_case_method(self) -> None:
        request = copy.deepcopy(self.request)
        request["api"]["method"] = "getModule"

        validator.validate_request_fixture(request, self.request_path)

    def test_rejects_method_starting_with_uppercase(self) -> None:
        request = copy.deepcopy(self.request)
        request["api"]["method"] = "GetModule"

        with self.assertRaises(validator.ValidationError):
            validator.validate_request_fixture(request, self.request_path)

    def test_rejects_redacted_marker_for_non_sensitive_parameter(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"][0].pop("encodedValue")
        request["parameters"][0]["redacted"] = True
        with self.assertRaisesRegex(validator.ValidationError, "只允许"):
            validator.validate_request_fixture(request, self.request_path)

    def test_rejects_private_request_value(self) -> None:
        request = copy.deepcopy(self.request)
        request["parameters"][0]["encodedValue"] = "https://nas.example.test/webapi"
        with self.assertRaisesRegex(validator.ValidationError, "URL"):
            validator.validate_request_fixture(request, self.request_path)

        request = copy.deepcopy(self.request)
        request["parameters"][1]["encodedValue"] = "[\"/private-share/file.txt\"]"
        with self.assertRaisesRegex(validator.ValidationError, "绝对路径"):
            validator.validate_request_fixture(request, self.request_path)

    def test_rejects_automatic_retry_for_destructive_write(self) -> None:
        request = copy.deepcopy(self.request)
        request["policy"]["retryPolicy"] = "readOnlyAutomatic"
        with self.assertRaisesRegex(validator.ValidationError, "不得启用"):
            validator.validate_request_fixture(request, self.request_path)

    def test_accepts_destructive_write_with_unavailable_readback_and_no_retry(
        self,
    ) -> None:
        request = copy.deepcopy(self.request)
        request["policy"]["readbackPolicy"] = "unavailable"
        request["policy"]["retryPolicy"] = "never"

        validator.validate_request_fixture(request, self.request_path)

    def test_rejects_retry_when_dangerous_write_cannot_be_read_back(self) -> None:
        request = copy.deepcopy(self.request)
        request["policy"]["readbackPolicy"] = "unavailable"
        request["policy"]["retryPolicy"] = "queryStateBeforeDecision"
        with self.assertRaisesRegex(validator.ValidationError, "必须禁止重试"):
            validator.validate_request_fixture(request, self.request_path)

    def test_rejects_unverified_result_without_refresh(self) -> None:
        result = copy.deepcopy(self.mutation)
        result["requiresRefresh"] = False
        with self.assertRaisesRegex(validator.ValidationError, "必须要求刷新"):
            validator.validate_mutation_result(result, self.mutation_path)

    def test_rejects_partial_result_without_success(self) -> None:
        result = copy.deepcopy(self.mutation)
        result["status"] = "partialSuccess"
        with self.assertRaisesRegex(validator.ValidationError, "同时包含成功"):
            validator.validate_mutation_result(result, self.mutation_path)


if __name__ == "__main__":
    unittest.main()
