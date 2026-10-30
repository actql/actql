"""Build one clean-source standard product/SDK/runtime wheel cohort; no publication."""
from __future__ import annotations

import argparse
from dataclasses import replace
from email.parser import BytesParser
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from actql_sdk._local_image_recipe import _SelectedImageRecipe

from python_release_cohort import (read_cohort, select_release_version,
                                   release_project_metadata, release_runtime_metadata)
from python_interface_inventory import wheel_source_correspondence

ROOT = Path(__file__).resolve().parents[1]


def host_capacity_original(source: str, components: object) -> bytes:
    """Stage only a selected clean Git original; missing capacity is not zero."""
    from actql_sdk._local_capacity_original import _encode_installed_capacity
    from actql_sdk._local_distribution import LocalComponents, _read_file
    if type(components) is not LocalComponents:
        raise ValueError('Unavailable original Python capacity context')
    relative = 'packages/python-local-runtime/selected-host-capacity.json'
    try:
        original = _read_file(ROOT / relative, maximum=65536)
        expected = subprocess.check_output(['git', 'rev-parse', '--verify', source + ':' + relative], cwd=ROOT).strip()
        actual = subprocess.check_output(['git', 'hash-object', '--stdin'], cwd=ROOT, input=original).strip()
        if actual != expected or components.source_sha != source:
            raise ValueError('Python capacity differs from the committed source original')
        return _encode_installed_capacity(original, components)
    except (OSError, subprocess.CalledProcessError) as failure:
        raise ValueError('Selected source-original Python Host capacity is unavailable') from failure


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
        expected_tag = ('py3-none-macosx_11_0_arm64'
                        if name == 'actql-local-runtime' else 'py3-none-any')
        if tag.get_all('Tag', []) != [expected_tag]:
            raise ValueError('Python cohort wheel target mismatch')
        if path.name != name.replace('-', '_') + '-' + version + '-' + expected_tag + '.whl':
            raise ValueError('Python cohort wheel filename differs from its metadata')
        if name == 'actql' and not {'actql/__init__.py', 'actql/__init__.pyi', 'actql/py.typed'} <= set(names):
            raise ValueError('Standard product wheel has no typed facade')
        if name != 'actql-local-runtime' and any(value.endswith(('.wasm', '.cwasm', '.dylib', '.so', '.dll')) for value in names):
            raise ValueError('Python facade/SDK wheel contains a native engine')


def runtime_wheel_components(wheel: Path, artifact: Path, stage: Path, *,
                             selected_recipe: _SelectedImageRecipe | None = None,
                             release_manifest: bytes | None = None) -> dict[str, str]:
    """Match the shipped resource bytes to the same verified original artifact."""
    with zipfile.ZipFile(wheel) as archive:
        for name in ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
                     'client_host_wasm.wasm', 'libduckdb.dylib',
                     'LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
            if name == 'artifact.json' and release_manifest is not None:
                if archive.read('actql_local_runtime/' + name) != release_manifest:
                    raise ValueError('Python wheel release metadata differs from its fixed projection')
                continue
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
        package = stage / 'src/actql_local_runtime'
        private = package / '_wasmtime'
        allocation = 'native-owned'
        if selected_recipe is not None:
            from actql_sdk._local_image_recipe import _SelectedImageRecipe, _recipe_from_original
            if type(selected_recipe) is not _SelectedImageRecipe:
                raise ValueError('Unavailable original runtime wheel recipe')
            actual = _recipe_from_original((artifact / 'engine-recipe.json').read_bytes(),
                source_sha=selected_recipe.source_sha, package_version=selected_recipe.package_version,
                module_sha256=selected_recipe.module_sha256)
            if actual != selected_recipe:
                raise ValueError('Runtime wheel recipe differs from its original')
            allocation = selected_recipe.runtime_allocation
        if allocation == 'platform':
            if private.exists() or private.is_symlink():
                raise ValueError('Ordinary runtime wheel must use its declared Wasmtime dependency')
            license_name = 'actql_local_runtime/WASMTIME-LICENSE'
            if archive.read(license_name) != (package / 'WASMTIME-LICENSE').read_bytes():
                raise ValueError('Ordinary runtime license bytes differ')
            if any(name.startswith('actql_local_runtime/_wasmtime/') for name in archive.namelist()):
                raise ValueError('Ordinary runtime wheel contains a private runtime')
            return {}
        if not private.is_dir() or private.is_symlink():
            raise ValueError('Python runtime stage has no original private bindings')
        expected = [package / 'WASMTIME-LICENSE'] + sorted(path for path in private.rglob('*') if path.is_file())
        for original in expected:
            if original.is_symlink():
                raise ValueError('Python runtime stage contains a linked private input')
            name = 'actql_local_runtime/' + original.relative_to(package).as_posix()
            info = archive.getinfo(name)
            if info.file_size != original.stat().st_size:
                raise ValueError('Python runtime wheel private component length mismatch')
            digest = hashlib.sha256()
            with archive.open(info) as member:
                for block in iter(lambda: member.read(65536), b''):
                    digest.update(block)
            if digest.hexdigest() != sha256(original):
                raise ValueError('Python runtime wheel private component digest mismatch')
        observed = {name for name in archive.namelist() if name.startswith('actql_local_runtime/_wasmtime/')}
        if observed != {'actql_local_runtime/' + path.relative_to(package).as_posix() for path in expected
                        if path != package / 'WASMTIME-LICENSE'}:
            raise ValueError('Python runtime wheel private component inventory mismatch')
        return {'actql_local_runtime/' + path.relative_to(package).as_posix(): sha256(path)
                for path in expected if path.suffix in ('.py', '.pyi')}


def sdk_runtime_binding(wheel: Path, original: bytes) -> None:
    """Check the SDK's generated same-source binding, not an execution grant."""
    with zipfile.ZipFile(wheel) as archive:
        name = 'actql_sdk/_local_release_binding.json'
        item = archive.getinfo(name)
        if not 0 < item.file_size <= 65536 or archive.read(item) != original:
            raise ValueError('SDK wheel Local release binding mismatch')


def sdk_host_capacity(wheel: Path, original: bytes) -> None:
    """Verify the exact generated capacity member without adopting or loading it."""
    with zipfile.ZipFile(wheel) as archive:
        item = archive.getinfo('actql_sdk/_local_host_capacity.json')
        if not 0 < item.file_size <= 131072 or archive.read(item) != original:
            raise ValueError('SDK wheel Local Host capacity original mismatch')


def copy_source(source: str, original: Path, target: Path) -> None:
    relative = original.relative_to(ROOT).as_posix()
    expected = subprocess.check_output(['git', 'show', source + ':' + relative], cwd=ROOT)
    if original.is_symlink() or original.read_bytes() != expected:
        raise ValueError('Python wheel source differs from the committed original')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(expected)


def build(artifact: Path, destination: Path, *, version: str, bindings_source: Path | None = None,
          native_libraries: Path | None = None) -> dict[str, object]:
    release = select_release_version(version)
    version = str(release['pythonVersion'])
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Build Python wheels from committed clean source')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    source_version = read_cohort(ROOT)
    subprocess.run(['node', str(ROOT / 'scripts/check-interface-owners.mjs'),
                    '--manifest', 'packages/python-product/pyproject.toml',
                    '--manifest', 'packages/python-sdk/pyproject.toml',
                    '--manifest', 'packages/python-local-runtime/pyproject.toml'],
                   cwd=ROOT, check=True, timeout=60)
    spec = importlib.util.spec_from_file_location('python_runtime_recipe', ROOT / 'scripts/prepare-python-local-runtime.py')
    if spec is None or spec.loader is None:
        raise ValueError('Original Python runtime recipe is unavailable')
    recipe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recipe)
    components = recipe.verify_artifact(artifact)
    original_components = components
    source_artifact_digest = sha256(artifact / 'artifact.json')
    artifact_body = json.loads((artifact / 'artifact.json').read_bytes())
    destination.mkdir()
    stages = destination / 'stages'
    stages.mkdir()
    runtime = stages / 'python-local-runtime'
    recipe.prepare(artifact, runtime, bindings_source=bindings_source, native_libraries=native_libraries)
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
    transforms = []
    for package, distribution in [('python-product', 'actql'), ('python-sdk', 'actql-sdk'),
                                  ('python-local-runtime', 'actql-local-runtime')]:
        path = stages / package / 'pyproject.toml'
        before = path.read_bytes()
        after = release_project_metadata(before, distribution, source_version, version)
        path.write_bytes(after)
        transforms.append({'file': path.relative_to(destination).as_posix(),
                           'before_sha256': hashlib.sha256(before).hexdigest(),
                           'after_sha256': hashlib.sha256(after).hexdigest()})
    runtime_root = runtime / 'src/actql_local_runtime'
    manifest = runtime_root / 'artifact.json'
    before = manifest.read_bytes()
    if hashlib.sha256(before).hexdigest() != source_artifact_digest:
        raise ValueError('Original runtime metadata changed before version staging')
    after = release_runtime_metadata(before, source, source_version, version)
    release_manifest = after
    manifest.write_bytes(after)
    transforms.append({'file': manifest.relative_to(destination).as_posix(),
                       'before_sha256': source_artifact_digest,
                       'after_sha256': hashlib.sha256(after).hexdigest()})
    components = recipe.inspect_local_components(runtime_root, package_version=version)
    if (components.source_sha != original_components.source_sha
            or components.module_sha256 != original_components.module_sha256
            or components.duckdb_sha256 != original_components.duckdb_sha256
            or components.image_sha256 != original_components.image_sha256
            or components.image_bytes != original_components.image_bytes
            or components.engine_recipe_sha256 != original_components.engine_recipe_sha256
            or components.image_recipe != replace(original_components.image_recipe, package_version=version)):
        raise ValueError('Python release staging changed original runtime components or recipe')
    artifact_digest = sha256(manifest)
    capacity = (None if components.image_recipe.runtime_allocation == 'platform'
                else host_capacity_original(source, components))
    binding_body = {'source_sha': source, 'package_version': version,
        'core_abi': artifact_body['core_abi'], 'artifact_sha256': artifact_digest}
    if capacity is None:
        binding_body['runtime_allocation'] = 'platform'
    else:
        binding_body['host_capacity_sha256'] = hashlib.sha256(capacity).hexdigest()
    binding = (json.dumps(binding_body,
        sort_keys=True, indent=2) + '\n').encode('ascii')
    (stages / 'python-sdk/src/actql_sdk/_local_release_binding.json').write_bytes(binding)
    if capacity is not None:
        (stages / 'python-sdk/src/actql_sdk/_local_host_capacity.json').write_bytes(capacity)
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
        verified_components = None
        if distribution == 'actql-sdk':
            sdk_runtime_binding(wheel, binding)
            if capacity is not None:
                sdk_host_capacity(wheel, capacity)
        if distribution == 'actql-local-runtime':
            verified_components = runtime_wheel_components(wheel, artifact, runtime,
                selected_recipe=components.image_recipe, release_manifest=release_manifest)
        wheel_source_correspondence(ROOT, wheel,
            'packages/' + package + '/pyproject.toml', source, verified_components)
        records.append({'distribution': distribution, 'file': wheel.name,
                        'bytes': wheel.stat().st_size, 'sha256': sha256(wheel)})
    if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
        raise ValueError('Python cohort source changed during build')
    # Reinspect the same original artifact after copying/building. Wheel success
    # is component packaging evidence, never Core execution or public acceptance.
    final = recipe.verify_artifact(artifact)
    if final != original_components or sha256(artifact / 'artifact.json') != source_artifact_digest:
        raise ValueError('Python cohort original components changed during build')
    if (manifest.read_bytes() != release_manifest
            or recipe.inspect_local_components(runtime_root, package_version=version) != components):
        raise ValueError('Python release stage changed during wheel construction')
    result: dict[str, object] = {'source_sha': source, 'package_version': version,
        'artifact_sha256': artifact_digest,
        'platform': artifact_body['platform'], 'core_abi': artifact_body['core_abi'],
        'module_sha256': components.module_sha256, 'duckdb_sha256': components.duckdb_sha256,
        'image_sha256': components.image_sha256, 'engine_recipe_sha256': components.engine_recipe_sha256,
        'host_capacity_sha256': None if capacity is None else hashlib.sha256(capacity).hexdigest(),
        'wheels': records, 'release_metadata': {'version': release['version'],
            'source_package_version': source_version, 'source_artifact_sha256': source_artifact_digest,
            'transforms': transforms},
        'runtime_executed': False, 'public_local_accepted': False,
        'recovery_accepted': False, 'published': False}
    (destination / 'cohort.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-directory', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--version', required=True, help='Explicit complete SemVer; mapped by the shared release parser')
    parser.add_argument('--bindings-source', type=Path)
    parser.add_argument('--native-libraries', type=Path)
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.artifact_directory, arguments.destination,
        version=arguments.version, bindings_source=arguments.bindings_source, native_libraries=arguments.native_libraries)))
