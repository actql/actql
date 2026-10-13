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
