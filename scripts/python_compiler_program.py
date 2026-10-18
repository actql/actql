"""Prepare the selected maintainer compiler executable; never load it.

This is the existing image producer's C compilation/link preparation. The
result is source/module/toolchain correspondence, not a physical receipt,
funding, an installed runtime or permission to deserialize an arbitrary image.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shlex
import stat
import subprocess
import time
from typing import Any, NamedTuple

from actql_sdk._local_distribution import WASMTIME_VERSION, _closed, _pairs, _read_file

ROOT = Path(__file__).resolve().parents[1]
BASE = 'packages/python-local-runtime/native/pre-root/'
spec = importlib.util.spec_from_file_location('compiler_program_original_inputs',
    ROOT / 'scripts/produce-python-native-provider.py')
assert spec is not None and spec.loader is not None
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
spec = importlib.util.spec_from_file_location('compiler_program_original_recipe',
    ROOT / 'scripts/prepare-python-local-runtime.py')
assert spec is not None and spec.loader is not None
recipe_owner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe_owner)


class _CompilerProgram(NamedTuple):
    source: str
    module_sha256: str
    receipt_sha256: str
    engine_sha256: str
    directory: Path
    executable: tuple[str, int, str]
    inputs: tuple[tuple[str, int, str], ...]


def _original(path: Path) -> tuple[str, int, str]:
    record = native.original(path)
    return record['path'], record['bytes'], record['sha256']


def _headers(source: str, directory: Path) -> tuple[tuple[str, int, str], ...]:
    declaration = recipe_owner._source_original(ROOT, source,
        BASE + 'compiler-c-api-headers.json', 'Original compiler C API headers')
    body = _closed(json.loads(declaration, object_pairs_hook=_pairs), (
        'scope', 'upstream_git_commit', 'runtime_version', 'target', 'features',
        'generated_configuration', 'headers'))
    workspace = json.loads(recipe_owner._source_original(ROOT, source,
        BASE + 'workspace-build-inputs.json', 'Original Runtime workspace'))
    if (body['scope'] != 'maintainer_compiler_c_api_headers_only'
            or body['runtime_version'] != WASMTIME_VERSION
            or body['target'] != workspace['target']
            or body['upstream_git_commit'] != workspace['upstream_git_commit']
            or not directory.is_absolute() or directory.resolve() != directory
            or not directory.is_dir() or directory.is_symlink()
            or type(body['headers']) is not list or not body['headers']):
        raise ValueError('Original compiler C API selection is unavailable')
    expected = []
    for item in body['headers']:
        item = _closed(item, ('path', 'bytes', 'sha256'))
        name = item['path']
        if (type(name) is not str or not name or name.startswith('/')
                or any(p in ('', '.', '..') for p in name.split('/'))
                or type(item['bytes']) is not int or item['bytes'] <= 0
                or type(item['sha256']) is not str or len(item['sha256']) != 64):
            raise ValueError('Original compiler C API member is unavailable')
        expected.append((str(directory / name), item['bytes'], item['sha256']))
    if len({p for p, _, _ in expected}) != len(expected):
        raise ValueError('Original compiler C API members repeat')
    actual = []
    for path in sorted(directory.rglob('*')):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError('Compiler C API contains a nonregular member')
        actual.append(_original(path))
    # Includes C++ headers and rejects extra PCH/GCH or symlink inputs. A
    # compiler must not silently consume an unrecorded header replacement.
    if tuple(sorted(actual)) != tuple(sorted(expected)):
        raise ValueError('Compiler C API differs from the original header closure')
    return tuple(actual)


def verify_program(original: dict[str, Any], program: _CompilerProgram) -> Path:
    if (type(program) is not _CompilerProgram or program.source != original['source']
            or program.module_sha256 != original['module_sha256']
            or program.receipt_sha256 != original['core_receipt_sha256']
            or program.engine_sha256 != hashlib.sha256(original['recipe'].engine_body).hexdigest()):
        raise ValueError('Compiler executable belongs to another original module/recipe')
    for filename, size, digest in (*program.inputs, program.executable):
        _read_file(Path(filename), maximum=size, expected=size, digest=digest, capture=False)
    return Path(program.executable[0])


def prepare_program(original: dict[str, Any], *, headers: Path,
                    clang: Path, sdk: Path, destination: Path,
                    seconds: float) -> _CompilerProgram:
    """Strict C2/link1 preparation from the same existing producer inputs.

    No import, constructor, initializer, Config, Engine or child is executed.
    Keep this fresh output directory on failure; never overwrite old artifacts.
    The caller verifies the original module and stages/validates both selected
    Runtime libraries using the shared original recipe before this operation.
    """
    if (type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds <= 0
            or not destination.is_absolute() or destination.resolve() != destination
            or destination.exists() or destination.is_symlink()
            or not clang.is_absolute() or not sdk.is_absolute()
            or sdk.resolve() != sdk or not sdk.is_dir()):
        raise ValueError('Select original compiler inputs and a fresh program directory')
    source = original['source']
    if (subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source
            or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)):
        raise ValueError('Compiler preparation requires its exact clean source')
    # Use the existing Engine Owner projection, not caller-supplied C text or
    # a second set of configuration setters. Loading this producer module does
    # not import/load the private Runtime or construct any native object.
    compiler_path = ROOT / 'scripts/compile-python-local-image.py'
    compiler_spec = importlib.util.spec_from_file_location('compiler_program_engine_projection', compiler_path)
    assert compiler_spec is not None and compiler_spec.loader is not None
    compiler = importlib.util.module_from_spec(compiler_spec)
    compiler_spec.loader.exec_module(compiler)
    configuration = compiler._compiler_configuration_header(original['recipe'])
    header_inputs = _headers(source, headers)
    inputs = {p: (p, n, d) for p, n, d in header_inputs}
    source_files = ('compiler_image.c', 'compiler_module_abi.c', 'compiler_module_abi.h',
                    'compiler_core_abi.generated.h', 'owned_domain_borrow.h', 'owned_capacity.h')
    for name in source_files:
        recipe_owner._source_original(ROOT, source, BASE + name, 'Original compiler source')
        path = ROOT / BASE / name
        inputs[str(path)] = _original(path)
    generator_path = ROOT / 'scripts/generate-local-wasm-abi.py'
    generator_spec = importlib.util.spec_from_file_location('compiler_program_generated_abi', generator_path)
    assert generator_spec is not None and generator_spec.loader is not None
    generator = importlib.util.module_from_spec(generator_spec)
    generator_spec.loader.exec_module(generator)
    if (ROOT / BASE / 'compiler_core_abi.generated.h').read_bytes() != generator.render_compiler_header(ROOT).encode():
        raise ValueError('Original compiler C ABI projection is stale')
    inputs[str(generator_path)] = _original(generator_path)
    for path in (clang, sdk / 'SDKSettings.json', compiler_path, Path(__file__).resolve(),
                 ROOT / BASE / 'compiler-c-api-headers.json',
                 Path(original['runtime_library']), Path(original['provider_library'])):
        inputs[str(path)] = _original(path)
    selected = original['recipe']
    for path, size, digest in ((Path(original['runtime_library']), selected.runtime_library_bytes,
                               selected.runtime_library_sha256),
                              (Path(original['provider_library']), selected.provider_library_bytes,
                               selected.provider_library_sha256)):
        if inputs[str(path)] != (str(path), size, digest):
            raise ValueError('Original compiler Runtime link input changed')
    destination.mkdir()
    configuration_path = destination / 'compiler_configuration.generated.h'
    configuration_path.write_bytes(configuration)
    inputs[str(configuration_path)] = _original(configuration_path)
    deadline = time.monotonic() + seconds
    commands = []
    environment = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'SDKROOT': str(sdk),
                   'MACOSX_DEPLOYMENT_TARGET': '11.0'}

    def run(name: str, arguments: list[str]) -> bytes:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Original compiler program preparation deadline elapsed')
        result = subprocess.run(arguments, cwd=ROOT, env=environment,
                                capture_output=True, timeout=remaining)
        (destination / (name + '.stdout')).write_bytes(result.stdout)
        (destination / (name + '.stderr')).write_bytes(result.stderr)
        commands.append({'name': name, 'command': arguments, 'exit': result.returncode})
        (destination / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        if result.returncode != 0:
            raise ValueError('Original compiler program preparation failed: ' + name)
        return result.stdout

    flags = [str(clang), '-std=c11', '-O0', '-Wall', '-Wextra', '-Wpedantic', '-Werror',
        '-Wstrict-prototypes', '-Wmissing-prototypes', '-isysroot', str(sdk),
        '-mmacosx-version-min=11.0', '-isystem', str(headers), '-I', str(ROOT / BASE),
        '-I', str(destination)]
    objects = []
    for name in ('compiler_module_abi', 'compiler_image'):
        output = destination / (name + '.o')
        dependency_file = destination / (name + '.d')
        run(name, [*flags, '-c', str(ROOT / BASE / (name + '.c')), '-o', str(output),
                   '-MD', '-MF', str(dependency_file)])
        objects.append(output)
        for value in shlex.split(dependency_file.read_text().replace('\\\n', ' ').split(':', 1)[1]):
            record = native.original_dependency(Path(value), sdk)
            inputs[record['path']] = (record['path'], record['bytes'], record['sha256'])
    executable = destination / 'compiler-image'
    run('link', [str(clang), '-isysroot', str(sdk), '-mmacosx-version-min=11.0',
        *(str(p) for p in objects), str(original['runtime_library']), str(original['provider_library']),
        '-Wl,-rpath,' + str(Path(original['runtime_library']).parent), '-o', str(executable)])
    dependencies = run('dependencies', ['/usr/bin/otool', '-L', str(executable)])
    actual = [line.strip().split(' (')[0] for line in dependencies.decode().splitlines()[1:]]
    if actual != ['@rpath/_libwasmtime.dylib', '@rpath/libactql_native_control.dylib',
                  '/usr/lib/libSystem.B.dylib']:
        raise ValueError('Original compiler executable has unexpected library dependencies')
    for path in objects:
        inputs[str(path)] = _original(path)
    program = _CompilerProgram(source, original['module_sha256'], original['core_receipt_sha256'],
        hashlib.sha256(selected.engine_body).hexdigest(), destination, _original(executable),
        tuple(sorted(inputs.values())))
    verify_program(original, program)
    (destination / 'program-receipt.json').write_text(json.dumps(
        {**program._asdict(), 'directory': str(program.directory), 'environment': environment}, indent=2) + '\n')
    return program
