"""Small wheel/installed DATA for monitor size tests, never SDK/runtime code."""
import base64
import csv
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import zipfile


def record(files, path):
    output = io.StringIO()
    writer = csv.writer(output, lineterminator='\n')
    for name, body in files.items():
        writer.writerow([name, 'sha256=' + base64.urlsafe_b64encode(hashlib.sha256(body).digest()).decode().rstrip('='), len(body)])
    writer.writerow([path, '', ''])
    return output.getvalue().encode()


def prepare(root):
    consumer, wheels = root / 'site-packages', root / 'wheels'
    consumer.mkdir()
    wheels.mkdir()
    source = 'a' * 40
    version = '1.2.3'
    inputs = {
        'actql': {'actql/__init__.py': b'# Synthetic product file, never imported\n'},
        'actql-sdk': {'actql_sdk/__init__.py': b'# Synthetic SDK file, never imported\n'},
        'actql-local-runtime': {
            'actql_local_runtime/__init__.py': b'# Synthetic runtime file, never imported\n',
            'actql_local_runtime/client_host_wasm.wasm': b'SYNTHETIC WASM DATA; NEVER EXECUTE',
            'actql_local_runtime/libduckdb.test': b'fixed DuckDB component data',
            'actql_local_runtime/_wasmtime/libwasmtime.test': b'fixed Wasmtime component data',
        },
    }
    archives, installed, unpacked, verified, roots = [], {}, {}, {}, set()
    for distribution, payload in inputs.items():
        metadata = distribution.replace('-', '_') + '-' + version + '.dist-info'
        files = dict(payload)
        files[metadata + '/METADATA'] = f'Metadata-Version: 2.1\nName: {distribution}\nVersion: {version}\n'.encode()
        files[metadata + '/WHEEL'] = b'Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n'
        record_path = metadata + '/RECORD'
        files[record_path] = record(files, record_path)
        archive = wheels / (distribution + '.whl')
        with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as wheel:
            for name, body in files.items():
                entry = zipfile.ZipInfo(name)
                entry.external_attr = 0o100644 << 16
                wheel.writestr(entry, body)
                roots.add(name.split('/')[0])
        raw = archive.read_bytes()
        archives.append(dict(distribution=distribution, file=archive.name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
        unpacked[distribution] = sum(map(len, files.values()))
        verified[distribution] = sum(map(len, payload.values()))
        actual = dict(files)
        actual[metadata + '/INSTALLER'] = b'pip\n'
        actual[metadata + '/REQUESTED'] = b''
        module = next(iter(payload)).split('/')[0]
        actual[module + '/__pycache__/__init__.cpython-312.pyc'] = b'SYNTHETIC BYTECODE DATA; NEVER IMPORT'
        actual[record_path] = record({name: body for name, body in actual.items() if name != record_path}, record_path)
        installed.update(actual)
    for name, body in installed.items():
        path = consumer / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        path.chmod(0o644)
    # A whole-site-packages walker would cross an unrelated root. The selected
    # product-wheel namespace inventory must never follow or classify this link.
    unrelated = root / 'unrelated'
    unrelated.mkdir()
    (unrelated / 'outside-scope').write_bytes(b'not a selected product package')
    (consumer / 'unrelated-package').symlink_to(unrelated, target_is_directory=True)
    manifest = root / 'manifest.json'
    key = {('Darwin', 'arm64'): 'darwin-arm64', ('Linux', 'x86_64'): 'linux-x64-gnu'}[platform.system(), platform.machine()]
    manifest.write_text(json.dumps(dict(source_sha=source, package_version=version, platform=key, wheels=archives)))
    return dict(manifest=str(manifest), consumer=str(consumer), source=source, roots=sorted(roots),
                installedBytes=sum(map(len, installed.values())), unpackedBytes=unpacked, verifiedPayloadBytes=verified)


if __name__ == '__main__':
    assert len(sys.argv) == 2
    print(json.dumps(prepare(Path(sys.argv[1]))))
