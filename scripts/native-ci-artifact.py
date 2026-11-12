"""Transfer one same-run Native software preparation, never application state."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import tarfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require_preparation(record, selected):
    target = {('Linux', 'x86_64'): 'linux-x64', ('Darwin', 'arm64'): 'darwin-arm64'}.get(tuple(selected['target']))
    if record.get('source') != selected['source'] or target is None or record.get('target') != target:
        raise ValueError('Original Native preparation source/target mismatch')


def context(repository, environment):
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
    if not re.fullmatch('[0-9a-f]{40}', source) or source != environment.get('GITHUB_SHA'):
        raise ValueError('Current Native artifact source mismatch')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=repository, text=True):
        raise ValueError('Clean Native artifact source required')
    for key in ['GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT']:
        if not re.fullmatch('[1-9][0-9]*', environment.get(key, '')):
            raise ValueError('Same-run Native artifact context required')
    image = environment.get('ImageVersion')
    if not isinstance(image, str) or not image.strip() or image != image.strip():
        raise ValueError('Exact hosted Native runner image required')
    return {'source': source, 'run': environment['GITHUB_RUN_ID'],
            'attempt': environment['GITHUB_RUN_ATTEMPT'], 'workspace': str(repository.resolve()),
            'target': [platform.system(), platform.machine()],
            'image': image,
            'toolchain': digest(repository / 'toolchain.json')}


def seal(preparation, output, selected):
    preparation = preparation.resolve(strict=True)
    record = json.loads((preparation / 'preparation.json').read_text())
    require_preparation(record, selected)
    if preparation.name != 'native-scoped-preparation':
        raise ValueError('Original Native preparation required')
    output.mkdir(mode=0o700)
    archive = output / 'software.tar.gz'
    # No test, Store or credential operation has run in this producer. Retain
    # the complete prepared tree: existing receipts keep their absolute paths.
    with tarfile.open(archive, 'w:gz', compresslevel=1, dereference=False) as stream:
        stream.add(preparation, arcname=preparation.name)
    manifest = {'version': 'actql-native-ci-inputs/0.1', 'context': selected,
                'preparation': str(preparation), 'bytes': archive.stat().st_size,
                'sha256': digest(archive)}
    (output / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True) + '\n')
    return manifest


def restore(artifact, parent, selected):
    parent = parent.resolve(strict=True)
    manifest = json.loads((artifact / 'manifest.json').read_text())
    archive = artifact / 'software.tar.gz'
    destination = parent / 'native-scoped-preparation'
    if (manifest.get('version') != 'actql-native-ci-inputs/0.1' or manifest.get('context') != selected
            or manifest.get('preparation') != str(destination)
            or manifest.get('bytes') != archive.stat().st_size or manifest.get('sha256') != digest(archive)):
        raise ValueError('Native artifact identity mismatch; rebuilding is not a fallback')
    if destination.exists() or destination.is_symlink():
        raise ValueError('Native artifact destination already exists')
    with tarfile.open(archive, 'r:gz') as stream:
        members = stream.getmembers()
        names = set()
        links = set()
        for item in members:
            path = PurePosixPath(item.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                    or item.name.rstrip('/') != path.as_posix() or '\\' in item.name
                    or path.parts[0] != destination.name or item.name in names
                    or item.mode & ~0o777 or not (item.isfile() or item.isdir() or item.issym() or item.islnk())):
                raise ValueError('Unsafe Native software archive member')
            names.add(item.name)
            if item.issym() or item.islnk():
                links.add(path)
                target = ((parent / item.name).parent / item.linkname if item.issym()
                          else parent / item.linkname).resolve()
                if not target.is_relative_to(destination):
                    raise ValueError('Native software link leaves its preparation')
            # Python's data filter rejects outside/absolute link targets and
            # devices before any member is extracted.
            tarfile.data_filter(item, str(parent))
        for item in members:
            if any(link in PurePosixPath(item.name).parents for link in links):
                raise ValueError('Native software archive traverses a link')
        stream.extractall(parent, members=members, filter='data')
        # Preserve original ordinary file/directory modes after safe extraction;
        # neither file ownership nor privileged permission bits are transferred.
        for item in reversed(members):
            if item.isfile() or item.isdir():
                os.chmod(parent / item.name, item.mode)
    record = json.loads((destination / 'preparation.json').read_text())
    require_preparation(record, selected)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['seal', 'restore'])
    parser.add_argument('--artifact', type=Path, required=True)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    selected = context(repository, os.environ)
    parent = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    if args.operation == 'seal':
        seal(parent / 'native-scoped-preparation', args.artifact, selected)
    else:
        destination = restore(args.artifact, parent, selected)
        # Existing consumers still validate every original compiler/input/body
        # descriptor before reuse; the archive is not a replacement verifier.
        with open(os.environ['GITHUB_ENV'], 'a') as stream:
            stream.write(f'ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION={destination}\n')
            stream.write(f'ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT={destination}/http/component/build.json\n')


if __name__ == '__main__':
    main()
