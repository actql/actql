"""Build one clean-source standard product/SDK/runtime wheel cohort; no publication."""
from __future__ import annotations

import argparse
from email.parser import BytesParser
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import zipfile

from python_release_cohort import read_cohort

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(65536), b''):
            value.update(block)
    return value.hexdigest()


def wheel_metadata(path: Path, name: str, version: str) -> None:
    """Inspect the actual wheel's defaults, tags and typed facade; never import it."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or any(value.startswith('/') or '..' in Path(value).parts for value in names):
            raise ValueError('Invalid Python cohort wheel member paths')
        metadata = [value for value in names if value.endswith('.dist-info/METADATA')]
        tags = [value for value in names if value.endswith('.dist-info/WHEEL')]
        if len(metadata) != 1 or len(tags) != 1:
            raise ValueError('Invalid Python cohort wheel metadata inventory')
        body = BytesParser().parsebytes(archive.read(metadata[0]))
        tag = BytesParser().parsebytes(archive.read(tags[0]))
        if body['Name'] != name or body['Version'] != version:
            raise ValueError('Python cohort wheel name/version mismatch')
        requirements = body.get_all('Requires-Dist', [])
        defaults = [value for value in requirements if ';' not in value]
        expected = {'actql': ['actql-sdk==' + version, 'actql-local-runtime==' + version],
                    'actql-sdk': ['httpx==0.28.1', 'rfc8785==0.1.4'],
                    'actql-local-runtime': ['wasmtime==38.0.0']}[name]
        if sorted(defaults) != sorted(expected):
            raise ValueError('Python cohort wheel default dependencies mismatch')
        if name == 'actql-sdk' and ('local' in body.get_all('Provides-Extra', [])
                or any('actql-local-runtime' in value or 'wasmtime' in value or 'duckdb' in value for value in requirements)):
            raise ValueError('Lightweight SDK wheel contains a Local dependency')
        if tag.get_all('Tag', []) != [
                'py3-none-macosx_11_0_arm64' if name == 'actql-local-runtime' else 'py3-none-any']:
            raise ValueError('Python cohort wheel target mismatch')
        if name == 'actql' and not {'actql/__init__.py', 'actql/__init__.pyi', 'actql/py.typed'} <= set(names):
            raise ValueError('Standard product wheel has no typed facade')
        if name != 'actql-local-runtime' and any(value.endswith(('.wasm', '.dylib', '.so', '.dll')) for value in names):
            raise ValueError('Python facade/SDK wheel contains a native engine')


def runtime_wheel_components(wheel: Path, artifact: Path) -> None:
    """Match the shipped resource bytes to the same verified original artifact."""
    with zipfile.ZipFile(wheel) as archive:
        for name in ('artifact.json', 'client_host_wasm.wasm', 'libduckdb.dylib',
                     'LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
            original = artifact / name
            info = archive.getinfo('actql_local_runtime/' + name)
            if info.file_size != original.stat().st_size:
                raise ValueError('Python runtime wheel component length mismatch')
            digest = hashlib.sha256()
            with archive.open(info) as member:
                for block in iter(lambda: member.read(65536), b''):
                    digest.update(block)
            if digest.hexdigest() != sha256(original):
                raise ValueError('Python runtime wheel component digest mismatch')


def copy_source(source: str, original: Path, target: Path) -> None:
    relative = original.relative_to(ROOT).as_posix()
    expected = subprocess.check_output(['git', 'show', source + ':' + relative], cwd=ROOT)
    if original.is_symlink() or original.read_bytes() != expected:
        raise ValueError('Python wheel source differs from the committed original')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(expected)


def build(artifact: Path, destination: Path) -> dict[str, object]:
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Build Python wheels from committed clean source')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    version = read_cohort(ROOT)
    spec = importlib.util.spec_from_file_location('python_runtime_recipe', ROOT / 'scripts/prepare-python-local-runtime.py')
    if spec is None or spec.loader is None:
        raise ValueError('Original Python runtime recipe is unavailable')
    recipe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recipe)
    components = recipe.verify_artifact(artifact)
    artifact_digest = sha256(artifact / 'artifact.json')
    artifact_body = json.loads((artifact / 'artifact.json').read_bytes())
    destination.mkdir()
    stages = destination / 'stages'
    stages.mkdir()
    runtime = stages / 'python-local-runtime'
    recipe.prepare(artifact, runtime)
    for package in ('python-product', 'python-sdk'):
        stage = stages / package
        stage.mkdir()
        original = ROOT / 'packages' / package
        for name in ('pyproject.toml', 'README.md', 'LICENSE'):
            copy_source(source, original / name, stage / name)
        # Only committed files enter the wheel; ignored caches and accidental
        # source-tree dependencies never become release inputs.
        tracked = subprocess.check_output(['git', 'ls-files', '--',
            'packages/' + package + '/src'], cwd=ROOT, text=True).splitlines()
        if not tracked:
            raise ValueError('Python cohort package source inventory is empty')
        for name in tracked:
            path = ROOT / name
            copy_source(source, path, stage / path.relative_to(original))
    wheels = destination / 'wheels'
    wheels.mkdir()
    records = []
    for package, distribution in [('python-sdk', 'actql-sdk'),
                                  ('python-local-runtime', 'actql-local-runtime'),
                                  ('python-product', 'actql')]:
        before = set(wheels.glob('*.whl'))
        subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation',
                        '--outdir', str(wheels), str(stages / package)], check=True)
        created = set(wheels.glob('*.whl')) - before
        if len(created) != 1:
            raise ValueError('Python cohort build did not create one wheel per package')
        wheel = created.pop()
        wheel_metadata(wheel, distribution, version)
        if distribution == 'actql-local-runtime':
            runtime_wheel_components(wheel, artifact)
        records.append({'distribution': distribution, 'file': wheel.name,
                        'bytes': wheel.stat().st_size, 'sha256': sha256(wheel)})
    if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
        raise ValueError('Python cohort source changed during build')
    # Reinspect the same original artifact after copying/building. Wheel success
    # is component packaging evidence, never Core execution or public acceptance.
    final = recipe.verify_artifact(artifact)
    if final != components or sha256(artifact / 'artifact.json') != artifact_digest:
        raise ValueError('Python cohort original components changed during build')
    result: dict[str, object] = {'source_sha': source, 'package_version': version,
        'artifact_sha256': artifact_digest,
        'platform': artifact_body['platform'], 'core_abi': artifact_body['core_abi'],
        'module_sha256': components.module_sha256, 'duckdb_sha256': components.duckdb_sha256,
        'wheels': records, 'runtime_executed': False, 'public_local_accepted': False,
        'recovery_accepted': False, 'published': False}
    (destination / 'cohort.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-directory', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.artifact_directory, arguments.destination)))
