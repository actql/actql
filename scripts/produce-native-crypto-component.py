"""Produce the selected private Crypto member for the ordinary Native recipe.

The component imports the existing process provider. It never loads another
provider, configures shared OpenSSL, acquires capacity or installs a profile.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import stat
import subprocess
import sys
import tarfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/python-local-runtime/native/crypto-component'
EXPORTS = tuple('actql_crypto_component_' + name for name in (
    'bind', 'enter', 'leave', 'borrow_library', 'release_library', 'symbol',
    'inventory', 'close', 'version', 'bind_current', 'enter_current',
    'leave_current', 'is_current', 'bind_current_with_custody'))
PROVIDER_IMPORTS = frozenset(('actql_native_owned_current', 'actql_native_owned_allocate',
    'actql_native_owned_retire', 'actql_read_context_retain',
    'actql_read_context_release_after_owner_ack', 'actql_bootstrap_current_read_context'))
LINUX_TARGET = 'x86_64-unknown-linux-gnu'
LINUX_LIBRARY = 'libactql_crypto_component.so'
LINUX_SYSTEM_LIBRARIES = frozenset(('libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0'))


def original(path: Path, maximum: int = 32 * 1024 * 1024) -> dict[str, object]:
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
            raise ValueError('Invalid original Crypto input')
        checksum = hashlib.sha256()
        while chunk := source.read(65536):
            checksum.update(chunk)
        after = os.fstat(source.fileno())
        fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
        if any(getattr(before, key) != getattr(after, key) for key in fields):
            raise ValueError('Original Crypto input changed')
        return {'bytes': before.st_size, 'sha256': checksum.hexdigest()}


def verify_original_inputs(*inventories: dict) -> None:
    for inventory in inventories:
        for name, expected in inventory.items():
            if original(Path(name), 512 * 1024 * 1024) != expected:
                raise ValueError('Original Crypto build input changed: ' + name)


def produce(output: Path, openssl: Path, clang: Path, sdk: Path, *,
            source_static: dict | None = None) -> dict[str, object]:
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Selected Crypto component target unavailable')
    if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'],
                               cwd=ROOT, text=True).strip():
        raise ValueError('Crypto producer requires committed source')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    recipe_path = SOURCE / 'source.json'
    recipe = json.loads(recipe_path.read_bytes())
    inputs = {str(recipe_path): original(recipe_path)}
    for name, expected in recipe['local'].items():
        path = SOURCE / name
        observed = original(path)
        if observed != expected:
            raise ValueError('Stale Crypto source identity: ' + name)
        inputs[str(path)] = observed
    if source_static is None:
        selected = recipe['candidate_static_input']
        minimum_macos = recipe['minimum_macos']
        qualification = selected['qualification']
        for path, checksum in ((openssl / '.brew/openssl@3.rb', selected['formula_sha256']),
                               (openssl / 'INSTALL_RECEIPT.json', selected['receipt_sha256'])):
            inputs[str(path)] = original(path)
            if inputs[str(path)]['sha256'] != checksum:
                raise ValueError('Selected OpenSSL archive origin mismatch')
    else:
        profile = recipe['source_builds']['darwin-arm64-macos11']
        if (source_static['source'] != head or source_static['profile'] != profile
                or source_static['prefix'] != str(openssl)
                or source_static['target'] != 'aarch64-apple-darwin'
                or source_static['archive']['path'] != str(openssl / 'lib/libcrypto.a')):
            raise ValueError('Original source-built Crypto profile differs')
        selected = {**source_static['archive'], 'header_count': source_static['header_count'],
                    'header_census_sha256': source_static['header_census_sha256']}
        minimum_macos = profile['minimum_macos']
        qualification = profile['qualification']
        for inventory in (source_static['inputs'], source_static['compiled_inputs']):
            for name, item in inventory.items():
                if name in inputs and inputs[name] != item:
                    raise ValueError('Original source-built Crypto input identities differ')
                inputs[name] = item
    headers = []
    for path in sorted((openssl / 'include').rglob('*')):
        if path.is_symlink():
            raise ValueError('Unqualified OpenSSL header alias')
        if path.is_file():
            identity = original(path)
            inputs[str(path)] = identity
            headers.append({'path': str(path.relative_to(openssl / 'include')), **identity})
    header_digest = hashlib.sha256(json.dumps(
        headers, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if len(headers) != selected['header_count'] or header_digest != selected['header_census_sha256']:
        raise ValueError('Selected OpenSSL header membership mismatch')
    archive = openssl / 'lib/libcrypto.a'
    inputs[str(archive)] = original(archive)
    if inputs[str(archive)] != {key: selected[key] for key in ('bytes', 'sha256')}:
        raise ValueError('Selected OpenSSL static archive mismatch')
    license_path = openssl / 'LICENSE.txt'
    inputs[str(license_path)] = original(license_path)
    if inputs[str(license_path)]['sha256'] != recipe['license_sha256']:
        raise ValueError('Selected OpenSSL license mismatch')
    # A linker deployment flag cannot lower the ABI of a precompiled input.
    archive_loads = subprocess.check_output(
        ['/Library/Developer/CommandLineTools/usr/bin/otool', '-l', str(archive)], text=True)
    archive_minimums = re.findall(
        r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos ([0-9.]+)', archive_loads)
    if not archive_minimums:
        raise ValueError('OpenSSL archive deployment requirements unavailable')
    def version(value: str) -> tuple[int, ...]:
        return tuple((list(map(int, value.split('.'))) + [0, 0, 0])[:3])
    if max(map(version, archive_minimums)) > version(minimum_macos):
        raise ValueError('OpenSSL archive requires a newer deployment target')
    inputs[str(clang)] = original(clang, 512 * 1024 * 1024)
    output.mkdir(parents=True, exist_ok=False)
    exports = output / 'component.exports'
    exports.write_text(''.join('_' + name + '\n' for name in EXPORTS))
    library = output / 'libactql_crypto_component.dylib'
    dependencies = output / 'component.d'
    command = [str(clang), '-isysroot', str(sdk), '-std=c11', '-O2',
               '-mmacosx-version-min=' + minimum_macos,
               '-Wall', '-Wextra', '-Werror', '-dynamiclib', '-MD', '-MF', str(dependencies),
               '-I', str(openssl / 'include'),
               '-I', str(ROOT / 'packages/python-local-runtime/native/pre-root'),
               str(SOURCE / 'component.c'), '-Wl,-load_hidden,' + str(archive),
               '-Wl,-undefined,dynamic_lookup', '-Wl,-exported_symbols_list,' + str(exports),
               '-Wl,-install_name,@rpath/' + library.name, '-o', str(library)]
    subprocess.run(command, cwd=ROOT, check=True)
    members = shlex.split(dependencies.read_text().replace('\\\n', '').split(': ', 1)[1])
    header_aliases = {}
    for member in members:
        path = Path(member)
        if path.is_relative_to(sdk):
            resolved = path.resolve(strict=True)
            if not resolved.is_relative_to(sdk):
                raise ValueError('Crypto SDK header escapes selected SDK')
            header_aliases[str(path)] = str(resolved)
            path = resolved
        inputs[str(path)] = original(path)
    names = {line.split()[-1] for line in subprocess.check_output(
        ['/Library/Developer/CommandLineTools/usr/bin/nm', '-gU', str(library)], text=True).splitlines()}
    if names != {'_' + name for name in EXPORTS}:
        raise ValueError('Unexpected private Crypto exports')
    links = subprocess.check_output(
        ['/Library/Developer/CommandLineTools/usr/bin/otool', '-L', str(library)], text=True)
    dependencies_seen = [line.strip().split(' (', 1)[0] for line in links.splitlines()[1:]]
    if dependencies_seen != ['@rpath/' + library.name, '/usr/lib/libSystem.B.dylib']:
        raise ValueError('Crypto component has an independent provider or crypto dependency')
    loads = subprocess.check_output(
        ['/Library/Developer/CommandLineTools/usr/bin/otool', '-l', str(library)], text=True)
    observed_minimum = re.search(
        r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos ([0-9.]+)', loads)
    if not observed_minimum or version(observed_minimum[1]) != version(minimum_macos):
        raise ValueError('Crypto component deployment identity mismatch')
    if 'cmd LC_RPATH' in loads:
        raise ValueError('Crypto component requires an ambient library search path')
    undefined = subprocess.check_output(
        ['/Library/Developer/CommandLineTools/usr/bin/nm', '-u', str(library)], text=True)
    required = ('actql_native_owned_current', 'actql_native_owned_allocate', 'actql_native_owned_retire',
                'actql_read_context_retain', 'actql_read_context_release_after_owner_ack',
                'actql_bootstrap_current_read_context')
    if not all('_' + name in undefined.split() for name in required):
        raise ValueError('Original process provider import missing')
    for name, expected in inputs.items():
        if original(Path(name), 512 * 1024 * 1024) != expected:
            raise ValueError('Crypto build input changed')
    (output / 'OPENSSL-LICENSE.txt').write_bytes(license_path.read_bytes())
    (output / 'CRYPTO-NOTICE').write_bytes((SOURCE / 'NOTICE').read_bytes())
    result = {'source': head, 'target': recipe['target'], 'recipe': inputs[str(recipe_path)],
              'source_qualification': qualification,
              'provider_binding': 'existing process provider; actual original binding required before first allocation',
              'command': command, 'inputs': inputs, 'exports': sorted(names), 'links': links,
              'undefined': undefined, 'archive_minimum_macos': sorted(set(archive_minimums), key=version),
              'archive_object_count': len(archive_minimums), 'minimum_macos': observed_minimum[1],
              'compiler_header_aliases': header_aliases, 'library': original(library),
              'license': original(output / 'OPENSSL-LICENSE.txt'),
              'notice': original(output / 'CRYPTO-NOTICE')}
    if source_static is not None:
        result['static_source'] = source_static
    (output / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def source_archive_members(archive: Path, expected: dict, prefix: str, destination: Path) -> list[dict]:
    observed = original(archive, 128 * 1024 * 1024)
    if observed != {key: expected[key] for key in ('bytes', 'sha256')}:
        raise ValueError('Pinned original OpenSSL source archive mismatch')
    members = []
    with tarfile.open(archive, 'r:gz') as container:
        seen = set()
        for member in container:
            path = Path(member.name)
            if (member.name in seen or path.is_absolute() or '..' in path.parts
                    or path.parts[0] != prefix or not (member.isfile() or member.isdir())):
                raise ValueError('Unselected OpenSSL source archive member')
            seen.add(member.name)
            if member.isdir():
                continue
            if member.size > 16 * 1024 * 1024:
                raise ValueError('Oversized OpenSSL source member')
            raw = container.extractfile(member).read(member.size + 1)
            if len(raw) != member.size:
                raise ValueError('Incomplete original OpenSSL source member')
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as output:
                output.write(raw)
            members.append({'path': member.name, 'bytes': len(raw),
                            'sha256': hashlib.sha256(raw).hexdigest()})
    return members


def produce_darwin_source(output: Path, clang: Path, sdk: Path, seconds: int, *,
                          source_archive: Path | None = None,
                          component_output: Path | None = None) -> dict:
    """Build the selected compatible static source; keep the Homebrew recipe separate."""
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Source-built Crypto requires the selected Darwin arm64 target')
    if type(seconds) is not int or not 0 < seconds <= 1800:
        raise ValueError('Explicit bounded source-built Crypto preparation required')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True):
        raise ValueError('Source-built Crypto requires exact clean committed source')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    recipe_path = SOURCE / 'source.json'
    recipe = json.loads(recipe_path.read_bytes())
    profile = recipe['source_builds']['darwin-arm64-macos11']
    if (profile['configure'] != ['darwin64-arm64-cc', 'no-shared', 'no-tests', 'no-module']
            or profile['minimum_macos'] != '11.0' or profile['target'] != 'aarch64-apple-darwin'
            or profile['optimization'] != '-O2' or profile['cpu_threads'] != 2
            or profile['make_target'] != 'build_libs' or profile['installed_supplier'] is not False
            or profile['normal_profile'] is not None):
        raise ValueError('Unselected compatible Crypto source build profile')
    output.mkdir(parents=True, exist_ok=False)
    deadline = time.monotonic() + seconds
    if source_archive is None:
        source_archive = output / 'openssl-original.tar.gz'
        with urllib.request.urlopen(recipe['upstream']['url'], timeout=min(seconds, 60)) as response:
            raw = response.read(recipe['upstream']['bytes'] + 1)
        with source_archive.open('xb') as stream:
            stream.write(raw)
    members = source_archive_members(source_archive, recipe['upstream'],
                                     'openssl-' + recipe['upstream']['version'], output / 'source')
    source = output / 'source' / ('openssl-' + recipe['upstream']['version'])
    tools = {name: Path('/Library/Developer/CommandLineTools/usr/bin') / name
             for name in ('ar', 'ranlib', 'otool', 'lipo')}
    tools.update(make=Path('/usr/bin/make'), perl=Path('/usr/bin/perl'))
    inputs = {str(path): original(path, 512 * 1024 * 1024)
              for path in (*tools.values(), clang, sdk / 'SDKSettings.json',
                           recipe_path, Path(__file__).resolve(), Path(sys.executable).resolve(), source_archive)}
    receipts = output / 'compiler-receipts'; receipts.mkdir()
    driver = output / 'cc'
    # Dependency capture alone changes -MMD to -MD. Original compile/link flags
    # and source remain selected by the pinned upstream build. Each invocation
    # records the actual compiler inputs immediately after it returns.
    driver.write_text('#!' + str(Path(sys.executable).resolve()) + '\n' + r'''
import hashlib,json,os,subprocess,sys,uuid
from pathlib import Path
original=sys.argv[1:]; selected=['-MD' if value=='-MMD' else value for value in original]
result=subprocess.run([COMPILER,*selected])
record={'original':original,'selected':selected,'exit':result.returncode,'inputs':{}}
if result.returncode==0 and '-MF' in selected:
    dependency=Path(selected[selected.index('-MF')+1])
    import shlex
    names=shlex.split(dependency.read_text().replace(chr(92)+chr(10),' ').split(':',1)[1])
    for name in names:
        path=Path(name).resolve(strict=True)
        with path.open('rb') as stream:
            before=os.fstat(stream.fileno())
            if before.st_size>16*1024*1024:raise ValueError('Oversized original compiler input')
            raw=stream.read(before.st_size+1);after=os.fstat(stream.fileno())
        fields=('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns')
        if len(raw)!=before.st_size or any(getattr(before,key)!=getattr(after,key) for key in fields):
            raise ValueError('Original static compiler input changed')
        record['inputs'][str(path)]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
with (RECEIPTS/(uuid.uuid4().hex+'.json')).open('x') as stream:json.dump(record,stream)
raise SystemExit(result.returncode)
'''.replace('COMPILER', repr(str(clang))).replace('RECEIPTS', 'Path(' + repr(str(receipts)) + ')'))
    driver.chmod(0o755)
    inputs[str(driver)] = original(driver)
    flags = ['-O2', '-fPIC', '-mmacosx-version-min=' + profile['minimum_macos'], '-isysroot', str(sdk)]
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C', 'LC_ALL': 'C',
        'CC': str(driver), 'AR': str(tools['ar']), 'RANLIB': str(tools['ranlib']),
        'CFLAGS': shlex.join(flags), 'SDKROOT': str(sdk),
        'MACOSX_DEPLOYMENT_TARGET': profile['minimum_macos']}
    steps = []
    def run(name, arguments):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Source-built Crypto preparation budget exhausted')
        result = subprocess.run(arguments, cwd=source, env=environment, capture_output=True,
                                text=True, timeout=remaining)
        (output / (name + '.stdout')).write_text(result.stdout)
        (output / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': arguments, 'exit': result.returncode})
        (output / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if result.returncode:
            raise ValueError('Source-built Crypto command failed: ' + name)
        return result.stdout
    target = run('compiler-target', [str(clang), '-dumpmachine']).strip()
    if re.fullmatch(r'(?:arm64|aarch64)-apple-darwin[0-9.]*', target) is None:
        raise ValueError('Source-built Crypto compiler is not Darwin arm64')
    run('configure', [str(tools['perl']), 'Configure', *profile['configure']])
    run('build-static', [str(tools['make']), '-j', str(profile['cpu_threads']), 'build_libs'])
    compiled = {}
    records = [json.loads(path.read_bytes()) for path in sorted(receipts.iterdir())]
    if not records or any(record['exit'] != 0 for record in records):
        raise ValueError('Original static compiler invocation did not succeed')
    for record in records:
        for path, item in record['inputs'].items():
            if path in compiled and compiled[path] != item:
                raise ValueError('Original static compiler input changed between invocations')
            compiled[path] = item
    if not compiled:
        raise ValueError('No actual original static compiler inputs observed')
    prefix = output / 'prefix'
    (prefix / 'lib').mkdir(parents=True)
    for name in ('libcrypto.a', 'LICENSE.txt'):
        target_path = prefix / ('lib/' + name if name.endswith('.a') else name)
        with target_path.open('xb') as stream:
            stream.write((source / name).read_bytes())
    headers = []
    for path in sorted((source / 'include/openssl').rglob('*.h')):
        if path.is_symlink():
            raise ValueError('Source-built public header is an alias')
        relative = path.relative_to(source / 'include')
        target_path = prefix / 'include' / relative
        target_path.parent.mkdir(parents=True, exist_ok=True)
        with target_path.open('xb') as stream:
            stream.write(path.read_bytes())
        headers.append({'path': str(relative), **original(target_path)})
    archive = prefix / 'lib/libcrypto.a'
    archive_members = run('archive-members', [str(tools['ar']), '-t', str(archive)]).splitlines()
    if not archive_members or run('archive-target', [str(tools['lipo']), '-archs', str(archive)]).strip() != 'arm64':
        raise ValueError('Static source archive does not contain the selected arm64 members')
    verify_original_inputs(inputs, compiled)
    proof = {'source': head, 'target': 'aarch64-apple-darwin', 'profile': profile,
        'prefix': str(prefix), 'archive': {'path': str(archive), **original(archive)},
        'archive_members': archive_members, 'source_members': members,
        'header_count': len(headers), 'header_census_sha256': hashlib.sha256(
            json.dumps(headers, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'compiler_target': target, 'compiler_flags': flags, 'compiler_invocations': len(records),
        'inputs': inputs, 'compiled_inputs': compiled, 'loaded': False, 'providers': 0}
    (output / 'static-source.json').write_text(json.dumps(proof, indent=2) + '\n')
    inputs[str(output / 'static-source.json')] = original(output / 'static-source.json')
    if time.monotonic() >= deadline:
        raise ValueError('Source-built Crypto preparation budget exhausted')
    return produce(component_output or output / 'component', prefix, clang, sdk, source_static=proof)


def linux_source_inputs(openssl: Path, selected: dict, *, query=subprocess.check_output) -> dict:
    """Select exact official Noble package members; no shared crypto loading."""
    if (selected['target'] != LINUX_TARGET or selected['required_defines'] != ['_GNU_SOURCE']
            or selected['archive']['path'] != 'lib/x86_64-linux-gnu/libcrypto.a'
            or selected['header_roots'] != ['include/openssl', 'include/x86_64-linux-gnu/openssl']):
        raise ValueError('Unselected Linux Crypto source profile')
    packages = query(['/usr/bin/dpkg-query', '--show',
        '--showformat=${Package}\t${Version}\t${Architecture}\n',
        'libssl-dev', 'libssl3t64'], text=True)
    observed = {tuple(line.split('\t')) for line in packages.splitlines()}
    expected = {(item['name'], item['version'], item['architecture'])
                for item in (selected['package'], selected['license']['package'])}
    if observed != expected or len(packages.splitlines()) != len(expected):
        raise ValueError('Selected official Linux OpenSSL package version/target mismatch')
    inputs = {}
    for item in (selected['archive'], selected['license']):
        path = openssl / item['path']
        actual = original(path)
        if actual != {key: item[key] for key in ('bytes', 'sha256')}:
            raise ValueError('Selected official Linux OpenSSL member mismatch')
        inputs[str(path)] = actual
    headers = []
    for directory in selected['header_roots']:
        root = openssl / directory
        if not root.is_dir() or root.is_symlink():
            raise ValueError('Original Linux OpenSSL header root unavailable')
        for path in sorted(root.rglob('*')):
            if path.is_symlink():
                raise ValueError('Unqualified Linux OpenSSL header alias')
            if path.is_file():
                actual = original(path)
                inputs[str(path)] = actual
                headers.append({'path': str(path.relative_to(openssl / 'include')), **actual})
    headers.sort(key=lambda item: item['path'])
    census = hashlib.sha256(json.dumps(headers, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if len(headers) != selected['header_count'] or census != selected['header_census_sha256']:
        raise ValueError('Selected Linux OpenSSL header membership mismatch')
    return inputs


def inspect_linux_component(library: Path, *, execute=subprocess.check_output) -> dict:
    observed = original(library)
    with library.open('rb') as stream:
        header = stream.read(64)
    if (len(header) != 64 or header[:7] != b'\x7fELF\x02\x01\x01' or header[7] not in (0, 3)
            or int.from_bytes(header[16:18], 'little') != 3
            or int.from_bytes(header[18:20], 'little') != 62
            or int.from_bytes(header[20:24], 'little') != 1
            or int.from_bytes(header[52:54], 'little') != 64):
        raise ValueError('Crypto component requires ELF64 little-endian x86-64 shared image')
    definitions = execute(['/usr/bin/nm', '-D', '--defined-only', str(library)], text=True)
    names = {line.split()[-1] for line in definitions.splitlines() if line.strip()}
    if names != set(EXPORTS):
        raise ValueError('Unexpected Linux Crypto component exports')
    undefined = execute(['/usr/bin/nm', '-D', '--undefined-only', str(library)], text=True)
    imports = set()
    for line in undefined.splitlines():
        if not line.strip():
            continue
        name = line.split()[-1]
        if name.startswith('actql_'):
            imports.add(name)
        elif re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*@GLIBC_[0-9]+(?:\.[0-9]+)*', name) is None:
            raise ValueError('Unexpected Linux Crypto component system import')
    if imports != PROVIDER_IMPORTS:
        raise ValueError('Original Linux Crypto process provider imports differ')
    dynamic = execute(['/usr/bin/readelf', '--dynamic', '--wide', str(library)], text=True)
    dependencies = re.findall(r'\(NEEDED\).*\[([^\]]+)\]', dynamic)
    if ('libc.so.6' not in dependencies or len(dependencies) != len(set(dependencies))
            or not set(dependencies) <= LINUX_SYSTEM_LIBRARIES):
        raise ValueError('Linux Crypto component has another provider or shared crypto dependency')
    if re.findall(r'\(SONAME\).*\[([^\]]+)\]', dynamic) != [LINUX_LIBRARY]:
        raise ValueError('Linux Crypto component SONAME differs')
    if re.search(r'\((?:RPATH|RUNPATH)\)', dynamic):
        raise ValueError('Linux Crypto component requires an ambient search path')
    if original(library) != observed:
        raise ValueError('Linux Crypto component changed during inspection')
    return {'library': observed, 'exports': sorted(names),
            'provider_imports': sorted(imports), 'dependencies': dependencies,
            'target': LINUX_TARGET, 'dynamic': dynamic}


def produce_linux(output: Path, openssl: Path, clang: Path, seconds: int) -> dict:
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ValueError('Selected Linux x64 Crypto component target unavailable')
    if type(seconds) is not int or not 0 < seconds <= 1800:
        raise ValueError('Explicit bounded Linux Crypto preparation required')
    def clean():
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True):
            raise ValueError('Linux Crypto producer requires exact clean committed source')
        return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    source = clean()
    recipe_path = SOURCE / 'source.json'
    recipe = json.loads(recipe_path.read_bytes())
    selected = recipe['source_targets'][LINUX_TARGET]
    inputs = {str(recipe_path): original(recipe_path)}
    for name, expected in recipe['local'].items():
        path = SOURCE / name
        actual = original(path)
        if actual != expected:
            raise ValueError('Stale original Crypto source identity: ' + name)
        inputs[str(path)] = actual
    inputs.update(linux_source_inputs(openssl, selected))
    for path in (clang, Path('/usr/bin/nm').resolve(), Path('/usr/bin/readelf').resolve(),
                 Path('/usr/bin/dpkg-query').resolve(), Path(__file__).resolve(),
                 ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h'):
        inputs[str(path)] = original(path, 512 * 1024 * 1024)
    output.mkdir(parents=True, exist_ok=False)
    deadline, steps = time.monotonic() + seconds, []
    def run(name, arguments):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('Linux Crypto build budget exhausted')
        result = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=remaining)
        (output / (name + '.stdout')).write_text(result.stdout)
        (output / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': arguments, 'exit': result.returncode})
        (output / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if result.returncode:
            raise ValueError('Linux Crypto command failed: ' + name)
        return result.stdout
    compiler_target = run('compiler-target', [str(clang), '-dumpmachine']).strip()
    if re.fullmatch(r'x86_64-(?:[A-Za-z0-9_.]+-)?linux-gnu', compiler_target) is None:
        raise ValueError('Selected Crypto compiler target is not Linux x86-64')
    compiler_version = run('compiler-version', [str(clang), '--version'])
    obj, library = output / 'component.o', output / LINUX_LIBRARY
    run('compile', [str(clang), '-std=c11', '-O2', '-fPIC', '-fvisibility=hidden',
        '-D_GNU_SOURCE', '-Wall', '-Wextra', '-Werror', '-MD', '-MF', str(output / 'component.d'),
        *('-I' + str(openssl / root) for root in ('include', 'include/x86_64-linux-gnu')),
        '-I' + str(ROOT / 'packages/python-local-runtime/native/pre-root'),
        '-c', str(SOURCE / 'component.c'), '-o', str(obj)])
    exports = output / 'component.exports'
    exports.write_text('{ global:\n' + ''.join('  ' + name + ';\n' for name in EXPORTS) + 'local: *;\n};\n')
    run('link', [str(clang), '-shared', '-nostartfiles', str(obj), str(openssl / selected['archive']['path']),
        '-Wl,--exclude-libs,ALL', '-Wl,--version-script=' + str(exports), '-Wl,-Bsymbolic',
        '-Wl,-soname,' + LINUX_LIBRARY, '-Wl,-z,now', '-Wl,-z,relro', '-o', str(library),
        '-ldl', '-lpthread', '-lm'])
    inspected = inspect_linux_component(library)
    dependencies = shlex.split((output / 'component.d').read_text().replace('\\\n', ' ').split(':', 1)[1])
    compiled, aliases = {}, {}
    for name in sorted(set(dependencies)):
        path = Path(name)
        resolved = path.resolve(strict=True)
        if resolved != path:
            if not path.is_relative_to('/usr/include') or not resolved.is_relative_to('/usr/include'):
                raise ValueError('Unqualified Linux Crypto compiler input alias')
            aliases[name] = str(resolved)
        compiled[str(resolved)] = original(resolved, 16 * 1024 * 1024)
    verify_original_inputs(inputs, compiled)
    if clean() != source:
        raise ValueError('Original Linux Crypto source changed')
    (output / 'OPENSSL-COPYRIGHT').write_bytes((openssl / selected['license']['path']).read_bytes())
    (output / 'CRYPTO-NOTICE').write_bytes((SOURCE / 'NOTICE').read_bytes())
    result = {'source': source, 'target': LINUX_TARGET, 'recipe': inputs[str(recipe_path)],
        'source_qualification': selected['qualification'], 'package': selected['package'],
        'provider_binding': 'existing original process provider; actual binding required before first allocation',
        'compiler_target': compiler_target, 'compiler_version': compiler_version,
        'inputs': inputs, 'compiled_inputs': compiled, 'compiler_header_aliases': aliases,
        **inspected, 'loaded': False, 'initialized': False, 'providers': 0}
    (output / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--openssl-prefix', type=Path)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--target', choices=('darwin-arm64', 'linux-x64'), default='darwin-arm64')
    parser.add_argument('--seconds', type=int, default=600)
    parser.add_argument('--static-profile', choices=('homebrew26', 'source-macos11'), default='homebrew26')
    parser.add_argument('--source-archive', type=Path)
    args = parser.parse_args()
    if args.target == 'linux-x64':
        if args.sdk is not None or args.openssl_prefix is None or args.source_archive is not None:
            raise ValueError('Linux Crypto preparation cannot select a Darwin SDK')
        result = produce_linux(args.output.resolve(), args.openssl_prefix.resolve(strict=True),
                               args.clang.resolve(strict=True), args.seconds)
    elif args.static_profile == 'source-macos11':
        if args.sdk is None or args.openssl_prefix is not None:
            raise ValueError('Source-built Darwin Crypto requires its SDK and source profile only')
        result = produce_darwin_source(args.output.resolve(), args.clang.resolve(strict=True),
            args.sdk.resolve(strict=True), args.seconds,
            source_archive=args.source_archive.resolve(strict=True) if args.source_archive else None)
    else:
        if args.sdk is None or args.openssl_prefix is None or args.source_archive is not None:
            raise ValueError('Darwin Crypto preparation requires its original SDK')
        result = produce(args.output.resolve(), args.openssl_prefix.resolve(strict=True),
                         args.clang.resolve(strict=True), args.sdk.resolve(strict=True))
    print(json.dumps({'source': result['source'], 'library': result['library']}))


if __name__ == '__main__':
    main()
