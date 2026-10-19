"""Explicit maintainer build of one selected CLI with the derived read allocator.

Run through the existing local-check guard. This prepares a distinct artifact;
never installs it, executes it, changes the selected toolchain, or grants capacity.
The default remains the Remote CLI. Select --entry src/cmd/native_client for
the Local CLI's original release/no-strip recipe, with the same derived provider.
Neither selection supplies an installed Host, read claim or numeric profile.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'src/cmd/native_remote_resident_site'
LOCAL_ENTRY = 'src/cmd/native_client'
RUNTIME_NAMES = frozenset(('runtime', 'env', 'utf', 'backtrace', 'sync_io'))
RELEASE_UTF_OBJECTS = frozenset(('moonbit_simdutf.o', 'simdutf.o'))
# Only the selected Local components import these same-process physical ports.
# No provider DLL, general symbol export or second allocator is introduced.
LOCAL_COMPONENT_PROVIDER_EXPORTS = (
    'actql_native_owned_current',
    'actql_native_owned_allocate',
    'actql_native_owned_retire',
    'actql_read_context_retain',
    'actql_read_context_release_after_owner_ack',
    'actql_bootstrap_current_read_context',
    'actql_native_file_scoped_allocate',
    'actql_native_file_scoped_free',
)


def selected_entry(entry: str) -> str:
    if entry not in (ENTRY, LOCAL_ENTRY):
        raise ValueError('Only the original Remote or Local CLI entry may be selected')
    return entry.removeprefix('src/')


def moon_build_arguments(moon_home: Path, emission: Path, entry: str) -> list[str]:
    selected_entry(entry)
    # The existing Remote recipe strips; the ordinary Local artifact recipe
    # does not. Its native_client package remains the source of its O0 flags.
    return [str(moon_home / 'bin/moon'), 'build', '--target', 'native', '--release',
            *(['--strip'] if entry == ENTRY else []),
            '--target-dir', str(emission), '-j', '1', entry]


def original(path: Path) -> dict[str, object]:
    if path.is_symlink() or not path.is_file():
        raise ValueError('Original build input unavailable: ' + str(path))
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def under(path: Path, root: Path) -> bool:
    return path.is_absolute() and path.resolve().is_relative_to(root.resolve())


def local_initial_entry_arguments(parts: list[str], moon_home: Path,
                                  emission: Path) -> list[str]:
    """Validate selected link members without imposing initializer order."""
    runtime = str(moon_home / 'lib/libmoonbitrun.o')
    directory = emission / 'native/release/build/cmd/native_client'
    archives = [p for p in parts if Path(p).parent == directory
                and re.fullmatch(r'libnative_client-[0-9a-f]{16}\.a', Path(p).name)]
    if parts.count(runtime) != 1 or len(archives) != 1:
        raise ValueError('Exact original CLI archive and allocator object are required')
    return list(parts)


def commands_for(output: str, moon_home: Path, emission: Path, allocator: Path,
                 clang: Path, sdk: Path, *, cc_driver: Path | None = None,
                 ar_driver: Path | None = None, entry: str = ENTRY,
                 source_sha: str | None = None) -> list[list[str]]:
    """Keep the actual pinned dry-run closure; reject other targets/entries."""
    entry_package = selected_entry(entry)
    if entry == LOCAL_ENTRY and (source_sha is None or re.fullmatch(r'[0-9a-f]{40}', source_sha) is None):
        raise ValueError('Exact Local CLI source pin is required')
    core = emission / 'native/release/build' / entry_package / (Path(entry_package).name + '.c')
    executable = core.with_suffix('.exe')
    commands: list[list[str]] = []
    links = finals = providers = source_pins = 0
    runtime: set[str] = set()
    modules: set[str] = set()
    for line in output.splitlines():
        parts = shlex.split(line)
        if not parts:
            continue
        parts = [p.replace('$MOON_HOME', str(moon_home)) for p in parts]
        if any('$' in p for p in parts):
            raise ValueError('Unresolved build placeholder')
        archive_files = None
        if ar_driver is not None and parts[0] == str(ar_driver):
            if parts[1:4] == ['-r', '-c', '-s']:
                archive_files = parts[4:]
            elif len(parts) >= 4 and parts[1] in ('rcs', 'crs', 'cq', 'qc'):
                archive_files = parts[2:]
            if archive_files is None or len(archive_files) < 2:
                raise ValueError('Unexpected original archive operation')
            output_path = Path(archive_files[0])
        elif '-o' in parts:
            output_path = Path(parts[parts.index('-o') + 1])
        else:
            raise ValueError('Missing selected build output')
        if not under(output_path, emission):
            raise ValueError('Build output escapes selected artifact')
        if parts[0] == 'moonc':
            if len(parts) < 2 or parts[1] not in ('build-package', 'link-core'):
                raise ValueError('Unexpected Moon compiler operation')
            if '-target' not in parts or parts[parts.index('-target') + 1] != 'native':
                raise ValueError('Foreign Moon compiler target')
            if parts[1] == 'build-package':
                package = parts[parts.index('-pkg') + 1]
                if not package.startswith('actql/actql/') or package in modules:
                    raise ValueError('Duplicate or foreign generated package')
                modules.add(package)
            else:
                links += 1
                if Path(parts[parts.index('-o') + 1]) != core:
                    raise ValueError('Foreign generated Core module')
            parts[0] = str(moon_home / 'bin/moonc')
        elif parts[0] == str(cc_driver or Path('/usr/bin/cc')):
            sources = [p for p in parts[1:] if p.endswith('.c')]
            if len(sources) != 1:
                raise ValueError('Each original C step must have one source')
            source = Path(sources[0])
            final = '-c' not in parts
            if final:
                finals += 1
                if source != core:
                    raise ValueError('Foreign final Core source')
                if Path(parts[parts.index('-o') + 1]) != executable:
                    raise ValueError('Foreign executable output')
                if entry == LOCAL_ENTRY:
                    parts = local_initial_entry_arguments(parts, moon_home, emission)
                    parts.extend('-Wl,-exported_symbol,_' + symbol
                                 for symbol in LOCAL_COMPONENT_PROVIDER_EXPORTS)
            elif under(source, moon_home / 'lib/runtime'):
                if source.stem not in RUNTIME_NAMES or source.stem in runtime:
                    raise ValueError('Duplicate or foreign runtime source')
                runtime.add(source.stem)
                parts[parts.index(sources[0])] = str(allocator / source.name)
            else:
                # Preserve the actual source, including relative include layout.
                resolved = source if source.is_absolute() else ROOT / source
                if not under(resolved, ROOT / 'src'):
                    raise ValueError('Foreign FFI source')
                if resolved.resolve() == (ROOT / 'src/platform_native/host_bootstrap/bootstrap_stub.c').resolve():
                    providers += 1
                    parts.append('-DACTQL_SCOPED_READ_PROVIDER="' + str(allocator / 'owned_capacity.c') + '"')
                if entry == LOCAL_ENTRY and resolved.resolve() == (ROOT / 'src/cmd/native_client/stdout_stub.c').resolve():
                    if any(p.startswith(('-DACTQL_NATIVE_CLIENT_SOURCE_SHA', '-DACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY', '-DACTQL_NATIVE_COMMAND_INITIAL_OS_RECIPE')) for p in parts):
                        raise ValueError('Duplicate Local CLI source pin')
                    source_pins += 1
                    parts.append('-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + source_sha + '"')
            # Every generated Core, original FFI, and runtime source sees the
            # same derived header first. There is exactly one provider below.
            parts[0] = str(clang)
            parts[1:1] = ['-isysroot', str(sdk), '-mmacosx-version-min=11.0',
                          '-I' + str(allocator), '-DACTQL_SCOPED_READ_ALLOCATOR']
        elif ar_driver is not None and parts[0] == str(ar_driver):
            outside = [Path(p) for p in archive_files if not under(Path(p), emission)]
            if outside:
                # Ordinary pinned release Moon links these two UTF conversion
                # objects into its runtime archive. Keep that exact command;
                # neither an arbitrary external object nor an FFI archive may
                # acquire this exception. Their bytes join the input receipt.
                selected = {moon_home / 'lib' / name for name in RELEASE_UTF_OBJECTS}
                if (output_path.parent != emission / 'native/release/build'
                        or not output_path.name.startswith('libruntime-')
                        or output_path.suffix != '.a'
                        or len(outside) != len(selected) or set(outside) != selected):
                    raise ValueError('Foreign archive input')
        elif Path(parts[0]).name == 'libtool':
            if parts[0] != '/Library/Developer/CommandLineTools/usr/bin/libtool' or '-static' not in parts:
                raise ValueError('Foreign archive tool')
        else:
            raise ValueError('Unexpected selected build tool')
        commands.append(parts)
    if (links, finals, providers) != (1, 1, 1) or runtime != RUNTIME_NAMES:
        raise ValueError('Incomplete or duplicated Core/runtime/provider composition')
    if entry == LOCAL_ENTRY and source_pins != 1:
        raise ValueError('Missing or duplicate Local CLI source pin entrance')
    if 'actql/actql/' + entry_package not in modules:
        raise ValueError('Selected CLI entry is missing')
    return commands


def canonical_c_arguments(arguments: list[str]) -> list[str]:
    # The pinned dry-run prints ./src paths while actual Moon execution makes
    # those same source paths absolute. No flags, outputs or foreign paths are
    # normalized; they must still match the exact selected command.
    return [str((ROOT / p).resolve()) if p.startswith('./src/') and p.endswith('.c')
            else p for p in arguments]


def compile_selected_c(plan_path: Path, arguments: list[str]) -> None:
    """Private cc port: accept only an exact step from this Moon invocation."""
    plan = json.loads(plan_path.read_text())
    actual = canonical_c_arguments(arguments)
    matches = [step for step in plan['steps']
               if canonical_c_arguments(step['original']) == actual]
    if len(matches) != 1:
        raise ValueError('Unplanned or ambiguous C compiler invocation')
    step = matches[0]
    for item in plan['allocator_inputs']:
        if original(Path(item['path'])) != item:
            raise ValueError('Derived allocator changed before C compilation')
    result = subprocess.run(step['selected'], check=False)
    output = Path(step['selected'][step['selected'].index('-o') + 1])
    receipt = {'original': arguments, 'selected': step['selected'], 'exit': result.returncode}
    if result.returncode == 0:
        receipt['output'] = original(output)
    # Distinct output names and j1 preserve one actual record per selected step.
    Path(step['receipt']).write_text(json.dumps(receipt, indent=2) + '\n')
    if result.returncode:
        raise SystemExit(result.returncode)


def build(source: str, moon_home: Path, clang: Path, sdk: Path,
          destination: Path, seconds: int, *, plan_only: bool,
          entry: str = ENTRY) -> dict[str, object]:
    entry_package = selected_entry(entry)
    if type(seconds) is not int or seconds <= 0 or type(plan_only) is not bool:
        raise ValueError('Explicit positive preparation budget required')
    deadline = time.monotonic() + seconds
    environment = {**os.environ, 'MOON_HOME': str(moon_home), 'MOONBIT_NEW_NATIVE': '0',
                   'SDKROOT': str(sdk), 'MACOSX_DEPLOYMENT_TARGET': '11.0',
                   'PATH': str(moon_home / 'bin') + ':/usr/bin:/bin:/usr/sbin:/sbin'}

    def run(command: list[str], *, capture: bool = False) -> str:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Selected build preparation budget exhausted')
        try:
            result = subprocess.run(command, cwd=ROOT, env=environment, check=True,
                                    timeout=remaining, text=True, capture_output=capture)
        except subprocess.CalledProcessError as error:
            if capture and destination.exists():
                (destination / 'tool-failure.stdout').write_text(error.stdout or '')
                (destination / 'tool-failure.stderr').write_text(error.stderr or '')
                (destination / 'tool-failure-command.json').write_text(json.dumps(command) + '\n')
            raise
        return result.stdout if capture else ''

    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('This explicit recipe selects darwin-arm64 only')
    if (run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != source
            or run(['git', 'status', '--porcelain'], capture=True)):
        raise ValueError('Exact clean committed build source required')
    pin = json.loads((ROOT / 'toolchain.json').read_text())
    if json.loads((moon_home / 'installed.json').read_text()) != {'pin': pin, 'platform': 'darwin-arm64'}:
        raise ValueError('Original toolchain marker mismatch')
    if (run([str(moon_home / 'bin/moonc'), '-v'], capture=True).strip() != pin['moonc']
            or run([str(moon_home / 'bin/moon'), 'version'], capture=True).splitlines()[0] != 'moon ' + pin['moon']):
        raise ValueError('Original compiler mismatch')
    if not sdk.is_dir() or sdk.is_symlink() or not clang.is_file():
        raise ValueError('Original compiler/SDK unavailable')
    destination.mkdir(parents=True, exist_ok=False)
    recipe = ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py'
    spec = importlib.util.spec_from_file_location('remote_scoped_source', recipe)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    allocator = destination / 'derived-read-source'
    selection = module.prepare(moon_home, allocator)
    emission = destination / 'emission'
    cc_driver = destination / 'bin/cc'
    cc_driver.parent.mkdir()
    ar_driver = cc_driver.parent / 'ar'
    # Moon resolves this sibling for an explicitly selected compiler directory.
    # Delegate the real selected archiver; no archive bytes are synthesized.
    ar_driver.write_text('#!/bin/sh\nexec /Library/Developer/CommandLineTools/usr/bin/ar "$@"\n')
    ar_driver.chmod(0o755)
    cc_plan = destination / 'cc-plan.json'
    # Only the C port is redirected. Ordinary Moon retains dependency/registry
    # generation and all package compiler arguments, including -all-pkgs.
    python = Path(sys.executable).resolve()
    cc_driver.write_text('#!' + str(python) + '\n'
        + 'import importlib.util, sys, subprocess\nfrom pathlib import Path\n'
        + 'if sys.argv[1:] in (["--version"], ["-v"]):\n'
        + '    raise SystemExit(subprocess.run([' + repr(str(clang)) + ',*sys.argv[1:]]).returncode)\n'
        + 's=importlib.util.spec_from_file_location("remote_cc",' + repr(str(Path(__file__).resolve())) + ')\n'
        + 'm=importlib.util.module_from_spec(s); s.loader.exec_module(m)\n'
        + 'm.compile_selected_c(Path(' + repr(str(cc_plan)) + '),sys.argv[1:])\n')
    cc_driver.chmod(0o755)
    environment['PATH'] = str(cc_driver.parent) + ':' + environment['PATH']
    moon_arguments = moon_build_arguments(moon_home, emission, entry)
    dry = run(moon_arguments + ['--dry-run'], capture=True)
    (destination / 'moon-dry-run.txt').write_text(dry)
    commands = commands_for(dry, moon_home, emission, allocator, clang, sdk,
                            cc_driver=cc_driver, ar_driver=ar_driver, entry=entry, source_sha=source)
    (destination / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    originals = [[p.replace('$MOON_HOME', str(moon_home)) for p in shlex.split(line)]
                 for line in dry.splitlines() if line.strip()]
    c_steps = [{'original': before[1:], 'selected': after,
                'receipt': str(destination / ('cc-' + str(index) + '.json'))}
               for index, (before, after) in enumerate(zip(originals, commands))
               if before[0] == str(cc_driver)]
    cc_plan.write_text(json.dumps({'steps': c_steps,
        'allocator_inputs': [original(p) for p in sorted(allocator.iterdir()) if p.is_file()]}, indent=2) + '\n')
    # Preserve all selected package sources, the original pinned Core and FFI
    # include closure, and the exact allocator recipe. Source SHA alone cannot
    # stand in for the separately installed compiler/runtime/Core inputs.
    packages = [c[c.index('-pkg') + 1].removeprefix('actql/actql/')
                for c in commands if c[0] == str(moon_home / 'bin/moonc') and c[1] == 'build-package']
    paths = {ROOT / 'toolchain.json', ROOT / 'moon.mod', Path(__file__), clang,
             cc_driver, ar_driver, cc_plan, python,
             Path('/Library/Developer/CommandLineTools/usr/bin/ar'),
             Path('/Library/Developer/CommandLineTools/usr/bin/libtool'),
             sdk / 'SDKSettings.json', moon_home / 'installed.json',
             moon_home / 'bin/moon', moon_home / 'bin/moonc',
             moon_home / 'lib/libmoonbitrun.o', moon_home / 'lib/libbacktrace.a'}
    paths.update(moon_home / 'lib' / name for name in RELEASE_UTF_OBJECTS)
    for package in packages:
        paths.update(p for p in (ROOT / 'src' / package).iterdir()
                     if p.is_file() and p.suffix in ('.mbt', '.pkg', '.c', '.h', '.inc'))
    for directory in (moon_home / 'include', moon_home / 'lib/runtime',
                      moon_home / 'lib/core/_build/native/release/bundle',
                      recipe.parent, allocator):
        paths.update(p for p in directory.rglob('*') if p.is_file()
                     and p.suffix in ('.mi', '.core', '.c', '.h', '.inc', '.json', '.py', '.patch'))
    inputs = [original(p) for p in sorted(paths)]
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    receipt: dict[str, object] = {
        'source': source, 'entry': entry, 'target': 'darwin-arm64',
        'compiler_backend': 'pinned ordinary C (MOONBIT_NEW_NATIVE=0)',
        'package_registry': 'Generated by ordinary pinned Moon; no compiler arguments omitted',
        'compiler_profile': 'ordinary Moon --release' + (' --strip' if entry == ENTRY else ''),
        'selected_packages': packages, 'core_modules': 1, 'providers': 1,
        'allocator': selection, 'plan_only': plan_only, 'commands_completed': 0,
        'installed_supplier': False, 'normal_profile': None, 'runtime_cases': 0, 'public_e2e': 0,
    }
    (destination / 'progress.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not plan_only:
        build_command = moon_arguments + ['--verbose']
        (destination / 'moon-build-command.json').write_text(json.dumps(build_command, indent=2) + '\n')
        with (destination / 'moon-build.stdout').open('wb') as stdout, (destination / 'moon-build.stderr').open('wb') as stderr:
            result = subprocess.run(build_command, cwd=ROOT, env=environment,
                                    timeout=max(0.001, deadline - time.monotonic()),
                                    stdout=stdout, stderr=stderr, check=False)
        receipt['moon_build_exit'] = result.returncode
        completed = [json.loads(Path(step['receipt']).read_text()) for step in c_steps if Path(step['receipt']).exists()]
        receipt['completed_c_steps'] = len(completed)
        (destination / 'progress.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if result.returncode:
            raise RuntimeError('Ordinary Moon build failed; original stdout/stderr and C receipts retained')
        if len(completed) != len(c_steps) or any(step['exit'] != 0 for step in completed):
            raise ValueError('Not every selected C step has an actual successful receipt')
        receipt['commands_completed'] = len(commands)
        executable = emission / 'native/release/build' / entry_package / (Path(entry_package).name + '.exe')
        receipt['executable'] = original(executable)
    for item in inputs:
        if original(Path(str(item['path']))) != item:
            raise ValueError('Original build input changed during preparation')
    if (run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != source
            or run(['git', 'status', '--porcelain'], capture=True)):
        raise ValueError('Original build source changed during preparation')
    # Last-only completion metadata. A failed command leaves the same partial
    # output/progress for inspection; it is never an installed runtime supplier.
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--moon-home', type=Path, required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--entry', choices=(ENTRY, LOCAL_ENTRY), default=ENTRY)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.moon_home.resolve(), args.clang,
                           args.sdk, args.destination.resolve(), args.seconds,
                           plan_only=args.plan_only, entry=args.entry), sort_keys=True))
