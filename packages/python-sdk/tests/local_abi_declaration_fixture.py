"""Source freshness for nominal tests, not an actual artifact admission.

Runtime version/export/import/memory acceptance remains in the real artifact
fixture. Reuse the existing generator's Owner projection instead of inventing
another version number for mocked transport tests.
"""
from functools import cache, wraps
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


def original_byte_fixture_port(original):
    """Adapt an explicitly mocked byte port to the current scalar transport.

    This is not an ABI fallback or an installed Core adapter. Each selected
    test still supplies its own original bytes, current checks, refusals and
    cleanup. Preserve those byte-level observations rather than duplicating
    their semantic fixtures in every test. Actual packed-output tests and
    real Core method/export bindings do not use this adapter.
    """
    @wraps(original)
    def call(family, name, *args):
        if (family, name) != ('buffer', 'read_packed'):
            return original(family, name, *args)
        handle, start, count = args
        assert type(start) is int and type(count) is int
        assert 0 <= start <= 2147483647 - count and 1 <= count <= 7
        packed = 0
        for offset in range(count):
            byte = original('buffer', 'byte', handle, start + offset)
            if byte < 0:
                return byte
            assert type(byte) is int and byte <= 255, 'Invalid original fixture byte'
            packed |= byte << (8 * offset)
        return packed
    return call
