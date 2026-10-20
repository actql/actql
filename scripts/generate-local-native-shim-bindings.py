"""Generate private ctypes declarations from the existing named C shim ABI.

Opaque pointer tags stay in the C declarations. Python receives pointers only;
the existing custody classes retain responsibility for lifetime and operation
meaning. This generator neither loads a library nor initializes a provider.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ENTRY = Path('src/platform_native/installed_arena_entry')
OUTPUT = Path('packages/python-sdk/src/actql_sdk/_local_native_shim_abi.py')
HEADER = ENTRY / 'shim_abi.generated.h'
INITIAL_OUTPUT = Path('packages/python-sdk/src/actql_sdk/_local_native_initial_abi.py')
INITIAL_HEADER = ENTRY / 'python_initial_abi.generated.h'
INITIAL_SOURCE = Path('src/platform_native/host_bootstrap/python_initial_platform.c')
INITIAL_SYMBOLS = frozenset('actql_native_python_initial_platform_' + name
                            for name in ('begin_into', 'current', 'restore'))
SHIMS = ('control', 'backing', 'domain', 'domain_read', 'worker_selection',
         'original_read', 'live_channel', 'process', 'sqlite', 'sqlite_database',
         'packaged_product', 'runtime_initialization', 'local_journal', 'local_host_resources',
         'local_adoption', 'read_crypto')
SCALARS = {'int': 'c_int', 'int32_t': 'c_int32', 'int64_t': 'c_int64',
           'uint64_t': 'c_uint64', 'size_t': 'c_size_t', 'uint16_t': 'c_uint16',
           'uint8_t': 'c_ubyte', 'unsigned char': 'c_ubyte', 'double': 'c_double',
           'bool': 'c_bool'}


def ctype(text: str) -> str:
    text = ' '.join(text.replace('const ', '').split())
    depth = text.count('*')
    base = text.replace('*', '').strip()
    if base in SCALARS:
        result = SCALARS[base]
    elif base == 'void' or base.startswith('actql_'):
        if depth == 0:
            raise ValueError('Opaque value must remain a pointer: ' + text)
        result, depth = 'c_void_p', depth - 1
    else:
        raise ValueError('Unclassified private Native C type: ' + text)
    for _ in range(depth):
        result = 'POINTER(' + result + ')'
    return result


def source_path(shim: str) -> Path:
    # The existing Native Host owns this one implementation. Its .c includes
    # the .h body so ordinary Moon incremental builds track include changes.
    if shim == 'local_journal':
        return Path('src/platform_native/client_host/local_journal_shim_impl.h')
    return ENTRY / (shim + '_shim.c')


def declarations(root: Path = ROOT, *, python_initial: bool = False):
    declarations = {}
    paths = (INITIAL_SOURCE,) if python_initial else tuple(source_path(shim) for shim in SHIMS)
    for path in paths:
        original = (root / path).read_text()
        source = original
        # Expand only the local, named operation macros already used by these
        # shims. Their bodies remain the source authority, including role names.
        for macro in re.finditer(r'^#define (\w+)\(([^()]*)\) ((?:[^\n]*\\\n)+[^\n]*)', original, re.M):
            name, parameters, body = macro.groups()
            parameters = [p.strip() for p in parameters.split(',')]
            body = body.replace('\\\n', '\n')
            def expand(call):
                arguments = [a.strip() for a in call[1].split(',')]
                if len(arguments) != len(parameters) or not all(re.fullmatch(r'\w+', a) for a in arguments):
                    raise ValueError('Unsupported private Native macro: ' + name)
                result = body
                for parameter, argument in zip(parameters, arguments):
                    result = re.sub(r'\b' + parameter + r'\b', argument, result)
                return result
            source = re.sub(r'^' + name + r'\(([^()]*)\)', expand, source, flags=re.M)
        results = 'int32_t|int64_t|uint64_t|int|size_t' + ('|bool' if python_initial else '')
        pattern = r'^((?:' + results + r'))\s+(actql_\w+)\s*\(([^()]*)\)\s*\{'
        for match in re.finditer(pattern, source, re.M):
            result, symbol, arguments = match.groups()
            if python_initial and symbol not in INITIAL_SYMBOLS:
                continue
            parameters = []
            for argument in arguments.split(','):
                argument = argument.strip()
                if argument in ('', 'void'):
                    continue
                parameter = re.fullmatch(r'(.+?)([A-Za-z_]\w*)(\[\d+\])?', argument, re.S)
                if parameter is None:
                    raise ValueError('Unnamed Native parameter: ' + symbol)
                native_type, name, array = parameter.groups()
                if array:
                    native_type = native_type.strip() + ' *'
                parameters.append((name, ' '.join(native_type.split()), ctype(native_type)))
            if symbol in declarations:
                raise ValueError('Duplicate Native symbol: ' + symbol)
            position = original.find(symbol)
            if position < 0:
                raise ValueError('Missing original Native declaration: ' + symbol)
            declarations[symbol] = (result, tuple(parameters), str(path),
                                    original[:position].count('\n') + 1)
    if not declarations:
        raise ValueError('No private Native declarations found')
    if python_initial and set(declarations) != INITIAL_SYMBOLS:
        raise ValueError('Selected Python initial Native declarations changed')
    return declarations


def render(root: Path = ROOT, *, python_initial: bool = False) -> str:
    lines = ['"""Generated from named existing C shim definitions; do not edit."""',
             'from ctypes import POINTER, c_int, c_int32, c_int64, c_uint64, c_size_t, c_uint16, c_ubyte, c_void_p, c_double' + (', c_bool' if python_initial else ''),
             'from typing import Any',
             '', 'SIGNATURES: dict[str, tuple[list[Any], Any]] = {']
    entries = declarations(root, python_initial=python_initial)
    for symbol, (result, parameters, _, _) in sorted(entries.items()):
        lines.append('    ' + repr(symbol) + ': ([' + ', '.join(p[2] for p in parameters) + '], ' + ctype(result) + '),')
    lines += ['}', '', 'PARAMETERS = {']
    for symbol, (_, parameters, _, _) in sorted(entries.items()):
        lines.append('    ' + repr(symbol) + ': ' + repr(tuple((p[0], p[1]) for p in parameters)) + ',')
    lines += ['}', '', 'ORIGINS = {']
    for symbol, (_, _, path, line) in sorted(entries.items()):
        lines.append('    ' + repr(symbol) + ': ' + repr((path, line)) + ',')
    lines += ['}', '', 'def bind(library: Any, symbol: str) -> Any:',
              '    """Bind only a declared operation on the already selected library."""',
              '    arguments, result = SIGNATURES[symbol]',
              '    call = getattr(library, symbol)',
              '    call.argtypes, call.restype = list(arguments), result',
              '    return call', '',
              'def bind_group(library: Any, prefix: str, names: tuple[str, ...]) -> dict[str, Any]:',
              '    return {name: bind(library, prefix + name) for name in names}', '']
    return '\n'.join(lines)


def render_header(root: Path = ROOT, *, python_initial: bool = False) -> str:
    guard = 'ACTQL_PRIVATE_PYTHON_INITIAL_ABI_GENERATED_H' if python_initial else 'ACTQL_PRIVATE_SHIM_ABI_GENERATED_H'
    lines = ['/* Generated from the existing named C shim definitions. */',
             '#ifndef ' + guard, '#define ' + guard]
    lines += (['#include "../host_bootstrap/python_initial_platform.h"'] if python_initial else
              ['#include "' + shim + '_shim.h"' for shim in SHIMS])
    for symbol, (result, parameters, _, _) in sorted(declarations(root, python_initial=python_initial).items()):
        args = ', '.join(native_type + ' ' + name for name, native_type, _ in parameters) or 'void'
        lines.append(result + ' ' + symbol + '(' + args + ');')
    return '\n'.join([*lines, '#endif', ''])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--python-initial', action='store_true',
                        help='Only the explicitly selected private Python initial-entry ABI')
    args = parser.parse_args()
    outputs = (INITIAL_OUTPUT, INITIAL_HEADER) if args.python_initial else (OUTPUT, HEADER)
    for relative, rendered in zip(outputs, (render(python_initial=args.python_initial),
                                          render_header(python_initial=args.python_initial))):
        path = ROOT / relative
        if args.check:
            if path.read_text() != rendered:
                raise SystemExit('Private Native shim binding is stale: ' + str(relative))
        else:
            path.write_text(rendered)
    print('Private Native shim C/ctypes declarations are current: ' +
          str(len(declarations(python_initial=args.python_initial))))
