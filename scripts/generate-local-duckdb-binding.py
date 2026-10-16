"""Generate the selected private DuckDB C binding from its vendored header.

The selection is the existing caller surface, not an execution capability or
version-compatibility decision. Actual selected library probes stay separate.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SELECTION = Path('scripts/local-duckdb-c-api.json')
OUTPUT = Path('packages/python-sdk/src/actql_sdk/_local_duckdb_abi.py')
RECORDS = {'duckdb_result': '_Result', 'duckdb_string_t': '_String',
           'duckdb_hugeint': '_HugeInt', 'duckdb_uhugeint': '_UHugeInt'}
SCALARS = {'void': 'None', 'bool': 'C.c_bool', 'char': 'C.c_char',
           'uint8_t': 'C.c_uint8', 'uint32_t': 'C.c_uint32',
           'uint64_t': 'C.c_uint64', 'int64_t': 'C.c_int64',
           'double': 'C.c_double'}


def split_fields(body):
    fields, depth, start = [], 0, 0
    for i, character in enumerate(body):
        depth += (character == '{') - (character == '}')
        if character == ';' and depth == 0:
            fields.append(body[start:i].strip())
            start = i + 1
    if body[start:].strip() or depth:
        raise ValueError('Unsupported DuckDB record declaration')
    return fields


def inputs(root=ROOT):
    selected = json.loads((root / SELECTION).read_text())
    source = (root / selected['header']).read_text()
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    opaque = set(re.findall(r'}\s*\*\s*(duckdb_\w+)\s*;', text))
    enums = set(re.findall(r'typedef enum\b[^{}]*{[^{}]*}\s*(\w+)\s*;', text, re.S))
    if not re.search(r'typedef\s+uint64_t\s+idx_t\s*;', text):
        raise ValueError('DuckDB index width changed')
    def kind(value, *, string=False):
        value = ' '.join(value.replace('const ', '').split())
        depth = value.count('*');base = value.replace('*', '').strip()
        if depth and base == 'char':
            if depth == 1:
                return 'C.c_char_p' if string else 'C.c_void_p'
            result, depth = 'C.c_void_p', depth - 1
        elif base in opaque or (depth and base in ('void', 'duckdb_column')):
            result = 'C.c_void_p'
            if base not in opaque:depth -= 1
        elif base == 'idx_t':result = 'C.c_uint64'
        elif base in enums:result = 'C.c_int'
        elif base in RECORDS:result = RECORDS[base]
        elif base in SCALARS:result = SCALARS[base]
        else:raise ValueError('Unclassified DuckDB C type: ' + value)
        for _ in range(depth):result = 'C.POINTER(' + result + ')'
        return result
    records = {}
    for match in re.finditer(r'typedef\s+struct\s*{', text):
        depth, end = 1, match.end()
        while depth and end < len(text):
            depth += (text[end] == '{') - (text[end] == '}');end += 1
        name = re.match(r'\s*(\w+)\s*;', text[end:])
        if name and name[1] in RECORDS:
            records[name[1]] = text[match.end():end-1]
    if set(records) != set(RECORDS):raise ValueError('Missing DuckDB value layout')
    return selected, text, kind, records


def render(root=ROOT):
    selected, text, kind, records = inputs(root)
    lines = ['"""Generated selected DuckDB C declarations; do not edit."""', 'import ctypes as C', 'from typing import Any', '']
    layouts = {}
    def record(body, name, union=False, prefix=''):
        fields, paths = [], []
        for field in split_fields(body):
            if field.startswith(('struct', 'union')):
                nested = re.fullmatch(r'(struct|union)\s*{(.*)}\s*(\w+)', field, re.S)
                if nested is None:raise ValueError('Unsupported nested DuckDB layout')
                category, nested_body, role = nested.groups()
                nested_name = name + '_' + role
                nested_paths = record(nested_body, nested_name, category == 'union')
                fields.append((role, nested_name))
                paths.extend(role + '.' + path for path in nested_paths)
            else:
                scalar = re.fullmatch(r'(.+?)(\w+)(?:\[(\d+)\])?', field, re.S)
                if scalar is None:raise ValueError('Unsupported DuckDB field')
                native_type, role, count = scalar.groups()
                value = kind(native_type)
                if count:value += ' * ' + count
                fields.append((role, value));paths.append(role)
        lines.extend(['class ' + name + '(C.' + ('Union' if union else 'Structure') + '):',
                      '    _fields_ = [' + ', '.join('(' + repr(role) + ', ' + value + ')' for role, value in fields) + ']', ''])
        return paths
    for native, name in RECORDS.items():layouts[native] = record(records[native], name)
    functions = []
    for name in selected['operations']:
        match = re.search(r'DUCKDB_C_API\s+([^;\n]+?)\bduckdb_' + re.escape(name) + r'\s*\(([^;]*)\);', text)
        if match is None:raise ValueError('Missing selected DuckDB function: ' + name)
        result, arguments = match.groups();parameters = []
        for argument in arguments.split(','):
            if argument.strip() in ('', 'void'):continue
            parameter = re.fullmatch(r'\s*(.+?)(\w+)\s*', argument, re.S)
            if parameter is None:raise ValueError('Unnamed DuckDB parameter: ' + name)
            native_type, role = parameter.groups()
            parameters.append((role, ' '.join(native_type.split()), kind(native_type, string=True)))
        functions.append((name, parameters, kind(result, string=name in selected['automatic_string_result'])))
    lines.append('SIGNATURES: dict[str, tuple[list[Any], Any]] = {')
    for name, parameters, result in functions:
        lines.append('    ' + repr(name) + ': ([' + ', '.join(p[2] for p in parameters) + '], ' + result + '),')
    lines.extend(['}', '', 'PARAMETERS = {'])
    for name, parameters, _ in functions:
        lines.append('    ' + repr(name) + ': ' + repr(tuple((p[0], p[1]) for p in parameters)) + ',')
    lines.extend(['}', '', 'LAYOUT_PATHS = ' + repr(layouts), '', 'def bind(library: Any) -> None:',
                  '    """Already digest-selected library only; no database or query operation."""',
                  '    for name, (arguments, result) in SIGNATURES.items():',
                  '        try:', '            call = getattr(library, "duckdb_" + name)',
                  '        except AttributeError as error:',
                  '            raise ValueError("Installed DuckDB lacks the bounded C API") from error',
                  '        call.argtypes, call.restype = list(arguments), result', ''])
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(); rendered = render();path = ROOT / OUTPUT
    if args.check:
        if path.read_text() != rendered:raise SystemExit('Selected DuckDB C binding is stale')
    else:path.write_text(rendered)
    print('Selected DuckDB C/ctypes declaration is current')
