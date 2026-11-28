"""Build one clean-source standard product/SDK/runtime wheel cohort; no publication."""
from __future__ import annotations

import argparse
from dataclasses import replace
from email.parser import BytesParser
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path
import subprocess
import sys
import zipfile
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from actql_sdk._local_distribution import _LocalModelCrypto
    from actql_sdk._local_image_recipe import _SelectedImageRecipe

from python_release_cohort import (PYTHON_RUNTIME_REQUIREMENTS, read_cohort, select_release_version,
                                   release_project_metadata, release_runtime_metadata)
from python_interface_inventory import wheel_source_correspondence

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
_DEFAULT_PACKAGING_TARGET = object()
_PAIRED_PLATFORMS = ('linux-x64', 'darwin-arm64')


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


def wheel_metadata(path: Path, name: str, version: str, *, target_platform: str = 'darwin-arm64') -> None:
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
                    'actql-local-runtime': PYTHON_RUNTIME_REQUIREMENTS}[name]
        if sorted(defaults) != sorted(expected):
            raise ValueError('Python cohort wheel default dependencies mismatch')
        if name == 'actql-sdk' and ('local' in body.get_all('Provides-Extra', [])
                or any('actql-local-runtime' in value or 'wasmtime' in value or 'duckdb' in value for value in requirements)):
            raise ValueError('Lightweight SDK wheel contains a Local dependency')
        runtime_tags = {'darwin-arm64': 'py3-none-macosx_11_0_arm64',
                        'linux-x64': 'py3-none-manylinux_2_28_x86_64'}
        if type(target_platform) is not str or target_platform not in runtime_tags:
            raise ValueError('Python cohort wheel has no selected target')
        expected_tag = runtime_tags[target_platform] if name == 'actql-local-runtime' else 'py3-none-any'
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
                             release_manifest: bytes | None = None,
                             model_crypto: _LocalModelCrypto | None = None) -> dict[str, str]:
    """Match the shipped resource bytes to the same verified original artifact."""
    from actql_sdk._local_distribution import _component_target, _MODEL_CRYPTO_NOTICE
    if selected_recipe is not None:
        from actql_sdk._local_image_recipe import _SelectedImageRecipe
        if type(selected_recipe) is not _SelectedImageRecipe:
            raise ValueError('Unavailable original runtime wheel recipe')
    target = _component_target(selected_recipe.platform if selected_recipe is not None else 'darwin-arm64')
    with zipfile.ZipFile(wheel) as archive:
        names = ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
                     'client_host_wasm.wasm', target.duckdb_file,
                     'LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')
        crypto_files = () if model_crypto is None else (model_crypto.file, _MODEL_CRYPTO_NOTICE)
        known_crypto = {_component_target(platform).model_crypto_file for platform in ('darwin-arm64', 'linux-x64')}
        known_crypto.add(_MODEL_CRYPTO_NOTICE)
        observed_crypto = {name.removeprefix('actql_local_runtime/') for name in archive.namelist()
                           if name.startswith('actql_local_runtime/')
                           and name.removeprefix('actql_local_runtime/') in known_crypto}
        if observed_crypto != set(crypto_files):
            raise ValueError('Python runtime wheel Model crypto member inventory mismatch')
        for name in names + crypto_files:
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


def build_source(version: str):
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
    return source, source_version, release, version, recipe


def stage_shared_source(stages: Path, source: str) -> None:
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


def paired_runtime_binding(artifacts: dict[str, Path], *, source: str, source_version: str,
                           version: str, recipe) -> tuple[bytes, dict[str, tuple[object, str]]]:
    if type(artifacts) is not dict or set(artifacts) != set(_PAIRED_PLATFORMS):
        raise ValueError('Select the two original runtime artifacts for a shared Python wheel')
    pins = {}
    originals = {}
    core_abi = None
    module_sha256 = None
    for platform in _PAIRED_PLATFORMS:
        artifact = artifacts[platform]
        selected = recipe.verify_artifact(artifact, target_platform=platform)
        manifest = artifact / 'artifact.json'
        before = manifest.read_bytes()
        digest = hashlib.sha256(before).hexdigest()
        metadata = json.loads(before)
        if (selected.source_sha != source or selected.package_version != source_version
                or selected.artifact_sha256 != digest or metadata['platform'] != platform
                or selected.image_recipe.runtime_allocation != 'platform'
                or type(metadata['core_abi']) is not int):
            raise ValueError('Foreign original runtime for shared Python wheel')
        if core_abi is not None and (metadata['core_abi'] != core_abi
                                     or selected.module_sha256 != module_sha256):
            raise ValueError('Original runtime pair ABI or Wasm module differs')
        core_abi = metadata['core_abi']
        module_sha256 = selected.module_sha256
        versioned = release_runtime_metadata(before, source, source_version, version)
        pins[platform] = hashlib.sha256(versioned).hexdigest()
        originals[platform] = selected, digest
    if len(set(pins.values())) != len(_PAIRED_PLATFORMS):
        raise ValueError('Original runtime pair reuses one artifact')
    binding = {'source_sha': source, 'package_version': version, 'core_abi': core_abi,
               'runtime_allocation': 'platform', 'artifact_sha256_by_platform': pins}
    return (json.dumps(binding, sort_keys=True, indent=2) + '\n').encode('ascii'), originals


def build_shared_wheels(artifacts: dict[str, Path], destination: Path, *, version: str) -> dict[str, object]:
    source, source_version, release, version, recipe = build_source(version)
    binding, originals = paired_runtime_binding(artifacts, source=source,
        source_version=source_version, version=version, recipe=recipe)
    destination.mkdir()
    stages = destination / 'stages'
    stages.mkdir()
    stage_shared_source(stages, source)
    sdk = stages / 'python-sdk/src/actql_sdk/_local_release_binding.json'
    sdk.write_bytes(binding)
    wheels = destination / 'wheels'
    wheels.mkdir()
    records = []
    for package, distribution in (('python-sdk', 'actql-sdk'), ('python-product', 'actql')):
        metadata = stages / package / 'pyproject.toml'
        metadata.write_bytes(release_project_metadata(metadata.read_bytes(), distribution, source_version, version))
        before = set(wheels.glob('*.whl'))
        subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation',
                        '--outdir', str(wheels), str(stages / package)], check=True)
        created = set(wheels.glob('*.whl')) - before
        if len(created) != 1:
            raise ValueError('Shared Python build did not produce one wheel per package')
        wheel = created.pop()
        wheel_metadata(wheel, distribution, version)
        if distribution == 'actql-sdk':
            sdk_runtime_binding(wheel, binding)
        wheel_source_correspondence(ROOT, wheel, 'packages/' + package + '/pyproject.toml', source, None)
        records.append({'distribution': distribution, 'file': wheel.name,
                        'bytes': wheel.stat().st_size, 'sha256': sha256(wheel)})
    after, current = paired_runtime_binding(artifacts, source=source,
        source_version=source_version, version=version, recipe=recipe)
    if (after != binding or current != originals
            or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
        raise ValueError('Shared Python source or runtime originals changed during build')
    receipt = {'source_sha': source, 'package_version': version, 'release_version': release['version'],
               'binding': json.loads(binding), 'wheels': records}
    (destination / 'shared-wheel-cohort.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def read_shared_wheels(directory: Path, *, source: str, version: str,
                       platform: str, artifact: str, core_abi: int) -> tuple[bytes, dict[str, tuple[Path, str]]]:
    from actql_sdk._local_distribution import _read_file, _pairs, _selected_release_binding
    body = json.loads(_read_file(directory / 'shared-wheel-cohort.json', maximum=65536), object_pairs_hook=_pairs)
    if (type(body) is not dict or set(body) != {'source_sha', 'package_version', 'release_version', 'binding', 'wheels'}
            or body['source_sha'] != source or body['package_version'] != version
            or select_release_version(body['release_version'])['pythonVersion'] != version
            or type(body['binding']) is not dict or 'artifact_sha256_by_platform' not in body['binding']
            or body['binding'].get('core_abi') != core_abi
            or type(body['wheels']) is not list or len(body['wheels']) != 2):
        raise ValueError('Shared Python originals are not the selected versioned source')
    binding = (json.dumps(body['binding'], sort_keys=True, indent=2) + '\n').encode('ascii')
    if _selected_release_binding(binding, version, platform) != (source, artifact, True):
        raise ValueError('Selected target runtime differs from the shared SDK original')
    wheels = {}
    for item in body['wheels']:
        if (type(item) is not dict or set(item) != {'distribution', 'file', 'bytes', 'sha256'}
                or item['distribution'] not in ('actql-sdk', 'actql') or item['distribution'] in wheels
                or type(item['file']) is not str or not item['file'].endswith('.whl')
                or Path(item['file']).name != item['file'] or type(item['bytes']) is not int
                or item['bytes'] <= 0 or type(item['sha256']) is not str):
            raise ValueError('Invalid shared Python wheel inventory')
        wheel = directory / 'wheels' / item['file']
        if wheel.is_symlink() or wheel.stat().st_size != item['bytes'] or sha256(wheel) != item['sha256']:
            raise ValueError('Original shared Python wheel changed')
        if item['distribution'] == 'actql-sdk':
            sdk_runtime_binding(wheel, binding)
        wheel_metadata(wheel, item['distribution'], version)
        wheels[item['distribution']] = wheel, item['sha256']
    if len({wheel for wheel, _ in wheels.values()}) != 2:
        raise ValueError('Shared Python roles reuse a wheel member')
    return binding, wheels


def build(artifact: Path, destination: Path, *, version: str, bindings_source: Path | None = None,
          native_libraries: Path | None = None, shared_wheels: Path | None = None,
          target_platform: str | object = _DEFAULT_PACKAGING_TARGET) -> dict[str, object]:
    source, source_version, release, version, recipe = build_source(version)
    if target_platform is _DEFAULT_PACKAGING_TARGET:
        target_platform = recipe._LOCAL_COMPONENT_PLATFORM
    if type(target_platform) is not str:
        raise ValueError('Select a named Python cohort target')
    from actql_sdk._local_distribution import _requires_paired_platform_runtime
    components = recipe.verify_artifact(artifact, target_platform=target_platform)
    if (components.image_recipe.runtime_allocation == 'platform'
            and _requires_paired_platform_runtime(version) and shared_wheels is None):
        raise ValueError('Select the original shared SDK and facade wheels for this runtime')
    original_components = components
    source_artifact_digest = sha256(artifact / 'artifact.json')
    artifact_body = json.loads((artifact / 'artifact.json').read_bytes())
    destination.mkdir()
    stages = destination / 'stages'
    stages.mkdir()
    runtime = stages / 'python-local-runtime'
    recipe.prepare(artifact, runtime, bindings_source=bindings_source, native_libraries=native_libraries, target_platform=target_platform)
    stage_shared_source(stages, source)
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
    components = recipe._inspect_local_components_for_packaging(runtime_root, target_platform=target_platform, package_version=version)
    if (components.source_sha != original_components.source_sha
            or components.module_sha256 != original_components.module_sha256
            or components.duckdb_sha256 != original_components.duckdb_sha256
            or components.image_sha256 != original_components.image_sha256
            or components.image_bytes != original_components.image_bytes
            or components.engine_recipe_sha256 != original_components.engine_recipe_sha256
            or components.model_crypto != original_components.model_crypto
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
    selected_shared = {}
    if shared_wheels is not None:
        if capacity is not None:
            raise ValueError('Shared Python wheels require both original platform allocators')
        binding, selected_shared = read_shared_wheels(shared_wheels, source=source, version=version,
            platform=target_platform, artifact=artifact_digest, core_abi=artifact_body['core_abi'])
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
        if distribution in selected_shared:
            original, digest = selected_shared[distribution]
            staged = wheels / original.name
            with original.open('rb') as source_wheel, staged.open('xb') as target_wheel:
                shutil.copyfileobj(source_wheel, target_wheel, length=65536)
            if sha256(staged) != digest:
                raise ValueError('Shared Python wheel changed while borrowing its original')
        else:
            subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation',
                            '--outdir', str(wheels), str(stages / package)], check=True)
        created = set(wheels.glob('*.whl')) - before
        if len(created) != 1:
            raise ValueError('Python cohort build did not create one wheel per package')
        wheel = created.pop()
        wheel_metadata(wheel, distribution, version, target_platform=target_platform)
        verified_components = None
        if distribution == 'actql-sdk':
            sdk_runtime_binding(wheel, binding)
            if capacity is not None:
                sdk_host_capacity(wheel, capacity)
        if distribution == 'actql-local-runtime':
            verified_components = runtime_wheel_components(wheel, artifact, runtime,
                selected_recipe=components.image_recipe, release_manifest=release_manifest,
                model_crypto=components.model_crypto)
        wheel_source_correspondence(ROOT, wheel,
            'packages/' + package + '/pyproject.toml', source, verified_components)
        records.append({'distribution': distribution, 'file': wheel.name,
                        'bytes': wheel.stat().st_size, 'sha256': sha256(wheel)})
    if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
        raise ValueError('Python cohort source changed during build')
    # Reinspect the same original artifact after copying/building. Wheel success
    # is component packaging evidence, never Core execution or public acceptance.
    final = recipe.verify_artifact(artifact, target_platform=target_platform)
    if final != original_components or sha256(artifact / 'artifact.json') != source_artifact_digest:
        raise ValueError('Python cohort original components changed during build')
    if (manifest.read_bytes() != release_manifest
            or recipe._inspect_local_components_for_packaging(runtime_root, target_platform=target_platform, package_version=version) != components):
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
    from actql_sdk._local_distribution import _LOCAL_COMPONENT_PLATFORM, _LOCAL_COMPONENT_PLATFORMS

    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--artifact-directory', type=Path)
    mode.add_argument('--paired-runtime-artifact', nargs=2, action='append', metavar=('PLATFORM', 'ARTIFACT'))
    parser.add_argument('--shared-wheels', type=Path)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--version', required=True, help='Explicit complete SemVer; mapped by the shared release parser')
    parser.add_argument('--bindings-source', type=Path)
    parser.add_argument('--native-libraries', type=Path)
    parser.add_argument('--target-platform', choices=_LOCAL_COMPONENT_PLATFORMS, default=_LOCAL_COMPONENT_PLATFORM,
                        help='Original artifact target; not an execution-platform or new wheel-tag permission')
    arguments = parser.parse_args()
    if arguments.paired_runtime_artifact is not None:
        selected = {platform: Path(location) for platform, location in arguments.paired_runtime_artifact}
        if len(selected) != len(arguments.paired_runtime_artifact) or arguments.shared_wheels is not None:
            parser.error('Choose exactly two distinct original runtime artifacts')
        print(json.dumps(build_shared_wheels(selected, arguments.destination, version=arguments.version)))
    else:
        print(json.dumps(build(arguments.artifact_directory, arguments.destination,
            version=arguments.version, bindings_source=arguments.bindings_source,
            native_libraries=arguments.native_libraries, shared_wheels=arguments.shared_wheels,
            target_platform=arguments.target_platform)))
