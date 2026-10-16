"""Source freshness for nominal tests, not an actual artifact admission.

Runtime version/export/import/memory acceptance remains in the real artifact
fixture. Reuse the existing generator's Owner projection instead of inventing
another version number for mocked transport tests.
"""
from functools import cache
import importlib.util
from pathlib import Path
import re
from unittest import TestCase


@cache
def current_owner_abi() -> int:
    root = Path(__file__).resolve().parents[3]
    spec = importlib.util.spec_from_file_location('local_wasm_owner_projection', root / 'scripts/generate-local-wasm-abi.py')
    assert spec is not None and spec.loader is not None
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    rendered = generator.render(root)
    value = re.search(r'^LOCAL_CORE_ABI = (\d+)$', rendered, re.M)
    assert value is not None
    return int(value[1])


def assert_current_local_abi(case: TestCase, actual: int) -> None:
    case.assertEqual(actual, current_owner_abi())
