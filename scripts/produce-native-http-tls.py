"""Produce only the private, explicitly retired TLS input for Native HTTP."""
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
spec = importlib.util.spec_from_file_location('native_inputs', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
NATIVE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NATIVE)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def command_profile(target, clang, sdk, destination, minimum_macos=None):
    """Explicit compiler DATA for the existing same-image TLS implementation."""
    require(target in ('darwin-arm64', 'linux-x64'), 'Selected Native TLS target differs')
    require((target == 'darwin-arm64') == (sdk is not None), 'Selected TLS SDK/target differs')
    require(minimum_macos in (None, '11.0', '26.0') and
            (target == 'darwin-arm64' or minimum_macos is None), 'Selected TLS deployment profile differs')
    minimum_macos = (minimum_macos or '26.0') if sdk is not None else None
    flags = '-O2 -fPIC' + (' -arch arm64 -isysroot ' + str(sdk) if sdk is not None else '')
    if minimum_macos == '11.0':
        flags += ' -mmacosx-version-min=11.0'
    environment = {'PATH': '/Library/Developer/CommandLineTools/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin'
                   if sdk is not None else '/usr/bin:/bin:/usr/sbin:/sbin',
                   'HOME': str(destination), 'CC': str(clang), 'LC_ALL': 'C', 'LANG': 'C',
                   'CFLAGS': flags, 'LDFLAGS': flags}
    if sdk is not None:
        environment.update({'SDKROOT': str(sdk), 'MACOSX_DEPLOYMENT_TARGET': minimum_macos})
    return {'configure': 'darwin64-arm64-cc' if sdk is not None else 'linux-x86_64',
            'environment': environment,
            'minimumMacOS': minimum_macos,
            'compilerFlags': (['-arch', 'arm64', '-isysroot', str(sdk)] +
                              (['-mmacosx-version-min=11.0'] if minimum_macos == '11.0' else []))
                              if sdk is not None else ['-D_GNU_SOURCE']}


def validate_archive_deployment(loads, minimum_macos):
    platforms = re.findall(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (\d+)', loads)
    versions = re.findall(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos (\d+\.\d+(?:\.\d+)?)', loads)
    versions += re.findall(r'cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)', loads)
    def version(value):
        return tuple((list(map(int, value.split('.'))) + [0, 0])[:3])
    require(versions and all(item == '1' for item in platforms) and
            all(version(value) <= version(minimum_macos) for value in versions),
            'Original TLS archive deployment requirement exceeds selected macOS profile')


def validate_receipt_profile(receipt, target, minimum_macos):
    require(receipt.get('target', 'darwin-arm64') == target and
            receipt.get('minimumMacOS', '26.0' if target == 'darwin-arm64' else None) == minimum_macos,
            'Owned TLS source/deployment profile differs')


def build(source, archive, destination, clang, sdk, make, perl, seconds, target='darwin-arm64',
          minimum_macos=None, *, jobs=1):
    require(type(jobs) is int and jobs in (1, 2), 'TLS build jobs must be one or two')
    actual = ('darwin-arm64' if sys.platform == 'darwin' and platform.machine() == 'arm64'
              else 'linux-x64' if sys.platform == 'linux' and platform.machine() == 'x86_64' else None)
    require(actual == target, 'Selected Native TLS target differs')
    require(re.fullmatch(r'[a-f0-9]{40}', source) is not None and type(seconds) is int and seconds > 0,
            'Invalid selected TLS source or build budget')
    profile = command_profile(target, clang, sdk, destination, minimum_macos)

    def clean():
        require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source and
                not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT), 'Exact clean Source required')

    clean()
    recipe = json.loads((ROOT / 'scripts/native-http-component-source.json').read_bytes())['ownedOpenSSLSource']
    original = NATIVE.original(archive)
    require({k: original[k] for k in ('bytes', 'sha256')} == recipe['archive'], 'Selected TLS source differs')
    require(not destination.exists(), 'Original TLS output already exists')
    destination.mkdir(parents=True)
    selected = [archive, Path(__file__).resolve(), ROOT / 'scripts/native-http-component-source.json',
                ROOT / 'scripts/produce-native-remote-scoped-runtime.py', clang, make, perl,
                Path(sys.executable).resolve()]
    if sdk is not None:
        selected.extend([sdk / 'SDKSettings.json', Path('/usr/bin/otool')])
    inputs = [NATIVE.original(p) for p in selected]
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        top = 'openssl-' + recipe['version']
        require(sum(x.size for x in members) < 768 * 1024 * 1024 and
                all(x.name == top or x.name.startswith(top + '/') for x in members), 'TLS source layout/bound differs')
        tar.extractall(destination / 'source', filter='data')
    source_root = destination / 'source' / top
    # The selected upstream lock constructor already forbids error reporting
    # here: ERR initialization would recursively enter the same pthread_once.
    # Preserve that contract with the allocator's explicit NULL/0 error-site
    # form. Keep the archive immutable and seal both exact derived bodies.
    lock_patch = recipe['lockAllocationRefusal']
    require(lock_patch['path'] == 'crypto/threads_pthread.c', 'Foreign TLS patch target')
    lock_source = source_root / lock_patch['path']
    before = lock_source.read_bytes()
    require(hashlib.sha256(before).hexdigest() == lock_patch['beforeSha256'],
            'TLS lock source differs before the selected correction')
    after = before
    for name in ('pthread_rwlock_t', 'pthread_mutex_t'):
        old = ('OPENSSL_zalloc(sizeof(' + name + '))').encode()
        new = ('CRYPTO_zalloc(sizeof(' + name + '), NULL, 0)').encode()
        require(after.count(old) == 1, 'TLS lock allocation source shape differs')
        after = after.replace(old, new)
    require(hashlib.sha256(after).hexdigest() == lock_patch['afterSha256'],
            'TLS lock source differs after the selected correction')
    lock_source.write_bytes(after)
    (destination / 'applied-lock-allocation-refusal.json').write_text(
        json.dumps(lock_patch, indent=2) + '\n')
    build_root = destination / 'build'
    build_root.mkdir()
    stage = destination / 'stage'
    env = profile['environment']
    deadline, steps = time.monotonic() + seconds, []

    def run(name, command):
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'TLS production budget exhausted')
        result = subprocess.run(command, cwd=build_root, env=env, capture_output=True, text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': command, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'TLS command failed: ' + name)
        return result.stdout

    run('configure', [str(perl), str(source_root / 'Configure'), profile['configure'],
                      '--prefix=' + str(stage), *recipe['configure']])
    run('build-libraries', [str(make), '-j' + str(jobs), 'build_libs'])
    (stage / 'lib').mkdir(parents=True)
    (stage / 'include/openssl').mkdir(parents=True)
    for name in ('libssl.a', 'libcrypto.a'):
        shutil.copy2(build_root / name, stage / 'lib' / name)
        if sdk is not None:
            loads = run('observed-' + name + '-deployment', ['/usr/bin/otool', '-l', str(stage / 'lib' / name)])
            validate_archive_deployment(loads, profile['minimumMacOS'])
    for headers in (source_root / 'include/openssl', build_root / 'include/openssl'):
        for path in headers.glob('*.h'):
            header_target = stage / 'include/openssl' / path.name
            require(not header_target.exists() or header_target.read_bytes() == path.read_bytes(), 'TLS header collision')
            shutil.copy2(path, header_target)
    shutil.copy2(source_root / 'LICENSE.txt', stage / 'LICENSE.txt')
    config = (stage / 'include/openssl/configuration.h').read_text()
    require(all(re.search(r'#\s*define\s+' + option + r'\b', config) for option in
                ('OPENSSL_NO_PINSHARED', 'OPENSSL_NO_ATEXIT')), 'Observed TLS cleanup configuration differs')
    for item in inputs:
        require(NATIVE.original(Path(item['path'])) == item, 'TLS original changed during production')
    clean()
    files = [NATIVE.original(p) for p in sorted(stage.rglob('*')) if p.is_file()]
    receipt = {'source': source, 'target': target, 'minimumMacOS': profile['minimumMacOS'], 'buildJobs': jobs,
               'upstream': recipe, 'inputs': inputs, 'stage': str(stage), 'files': files,
               'compiledLibraries': 2, 'loaded': 0, 'installedSupplier': False, 'normalProfile': None,
               'scope': 'Static TLS dependency only; no Runtime/Host/transport/physical-stop acceptance.'}
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    for name in ('archive', 'destination', 'clang', 'make', 'perl'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--target', choices=('darwin-arm64', 'linux-x64'), default='darwin-arm64')
    parser.add_argument('--minimum-macos', choices=('11.0', '26.0'))
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--jobs', type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.archive, args.destination, args.clang,
                           args.sdk, args.make, args.perl, args.seconds, args.target, args.minimum_macos, jobs=args.jobs)))
