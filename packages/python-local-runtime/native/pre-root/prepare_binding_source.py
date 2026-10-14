"""Stage pinned binding source for review; do not import, install or build it."""
from __future__ import annotations

import argparse
import ast
import difflib
import hashlib
import json
from pathlib import Path
import tarfile


SOURCE_SHA256 = '75d38a075571756543266df782979fc2204cafd1fb7f3ebbb901e05df916dd34'
PRIVATE_NAMESPACE = 'actql_local_runtime._wasmtime'
SOURCE_PREFIX = 'wasmtime-38.0.0/wasmtime/'


def _private_imports(source: bytes) -> tuple[bytes, int]:
    tree = ast.parse(source)
    lines = source.splitlines(keepends=True)
    starts = [0]
    for line in lines:
        starts.append(starts[-1] + len(line))
    changes: list[tuple[int, int, bytes]] = []
    for node in ast.walk(tree):
        replacement: ast.AST | None = None
        if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            if node.module == 'wasmtime' or node.module.startswith('wasmtime.'):
                replacement = ast.ImportFrom(
                    module=PRIVATE_NAMESPACE + node.module[len('wasmtime'):],
                    names=node.names, level=0,
                )
        if isinstance(node, ast.Import) and any(
            name.name == 'wasmtime' or name.name.startswith('wasmtime.') for name in node.names
        ):
            names = []
            for name in node.names:
                if name.name == 'wasmtime':
                    names.append(ast.alias(name=PRIVATE_NAMESPACE, asname=name.asname or 'wasmtime'))
                elif name.name.startswith('wasmtime.'):
                    if name.asname is None:
                        raise ValueError('Unaliased nested upstream import requires explicit review')
                    names.append(ast.alias(name=PRIVATE_NAMESPACE + name.name[len('wasmtime'):],
                                           asname=name.asname))
                else:
                    names.append(name)
            replacement = ast.Import(names=names)
        if replacement is not None:
            if node.end_lineno is None or node.end_col_offset is None:
                raise ValueError('Unavailable exact import span')
            start = starts[node.lineno - 1] + node.col_offset
            end = starts[node.end_lineno - 1] + node.end_col_offset
            changes.append((start, end, ast.unparse(replacement).encode('utf-8')))
    output = source
    for start, end, replacement in sorted(changes, reverse=True):
        output = output[:start] + replacement + output[end:]
    ast.parse(output)
    return output, len(changes)


def prepare(archive_path: Path, destination: Path) -> dict[str, object]:
    raw = archive_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError('Pinned Wasmtime Python source digest mismatch')
    if destination.exists():
        raise ValueError('Binding review destination already exists')
    staged: dict[str, bytes] = {}
    inputs: list[dict[str, object]] = []
    patches = []
    import_count = 0
    with tarfile.open(archive_path) as archive:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.startswith(SOURCE_PREFIX):
                continue
            name = member.name[len(SOURCE_PREFIX):]
            # The existing Core uses the high-level binding package. Do not
            # stage bindgen/CLI/loader example entry points or native libraries.
            if '/' in name or name == 'loader.py' or not name.endswith('.py'):
                continue
            stream = archive.extractfile(member)
            if stream is None or member.size > 2 * 1024 * 1024:
                raise ValueError('Invalid upstream Python source member')
            original = stream.read(member.size + 1)
            if len(original) != member.size:
                raise ValueError('Incomplete upstream Python source member')
            output, imports = _private_imports(original)
            staged[name] = output
            import_count += imports
            inputs.append({'file': name, 'source_sha256': hashlib.sha256(original).hexdigest(),
                           'private_sha256': hashlib.sha256(output).hexdigest(),
                           'rewritten_imports': imports})
            if output != original:
                patches.extend(difflib.unified_diff(
                    original.decode().splitlines(True), output.decode().splitlines(True),
                    fromfile='a/wasmtime/' + name, tofile='b/wasmtime/' + name, n=0))
        license_stream = archive.extractfile('wasmtime-38.0.0/LICENSE')
        if license_stream is None:
            raise ValueError('Missing original Wasmtime Python license')
        license_body = license_stream.read()
    if '_ffi.py' not in staged or '_bindings.py' not in staged or '__init__.py' not in staged:
        raise ValueError('Incomplete pinned binding package')
    symbols = sorted({node.attr for node in ast.walk(ast.parse(staged['_bindings.py']))
                      if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name)
                      and node.value.id == 'dll'})
    report: dict[str, object] = {
        'status': 'source-review-only', 'source_sha256': SOURCE_SHA256,
        'namespace': PRIVATE_NAMESPACE, 'inputs': sorted(inputs, key=lambda item: str(item['file'])),
        'absolute_imports_rewritten': import_count,
        'required_dll_symbols': symbols,
        'native_library_included': False, 'bindings_imported': False,
        'engine_executed': 0, 'wheel_built': 0, 'complete_supplier': False,
        'license_sha256': hashlib.sha256(license_body).hexdigest(),
        'not_ready': [
            'Original loader selects DLL relative to its private package; no DLL staged',
            'SDK original component/recipe library fence must precede import',
            'Generated bindings capture function addresses at import; post-load dll replacement forbidden',
            'Native feature/export closure must match all required symbols',
            'Original native call/handle cleanup scopes and image pointer borrow unconnected',
            'Loader/Python/native baseline and infallible heap exhaustion unclosed',
        ],
    }
    destination.mkdir(parents=True)
    package = destination / 'actql_local_runtime' / '_wasmtime'
    package.mkdir(parents=True)
    for name, output in staged.items():
        (package / name).write_bytes(output)
    (destination / 'WASMTIME-PYTHON-LICENSE').write_bytes(license_body)
    (destination / 'namespace-review.patch').write_text(''.join(patches))
    (destination / 'binding-source.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.source, args.destination)
    print(json.dumps({'source_files': len(result['inputs']),
                      'rewritten_imports': result['absolute_imports_rewritten'],
                      'dll_symbols': len(result['required_dll_symbols']),
                      'engine_executed': 0, 'wheel_built': 0, 'complete_supplier': False}))
