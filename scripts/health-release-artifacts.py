"""Inspect supplied ordinary wheels through the existing package verifier.

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
    value, _, _ = ordinary.verify_packages('python', manifest, Path(consumer), source)
    artifacts = []
    for wheel in value['wheels']:
        archive = manifest.parent / 'wheels' / wheel['file']
        with zipfile.ZipFile(archive) as z:
            members = [entry for entry in z.infolist() if not entry.is_dir()]
            artifacts.append(dict(name=wheel['distribution'], version=value['package_version'],
                sourceSha=source, artifactKind='wheel', file=wheel['file'],
                acquisitionBytes=wheel['bytes'], sha256=wheel['sha256'],
                installedBytes=sum(entry.file_size for entry in members),
                bundled=[dict(path=entry.filename, bytes=entry.file_size,
                              sha256=ordinary.digest(z.read(entry))) for entry in members
                         if any(name in entry.filename.lower() for name in ('duckdb', 'wasmtime', '.wasm'))]))
    return artifacts


if __name__ == '__main__':
    assert len(sys.argv) == 4
    print(json.dumps(inspect(*sys.argv[1:])))
