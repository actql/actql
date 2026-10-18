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

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/python-local-runtime/native/crypto-component'
EXPORTS = tuple('actql_crypto_component_' + name for name in (
    'bind', 'enter', 'leave', 'borrow_library', 'release_library', 'symbol',
    'inventory', 'close', 'version', 'bind_current', 'enter_current',
    'leave_current', 'is_current', 'bind_current_with_custody'))


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


def produce(output: Path, openssl: Path, clang: Path, sdk: Path) -> dict[str, object]:
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
    selected = recipe['candidate_static_input']
    for path, checksum in ((openssl / '.brew/openssl@3.rb', selected['formula_sha256']),
                           (openssl / 'INSTALL_RECEIPT.json', selected['receipt_sha256'])):
        inputs[str(path)] = original(path)
        if inputs[str(path)]['sha256'] != checksum:
            raise ValueError('Selected OpenSSL archive origin mismatch')
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
    if inputs[str(archive)] != {key: recipe['candidate_static_input'][key]
                               for key in ('bytes', 'sha256')}:
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
    if max(map(version, archive_minimums)) > version(recipe['minimum_macos']):
        raise ValueError('OpenSSL archive requires a newer deployment target')
    inputs[str(clang)] = original(clang, 512 * 1024 * 1024)
    output.mkdir(parents=True, exist_ok=False)
    exports = output / 'component.exports'
    exports.write_text(''.join('_' + name + '\n' for name in EXPORTS))
    library = output / 'libactql_crypto_component.dylib'
    dependencies = output / 'component.d'
    command = [str(clang), '-isysroot', str(sdk), '-std=c11', '-O2',
               '-mmacosx-version-min=' + recipe['minimum_macos'],
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
    if not observed_minimum or version(observed_minimum[1]) != version(recipe['minimum_macos']):
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
              'source_qualification': recipe['candidate_static_input']['qualification'],
              'provider_binding': 'existing process provider; actual original binding required before first allocation',
              'command': command, 'inputs': inputs, 'exports': sorted(names), 'links': links,
              'undefined': undefined, 'archive_minimum_macos': sorted(set(archive_minimums), key=version),
              'archive_object_count': len(archive_minimums), 'minimum_macos': observed_minimum[1],
              'compiler_header_aliases': header_aliases, 'library': original(library),
              'license': original(output / 'OPENSSL-LICENSE.txt'),
              'notice': original(output / 'CRYPTO-NOTICE')}
    (output / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--openssl-prefix', type=Path, required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    args = parser.parse_args()
    result = produce(args.output.resolve(), args.openssl_prefix.resolve(strict=True),
                     args.clang.resolve(strict=True), args.sdk.resolve(strict=True))
    print(json.dumps({'source': result['source'], 'library': result['library']}))


if __name__ == '__main__':
    main()
