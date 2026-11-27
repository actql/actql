"""Prepare the ordinary Python wheel's selected Portable Crypto component."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PIN = ROOT / 'packages/python-local-runtime/native/crypto-component/source.json'
PRODUCER = ROOT / 'scripts/produce-native-crypto-component.py'
PERL_REPOSITORY = 'https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/'


def require_source(source: str) -> None:
    if (re.fullmatch('[0-9a-f]{40}', source) is None
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source
            or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)):
        raise ValueError('Exact clean ordinary Python Model Crypto Source required')


def acquire(url: str, expected: dict, path: Path, timeout: int) -> None:
    request = urllib.request.Request(url, headers={'User-Agent': 'ActQL-Python-Crypto-Original'})
    with urllib.request.urlopen(request, timeout=min(60, timeout)) as response:
        if not response.geturl().startswith('https://'):
            raise ValueError('Portable Crypto source requires HTTPS')
        raw = response.read(expected['bytes'] + 1)
    if len(raw) != expected['bytes'] or hashlib.sha256(raw).hexdigest() != expected['sha256']:
        raise ValueError('Portable Crypto source bytes differ from the selected original')
    with path.open('xb') as stream:
        stream.write(raw)


def prepare(source: str, destination: Path, seconds: int = 1200) -> Path:
    target = {('Linux', 'x86_64'): 'linux-x64',
              ('Darwin', 'arm64'): 'darwin-arm64'}.get((platform.system(), platform.machine()))
    if target is None or type(seconds) is not int or not 0 < seconds <= 1800:
        raise ValueError('Select a supported physical target and bounded Python Model Crypto preparation')
    if not destination.is_absolute() or destination == ROOT or ROOT in destination.parents:
        raise ValueError('Portable Crypto output must be outside the ordinary source checkout')
    require_source(source)
    deadline = time.monotonic() + seconds

    def remaining() -> int:
        count = int(deadline - time.monotonic())
        if count <= 0:
            raise ValueError('Ordinary Python Model Crypto preparation budget exhausted')
        return count

    def run(*arguments, capture=False):
        return subprocess.run(arguments, cwd=ROOT, timeout=remaining(), check=True,
                              capture_output=capture, text=True).stdout

    recipe = json.loads(PIN.read_bytes())
    selected = recipe['portable'][target]
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    inputs = destination / 'inputs'
    inputs.mkdir(mode=0o700)
    archive = inputs / 'openssl.tar.gz'
    acquire(recipe['upstream']['url'], recipe['upstream'], archive, remaining())
    component = destination / 'component'
    if target == 'linux-x64':
        rpms = inputs / 'rpms'
        rpms.mkdir(mode=0o700)
        for name, original in selected['perl_inputs'].items():
            acquire(PERL_REPOSITORY + name, original, rpms / name, remaining())
        image = selected['build_image']
        if re.fullmatch(r'quay\.io/pypa/manylinux_2_28_x86_64@sha256:[0-9a-f]{64}', image) is None:
            raise ValueError('The ordinary Linux Crypto build image must be pinned by digest')
        run('docker', 'pull', '--platform', 'linux/amd64', image)
        if run('docker', 'image', 'inspect', '--format', '{{.Os}}/{{.Architecture}}',
               image, capture=True).strip() != 'linux/amd64':
            raise ValueError('Selected Portable Crypto image is not linux/amd64')
        run('docker', 'run', '--rm', '--pull=never', '--platform', 'linux/amd64', '--network=none',
            '--mount', f'type=bind,src={ROOT},dst=/actql/source,readonly',
            '--mount', f'type=bind,src={inputs},dst=/actql/inputs,readonly',
            '--mount', f'type=bind,src={destination},dst=/actql/output',
            '--env', 'GIT_CONFIG_COUNT=1', '--env', 'GIT_CONFIG_KEY_0=safe.directory',
            '--env', 'GIT_CONFIG_VALUE_0=/actql/source', '--env', 'GIT_OPTIONAL_LOCKS=0',
            '--entrypoint', '/bin/bash', image, '-euc', '''
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux
rpmkeys --checksig /actql/inputs/rpms/*.rpm
rpm --install --noscripts --notriggers /actql/inputs/rpms/*.rpm
exec /opt/python/cp312-cp312/bin/python -B /actql/source/scripts/produce-native-crypto-component.py \
  --portable --target linux-x64 --clang "$(command -v gcc)" \
  --source-archive /actql/inputs/openssl.tar.gz --portable-linux-perl-rpms /actql/inputs/rpms \
  --output /actql/output/component --seconds "$1"
''', 'portable-linux-crypto', str(remaining()))
    else:
        clang = run('/usr/bin/xcrun', '--sdk', 'macosx', '--find', 'clang', capture=True).strip()
        sdk = run('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path', capture=True).strip()
        run(sys.executable, '-B', PRODUCER, '--portable', '--target', target,
            '--clang', clang, '--sdk', sdk, '--source-archive', archive,
            '--output', component, '--seconds', str(remaining()))
    require_source(source)
    with (component / 'producer.json').open('rb') as stream:
        maximum = 2 * 1024 * 1024
        raw = stream.read(maximum + 1)
    if not 0 < len(raw) <= maximum:
        raise ValueError('Ordinary Model Crypto producer receipt is unavailable')
    receipt = json.loads(raw)
    if receipt['source'] != source or receipt['target'] != target or receipt['profile'] != selected:
        raise ValueError('Ordinary Model Crypto producer returned a foreign Source or target')
    return component


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--destination', type=Path, required=True)
    arguments = parser.parse_args()
    print(prepare(arguments.source, arguments.destination.resolve()))
