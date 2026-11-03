"""Prepare signed curl and the existing owned TLS implementation for Resident.

Only public source/build DATA is retained. This never loads a component,
installs a supplier, or supplies Host, Read or capacity authority.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('resident_http_producer', ROOT / 'scripts/produce-native-http-component.py')
HTTP = importlib.util.module_from_spec(spec)
spec.loader.exec_module(HTTP)


def acquire(url: str, expected: dict, destination: Path, original: Path | None,
            seconds: int) -> Path:
    if original is not None:
        item = HTTP.original(original)
        HTTP.require({key: item[key] for key in ('bytes', 'sha256')} == expected,
                     'Selected original HTTP preparation input differs')
        return original
    with urllib.request.urlopen(urllib.request.Request(url, headers={
            'User-Agent': 'ActQL-native-input-verification'}), timeout=min(seconds, 60)) as response:
        HTTP.require(response.geturl().startswith('https://'), 'HTTP source redirect requires HTTPS')
        raw = response.read(expected['bytes'] + 1)
    HTTP.require(len(raw) == expected['bytes'] and hashlib.sha256(raw).hexdigest() == expected['sha256'],
                 'Pinned original HTTP preparation download differs')
    with destination.open('xb') as stream:
        stream.write(raw)
    return destination


def prepare(source: str, target: str, clang: Path, sdk: Path | None, make: Path,
            perl: Path, gpg: Path, gpgv: Path, destination: Path, seconds: int, *,
            curl_archive: Path | None = None, curl_signature: Path | None = None,
            release_key: Path | None = None, tls_archive: Path | None = None) -> dict:
    HTTP.require(type(seconds) is int and 0 < seconds <= 1800, 'Bounded HTTP preparation required')
    HTTP.TLS.command_profile(target, clang, sdk, destination, '11.0' if sdk else None)
    def clean():
        HTTP.require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
            text=True).strip() == source and not subprocess.check_output(
            ['git', 'status', '--porcelain'], cwd=ROOT), 'Exact clean HTTP preparation Source required')
    clean()
    deadline = time.monotonic() + seconds
    def remaining():
        value = int(deadline - time.monotonic())
        HTTP.require(value > 0, 'HTTP preparation budget exhausted')
        return value
    destination.mkdir(parents=True, exist_ok=False)
    recipe_path = ROOT / 'scripts/native-http-component-source.json'
    recipe = json.loads(recipe_path.read_bytes())
    upstream, tls_recipe = recipe['upstream'], recipe['ownedOpenSSLSource']
    curl_archive = acquire(upstream['url'], upstream['archive'], destination / 'curl.tar.xz', curl_archive, remaining())
    curl_signature = acquire(upstream['url'] + '.asc', upstream['signature'], destination / 'curl.tar.xz.asc', curl_signature, remaining())
    key = upstream['releaseKey']
    release_key = acquire(key['url'], {name: key[name] for name in ('bytes', 'sha256')},
                          destination / 'release-key.asc', release_key, remaining())
    tls_archive = acquire(tls_recipe['url'], tls_recipe['archive'], destination / 'openssl.tar.gz', tls_archive, remaining())
    selected = [Path(__file__).resolve(), recipe_path, gpg, release_key, curl_archive, curl_signature, tls_archive]
    inputs = [HTTP.NATIVE.original(path) for path in selected]
    home = destination / 'public-key-verifier'
    home.mkdir(mode=0o700)
    base = [str(gpg), '--no-options', '--homedir', str(home), '--batch', '--no-autostart', '--no-auto-key-retrieve']
    steps = []
    def run(name, command):
        result = subprocess.run(command, capture_output=True, timeout=remaining())
        (destination / (name + '.stdout')).write_bytes(result.stdout)
        (destination / (name + '.stderr')).write_bytes(result.stderr)
        steps.append({'name': name, 'command': command, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        HTTP.require(result.returncode == 0, 'HTTP public-key preparation failed: ' + name)
        return result.stdout
    observed = run('public-key-fingerprint', base + ['--with-colons', '--import-options', 'show-only', '--import', str(release_key)])
    fingerprints, primary = [], False
    for line in observed.decode().splitlines():
        fields = line.split(':')
        if fields[0] in ('pub', 'sub'):
            primary = fields[0] == 'pub'
        elif fields[0] == 'fpr' and primary:
            fingerprints.append(fields[9])
            primary = False
    HTTP.require(fingerprints == [upstream['signerFingerprint']], 'Selected curl release key fingerprint differs')
    run('public-key-import', base + ['--import', str(release_key)])
    keyring = destination / 'release-key.gpg'
    with keyring.open('xb') as stream:
        stream.write(run('public-key-export', base + ['--export', upstream['signerFingerprint']]))
    tls = HTTP.TLS.build(source, tls_archive, destination / 'owned-tls', clang, sdk, make, perl,
                         remaining(), target, '11.0' if sdk else None)
    HTTP.build(source, curl_archive, curl_signature, keyring, Path(tls['stage']), clang, sdk,
               make, gpgv, destination / 'component', remaining(), destination / 'owned-tls/build.json',
               target, '11.0' if sdk else None)
    for item in inputs:
        HTTP.require(HTTP.NATIVE.original(Path(item['path'])) == item, 'Original HTTP preparation input changed')
    clean()
    result = {'source': source, 'target': target, 'minimumMacOS': '11.0' if sdk else None,
              'inputs': inputs, 'tls': HTTP.NATIVE.original(destination / 'owned-tls/build.json'),
              'component': HTTP.NATIVE.original(destination / 'component/build.json'),
              'loaded': 0, 'initialized': 0, 'installed_supplier': False}
    (destination / 'preparation.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--target', choices=('darwin-arm64', 'linux-x64'), required=True)
    for name in ('clang', 'make', 'perl', 'gpg', 'gpgv', 'destination'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--seconds', type=int, required=True)
    for name in ('curl-archive', 'curl-signature', 'release-key', 'tls-archive'):
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.target, args.clang, args.sdk, args.make,
        args.perl, args.gpg, args.gpgv, args.destination, args.seconds,
        curl_archive=args.curl_archive, curl_signature=args.curl_signature,
        release_key=args.release_key, tls_archive=args.tls_archive)))
