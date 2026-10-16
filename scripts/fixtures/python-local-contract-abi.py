"""Actual scalar artifact shape and independent entry-refusal mutations.

Synthetic modules only test the rejecting boundary. Buffer/physical fixtures
execute the actual fixed-source module separately; a synthetic pass is never
execution evidence for Core.
"""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_core import LOCAL_CORE_ABI, _validate_core_module
from actql_sdk import _local_wasm_abi as abi
from python_local_physical import PhysicalFixture

raw = Path(sys.argv[1]).read_bytes()
engine = wasmtime.Engine()
module = wasmtime.Module(engine, raw)
try:
    _validate_core_module(wasmtime, module)
    exports = {item.name: item.type for item in module.exports}
    # Independently fixed operation meaning, including two same-width fields.
    assert str(exports['actql_buffer_fill'].params) == '[i64, i32, i32, i32]'
    assert abi.ABI_PARAMETERS['actql_buffer_fill'] == (
        ('nonce', 'i64'), ('handle', 'i32'), ('start', 'i32'), ('count', 'i32'))
finally:
    module.close()
    engine.close()


def synthetic(change):
    declarations = []
    for name, (params, result) in abi._IMPORT_SIGNATURES.items():
        if change == 'import-signature' and name == 'input_byte':
            params = 'i64 i32'
        declarations.append(f'(import "actql_host" "{name}" (func (param {params}) (result {result})))')
    for group in vars(abi):
        if not group.endswith('_SIGNATURES') or group == '_IMPORT_SIGNATURES':
            continue
        family = group[1:-11].lower()
        for short, (params, result) in getattr(abi, group).items():
            name = 'actql_' + family + '_' + short
            if change == 'missing-export' and name == 'actql_buffer_fill':
                continue
            if change == 'export-signature' and name == 'actql_buffer_fill':
                params = 'i64 i32 i64 i32'
            declarations.append(f'(func (export "{name}") (param {params}) (result {result}) ({result}.const 0))')
    version = LOCAL_CORE_ABI - 1 if change == 'old-version' else LOCAL_CORE_ABI
    declarations.append(f'(func (export "actql_host_abi_version") (result i32) (i32.const {version}))')
    memory = '(memory (export "memory") 1 256)'
    if change == 'memory':
        memory = '(memory (export "memory") 1 257)'
    if change == 'unknown-export':
        declarations.append('(func (export "actql_unrecognized") (result i32) (i32.const 0))')
    return wasmtime.wat2wasm('(module ' + ' '.join(declarations) + memory + ')')


cases = []
for change, expected in [
    ('import-signature', 'physical imports'),
    ('missing-export', 'exports'),
    ('export-signature', 'exports'),
    ('unknown-export', 'exports'),
    ('memory', 'linear memory'),
    ('old-version', 'fixture ABI version'),
]:
    try:
        PhysicalFixture(synthetic(change), 901)
    except ValueError as error:
        assert expected in str(error), (change, str(error))
    else:
        raise AssertionError('Invalid artifact reached buffer initialization: ' + change)
    cases.append(change)

print(json.dumps({'success': True, 'abi': LOCAL_CORE_ABI,
                  'module_sha256': hashlib.sha256(raw).hexdigest(),
                  'actual_artifact_shape': True, 'rejection_cases': cases}))
