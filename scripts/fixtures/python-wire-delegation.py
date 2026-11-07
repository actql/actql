"""Runtime identity and lightweight-import counter, independent of import spelling."""
import importlib.abc
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / 'packages/python-sdk/src'))


class RemoteOnly(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in {'wasmtime', 'duckdb', 'actql_local_runtime'}:
            raise AssertionError(f'Remote wire import attempted Local dependency: {fullname}')
        return None


sys.meta_path.insert(0, RemoteOnly())
from actql_sdk import AsyncClient, Client, _wire, _wire_codec

for name in ['valid', 'utf16_length', 'SCHEMAS', 'CONTRACT']:
    assert getattr(_wire, name) is getattr(_wire_codec, name), name
assert Path(_wire.__file__).resolve() == root / 'packages/python-sdk/src/actql_sdk/_wire.py'
assert Path(_wire_codec.__file__).resolve() == root / 'packages/python-sdk/src/actql_sdk/_wire_codec.py'
assert _wire.valid(0, {'type': 'integer'})
assert not _wire.valid(False, {'type': 'integer'})
assert not _wire.valid(10 ** 400, {'type': 'integer'})
assert Client is not None and AsyncClient is not None
assert not {'wasmtime', 'duckdb', 'actql_local_runtime'} & sys.modules.keys()
# Same wire envelope boundaries as Node. This establishes shape/Unicode only,
# not installed preparation capacity, execution or normal package acceptance.
connection = {'mode': 'remote', 'owner': 'remote', 'consentRefs': [], 'runners': []}
for units in (65535, 65536, 65537):
    for text in ('x' * units, '日' * units,
                 '😀' * (units // 2) + ('x' if units % 2 else ''), '\n' * units):
        assert _wire.utf16_length(text) == units
        source = {'text': text, 'format': 'sql'}
        assert _wire.valid_body('submit', {'connection': connection, 'requestId': 'text-demand',
            'kind': 'aql', 'input': source, 'parameters': None})
        assert _wire.valid_body('check', {'connection': connection, 'scope': 'template_only',
            'kind': 'text', 'input': source})
for text in ('', 'a\0b', '\ud800'):
    assert not _wire.valid_body('check', {'connection': connection, 'scope': 'template_only',
        'kind': 'text', 'input': {'text': text, 'format': 'sql'}})
print('Python codec delegation and Remote-only import: passed')
