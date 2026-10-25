"""Generate scalar binding declarations from the existing MoonBit ABI roots.

This reads declarations, not function bodies or transition rules. Unsupported
syntax/types fail closed; actual compiled imports/exports remain an independent
check. Run with --check for read-only freshness validation.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py'
COMPILER_OUTPUT = ROOT / 'packages/python-local-runtime/native/pre-root/compiler_core_abi.generated.h'
SCALAR = {'Int': 'i32', 'Int64': 'i64'}
EXPORT = re.compile(r'#export_name\("([^"]+)"\)\s*pub fn (\w+)\((.*?)\)\s*->\s*(\w+)\s*\{', re.S)
IMPORT = re.compile(r'\bfn (\w+)\(([^()]*)\)\s*->\s*(\w+)\s*=\s*"actql_host"\s*"([^"]+)"', re.S)
FAMILIES = (
    'buffer', 'program', 'check', 'run', 'submission', 'bootstrap', 'source_publication',
    'run_invocation', 'material', 'publication', 'publication_preflight',
    'publication_commit_export', 'payload_request', 'result_binding',
    'payload_chunk', 'payload_record', 'payload_reservation', 'payload_writing',
    'payload_allocation', 'payload_names', 'payload_binding', 'source', 'task',
    'compute', 'result', 'workspace', 'publisher', 'journal', 'current', 'original',
)


def unit(symbol: str, name: str) -> str:
    """Name the existing scalar domain, without copying Owner validation."""
    if name == 'nonce':
        return 'positive instance nonce; identity only, not authority'
    if name.endswith('_bytes') or name in {
        'bytes', 'length', 'transferred', 'uncertain', 'reserved_transfer',
        'held', 'reserved_retention', 'reserved_execution', 'peak_retention',
    }:
        return 'bytes; bounds and retention charge remain with original Owner'
    if name in {'planning', 'planning_work', 'quantum'}:
        return 'logical work units; original Owner bounds'
    if name in {'max_slots', 'attempts', 'holdings', 'count',
                'reserved_attempts', 'live_reservations', 'live_delegations'}:
        return 'count in ' + symbol + '; original named collection/chunk bounds'
    if name in {'start', 'index', 'byte'}:
        return ('byte value0..255' if name == 'byte' else
                'zero-based position in ' + symbol + '; original Owner bounds')
    if name in {'kind', 'ordinal', 'field', 'stage', 'binding_index', 'eof', 'mode'}:
        return 'closed selector/flag of ' + symbol + '; unknown refused by original Owner'
    if name in {'ticket', 'physical_ticket', 'physical_input'} or (
            symbol.startswith('actql_host.') and name == 'input'):
        return 'original physical callback ticket; no authority or wire identity'
    if name in {
        'account_input', 'attempt', 'clock_input', 'compute', 'configuration',
        'current', 'current_configuration', 'current_handle', 'environment',
        'first_handle', 'handle', 'input', 'material', 'materials', 'parent',
        'payload_record', 'preparation', 'publication', 'publisher', 'reader',
        'request', 'result', 'run', 'source', 'step_handle', 'submission', 'task',
    }:
        return 'same-instance original handle of ' + symbol + '.' + name
    raise ValueError('Unclassified ABI parameter unit: ' + symbol + '.' + name)


def parameters(raw: str) -> tuple[tuple[str, str], ...]:
    result = []
    for part in raw.split(','):
        if not part.strip():
            continue
        match = re.fullmatch(r'\s*(\w+)\s*:\s*(Int|Int64)\s*', part)
        if match is None:
            raise ValueError('Unsupported scalar ABI parameter declaration')
        result.append((match[1], SCALAR[match[2]]))
    if len({name for name, _ in result}) != len(result):
        raise ValueError('Duplicate scalar ABI parameter')
    return tuple(result)


def render(root: Path = ROOT) -> str:
    exports, imports, origins, names = {}, {}, {}, {}
    sources = sorted((root / 'src/client_host_wasm').glob('*.mbt'))
    sources += [root / 'src/physical_resources/imported_child_ledger_wasm.mbt']
    for path in sources:
        text = path.read_text()
        matches = list(EXPORT.finditer(text))
        if len(matches) != text.count('#export_name('):
            raise ValueError('Unrecognized exported ABI declaration: ' + str(path))
        for match in matches:
            export, _, raw, result = match.groups()
            if export in exports or result not in SCALAR:
                raise ValueError('Duplicate or unsupported ABI export')
            args = parameters(raw)
            exports[export] = (' '.join(kind for _, kind in args), SCALAR[result])
            names[export] = args
            origins[export] = (str(path.relative_to(root)), match[2])
        for match in IMPORT.finditer(text):
            local, raw, result, name = match.groups()
            if name in imports or result not in SCALAR:
                raise ValueError('Duplicate or unsupported ABI import')
            args = parameters(raw)
            imports[name] = (' '.join(kind for _, kind in args), SCALAR[result])
            names['actql_host.' + name] = args
            origins['actql_host.' + name] = (str(path.relative_to(root)), local)
    version_source = (root / 'src/client_host_wasm/version.mbt').read_text()
    version = re.search(r'pub fn host_abi_version\(\) -> Int\s*\{\s*(\d+)\s*\}', version_source)
    if version is None:
        raise ValueError('Unsupported ABI version declaration')
    groups = {family: {} for family in FAMILIES}
    for name, signature in sorted(exports.items()):
        if name == 'actql_host_abi_version':
            continue
        family = next((f for f in sorted(FAMILIES, key=len, reverse=True)
                       if name.startswith('actql_' + f + '_')), None)
        if family is None:
            raise ValueError('Unclassified ABI export: ' + name)
        groups[family][name.removeprefix('actql_' + family + '_')] = signature
    lines = ['"""Generated by scripts/generate-local-wasm-abi.py; do not edit."""',
             '', 'LOCAL_CORE_ABI = ' + version[1], '']
    for family, values in [*groups.items(), ('import', dict(sorted(imports.items())))]:
        lines.append('_' + family.upper() + '_SIGNATURES = {')
        lines.extend('    ' + repr(k) + ': ' + repr(v) + ',' for k, v in values.items())
        lines.extend(['}', ''])
    units = {symbol: tuple((name, unit(symbol, name)) for name, _ in args)
             for symbol, args in names.items()}
    for label, values in [('ABI_PARAMETERS', names), ('ABI_PARAMETER_UNITS', units),
                          ('ABI_ORIGINS', origins)]:
        lines.append(label + ' = {')
        lines.extend('    ' + repr(k) + ': ' + repr(v) + ',' for k, v in sorted(values.items()))
        lines.extend(['}', ''])
    return '\n'.join(lines)


def render_compiler_header(root: Path = ROOT) -> str:
    """Project the same scalar declarations for the private image compiler.

    This is neither a module parser nor another signature authority. Keep the
    Python projection byte-identical and read its generated literal tables;
    the actual C-API module imports/exports remain independently inspected.
    """
    tables = {}
    for node in ast.parse(render(root)).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name):
                tables[target.id] = ast.literal_eval(node.value)
    exports = {'actql_host_abi_version': ('', 'i32')}
    for family in FAMILIES:
        exports.update({'actql_' + family + '_' + name: signature
                        for name, signature in tables['_' + family.upper() + '_SIGNATURES'].items()})
    lines = ['/* Generated by scripts/generate-local-wasm-abi.py; do not edit. */',
             '#ifndef ACTQL_COMPILER_CORE_ABI_H', '#define ACTQL_COMPILER_CORE_ABI_H',
             '#include <stddef.h>',
             'typedef struct { const char *name; const char *parameters; const char *result; } actql_compiler_signature;',
             '#define ACTQL_COMPILER_CORE_ABI ' + str(tables['LOCAL_CORE_ABI'])]
    for label, values in [('imports', tables['_IMPORT_SIGNATURES']), ('exports', exports)]:
        lines.append('static const actql_compiler_signature actql_compiler_' + label + '[] = {')
        for name, (parameters, result) in sorted(values.items()):
            lines.append('    {' + ', '.join(json.dumps(value) for value in (name, parameters, result)) + '},')
        lines.append('};')
        lines.append('#define ACTQL_COMPILER_' + label.upper() + '_COUNT ' + str(len(values)))
    lines.extend(['#endif', ''])
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rendered = render()
    compiler_rendered = render_compiler_header()
    if args.check:
        if OUTPUT.read_text() != rendered:
            raise SystemExit('Local Wasm ABI binding is stale')
        if COMPILER_OUTPUT.read_text() != compiler_rendered:
            raise SystemExit('Local image compiler ABI binding is stale')
    else:
        OUTPUT.write_text(rendered)
        COMPILER_OUTPUT.write_text(compiler_rendered)
    print('Local Wasm ABI binding SHA256 ' + hashlib.sha256(rendered.encode()).hexdigest())
