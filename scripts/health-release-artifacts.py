"""Inspect supplied ordinary package payloads through the existing verifier.

No installation, provider contact, benchmark or build occurs in this adapter.
"""
import importlib.util
import json
from pathlib import Path
import sys
import zipfile


def inspect(manifest, consumer, source):
    spec = importlib.util.spec_from_file_location('ordinary', Path(__file__).with_name('benchmark-ordinary-processes.py'))
    ordinary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ordinary)
    manifest = Path(manifest)
    value, _, observed = ordinary.verify_packages('python', manifest, Path(consumer), source)
    artifacts = []
    for wheel in value['wheels']:
        archive = manifest.parent / 'wheels' / wheel['file']
        with zipfile.ZipFile(archive) as z:
            members = [entry for entry in z.infolist() if not entry.is_dir()]
            artifacts.append(dict(name=wheel['distribution'], version=value['package_version'],
                sourceSha=source, artifactKind='wheel', file=wheel['file'],
                acquisitionBytes=wheel['bytes'], sha256=wheel['sha256'],
                unpackedBytes=sum(entry.file_size for entry in members),
                installedRoots=sorted({entry.filename.split('/')[0] for entry in members}),
                verifiedPayloadBytes=sum(observed[entry.filename]['bytes'] for entry in members
                                         if '.dist-info/' not in entry.filename),
                verifiedPayloads=[dict(path=entry.filename, **observed[entry.filename]) for entry in members
                                  if '.dist-info/' not in entry.filename],
                bundled=[dict(path=entry.filename, bytes=entry.file_size,
                              sha256=ordinary.digest(z.read(entry))) for entry in members
                         if any(name in entry.filename.lower() for name in ('duckdb', 'wasmtime', '.wasm'))]))
    return artifacts


def inspect_native_installed(manifest, consumer, source):
    """Read verified installed product bytes; never start the Native binary."""
    spec = importlib.util.spec_from_file_location('ordinary', Path(__file__).with_name('benchmark-ordinary-processes.py'))
    ordinary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ordinary)
    value, cohort, observed = ordinary.verify_packages('native', Path(manifest), Path(consumer), source)
    selected = {'actql', '@actql/cli-' + ordinary.platform_key()}
    packages = {}
    for package in value['packages']:
        if package['name'] not in selected:
            continue
        prefix = Path() if package['name'] == 'actql' else Path('node_modules') / package['name']
        members = {(prefix / row['path']).as_posix(): observed[(prefix / row['path']).as_posix()]
                   for row in package['files']}
        packages[package['name']] = dict(installedBytes=sum(row['bytes'] for row in members.values()),
            payloads=len(members), inventorySha256=ordinary.digest(ordinary.wire(members)))
    return dict(sourceSha=source, cohortSha256=cohort, platform=ordinary.platform_key(), packages=packages)


if __name__ == '__main__':
    arguments = sys.argv[1:]
    native = len(arguments) == 4 and arguments[:1] == ['--native-installed']
    if native:
        arguments = arguments[1:]
    assert len(arguments) == 3
    print(json.dumps((inspect_native_installed if native else inspect)(*arguments)))
