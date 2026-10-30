"""Verify the selected Python product/SDK/runtime release composition."""
from pathlib import Path
import tomllib


def read_cohort(root: Path) -> str:
    projects = [tomllib.loads((root / 'packages' / name / 'pyproject.toml').read_text())['project']
                for name in ('python-product', 'python-sdk', 'python-local-runtime')]
    product, sdk, runtime = projects
    version = sdk['version']
    if (type(version) is not str or not version
            or [value['name'] for value in projects] != ['actql', 'actql-sdk', 'actql-local-runtime']
            or any(value['version'] != version for value in projects)
            or any(value['requires-python'] != sdk['requires-python'] for value in projects)
            or product['dependencies'] != ['actql-sdk==' + version, 'actql-local-runtime==' + version]
            or sdk['dependencies'] != ['httpx==0.28.1', 'rfc8785==0.1.4']
            or 'local' in sdk.get('optional-dependencies', {})
            or runtime['dependencies'] != ['wasmtime==38.0.0']):
        raise ValueError('Python standard product/SDK/runtime do not form the selected release cohort')
    return version


def verify_built_cohort(directory: Path, source: str, version: str) -> dict[str, object]:
    """Reobserve actual wheel bytes/metadata without loading a runtime or publishing.

    The producer's component/source correspondence and actual install acceptance
    remain separate evidence. Reuse its existing wheel metadata rules here;
    this is not another wheel/parser implementation or Linux support claim.
    """
    import hashlib
    import importlib.util
    import json
    import re

    if not re.fullmatch(r'[a-f0-9]{40}', source) or not version:
        raise ValueError('Expected the fixed source and explicit Python package version')
    root = directory.resolve(strict=True)
    manifest_path = root / 'cohort.json'
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError('Missing original Python cohort manifest')
    original = manifest_path.read_bytes()
    cohort = json.loads(original)
    fields = {'source_sha', 'package_version', 'artifact_sha256', 'platform', 'core_abi',
              'module_sha256', 'duckdb_sha256', 'image_sha256', 'engine_recipe_sha256',
              'host_capacity_sha256', 'wheels', 'runtime_executed',
              'public_local_accepted', 'recovery_accepted', 'published'}
    if set(cohort) != fields:
        raise ValueError('Python cohort does not have the original producer fields')
    for key in ('artifact_sha256', 'module_sha256', 'duckdb_sha256', 'image_sha256', 'engine_recipe_sha256'):
        if not isinstance(cohort[key], str) or not re.fullmatch(r'[a-f0-9]{64}', cohort[key]):
            raise ValueError('Python cohort component digest is invalid')
    if (cohort['host_capacity_sha256'] is not None
            and (not isinstance(cohort['host_capacity_sha256'], str)
                 or not re.fullmatch(r'[a-f0-9]{64}', cohort['host_capacity_sha256']))):
        raise ValueError('Python cohort Host capacity digest is invalid')
    if type(cohort['core_abi']) is not int or cohort['core_abi'] <= 0:
        raise ValueError('Python cohort ABI is unavailable')
    if any(cohort[key] is not False for key in
           ('runtime_executed', 'public_local_accepted', 'recovery_accepted', 'published')):
        raise ValueError('Packaging manifest cannot supply runtime or publication acceptance')
    if cohort.get('source_sha') != source or cohort.get('package_version') != version:
        raise ValueError('Python cohort differs from the selected source/version')
    # The current producer and its shared wheel checker have one actual
    # macOS-arm64 layout. Never infer Linux/other-profile readiness from it.
    if cohort.get('platform') != 'darwin-arm64':
        raise ValueError('Python cohort platform has no selected existing verifier')
    records = cohort.get('wheels')
    if (not isinstance(records, list) or [record.get('distribution') for record in records]
            != ['actql-sdk', 'actql-local-runtime', 'actql']):
        raise ValueError('Python release must retain the complete dependency-ordered cohort')
    specification = importlib.util.spec_from_file_location(
        'actql_existing_wheel_verifier', Path(__file__).with_name('build-python-product-wheels.py'))
    if specification is None or specification.loader is None:
        raise ValueError('Original wheel verifier is unavailable')
    verifier = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(verifier)
    seen = set()
    if (root / 'wheels').is_symlink() or not (root / 'wheels').is_dir():
        raise ValueError('Original wheel directory is unavailable')
    for record in records:
        if set(record) != {'distribution', 'file', 'bytes', 'sha256'}:
            raise ValueError('Unexpected Python wheel identity fields')
        name = record['file']
        if (not isinstance(name, str) or Path(name).name != name or '\\' in name
                or not name.endswith('.whl') or name in seen):
            raise ValueError('Invalid Python wheel filename')
        seen.add(name)
        wheel = root / 'wheels' / name
        if wheel.is_symlink() or not wheel.is_file():
            raise ValueError('Python release wheel is unavailable')
        if (type(record['bytes']) is not int or record['bytes'] <= 0
                or wheel.stat().st_size != record['bytes']
                or verifier.sha256(wheel) != record['sha256']):
            raise ValueError('Python release wheel bytes changed')
        verifier.wheel_metadata(wheel, record['distribution'], version)
    if manifest_path.read_bytes() != original:
        raise ValueError('Python cohort manifest changed during verification')
    return {'qualification': 'existing wheel metadata and frozen-byte verification only; '
            'not component execution, install, Linux or public acceptance',
            'manifest_sha256': hashlib.sha256(original).hexdigest(), 'cohort': cohort}


if __name__ == '__main__':
    import argparse
    import json
    parser = argparse.ArgumentParser(description='Verify an existing frozen Python wheel cohort; no build or publication')
    parser.add_argument('--verify-directory', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--version', required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify_built_cohort(arguments.verify_directory, arguments.source, arguments.version)))
