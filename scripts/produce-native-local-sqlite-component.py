"""Build the selected Local SQLite component for its original CLI provider.

This producer stages pinned source and observes bytes/symbols only. It never
loads a component, initializes SQLite or supplies Host/resource authority.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError('Selected component recipe is unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SQLITE = load('local_sqlite_original', ROOT / 'scripts/produce-python-sqlite-component.py')
NATIVE = load('local_cli_original', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
PROVIDER_IMPORTS = frozenset((
    'actql_bootstrap_current_read_context',
    'actql_read_context_retain',
    'actql_read_context_release_after_owner_ack',
    'actql_native_owned_current',
    'actql_native_owned_retire',
    'actql_native_file_scoped_allocate',
    'actql_native_file_scoped_free',
))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def provider_original(record: object, source: str) -> tuple[Path, dict]:
    """Select an actual completed Local CLI, never a DLL or planned command."""
    require(type(record) is dict and SQLITE._hex(source, 40), 'Invalid CLI provider source')
    require(record.get('source') == source and record.get('entry') == NATIVE.LOCAL_ENTRY
            and record.get('target') == 'darwin-arm64'
            and record.get('plan_only') is False
            and type(record.get('moon_build_exit')) is int and record['moon_build_exit'] == 0
            and type(record.get('providers')) is int and record['providers'] == 1
            and type(record.get('commands_completed')) is int and record['commands_completed'] > 0,
            'A completed same-source original Local CLI provider is required')
    allocator = record.get('allocator')
    recipe_raw = (ROOT / 'packages/python-local-runtime/native/pre-root/scoped-read-source.json').read_bytes()
    recipe = json.loads(recipe_raw)
    require(type(allocator) is dict and allocator.get('target') == recipe['target']
            and allocator.get('recipe_sha256') == hashlib.sha256(recipe_raw).hexdigest()
            and allocator.get('patch_sha256') == recipe['patch']['sha256']
            and allocator.get('required_defines') == recipe['required_defines']
            and allocator.get('outputs') == recipe['outputs'],
            'Original CLI scoped allocation source differs from this component')
    item = record.get('executable')
    require(type(item) is dict and set(item) == {'path', 'bytes', 'sha256'}
            and type(item['path']) is str and Path(item['path']).is_absolute()
            and type(item['bytes']) is int and 0 < item['bytes'] <= 256 * 1024 * 1024
            and SQLITE._hex(item['sha256'], 64), 'Invalid original CLI executable')
    path = Path(item['path'])
    require(SQLITE.identity(path, 256 * 1024 * 1024) ==
            {key: item[key] for key in ('bytes', 'sha256')}, 'Original CLI executable changed')
    return path, item


def link_arguments(common: list[str], obj: Path, library: Path) -> list[str]:
    # Only these original physical ports resolve from the main executable.
    # Every other undefined symbol remains a link error or a system import.
    return [*common, '-dynamiclib', str(obj), '-Wl,-undefined,error',
            *('-Wl,-U,_' + name for name in sorted(PROVIDER_IMPORTS)),
            '-Wl,-install_name,@rpath/' + SQLITE.LIBRARY, '-o', str(library)]


def symbol_inventory(output: str, *, undefined: bool) -> set[str]:
    values = {line.split()[-1] for line in output.splitlines() if line.strip()}
    if undefined:
        actual = {name for name in values if name.startswith('_actql_')}
        require(actual == {'_' + name for name in PROVIDER_IMPORTS},
                'SQLite imports do not match its original CLI provider ports')
        require(not any(name.startswith('_sqlite3_') for name in values),
                'SQLite API must not resolve to another SQLite instance')
    else:
        require(values == SQLITE.EXPORTS, 'Unexpected SQLite component exports')
    return values


def build(source: str, archive: Path, provider_receipt: Path, clang: Path,
          sdk: Path, node: Path, destination: Path, seconds: int) -> dict:
    require(sys.platform == 'darwin' and platform.machine() == 'arm64',
            'The selected Local component requires darwin-arm64')
    require(SQLITE._hex(source, 40) and type(seconds) is int and seconds > 0,
            'Invalid component build selection')

    def clean() -> None:
        require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                text=True).strip() == source
                and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
                'Exact clean committed component source is required')

    clean()
    require(not destination.exists() and not destination.is_symlink(), 'Output already exists')
    raw = SQLITE._read_file(provider_receipt, maximum=65536, capture=True)
    provider, provider_item = provider_original(
        json.loads(raw, object_pairs_hook=SQLITE._pairs), source)
    inputs = {str(path): SQLITE.identity(path, maximum) for path, maximum in (
        (clang, 512 * 1024 * 1024), (node, 256 * 1024 * 1024),
        (Path(sys.executable).resolve(), 256 * 1024 * 1024),
        (sdk / 'SDKSettings.json', 1024 * 1024), (provider_receipt, 65536),
        (Path('/usr/bin/nm'), 16 * 1024 * 1024),
        (Path('/usr/bin/otool'), 16 * 1024 * 1024),
        (Path('/usr/bin/codesign'), 16 * 1024 * 1024),
        (ROOT / 'scripts/produce-native-local-sqlite-component.py', 65536),
        (ROOT / 'scripts/produce-python-sqlite-component.py', 65536),
        (ROOT / 'scripts/produce-native-remote-scoped-runtime.py', 65536),
        (ROOT / 'packages/python-sdk/src/actql_sdk/_local_distribution.py', 65536),
        (ROOT / 'scripts/native-cli-local-runtime.mjs', 65536),
        (ROOT / 'packages/native-cli/lib/local-runtime.mjs', 65536),
        (SQLITE.SOURCE / 'prepare.py', 65536), (SQLITE.SOURCE / 'source.json', 65536),
        (ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536),
        (ROOT / 'packages/python-local-runtime/native/pre-root/scoped-read-source.json', 65536),
    )}
    destination.mkdir(parents=True, exist_ok=False)
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    deadline, steps = time.monotonic() + seconds, []
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'SDKROOT': str(sdk),
                   'MACOSX_DEPLOYMENT_TARGET': '26.0', 'LANG': 'C', 'LC_ALL': 'C'}

    def run(name: str, args: list[str]) -> str:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'Component build budget exhausted')
        result = subprocess.run(args, cwd=ROOT, env=environment, capture_output=True,
                                text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': args, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'Component command failed: ' + name)
        return result.stdout

    provider_symbols = run('provider-exports', ['/usr/bin/nm', '-gU', str(provider)])
    observed = {line.split()[-1] for line in provider_symbols.splitlines() if line.strip()}
    require({'_' + name for name in PROVIDER_IMPORTS} <= observed,
            'Original CLI lacks required same-process provider exports')
    stage = destination / 'source'
    staged = SQLITE.STAGE.prepare(archive, stage)
    bundle = destination / 'bundle'
    bundle.mkdir()
    obj, library = destination / 'component.o', bundle / SQLITE.LIBRARY
    common = [str(clang), '-std=c11', staged['optimization'], '-fPIC', '-fvisibility=hidden',
              '-mmacosx-version-min=26.0', '-isysroot', str(sdk), '-I' + str(stage),
              '-I' + str(ROOT / 'packages/python-local-runtime/native/pre-root')]
    run('compile', [*common, '-MD', '-MF', str(destination / 'component.d'),
                    '-c', str(stage / 'component.c'), '-o', str(obj)])
    run('link', link_arguments(common, obj, library))
    run('sign-generated-component', ['/usr/bin/codesign', '--force', '--sign', '-', str(library)])
    run('verify-generated-component', ['/usr/bin/codesign', '--verify', '--strict', str(library)])
    symbol_inventory(run('component-exports', ['/usr/bin/nm', '-gU', str(library)]), undefined=False)
    symbol_inventory(run('component-imports', ['/usr/bin/nm', '-u', str(library)]), undefined=True)
    # Use the ordinary CLI library observer, including its actual minOS and
    # closed dependency/rpath checks. No Python macOS11 assumption is imported.
    observation = json.loads(run('ordinary-library-observation', [str(node), '--input-type=module',
        '-e', "import {inspectLocalLibrary} from './scripts/native-cli-local-runtime.mjs';"
        "console.log(JSON.stringify(inspectLocalLibrary(process.argv[1],'darwin-arm64',new Set())));",
        str(library)]))
    notice = SQLITE.identity(stage / 'NOTICE', 1024 * 1024)
    SQLITE.checked_copy(stage / 'NOTICE', bundle / SQLITE.NOTICE, notice, 1024 * 1024)
    dependencies = shlex.split((destination / 'component.d').read_text().replace('\\\n', ' ').split(':', 1)[1])
    compiled = {path: SQLITE.compiled_input(Path(path), sdk) for path in sorted(set(dependencies))}
    (destination / 'compiled-inputs.json').write_text(json.dumps(compiled, indent=2) + '\n')
    for name, item in staged['outputs'].items():
        require(SQLITE.identity(stage / name, 16 * 1024 * 1024) == item,
                'Staged SQLite compilation input changed')
    for path, item in inputs.items():
        require(SQLITE.identity(Path(path), 512 * 1024 * 1024) == item, 'Component input changed')
    require(SQLITE.identity(provider, 256 * 1024 * 1024) ==
            {key: provider_item[key] for key in ('bytes', 'sha256')}, 'CLI provider changed')
    clean()
    receipt = {'source': source, 'provider': provider_item, 'upstream': staged['upstream'],
               'recipe_sha256': staged['recipe_sha256'], 'inputs': inputs,
               'library': {'path': str(library), **SQLITE.identity(library, 128 * 1024 * 1024)},
               'notice': {'path': str(bundle / SQLITE.NOTICE), **notice},
               'loader': observation, 'provider_imports': sorted(PROVIDER_IMPORTS),
               'compiled': 1, 'linked': 1, 'loaded': 0, 'initialized': 0,
               'installed_supplier': False, 'normal_profile': None, 'public_e2e': 0}
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--provider-receipt', type=Path, required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--node', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.archive, args.provider_receipt, args.clang,
                           args.sdk, args.node, args.destination, args.seconds)))
