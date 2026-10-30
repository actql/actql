"""Verify the selected Python product/SDK/runtime release composition."""
from pathlib import Path
import tomllib


def select_release_version(value: str) -> dict[str, object]:
    """Use the sole build-time SemVer/PEP 440 projection; no Python grammar fork."""
    import json
    import subprocess

    if type(value) is not str or not 0 < len(value) <= 128:
        raise ValueError('Supply one complete explicit release version')
    result = subprocess.run(['node', str(Path(__file__).with_name('release-version.mjs')), value],
                            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    return json.loads(result.stdout)


def release_project_metadata(original: bytes, distribution: str, source_version: str,
                             version: str) -> bytes:
    """Project only the already-selected version and internal exact pins in staging."""
    import copy
    import json
    import re

    before = tomllib.loads(original.decode('utf-8'))
    project = before['project']
    if project['name'] != distribution or project['version'] != source_version:
        raise ValueError('Python release project differs from its original cohort')
    # Deliberately bounded to the existing literal project fields. A changed
    # source layout needs review, rather than a generic TOML reserializer.
    blocks = re.split(r'(?m)(?=^\[)', original.decode('utf-8'))
    selected = [index for index, body in enumerate(blocks) if body.startswith('[project]\n')]
    if len(selected) != 1:
        raise ValueError('Unavailable original Python project section')
    index = selected[0]
    body = blocks[index]
    old = 'version = ' + json.dumps(source_version)
    if body.count(old + '\n') != 1:
        raise ValueError('Python project version is not the selected literal')
    body = body.replace(old + '\n', 'version = ' + json.dumps(version) + '\n', 1)
    expected = copy.deepcopy(before)
    expected['project']['version'] = version
    if distribution == 'actql':
        dependencies = ['actql-sdk==' + source_version, 'actql-local-runtime==' + source_version]
        if project['dependencies'] != dependencies:
            raise ValueError('Original product dependencies are not the exact cohort')
        for dependency in dependencies:
            old = json.dumps(dependency)
            if body.count(old) != 1:
                raise ValueError('Unavailable original product dependency literal')
            body = body.replace(old, json.dumps(dependency.rsplit('==', 1)[0] + '==' + version), 1)
        expected['project']['dependencies'] = ['actql-sdk==' + version, 'actql-local-runtime==' + version]
    blocks[index] = body
    projected = ''.join(blocks).encode('utf-8')
    if tomllib.loads(projected.decode('utf-8')) != expected:
        raise ValueError('Python release projection changed non-version project fields')
    return projected


def release_runtime_metadata(original: bytes, source: str, source_version: str,
                             version: str) -> bytes:
    """Version-only projection after full artifact admission, before full reinspection.

    This helper is not an artifact verifier or runtime authority. The existing
    original and staged component readers remain mandatory in the builder.
    """
    import json

    def pairs(values):
        body = {}
        for key, value in values:
            if key in body:
                raise ValueError('Duplicate runtime metadata field')
            body[key] = value
        return body

    if type(original) is not bytes or not 0 < len(original) <= 65536:
        raise ValueError('Unavailable original runtime metadata')
    body = json.loads(original, object_pairs_hook=pairs)
    image = body['compiled_image']
    if (body['source_sha'] != source or image['source_sha'] != source
            or body['package_version'] != source_version or image['package_version'] != source_version):
        raise ValueError('Runtime version projection differs from its original context')
    body['package_version'] = image['package_version'] = version
    encoded = (json.dumps(body, indent=2, allow_nan=False) + '\n').encode('utf-8')
    if len(encoded) > 65536:
        raise ValueError('Projected runtime metadata exceeds the original bound')
    return encoded


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


def verify_built_cohort(directory: Path, source: str, version: str, *,
                        frozen_layout: bool = False) -> dict[str, object]:
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
    if set(cohort) not in (fields, fields | {'release_metadata'}):
        raise ValueError('Python cohort does not have the original producer fields')
    if 'release_metadata' in cohort:
        projection = cohort['release_metadata']
        if (type(projection) is not dict or set(projection) != {
                'version', 'source_package_version', 'source_artifact_sha256', 'transforms'}
                or select_release_version(projection['version'])['pythonVersion'] != version
                or type(projection['source_package_version']) is not str
                or not projection['source_package_version']
                or not isinstance(projection['source_artifact_sha256'], str)
                or not re.fullmatch(r'[a-f0-9]{64}', projection['source_artifact_sha256'])):
            raise ValueError('Python release metadata projection is invalid')
        transforms = projection['transforms']
        names = ['stages/python-product/pyproject.toml', 'stages/python-sdk/pyproject.toml',
                 'stages/python-local-runtime/pyproject.toml',
                 'stages/python-local-runtime/src/actql_local_runtime/artifact.json']
        if (type(transforms) is not list or len(transforms) != len(names)
                or any(type(item) is not dict or set(item) != {'file', 'before_sha256', 'after_sha256'}
                       or item['file'] != name
                       or any(not isinstance(item[key], str) or not re.fullmatch(r'[a-f0-9]{64}', item[key])
                              for key in ('before_sha256', 'after_sha256'))
                       for item, name in zip(transforms, names))
                or transforms[-1]['before_sha256'] != projection['source_artifact_sha256']
                or transforms[-1]['after_sha256'] != cohort['artifact_sha256']):
            raise ValueError('Python release metadata transform inventory is invalid')
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
    if type(frozen_layout) is not bool:
        raise ValueError('Select an explicit original or upper-fixed wheel layout')
    wheel_root = root if frozen_layout else root / 'wheels'
    if wheel_root.is_symlink() or not wheel_root.is_dir():
        raise ValueError('Original wheel directory is unavailable')
    for record in records:
        if set(record) != {'distribution', 'file', 'bytes', 'sha256'}:
            raise ValueError('Unexpected Python wheel identity fields')
        name = record['file']
        if (not isinstance(name, str) or Path(name).name != name or '\\' in name
                or not name.endswith('.whl') or name in seen):
            raise ValueError('Invalid Python wheel filename')
        seen.add(name)
        wheel = wheel_root / name
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


def verify_installed_release(plan: dict[str, object], report_path: Path,
                             entry: str, site: Path, *, manager: str = 'pip',
                             project_path: Path | None = None) -> dict[str, object]:
    """Audit original manager evidence and installed bytes; never import product code.

    The caller first cold-verifies the complete original cohort. This reader
    compares that exact wheel material, not a second package/engine verifier.
    It supplies no runtime, Linux, approval or publication acceptance.
    """
    import hashlib
    import csv
    from io import StringIO
    from importlib import metadata
    import json
    import os
    import re
    import stat
    import sys
    from urllib.parse import unquote, urlsplit
    import zipfile

    def normalized(value):
        if type(value) is not str:
            raise ValueError('Unavailable installed distribution name')
        return re.sub(r'[-_.]+', '-', value).lower()

    def stable_file(path, maximum, visit):
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
            before = os.fstat(source.fileno())
            if not stat.S_ISREG(before.st_mode) or not 0 <= before.st_size <= maximum:
                raise ValueError('Unavailable original installed-release file')
            value = visit(source)
            after = os.fstat(source.fileno())
        fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
        if any(getattr(before, field) != getattr(after, field) for field in fields):
            raise ValueError('Original installed-release file changed during audit')
        return value

    def sha_stream(source):
        digest = hashlib.sha256()
        for block in iter(lambda: source.read(65536), b''):
            digest.update(block)
        return digest.hexdigest()

    def child(root, name):
        parts = Path(name).parts
        if (not parts or Path(name).is_absolute() or any(part in ('.', '..') for part in parts)
                or '\\' in name):
            raise ValueError('Installed wheel path leaves its original site')
        path = root
        for part in parts:
            path /= part
            if path.is_symlink():
                raise ValueError('Installed payload is a source/workspace link')
        return path

    if entry not in ('actql', 'actql-sdk') or type(plan) is not dict or manager not in ('pip', 'uv'):
        raise ValueError('Select one exact public Python entry')
    if (not re.fullmatch(r'[a-f0-9]{64}', plan.get('manifestSha256', ''))
            or type(plan.get('artifacts')) is not list):
        raise ValueError('Unavailable original fixed Python install plan')
    artifacts = plan['artifacts']
    if [item['name'] for item in artifacts] != ['actql-sdk', 'actql-local-runtime', 'actql']:
        raise ValueError('Incomplete original Python cohort')
    names = ['actql-sdk'] if entry == 'actql-sdk' else [item['name'] for item in artifacts]
    original_report = stable_file(report_path, 4 * 1024 * 1024, lambda f: f.read())
    def public_wheel(url):
        if type(url) is not str:
            raise ValueError('Unavailable public artifact URL')
        parsed = urlsplit(url)
        if (url != url.strip() or any(ord(c) <= 32 or ord(c) == 127 for c in url)
                or parsed.scheme != 'https' or parsed.netloc != 'files.pythonhosted.org'
                or parsed.username or parsed.password or parsed.query or parsed.fragment
                or not parsed.path.endswith('.whl')):
            raise ValueError('Install did not use an official public wheel origin')
        return unquote(Path(parsed.path).name)

    original_project = None
    if manager == 'pip':
        if project_path is not None:
            raise ValueError('Pip acceptance does not use a uv project')
        report = json.loads(original_report)
        if report.get('version') != '1' or type(report.get('install')) is not list:
            raise ValueError('Select the stable pip installation report format')
        selected = {}
        for item in report['install']:
            name = normalized(item['metadata']['name'])
            if (item.get('is_direct') is not False or item.get('is_yanked') is not False
                    or item.get('requested') is not (name == entry)):
                raise ValueError('Install must request only its public entry without direct/yanked artifacts')
            filename = public_wheel(item['download_info']['url'])
            if name.startswith('actql'):
                if name not in names or name in selected:
                    raise ValueError('Unexpected or duplicate ActQL dependency')
                original = next(value for value in artifacts if value['name'] == name)
                if (item['metadata']['version'] != original['version']
                        or filename != Path(original['path']).name
                        or item['download_info']['archive_info']['hashes']['sha256'] != original['sha256']):
                    raise ValueError('Installed report differs from the fixed original wheel')
                selected[name] = item
        if set(selected) != set(names):
            raise ValueError('Pip report omits the complete selected ActQL graph')
    else:
        if project_path is None:
            raise ValueError('uv acceptance requires its original project and lock')
        original_project = stable_file(project_path, 65536, lambda f: f.read())
        project = tomllib.loads(original_project.decode('utf-8'))
        version = next(value['version'] for value in artifacts if value['name'] == entry)
        minor = str(sys.version_info.major) + '.' + str(sys.version_info.minor)
        expected_project = {'project': {'name': 'release-consumer-check', 'version': '0.0.0',
            'requires-python': '==' + minor + '.*', 'dependencies': [entry + '==' + version]}}
        # uv add can persist the explicit default index. This exact official
        # index is the sole permitted configuration; no source/workspace table.
        indexed_project = {**expected_project, 'tool': {'uv': {'index': [
            {'url': 'https://pypi.org/simple', 'default': True}]}}}
        if project != expected_project and project != indexed_project:
            raise ValueError('uv must request only its exact public entry in the fresh project')
        lock = tomllib.loads(original_report.decode('utf-8'))
        # Do not guess at future lock revisions or marker/fork semantics.
        if (set(lock) != {'version', 'revision', 'requires-python', 'package'}
                or type(lock['version']) is not int or lock['version'] != 1
                or type(lock['revision']) is not int or lock['revision'] != 3
                or lock['requires-python'] != expected_project['project']['requires-python']
                or type(lock['package']) is not list or not 1 <= len(lock['package']) <= 1000):
            raise ValueError('Unavailable selected uv lock format')
        selected = {}
        packages = {}
        roots = []
        for package in lock['package']:
            name = normalized(package['name'])
            if name in packages:
                raise ValueError('Duplicated/forked uv resolution requires a separate audit')
            packages[name] = package
            if name == 'release-consumer-check':
                roots.append(package)
                continue
            if package.get('source') != {'registry': 'https://pypi.org/simple'}:
                raise ValueError('uv resolution contains a non-public or local source')
            if name.startswith('actql'):
                if (name not in names or set(package) - {'name', 'version', 'source', 'dependencies', 'wheels'}
                        or type(package.get('wheels')) is not list or len(package['wheels']) != 1):
                    raise ValueError('Unexpected ActQL uv resolution or artifact alternatives')
                original = next(value for value in artifacts if value['name'] == name)
                wheel = package['wheels'][0]
                if (set(wheel) - {'url', 'hash', 'size', 'upload-time'} or not {'url', 'hash', 'size'} <= set(wheel)
                        or package['version'] != original['version']
                        or public_wheel(wheel['url']) != Path(original['path']).name
                        or wheel['hash'] != 'sha256:' + original['sha256']
                        or type(wheel['size']) is not int or wheel['size'] != original['bytes']):
                    raise ValueError('uv resolution differs from the fixed original wheel')
                selected[name] = package
        expected_root = {'name': 'release-consumer-check', 'version': '0.0.0', 'source': {'virtual': '.'},
            'dependencies': [{'name': entry}],
            'metadata': {'requires-dist': [{'name': entry, 'specifier': '==' + version}]}}
        if roots != [expected_root] or set(selected) != set(names):
            raise ValueError('uv lock omits the complete exact single-entry ActQL graph')
        # Every graph edge must resolve in this finite lock. Conditional third-
        # party edges remain resolution DATA, not proof that every wheel ran.
        for package in packages.values():
            for dependency in package.get('dependencies', []):
                if normalized(dependency['name']) not in packages:
                    raise ValueError('uv resolution has an unresolved dependency')
    if site.is_symlink():
        raise ValueError('Installed site is a source/workspace link')
    site = site.resolve(strict=True)
    distributions = {}
    for distribution in metadata.distributions(path=[str(site)]):
        name = normalized(distribution.metadata['Name'])
        if name.startswith('actql'):
            if name not in names or name in distributions:
                raise ValueError('Installed ActQL namespace is foreign or duplicated')
            distributions[name] = distribution
    if set(distributions) != set(names):
        raise ValueError('Installed ActQL distribution graph differs')
    payloads = []
    expected_roots = set()
    for name in names:
        item = next(value for value in artifacts if value['name'] == name)
        distribution = distributions[name]
        if distribution.version != item['version']:
            raise ValueError('Installed version differs from the original wheel')
        expected = set()
        def inspect(source):
            if os.fstat(source.fileno()).st_size != item['bytes'] or sha_stream(source) != item['sha256']:
                raise ValueError('Original fixed wheel bytes changed')
            source.seek(0)
            with zipfile.ZipFile(source) as archive:
                infos = archive.infolist()
                if len(infos) > 10000 or len({i.filename for i in infos}) != len(infos):
                    raise ValueError('Unavailable bounded original wheel inventory')
                total = 0
                for info in infos:
                    path = child(site, info.filename)
                    mode = info.external_attr >> 16
                    if stat.S_ISLNK(mode) or '.data' in Path(info.filename).parts[0]:
                        raise ValueError('Selected wheel scheme requires separate consumer correspondence')
                    if info.is_dir():
                        continue
                    total += info.file_size
                    if info.file_size > 1024 ** 3 or total > 4 * 1024 ** 3:
                        raise ValueError('Original wheel exceeds the finite consumer audit bound')
                    expected.add(info.filename)
                    if info.filename.endswith('.dist-info/RECORD'):
                        continue  # pip necessarily records its own installation metadata.
                    with archive.open(info) as wheel_file:
                        digest = sha_stream(wheel_file)
                    installed = stable_file(path, info.file_size, sha_stream)
                    if (path.stat().st_size != info.file_size or installed != digest
                            or stat.S_IMODE(path.stat().st_mode) != stat.S_IMODE(mode)):
                        raise ValueError('Installed payload differs from the fixed wheel bytes/mode')
        stable_file(Path(item['path']), item['bytes'], inspect)
        dist_info = next(value.split('/')[0] for value in expected if value.endswith('.dist-info/METADATA'))
        generated = {dist_info + '/INSTALLER'}
        if name == entry or manager == 'uv':
            generated.add(dist_info + '/REQUESTED')
        installer = b'pip\n' if manager == 'pip' else b'uv'
        if stable_file(child(site, dist_info + '/INSTALLER'), 16, lambda f: f.read()) != installer:
            raise ValueError('Unexpected installed wheel installer')
        if (name == entry or manager == 'uv') and stable_file(child(site, dist_info + '/REQUESTED'), 0, lambda f: f.read()) != b'':
            raise ValueError('Unexpected requested-entry marker')
        # importlib.metadata.files intentionally hides missing entries on some
        # supported Python versions. Read the original installed RECORD itself
        # so missing/foreign/duplicate rows cannot disappear from this fence.
        record = stable_file(child(site, dist_info + '/RECORD'), 4 * 1024 * 1024, lambda f: f.read())
        rows = list(csv.reader(StringIO(record.decode('utf-8'))))
        if len(rows) > 10000 or any(len(row) != 3 for row in rows):
            raise ValueError('Invalid bounded installed RECORD')
        recorded = [row[0] for row in rows]
        for path in recorded:
            child(site, path)
        if len(recorded) != len(set(recorded)) or set(recorded) != expected | generated:
            raise ValueError('Installed RECORD inventory differs from the exact wheel plus manager metadata')
        roots = {Path(value).parts[0] for value in expected}
        expected_roots.update(roots)
        actual = set()
        for root in roots:
            for path in child(site, root).rglob('*'):
                if path.is_symlink():
                    raise ValueError('Installed payload contains a linked member')
                if path.is_file():
                    actual.add(path.relative_to(site).as_posix())
        if actual != expected | generated:
            raise ValueError('Installed package has missing or surplus material')
        payloads.append({'name': name, 'version': item['version'], 'sha256': item['sha256'], 'files': len(expected)})
    actual_roots = {path.name for path in site.iterdir() if normalized(path.name).startswith('actql')}
    if actual_roots != expected_roots:
        raise ValueError('Installed ActQL namespace contains unregistered or surplus material')
    if stable_file(report_path, 4 * 1024 * 1024, lambda f: f.read()) != original_report:
        raise ValueError('Original manager evidence changed during audit')
    if original_project is not None and stable_file(project_path, 65536, lambda f: f.read()) != original_project:
        raise ValueError('Original uv project changed during audit')
    return {'entry': entry, 'manifestSha256': plan['manifestSha256'], 'payloads': payloads,
            'manager': manager, 'evidenceKind': 'pip-install-report' if manager == 'pip' else 'uv-resolution-lock',
            ('reportSha256' if manager == 'pip' else 'lockSha256'): hashlib.sha256(original_report).hexdigest(),
            **({'projectSha256': hashlib.sha256(original_project).hexdigest()} if original_project is not None else {}),
            'qualification': 'Original manager evidence and exact installed ActQL wheel bytes only; '
                             'uv lock is resolution, not a download transaction report; '
                             'not engine execution, public Client acceptance or owner approval'}


if __name__ == '__main__':
    import argparse
    import json
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == '--audit-installed':
        import sysconfig
        parser = argparse.ArgumentParser(description='Audit the selected public installed Python wheel bytes')
        parser.add_argument('--audit-installed', type=Path, required=True)
        evidence = parser.add_mutually_exclusive_group(required=True)
        evidence.add_argument('--pip-report', type=Path)
        evidence.add_argument('--uv-lock', type=Path)
        parser.add_argument('--uv-project', type=Path)
        parser.add_argument('--entry', choices=('actql', 'actql-sdk'), required=True)
        arguments = parser.parse_args()
        print(json.dumps(verify_installed_release(
            json.loads(arguments.audit_installed.read_bytes()), arguments.pip_report or arguments.uv_lock,
            arguments.entry, Path(sysconfig.get_path('purelib')),
            manager='uv' if arguments.uv_lock else 'pip', project_path=arguments.uv_project)))
        raise SystemExit(0)
    parser = argparse.ArgumentParser(description='Verify an existing frozen Python wheel cohort; no build or publication')
    parser.add_argument('--verify-directory', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--frozen-layout', action='store_true')
    arguments = parser.parse_args()
    print(json.dumps(verify_built_cohort(arguments.verify_directory, arguments.source, arguments.version,
                                       frozen_layout=arguments.frozen_layout)))
