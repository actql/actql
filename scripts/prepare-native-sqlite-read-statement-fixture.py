"""Compile only the private actor; its component is the job's verified input."""
from __future__ import annotations

import argparse
import ast
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def prepare(destination: Path, moon: Path, clang: Path, sdk: Path) -> Path:
    if sys.platform != 'darwin' or destination.exists():
        raise ValueError('Select the existing macOS Native route and a fresh actor directory')
    destination.mkdir()
    spec = importlib.util.spec_from_file_location('original_scoped_source',
        ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    source = destination / 'allocator-source'
    module.prepare(moon, source)
    # Consume the existing exact finite provider export inventory. This does
    # not import or run a producer, allocate another component or select SQL.
    recipe = ast.parse((ROOT / 'scripts/produce-native-local-sqlite-component.py').read_text())
    imports = next(n for n in recipe.body if isinstance(n, ast.Assign) and
                   any(isinstance(t, ast.Name) and t.id == 'PROVIDER_IMPORTS' for t in n.targets))
    ports = frozenset(ast.literal_eval(imports.value.args[0]))
    if len(ports) != 7 or any(not name.startswith('actql_') for name in ports):
        raise ValueError('Original selected component provider inventory changed')
    flags = [str(clang), '-std=c11', '-O0', '-DACTQL_SCOPED_READ_ALLOCATOR',
             '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', '-isysroot', str(sdk),
             '-I' + str(source)]
    commands = []

    def run(name, command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        (destination / (name + '.stdout')).write_bytes(result.stdout)
        (destination / (name + '.stderr')).write_bytes(result.stderr)
        commands.append({'name': name, 'command': command, 'exitCode': result.returncode})
        (destination / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        if result.returncode:
            sys.stderr.buffer.write(result.stderr)
            raise ValueError('Private read-statement actor compilation failed: ' + name)

    objects = []
    for name, original, extra in [
        ('bootstrap', ROOT / 'src/platform_native/host_bootstrap/bootstrap_stub.c',
         ['-DACTQL_SCOPED_READ_PROVIDER="' + str(source / 'owned_capacity.c') + '"']),
        ('runtime', source / 'runtime.c', []),
        ('backtrace', source / 'backtrace.c', []),
        ('filesystem', ROOT / 'src/platform_native/filesystem/filesystem_stub.c', []),
        ('read-statement', ROOT / 'packages/python-local-runtime/native/sqlite-component/fixtures/read_statement.c', []),
    ]:
        output = destination / (name + '.o')
        run(name, [*flags, *extra, '-c', str(original), '-o', str(output)])
        objects.append(str(output))
    binary = destination / 'read-statement'
    run('link', [str(clang), '-Wl,-dead_strip', '-Wl,-exported_symbol,_main',
        *('-Wl,-exported_symbol,_' + name for name in sorted(ports)), *objects,
        str(source / 'libmoonbitrun.o'), str(source / 'libbacktrace.a'),
        '-isysroot', str(sdk), '-o', str(binary)])
    return binary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--moon-home', type=Path, required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.destination, args.moon_home, args.clang, args.sdk))
