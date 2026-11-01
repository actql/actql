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


def build(source, archive, destination, clang, sdk, make, perl, seconds):
    require(sys.platform == 'darwin' and platform.machine() == 'arm64', 'Selected Native TLS target differs')

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
                sdk / 'SDKSettings.json', Path(sys.executable).resolve()]
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
    env = {'PATH': '/Library/Developer/CommandLineTools/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin',
           'HOME': str(destination), 'CC': str(clang), 'SDKROOT': str(sdk),
           'MACOSX_DEPLOYMENT_TARGET': '26.0', 'LC_ALL': 'C', 'LANG': 'C',
           'CFLAGS': '-O2 -fPIC -arch arm64 -isysroot ' + str(sdk),
           'LDFLAGS': '-arch arm64 -isysroot ' + str(sdk)}
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

    run('configure', [str(perl), str(source_root / 'Configure'), 'darwin64-arm64-cc',
                      '--prefix=' + str(stage), *recipe['configure']])
    run('build-libraries', [str(make), '-j1', 'build_libs'])
    (stage / 'lib').mkdir(parents=True)
    (stage / 'include/openssl').mkdir(parents=True)
    for name in ('libssl.a', 'libcrypto.a'):
        shutil.copy2(build_root / name, stage / 'lib' / name)
    for headers in (source_root / 'include/openssl', build_root / 'include/openssl'):
        for path in headers.glob('*.h'):
            target = stage / 'include/openssl' / path.name
            require(not target.exists() or target.read_bytes() == path.read_bytes(), 'TLS header collision')
            shutil.copy2(path, target)
    shutil.copy2(source_root / 'LICENSE.txt', stage / 'LICENSE.txt')
    config = (stage / 'include/openssl/configuration.h').read_text()
    require(all(re.search(r'#\s*define\s+' + option + r'\b', config) for option in
                ('OPENSSL_NO_PINSHARED', 'OPENSSL_NO_ATEXIT')), 'Observed TLS cleanup configuration differs')
    for item in inputs:
        require(NATIVE.original(Path(item['path'])) == item, 'TLS original changed during production')
    clean()
    files = [NATIVE.original(p) for p in sorted(stage.rglob('*')) if p.is_file()]
    receipt = {'source': source, 'upstream': recipe, 'inputs': inputs, 'stage': str(stage), 'files': files,
               'compiledLibraries': 2, 'loaded': 0, 'installedSupplier': False, 'normalProfile': None,
               'scope': 'Static TLS dependency only; no Runtime/Host/transport/physical-stop acceptance.'}
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    for name in ('archive', 'destination', 'clang', 'sdk', 'make', 'perl'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.archive, args.destination, args.clang,
                           args.sdk, args.make, args.perl, args.seconds)))
