"""Build one explicit file-backed libcurl input for the Native HTTP owner.

This runs under the ordinary local guard. It never installs a library, imports
a runtime, creates a Host, or acknowledges transport/global resource cleanup.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / 'scripts/native-http-component-source.json'
spec = importlib.util.spec_from_file_location(
    'native_original_inputs', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
if spec is None or spec.loader is None:
    raise ValueError('Existing native input observer is unavailable')
NATIVE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NATIVE)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def original(path: Path) -> dict:
    before = path.stat(follow_symlinks=False)
    value = NATIVE.original(path)
    after = path.stat(follow_symlinks=False)
    require((before.st_dev, before.st_ino, before.st_mode, before.st_size,
             before.st_mtime_ns, before.st_ctime_ns) ==
            (after.st_dev, after.st_ino, after.st_mode, after.st_size,
             after.st_mtime_ns, after.st_ctime_ns), 'Input changed while read')
    return {**value, 'dev': after.st_dev, 'ino': after.st_ino, 'mode': after.st_mode}


def build(source: str, archive: Path, signature: Path, keyring: Path,
          openssl: Path, clang: Path, sdk: Path, make: Path, gpgv: Path,
          destination: Path, seconds: int, owned_openssl_receipt: Path | None = None) -> dict:
    require(sys.platform == 'darwin' and platform.machine() == 'arm64',
            'Selected HTTP component requires darwin-arm64')
    require(re.fullmatch(r'[a-f0-9]{40}', source) is not None and seconds > 0,
            'Invalid selected source or build budget')

    def clean() -> None:
        require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                text=True).strip() == source and not subprocess.check_output(
                ['git', 'status', '--porcelain'], cwd=ROOT),
                'Exact clean committed HTTP component source is required')

    clean()
    recipe = json.loads(RECIPE.read_bytes())
    for path, expected in [(archive, recipe['upstream']['archive']),
                           (signature, recipe['upstream']['signature'])]:
        item = original(path)
        require({key: item[key] for key in ('bytes', 'sha256')} == expected,
                'Selected signed source input differs')
    selected = [archive, signature, keyring, RECIPE,
                Path(__file__).resolve(), ROOT / 'scripts/produce-native-remote-scoped-runtime.py',
                clang, make, gpgv, Path(sys.executable).resolve(), sdk / 'SDKSettings.json',
                Path('/usr/bin/otool'), Path('/usr/bin/nm'), Path('/usr/bin/codesign'),
                Path('/usr/bin/install_name_tool')]
    if owned_openssl_receipt is not None:
        owned = json.loads(owned_openssl_receipt.read_bytes())
        require(owned['upstream'] == recipe['ownedOpenSSLSource'] and
                Path(owned['stage']) == openssl, 'Owned TLS source/recipe differs')
        # Reuse the exact static input when its actual producer/source/tool
        # inputs remain unchanged. A later HTTP adapter child does not retag
        # the TLS build or justify compiling those same libraries again.
        for item in owned['inputs']:
            require(NATIVE.original(Path(item['path'])) == item,
                    'Owned TLS producer original changed')
        tls_files = {}
        for item in owned['files']:
            relative = Path(item['path']).relative_to(openssl).as_posix()
            tls_files[relative] = {key: item[key] for key in ('bytes', 'sha256')}
        selected.extend([owned_openssl_receipt,
                         ROOT / 'src/platform_native/http_client/component_tls_lifetime.c',
                         ROOT / 'src/platform_native/http_client/component_tls_lifetime.h'])
    else:
        tls_files = recipe['openssl']['files']
    for relative, expected in tls_files.items():
        path = openssl / relative
        item = original(path)
        require({key: item[key] for key in ('bytes', 'sha256')} == expected,
                'Selected original OpenSSL input differs: ' + relative)
        selected.append(path)
    inputs = [original(path) for path in selected]
    require(not destination.exists() and not destination.is_symlink(), 'Output already exists')
    destination.mkdir(parents=True)
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    deadline, steps = time.monotonic() + seconds, []
    environment = {'PATH': '/Library/Developer/CommandLineTools/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin',
                   'SDKROOT': str(sdk), 'DEVELOPER_DIR': '/Library/Developer/CommandLineTools',
                   'MACOSX_DEPLOYMENT_TARGET': recipe['minimumMacOS'], 'LC_ALL': 'C', 'LANG': 'C',
                   'HOME': str(destination), 'CC': str(clang), 'PKG_CONFIG': '/usr/bin/false',
                   'CFLAGS': '-O2 -fPIC -arch arm64 -isysroot ' + str(sdk),
                   'LDFLAGS': '-arch arm64 -isysroot ' + str(sdk), 'OPENSSL_CONF': '/dev/null'}

    def run(name: str, command: list[str], cwd: Path = ROOT) -> str:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'HTTP component build budget exhausted')
        result = subprocess.run(command, cwd=cwd, env=environment,
                                capture_output=True, text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': command, 'cwd': str(cwd), 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'HTTP component command failed: ' + name)
        return result.stdout

    keyhome = destination / 'public-key-verifier'
    keyhome.mkdir(mode=0o700)
    verified = run('verify-signed-source', [str(gpgv), '--homedir', str(keyhome),
        '--keyring', str(keyring), '--status-fd', '1', str(signature), str(archive)])
    require(any(line.startswith('[GNUPG:] VALIDSIG ') and
                recipe['upstream']['signerFingerprint'] in line.split()
                for line in verified.splitlines()), 'Required upstream signature was not observed')
    # Only the two exact static archives are visible in this private prefix.
    # Header links are read-only; no tool installation or donor edit occurs.
    loans = []
    try:
        prefix = destination / 'openssl-input'
        (prefix / 'lib').mkdir(parents=True)
        (prefix / 'include').symlink_to(openssl / 'include', target_is_directory=True)
        loans.append((prefix / 'include', openssl / 'include'))
        for name in ('libssl.a', 'libcrypto.a'):
            (prefix / 'lib' / name).symlink_to(openssl / 'lib' / name)
            loans.append((prefix / 'lib' / name, openssl / 'lib' / name))
        stage = destination / 'source'
        stage.mkdir()
        with tarfile.open(archive, 'r:xz') as tar:
            members = tar.getmembers()
            top = 'curl-' + recipe['upstream']['version']
            require(sum(item.size for item in members) <= 128 * 1024 * 1024 and
                    all(item.name == top or item.name.startswith(top + '/') for item in members),
                    'Unexpected selected source archive layout')
            tar.extractall(stage, filter='data')
        source_root = stage / top
        build_root = destination / 'build'
        build_root.mkdir()
        configuration = run('configure', ['/bin/sh', str(source_root / 'configure'),
            '--prefix=/actql-native-http-component', '--with-openssl=' + str(prefix),
            *recipe['configure']], build_root)
        require('unrecognized options' not in configuration and 'unrecognized options' not in
                (destination / 'configure.stderr').read_text(), 'Unknown component configure option')
        build_command = [str(make), '-C', 'lib', '-j1', 'V=1']
        if owned_openssl_receipt is not None:
            physical_adapter = destination / 'component-tls-lifetime.o'
            run('compile-tls-lifetime', [str(clang), '-std=c11', '-O2', '-fPIC',
                '-fvisibility=hidden', '-arch', 'arm64', '-isysroot', str(sdk),
                '-I', str(openssl / 'include'), '-I', str(ROOT / 'src/platform_native/http_client'),
                '-c', str(ROOT / 'src/platform_native/http_client/component_tls_lifetime.c'),
                '-o', str(physical_adapter)])
            build_command.append('libcurl_la_LIBADD=' + str(physical_adapter))
        run('build-library', build_command, build_root)
        produced = build_root / 'lib/.libs/libcurl.4.dylib'
        require(produced.is_file(), 'Expected shared HTTP library was not produced')
        bundle = destination / 'bundle'
        bundle.mkdir()
        library = bundle / 'libcurl.4.dylib'
        shutil.copy2(produced.resolve(), library)
        run('original-install-name', ['/usr/bin/install_name_tool', '-id', '@rpath/libcurl.4.dylib', str(library)])
        run('sign-component', ['/usr/bin/codesign', '--force', '--sign', '-', str(library)])
        run('verify-component-signature', ['/usr/bin/codesign', '--verify', '--strict', str(library)])
        loads = run('observed-load-commands', ['/usr/bin/otool', '-l', str(library)])
        require('cmd LC_RPATH' not in loads, 'HTTP component has an ambient loader search path')
        minimum = re.search(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos (\d+\.\d+(?:\.\d+)?)', loads)
        require(minimum is not None and minimum[1] == recipe['minimumMacOS'],
                'Observed HTTP component deployment requirement differs')
        header = run('observed-mach-header', ['/usr/bin/otool', '-hv', str(library)])
        require(re.search(r'\bARM64\b', header) is not None, 'Unexpected HTTP component machine ABI')
        dependencies = run('observed-dependencies', ['/usr/bin/otool', '-L', str(library)])
        require(str(openssl) not in dependencies and str(prefix) not in dependencies,
                'Static TLS input unexpectedly became an external dynamic dependency')
        observed_dependencies = []
        for line in dependencies.splitlines()[1:]:
            name = line.strip().split(' (compatibility version ', 1)[0]
            if name == '@rpath/libcurl.4.dylib':
                continue
            require(name.startswith(('/usr/lib/', '/System/Library/Frameworks/')),
                    'Unselected non-system HTTP library dependency')
            observed_dependencies.append(name)
        exports = run('observed-exports', ['/usr/bin/nm', '-gU', str(library)])
        names = {line.split()[-1] for line in exports.splitlines() if line.strip()}
        require({'_' + name for name in ('curl_global_init', 'curl_global_init_mem', 'curl_global_cleanup',
                 'curl_version', 'curl_version_info', 'curl_easy_init', 'curl_easy_setopt',
                 'curl_easy_perform', 'curl_easy_getinfo', 'curl_easy_cleanup',
                 'curl_easy_strerror', 'curl_slist_append', 'curl_slist_free_all')} <= names,
                'Existing Native HTTP loader symbols are incomplete')
        if owned_openssl_receipt is not None:
            require('_curl_actql_native_tls_api_v3' in names, 'Original Read/TLS cleanup export is missing')
        run('observed-imports', ['/usr/bin/nm', '-u', str(library)])
        shutil.copy2(source_root / 'COPYING', bundle / 'CURL-COPYING')
        shutil.copy2(openssl / 'LICENSE.txt', bundle / 'OPENSSL-LICENSE.txt')
    finally:
        returned = []
        for path, target in reversed(loans):
            require(path.is_symlink() and path.readlink() == target, 'Original component input alias changed')
            path.unlink()
            returned.append({'path': str(path), 'target': str(target)})
        (destination / 'input-alias-closure.json').write_text(json.dumps({'returned': returned, 'remainingOwnAliases': 0}, indent=2) + '\n')
    (destination / 'configure-summary.txt').write_text(configuration)
    for item in inputs:
        require(original(Path(item['path'])) == item, 'Original input changed during component production')
    clean()
    receipt = {'source': source, 'target': recipe['target'], 'upstream': recipe['upstream'],
               'recipe_sha256': hashlib.sha256(RECIPE.read_bytes()).hexdigest(), 'inputs': inputs,
               'library': original(library), 'loaded': 0, 'initialized': 0,
               'installed_supplier': False, 'normal_profile': None, 'public_e2e': 0,
               'minimumMacOS': minimum[1], 'systemDependencies': observed_dependencies,
               'scope': 'File-backed dependency only. No Native Host/Read funding, transport/thread stop or runtime acceptance.'}
    receipt['ownedOpenSSLReceipt'] = original(owned_openssl_receipt) if owned_openssl_receipt else None
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    for name in ('archive', 'signature', 'keyring', 'openssl', 'clang', 'sdk', 'make', 'gpgv', 'destination'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--owned-openssl-receipt', type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.archive, args.signature, args.keyring,
        args.openssl, args.clang, args.sdk, args.make, args.gpgv, args.destination, args.seconds,
        args.owned_openssl_receipt)))
