"""Derive private memory ctypes from the existing C headers and Rust forwarders."""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
NATIVE = Path('packages/python-local-runtime/native/pre-root')
OUTPUT = Path('packages/python-sdk/src/actql_sdk/_local_native_memory_abi.py')
HEADER = NATIVE / 'memory_abi.generated.h'
spec = importlib.util.spec_from_file_location('native_shim_types', ROOT / 'scripts/generate-local-native-shim-bindings.py')
TYPES = importlib.util.module_from_spec(spec)
spec.loader.exec_module(TYPES)


def declarations(root: Path = ROOT):
    functions = {}
    thread_header = (root / NATIVE / 'owned_thread.h').read_text()
    if re.search(r'typedef\s+void\s*\(\*actql_owned_thread_entry\)\(void \*argument\);', thread_header) is None:
        raise ValueError('Original thread callback result/argument/convention changed')
    for file in ('owned_capacity.h', 'owned_domain_borrow.h', 'owned_thread.h'):
        original = (root / NATIVE / file).read_text()
        source = re.sub(r'/\*.*?\*/', '', original, flags=re.S)
        for match in re.finditer(r'^(int|size_t|actql_owned_capacity\s*\*)\s*(actql_native_\w+)\s*\(([^()]*)\);', source, re.M):
            result, name, arguments = match.groups()
            parameters = []
            for argument in arguments.split(','):
                if argument.strip() in ('', 'void'):
                    continue
                parameter = re.fullmatch(r'\s*(.+?)(\w+)(\[\d+\])?\s*', argument, re.S)
                if parameter is None:
                    raise ValueError('Unclassified memory parameter: ' + name)
                kind, role, array = parameter.groups()
                kind = ' '.join(kind.split())
                parameters.append((role, kind + (' *' if array else ''), array))
            functions[name] = (result, tuple(parameters), str(NATIVE / file))
    rust = (root / NATIVE / 'owned_abi.rs').read_text()
    rust_types = {'usize': 'c_size_t', 'u64': 'c_uint64', 'c_int': 'c_int',
                  '*const u8': 'POINTER(c_ubyte)', '*const c_void': 'c_void_p',
                  '*mut c_void': 'c_void_p', '*mut *mut c_void': 'POINTER(c_void_p)',
                  '*mut u64': 'POINTER(c_uint64)'}
    forwards = list(re.finditer(r'forward!\((\w+),\s*(\w+),\s*\(([^()]*)\),\s*([^;]+)\);', rust, re.S))
    if len(forwards) != 13:
        raise ValueError('Original Rust memory forwarding inventory changed')
    for forward in forwards:
        alias, native, arguments, result = forward.groups()
        declaration = re.search(r'fn ' + native + r'\(([^()]*)\)\s*->\s*([^;]+);', rust, re.S)
        if declaration is None or re.sub(r'\s+', '', declaration[1] + declaration[2]) != re.sub(r'\s+', '', arguments + result):
            raise ValueError('Rust forwarder differs from its native declaration: ' + alias)
        c_result, c_parameters, _ = functions[native]
        rust_parameters = [tuple(map(str.strip, p.split(':', 1))) for p in arguments.split(',') if p.strip()]
        if len(rust_parameters) != len(c_parameters) or rust_types[result.strip()] != TYPES.ctype(c_result):
            raise ValueError('Rust memory result/arity mismatch: ' + alias)
        for (role, kind), (c_role, c_kind, _) in zip(rust_parameters, c_parameters):
            # The existing Rust spelling omits the explicit byte unit suffix.
            if role not in (c_role, c_role.removesuffix('_bytes')) or rust_types[kind] != TYPES.ctype(c_kind):
                raise ValueError('Rust memory role/type mismatch: ' + alias)
        functions[alias] = (c_result, c_parameters, str(NATIVE / 'owned_abi.rs'))
    return functions


def memory_ctype(kind: str) -> str:
    # One exact C callback typedef, not a data pointer or another calling convention.
    return '_CFUNCTYPE(None, c_void_p)' if kind == 'actql_owned_thread_entry' else TYPES.ctype(kind)


def outputs(root: Path = ROOT):
    functions = declarations(root)
    python = ['"""Generated private C/Rust memory declarations; do not edit."""',
              'from ctypes import CFUNCTYPE as _CFUNCTYPE, POINTER, c_int, c_int64, c_uint64, c_size_t, c_ubyte, c_void_p',
              'from typing import Any', '', 'SIGNATURES: dict[str, tuple[list[Any], Any]] = {']
    header = ['/* Generated from existing C headers and checked Rust forwarders. */',
              '#ifndef ACTQL_PRIVATE_MEMORY_ABI_GENERATED_H', '#define ACTQL_PRIVATE_MEMORY_ABI_GENERATED_H',
              '#include "owned_capacity.h"', '#include "owned_domain_borrow.h"', '#include "owned_thread.h"']
    for name, (result, parameters, _) in sorted(functions.items()):
        python.append('    ' + repr(name) + ': ([' + ', '.join(memory_ctype(p[1]) for p in parameters) + '], ' + TYPES.ctype(result) + '),')
        arguments = ', '.join(p[1] + ' ' + p[0] for p in parameters) or 'void'
        header.append(result + ' ' + name + '(' + arguments + ');')
    python += ['}', '', 'PARAMETERS = {']
    for name, (_, parameters, _) in sorted(functions.items()):
        python.append('    ' + repr(name) + ': ' + repr(parameters) + ',')
    python += ['}', '', 'ORIGINS = {']
    for name, (_, _, origin) in sorted(functions.items()):
        python.append('    ' + repr(name) + ': ' + repr(origin) + ',')
    python += ['}', '', 'def bind(library: Any, symbol: str) -> Any:',
               '    """No loader, allocation, adoption, transfer or permission."""',
               '    arguments, result = SIGNATURES[symbol]', '    call = getattr(library, symbol)',
               '    call.argtypes, call.restype = list(arguments), result', '    return call', '']
    return {ROOT / OUTPUT: '\n'.join(python), ROOT / HEADER: '\n'.join([*header, '#endif', ''])}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, rendered in outputs().items():
        if args.check:
            if path.read_text() != rendered:
                raise SystemExit('Private Native memory binding is stale: ' + str(path))
        else:
            path.write_text(rendered)
    print('Private Native memory binding is current: ' + str(len(declarations())))
