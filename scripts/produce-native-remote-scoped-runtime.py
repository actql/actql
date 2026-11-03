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
import shutil

ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'src/cmd/native_remote_resident_site'
LOCAL_ENTRY = 'src/cmd/native_client'
BUNDLE_ENTRY = 'src/cmd/native_runtime_bundle'
RUNTIME_NAMES = frozenset(('runtime', 'env', 'utf', 'backtrace', 'sync_io'))
RELEASE_UTF_OBJECTS = frozenset(('moonbit_simdutf.o', 'simdutf.o'))
RESIDENT_RECIPE = Path(ENTRY) / 'initial_control_recipe.json'
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
    'actql_native_private_scoped_allocate',
    'actql_native_private_scoped_free',
    'actql_native_private_scoped_contains_allocation',
)


def selected_entry(entry: str) -> str:
    if entry not in (ENTRY, LOCAL_ENTRY, BUNDLE_ENTRY):
        raise ValueError('Only the original Remote, Local or bundle installer CLI entry may be selected')
    return entry.removeprefix('src/')


def moon_build_arguments(moon_home: Path, emission: Path, entry: str) -> list[str]:
    selected_entry(entry)
    # The existing Remote recipe strips; the ordinary Local artifact recipe
    # does not. Its native_client package remains the source of its selected flags.
    return [str(moon_home / 'bin/moon'), 'build', '--target', 'native', '--release',
            *(['--strip'] if entry != LOCAL_ENTRY else []),
            '--target-dir', str(emission), '-j', '1', entry]


def original(path: Path) -> dict[str, object]:
    if path.is_symlink() or not path.is_file():
        raise ValueError('Original build input unavailable: ' + str(path))
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def under(path: Path, root: Path) -> bool:
    return path.is_absolute() and path.resolve().is_relative_to(root.resolve())


def selected_path_arguments(arguments: list[str], emission: Path,
                            drivers: tuple[Path, ...] = ()) -> list[str]:
    """Canonicalize only the selected emission and exact private drivers.

    Pinned Moon prints in-checkout outputs relatively, then may invoke its C
    port with absolute paths. Other inputs and compiler flags remain literal.
    """
    result = []
    for index, argument in enumerate(arguments):
        path = Path(argument)
        if not path.is_absolute():
            absolute = (ROOT / path).resolve()
            if under(absolute, emission) or (index == 0 and absolute in drivers):
                argument = str(absolute)
        result.append(argument)
    return result


def resident_initial_control_header(source: str, destination: Path) -> dict[str, object]:
    return command_initial_control_header(source, destination, ENTRY)


def command_initial_control_header(source: str, destination: Path, entry: str,
                                   target: str = 'darwin-arm64') -> dict[str, object]:
    """Pin a private physical entry, not a public Host/Run budget profile."""
    if re.fullmatch(r'[0-9a-f]{40}', source) is None:
        raise ValueError('Exact Resident source pin is required')
    if entry not in (ENTRY, BUNDLE_ENTRY):
        raise ValueError('No private command recipe for this entry')
    if target not in ('darwin-arm64', 'linux-x64') or (target == 'linux-x64' and entry != BUNDLE_ENTRY):
        raise ValueError('No selected command recipe for this target/entry')
    path = ROOT / entry / ('initial_control_recipe.linux-x64.json' if target == 'linux-x64'
                           else 'initial_control_recipe.json')
    raw = path.read_bytes()
    recipe = json.loads(raw)
    quantities = {
        'generation': 'GENERATION', 'capacityBytes': 'CAPACITY',
        'controlEnvelopeBytes': 'CONTROL_ENVELOPE', 'maximumArguments': 'ARGUMENTS',
        'maximumArgumentBytes': 'ARGUMENT_BYTES',
        'maximumArgumentStorageBytes': 'ARGUMENT_STORAGE',
        'maximumEnvironmentEntries': 'ENVIRONMENT_ENTRIES',
        'maximumEnvironmentStorageBytes': 'ENVIRONMENT_STORAGE',
    }
    resident_quantities = ({'sqliteHeapBytes': 'SQLITE_HEAP',
                            'cryptoHeapBytes': 'CRYPTO_HEAP',
                            'maximumDiagnosticBytes': 'DIAGNOSTIC_BYTES'}
                           if entry == ENTRY else {})
    installer_quantities = ({'managedPayloadBytes': 'MANAGED_PAYLOAD',
                             'sqliteHeapBytes': 'SQLITE_HEAP',
                             'cryptoHeapBytes': 'CRYPTO_HEAP',
                             'maximumDiagnosticBytes': 'DIAGNOSTIC_BYTES'}
                            if entry == BUNDLE_ENTRY else {})
    if target == 'linux-x64':
        installer_quantities['stockFileControlBytes'] = 'STOCK_FILE_CONTROL_BYTES'
    if (set(recipe) != {'kind', 'target', 'ledger', *quantities, *resident_quantities, *installer_quantities}
            or recipe['kind'] != ('private-resident-command-initial-control' if entry == ENTRY
                                  else 'private-runtime-bundle-command-initial-control')
            or recipe['target'] != target
            or set(recipe['ledger']) != {'planning_work', 'attempts', 'holdings',
                                         'transfer_bytes', 'retained_bytes'}
            or any(type(recipe[k]) is not int or not 0 < recipe[k] <= 2**31-1
                   for k in {**quantities, **resident_quantities, **installer_quantities})
            or any(type(v) is not int or not 0 <= v <= 2**31-1
                   for v in recipe['ledger'].values())
            or any(recipe['ledger'][k] <= 0 for k in ('planning_work', 'attempts', 'holdings'))
            or recipe['ledger']['transfer_bytes'] != 0
            or recipe['ledger']['retained_bytes'] != 0
            or recipe['maximumArgumentStorageBytes'] > 1048576
            or recipe['maximumEnvironmentEntries'] > 10000
            or recipe['maximumArgumentBytes'] > recipe['maximumArgumentStorageBytes']
            or recipe['capacityBytes'] % (4096 if target == 'linux-x64' else 16384)
            or (target == 'linux-x64' and (recipe['stockFileControlBytes'] != 4096
                or recipe['stockFileControlBytes'] >= recipe['controlEnvelopeBytes']))):
        raise ValueError('Incomplete Resident initial-control recipe')
    if entry == ENTRY and (
            recipe['sqliteHeapBytes'] % 16384 or recipe['cryptoHeapBytes'] % 16384
            or recipe['sqliteHeapBytes'] + recipe['cryptoHeapBytes'] >= recipe['capacityBytes']):
        raise ValueError('Resident component extents cannot coexist in original arena')
    if entry == BUNDLE_ENTRY and (
            recipe['sqliteHeapBytes'] % 16384 or recipe['cryptoHeapBytes'] % 16384
            or recipe['managedPayloadBytes'] + recipe['sqliteHeapBytes']
               + recipe['cryptoHeapBytes'] >= recipe['capacityBytes']):
        raise ValueError('Installer component extents cannot coexist in original arena')
    digest = hashlib.sha256(raw).hexdigest()
    lines = ['/* Private selected Resident entry DATA; not authority or capacity. */',
             '#define ACTQL_RESIDENT_SOURCE_SHA "' + source + '"',
             '#define ACTQL_RESIDENT_RECIPE_SHA "' + digest + '"',
             '#define ACTQL_RESIDENT_TARGET_' + ('LINUX_X64' if target == 'linux-x64' else 'DARWIN_ARM64') + ' 1']
    lines += ['#define ACTQL_RESIDENT_' + macro + ' ' + str(recipe[key])
              for key, macro in quantities.items()]
    lines += ['#define ACTQL_RESIDENT_' + key.upper() + ' ' + str(recipe['ledger'][key])
              for key in ('planning_work', 'attempts', 'holdings')]
    lines += ['#define ACTQL_RESIDENT_' + macro + ' ' + str(recipe[key])
              for key, macro in resident_quantities.items()]
    lines += ['#define ACTQL_BUNDLE_' + macro + ' ' + str(recipe[key])
              for key, macro in installer_quantities.items()]
    with destination.open('x') as stream:
        stream.write('\n'.join(lines) + '\n')
    return {'recipe': original(path), 'header': original(destination),
            'source': source, 'recipeSha256': digest, 'selected': recipe,
            'permission': False, 'physicalAcquired': False}


def local_initial_entry_arguments(parts: list[str], moon_home: Path,
                                  emission: Path) -> list[str]:
    """Validate selected link members without imposing initializer order."""
    runtime = str(moon_home / 'lib/libmoonbitrun.o')
    directory = emission / 'native/release/build/cmd/native_client'
    archives = [p for p in parts if Path(p).parent == directory
                and re.fullmatch(r'libnative_client-[0-9a-f]{16}\.a', Path(p).name)]
    runtime_members = [str(p if p.is_absolute() else ROOT / p) for p in map(Path, parts)]
    if runtime_members.count(runtime) != 1 or len(archives) != 1:
        raise ValueError('Exact original CLI archive and allocator object are required')
    return list(parts)


def commands_for(output: str, moon_home: Path, emission: Path, allocator: Path,
                 clang: Path, sdk: Path, *, cc_driver: Path | None = None,
                 ar_driver: Path | None = None, entry: str = ENTRY,
                 source_sha: str | None = None,
                 package_version: str | None = None,
                 resident_control_header: Path | None = None,
                 bundle_control_header: Path | None = None,
                 target: str = 'darwin-arm64',
                 stock_file_control_bytes: int | None = None) -> list[list[str]]:
    """Keep the actual pinned dry-run closure; reject other targets/entries."""
    entry_package = selected_entry(entry)
    if target not in ('darwin-arm64', 'linux-x64') or (target == 'linux-x64' and entry != BUNDLE_ENTRY):
        raise ValueError('No selected scoped command for this target/entry')
    if target == 'linux-x64' and stock_file_control_bytes != 4096:
        raise ValueError('Exact bundle stock-File control page required')
    if package_version is not None:
        from python_release_cohort import select_release_version
        if entry != LOCAL_ENTRY:
            raise ValueError('Package version belongs to the Native client, not the resident helper')
        package_version = select_release_version(package_version)['version']
    if entry == LOCAL_ENTRY and (source_sha is None or re.fullmatch(r'[0-9a-f]{40}', source_sha) is None):
        raise ValueError('Exact Local CLI source pin is required')
    control_header = resident_control_header if entry == ENTRY else bundle_control_header
    control_label = 'Resident' if entry == ENTRY else 'Bundle installer'
    control_macro = 'ACTQL_RESIDENT_' if entry == ENTRY else 'ACTQL_BUNDLE_'
    valid_resident_pin = (source_sha is not None and re.fullmatch(r'[0-9a-f]{40}', source_sha) is not None
                          and control_header is not None
                          and under(control_header, emission.parent)
                          and not any(c in str(control_header) for c in '\n\r"\\'))
    core = emission / 'native/release/build' / entry_package / (Path(entry_package).name + '.c')
    executable = core.with_suffix('.exe')
    commands: list[list[str]] = []
    links = finals = providers = source_pins = version_pins = resident_entries = 0
    runtime: set[str] = set()
    modules: set[str] = set()
    for line in output.splitlines():
        parts = shlex.split(line)
        if not parts:
            continue
        parts = [p.replace('$MOON_HOME', str(moon_home)) for p in parts]
        if any('$' in p for p in parts):
            raise ValueError('Unresolved build placeholder')
        parts = selected_path_arguments(parts, emission,
                    tuple(p for p in (cc_driver, ar_driver) if p is not None))
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
            resolved = source if source.is_absolute() else ROOT / source
            final = '-c' not in parts
            if final:
                finals += 1
                if source != core:
                    raise ValueError('Foreign final Core source')
                if Path(parts[parts.index('-o') + 1]) != executable:
                    raise ValueError('Foreign executable output')
                if entry == LOCAL_ENTRY:
                    parts = local_initial_entry_arguments(parts, moon_home, emission)
                if entry in (LOCAL_ENTRY, BUNDLE_ENTRY):
                    parts.extend(('-Wl,-exported_symbol,_' if target == 'darwin-arm64'
                                  else '-Wl,--export-dynamic-symbol=') + symbol
                                 for symbol in LOCAL_COMPONENT_PROVIDER_EXPORTS)
            elif under(resolved, moon_home / 'lib/runtime'):
                if source.stem not in RUNTIME_NAMES or source.stem in runtime:
                    raise ValueError('Duplicate or foreign runtime source')
                runtime.add(source.stem)
                parts[parts.index(sources[0])] = str(allocator / source.name)
            else:
                # Preserve the actual source, including relative include layout.
                if not under(resolved, ROOT / 'src'):
                    raise ValueError('Foreign FFI source')
                if resolved.resolve() == (ROOT / 'src/platform_native/host_bootstrap/bootstrap_stub.c').resolve():
                    providers += 1
                    parts.append('-DACTQL_SCOPED_READ_PROVIDER="' + str(allocator / 'owned_capacity.c') + '"')
                if entry in (ENTRY, BUNDLE_ENTRY) and resolved.resolve() == (ROOT / entry / 'initial_control_stub.c').resolve():
                    if not valid_resident_pin:
                        raise ValueError('Exact ' + control_label + ' source and owned initial-control header required')
                    if any(p.startswith(('-DACTQL_RESIDENT_', '-DACTQL_BUNDLE_')) for p in parts):
                        raise ValueError('Duplicate ' + control_label + ' entry compiler selection')
                    resident_entries += 1
                    parts.append('-D' + control_macro + 'INITIAL_CONTROL_HEADER="' + str(control_header) + '"')
                if entry == LOCAL_ENTRY and resolved.resolve() == (ROOT / 'src/cmd/native_client/stdout_stub.c').resolve():
                    if any(p.startswith(('-DACTQL_NATIVE_CLIENT_SOURCE_SHA', '-DACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY', '-DACTQL_NATIVE_COMMAND_INITIAL_OS_RECIPE')) for p in parts):
                        raise ValueError('Duplicate Local CLI source pin')
                    source_pins += 1
                    parts.append('-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + source_sha + '"')
                if package_version is not None and resolved.resolve() == (ROOT / 'src/cmd/native_client/version_stub.c').resolve():
                    if any(p.startswith('-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION') for p in parts):
                        raise ValueError('Duplicate Native package version compiler input')
                    version_pins += 1
                    parts.append('-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="' + package_version + '"')
            # Every generated Core, original FFI, and runtime source sees the
            # same derived header first. There is exactly one provider below.
            parts[0] = str(clang)
            parts[1:1] = (["-isysroot", str(sdk), "-mmacosx-version-min=11.0"]
                          if target == 'darwin-arm64' else [
                              '-D_GNU_SOURCE', '-DACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN',
                              '-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', '-include', str(control_header),
                              # Original LP64 {pointer,size_t,unsigned} record is24; its
                              # same compiled provider checks that layout and total page.
                              '-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=' + str((stock_file_control_bytes - 8) // 24),
                          ]) + ['-I' + str(allocator), '-DACTQL_SCOPED_READ_ALLOCATOR',
                          *(['-DACTQL_RUNTIME_MANAGED_VALUES=1'] if entry == LOCAL_ENTRY else [])]
        elif ar_driver is not None and parts[0] == str(ar_driver):
            members = [p if p.is_absolute() else ROOT / p for p in map(Path, archive_files)]
            outside = [p for p in members if not under(p, emission)]
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
    if entry in (ENTRY, BUNDLE_ENTRY) and not valid_resident_pin:
        raise ValueError('Exact ' + control_label + ' source and owned initial-control header required')
    if entry == LOCAL_ENTRY and source_pins != 1:
        raise ValueError('Missing or duplicate Local CLI source pin entrance')
    if entry in (ENTRY, BUNDLE_ENTRY) and resident_entries != 1:
        raise ValueError('Missing or duplicate ' + control_label + ' initial-control entrance')
    if package_version is not None and version_pins != 1:
        raise ValueError('Missing or duplicate Native package version stub compilation')
    if 'actql/actql/' + entry_package not in modules:
        raise ValueError('Selected CLI entry is missing')
    return commands


def canonical_c_arguments(arguments: list[str], emission: Path | None = None) -> list[str]:
    # Moon prints checkout C and in-checkout toolchain members relatively, then
    # invokes cc with absolute spellings. Selection has already checked the exact
    # source/runtime/link members; flags and outputs still match unchanged.
    if emission is not None:
        arguments = selected_path_arguments(arguments, emission)
    selected = []
    for p in arguments:
        if p.startswith('-I./.toolchains/'):
            selected.append('-I' + str((ROOT / p[2:]).resolve()))
        elif (p.startswith('./src/') and p.endswith('.c')) or p.startswith('./.toolchains/'):
            selected.append(str((ROOT / p).resolve()))
        else:
            selected.append(p)
    return selected


def compile_selected_c(plan_path: Path, arguments: list[str]) -> None:
    """Private cc port: accept only an exact step from this Moon invocation."""
    plan = json.loads(plan_path.read_text())
    emission = Path(plan['emission']) if 'emission' in plan else None
    actual = canonical_c_arguments(arguments, emission)
    matches = [step for step in plan['steps']
               if canonical_c_arguments(step['original'], emission) == actual]
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
          entry: str = ENTRY, package_version: str | None = None,
          target: str = 'darwin-arm64') -> dict[str, object]:
    entry_package = selected_entry(entry)
    if target not in ('darwin-arm64', 'linux-x64') or (target == 'linux-x64' and entry != BUNDLE_ENTRY):
        raise ValueError('No selected scoped command for this target/entry')
    if package_version is not None:
        from python_release_cohort import select_release_version
        if entry != LOCAL_ENTRY:
            raise ValueError('Only the Native client has a release package version')
        package_version = select_release_version(package_version)['version']
    if type(seconds) is not int or seconds <= 0 or type(plan_only) is not bool:
        raise ValueError('Explicit positive preparation budget required')
    deadline = time.monotonic() + seconds
    environment = {**os.environ, 'MOON_HOME': str(moon_home), 'MOONBIT_NEW_NATIVE': '0',
                   **({'SDKROOT': str(sdk), 'MACOSX_DEPLOYMENT_TARGET': '11.0'} if target == 'darwin-arm64' else {}),
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

    actual = ('darwin-arm64' if platform.system() == 'Darwin' and platform.machine() == 'arm64'
              else 'linux-x64' if platform.system() == 'Linux' and platform.machine() == 'x86_64' else None)
    if actual != target:
        raise ValueError('Selected command target does not match the actual producer')
    if (run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != source
            or run(['git', 'status', '--porcelain'], capture=True)):
        raise ValueError('Exact clean committed build source required')
    pin = json.loads((ROOT / 'toolchain.json').read_text())
    if json.loads((moon_home / 'installed.json').read_text()) != {'pin': pin, 'platform': target}:
        raise ValueError('Original toolchain marker mismatch')
    if (run([str(moon_home / 'bin/moonc'), '-v'], capture=True).strip() != pin['moonc']
            or run([str(moon_home / 'bin/moon'), 'version'], capture=True).splitlines()[0] != 'moon ' + pin['moon']):
        raise ValueError('Original compiler mismatch')
    if (target == 'darwin-arm64' and (sdk is None or not sdk.is_dir() or sdk.is_symlink())) or not clang.is_file():
        raise ValueError('Original compiler/SDK unavailable')
    destination.mkdir(parents=True, exist_ok=False)
    recipe = ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py'
    spec = importlib.util.spec_from_file_location('remote_scoped_source', recipe)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    allocator = destination / 'derived-read-source'
    selection = module.prepare(moon_home, allocator,
                               target='x86_64-unknown-linux-gnu' if target == 'linux-x64' else None)
    resident_control = (command_initial_control_header(source, destination /
                        ('resident-initial-control.h' if entry == ENTRY else 'bundle-initial-control.h'), entry, target)
                        if entry in (ENTRY, BUNDLE_ENTRY) else None)
    emission = destination / 'emission'
    cc_driver = destination / 'bin/cc'
    cc_driver.parent.mkdir()
    ar_driver = cc_driver.parent / 'ar'
    # Moon resolves this sibling for an explicitly selected compiler directory.
    # Delegate the real selected archiver; no archive bytes are synthesized.
    original_ar = (Path('/Library/Developer/CommandLineTools/usr/bin/ar') if target == 'darwin-arm64'
                   else Path(shutil.which('ar') or '/missing-selected-ar').resolve())
    if not original_ar.is_file():
        raise ValueError('Original selected archiver unavailable')
    ar_driver.write_text('#!/bin/sh\nexec ' + shlex.quote(str(original_ar)) + ' "$@"\n')
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
                            cc_driver=cc_driver, ar_driver=ar_driver, entry=entry, source_sha=source,
                            package_version=package_version,
                            resident_control_header=(Path(resident_control['header']['path'])
                                                     if resident_control and entry == ENTRY else None),
                            bundle_control_header=(Path(resident_control['header']['path'])
                                                   if resident_control and entry == BUNDLE_ENTRY else None), target=target,
                            stock_file_control_bytes=(resident_control['selected']['stockFileControlBytes']
                                if target == 'linux-x64' else None))
    (destination / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    originals = [selected_path_arguments(
                    [p.replace('$MOON_HOME', str(moon_home)) for p in shlex.split(line)],
                    emission, (cc_driver, ar_driver))
                 for line in dry.splitlines() if line.strip()]
    c_steps = [{'original': before[1:], 'selected': after,
                'receipt': str(destination / ('cc-' + str(index) + '.json'))}
               for index, (before, after) in enumerate(zip(originals, commands))
               if before[0] == str(cc_driver)]
    command_include_inputs = ([original(ROOT / ENTRY / name) for name in
                               ('initial_control_stub.c', 'initial_control_capture.h')]
                              if entry == BUNDLE_ENTRY else [])
    cc_plan.write_text(json.dumps({'steps': c_steps, 'emission': str(emission),
        'allocator_inputs': [original(p) for p in sorted(allocator.iterdir()) if p.is_file()]
            + ([resident_control['recipe'], resident_control['header']] if resident_control else [])
            + command_include_inputs}, indent=2) + '\n')
    # Preserve all selected package sources, the original pinned Core and FFI
    # include closure, and the exact allocator recipe. Source SHA alone cannot
    # stand in for the separately installed compiler/runtime/Core inputs.
    packages = [c[c.index('-pkg') + 1].removeprefix('actql/actql/')
                for c in commands if c[0] == str(moon_home / 'bin/moonc') and c[1] == 'build-package']
    paths = {ROOT / 'toolchain.json', ROOT / 'moon.mod', Path(__file__), clang,
             cc_driver, ar_driver, cc_plan, python,
             original_ar, moon_home / 'installed.json',
             moon_home / 'bin/moon', moon_home / 'bin/moonc',
             moon_home / 'lib/libmoonbitrun.o', moon_home / 'lib/libbacktrace.a'}
    if target == 'darwin-arm64':
        paths.update((Path('/Library/Developer/CommandLineTools/usr/bin/libtool'), sdk / 'SDKSettings.json'))
    paths.update(moon_home / 'lib' / name for name in RELEASE_UTF_OBJECTS)
    if resident_control:
        paths.update((Path(resident_control['recipe']['path']), Path(resident_control['header']['path'])))
        if entry == BUNDLE_ENTRY:
            # The installer compiles these exact private capture helpers into
            # its OWN image. Preserve their include closure, not a Resident handle.
            paths.update(ROOT / ENTRY / name for name in
                         ('initial_control_stub.c', 'initial_control_capture.h'))
    if package_version is not None:
        node = shutil.which('node')
        if node is None:
            raise ValueError('Explicit package version needs the selected build-time Node parser')
        paths.update((ROOT / 'scripts/release-version.mjs', ROOT / 'scripts/python_release_cohort.py', Path(node).resolve()))
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
        'source': source, 'entry': entry, 'target': target,
        'compiler_backend': 'pinned ordinary C (MOONBIT_NEW_NATIVE=0)',
        'package_registry': 'Generated by ordinary pinned Moon; no compiler arguments omitted',
        'compiler_profile': 'ordinary Moon --release' + (' --strip' if entry != LOCAL_ENTRY else ''),
        'selected_packages': packages, 'core_modules': 1, 'providers': 1,
        'allocator': selection, 'plan_only': plan_only, 'commands_completed': 0,
        'installed_supplier': False, 'normal_profile': None, 'runtime_cases': 0, 'public_e2e': 0,
    }
    if resident_control:
        receipt['resident_initial_control' if entry == ENTRY else 'bundle_initial_control'] = resident_control
    if package_version is not None:
        receipt['package_version'] = package_version
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
        receipt['generated_c'] = original(executable.with_suffix('.c'))
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
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--target', choices=('darwin-arm64', 'linux-x64'), default='darwin-arm64')
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--entry', choices=(ENTRY, LOCAL_ENTRY, BUNDLE_ENTRY), default=ENTRY)
    parser.add_argument('--package-version')
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.moon_home.resolve(), args.clang,
                           args.sdk, args.destination.resolve(), args.seconds,
                           plan_only=args.plan_only, entry=args.entry,
                           package_version=args.package_version, target=args.target), sort_keys=True))
