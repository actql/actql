"""Tiny package DATA for the monitor's installed Native verifier tests.

These bytes are deliberately not a runnable Native distribution. No compiler,
installation command, Native executable or SDK is invoked.
"""
import hashlib
import base64
import importlib.util
import io
import json
from pathlib import Path
import platform
import subprocess
import sys
import tarfile
import tempfile
from contextlib import nullcontext


def run(helper_path, retained=None):
    spec = importlib.util.spec_from_file_location('health_artifacts', helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    key = {('Darwin', 'arm64'): 'darwin-arm64', ('Linux', 'x86_64'): 'linux-x64-gnu'}[
        platform.system(), platform.machine()]
    source = 'a' * 40
    native_calls = 0

    def never_start(*_args, **_kwargs):
        nonlocal native_calls
        native_calls += 1
        raise AssertionError('This source-tool fixture must never execute a child')

    original = subprocess.Popen
    subprocess.Popen = never_start
    try:
        with (tempfile.TemporaryDirectory(prefix='actql-health-native-data-') if retained is None else nullcontext(retained)) as temporary:
            root = Path(temporary)
            consumer = root / 'consumer'
            consumer.mkdir()
            packages = []
            native_name = '@actql/cli-' + key
            authored = {
                'actql': {'package.json': b'{"name":"actql","version":"1.2.3"}\n',
                          'bin/actql.mjs': b'SYNTHETIC LAUNCHER DATA; NEVER EXECUTE\n'},
                native_name: {'package.json': json.dumps({'name': native_name, 'version': '1.2.3'}).encode(),
                              'bin/actql-native-client': b'SYNTHETIC NATIVE DATA; NEVER EXECUTE\n',
                              'lib/libduckdb.test': b'authored bundled library data'},
            }
            for index, (name, files) in enumerate(authored.items()):
                archive = root / f'unit-{index}.tgz'
                entries = []
                prefix = Path() if name == 'actql' else Path('node_modules') / name
                with tarfile.open(archive, 'w:gz') as package:
                    for path, body in files.items():
                        member = tarfile.TarInfo('package/' + path)
                        member.mode, member.size = 0o644, len(body)
                        package.addfile(member, io.BytesIO(body))
                        entries.append(dict(path=path, bytes=len(body), mode=0o644,
                                            sha256=hashlib.sha256(body).hexdigest()))
                        target = consumer / prefix / path
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(body)
                        target.chmod(0o644)
                body = archive.read_bytes()
                packages.append(dict(name=name, file=archive.name, bytes=len(body),
                    sha256=hashlib.sha256(body).hexdigest(),
                    integrity='sha512-' + base64.b64encode(hashlib.sha512(body).digest()).decode(), files=entries))
            manifest = root / 'release.json'
            manifest.write_text(json.dumps(dict(version='actql-native-cli-release/0.1', sourceSha=source,
                                                platforms={key: {}}, packages=packages)))
            observed = helper.inspect_native_installed(manifest, consumer, source)
            assert observed['sourceSha'] == source and observed['platform'] == key
            assert observed['cohortSha256'] == hashlib.sha256(manifest.read_bytes()).hexdigest()
            assert set(observed['packages']) == set(authored)
            for name, files in authored.items():
                assert observed['packages'][name]['installedBytes'] == sum(map(len, files.values()))
                assert observed['packages'][name]['payloads'] == len(files)
            rejected = 0

            def refuses(action, expected, message=None):
                nonlocal rejected
                try:
                    action()
                except expected as error:
                    if message is not None:
                        assert message in str(error), str(error)
                    rejected += 1
                else:
                    raise AssertionError('Invalid installed consumer was accepted')

            inspect = lambda path=consumer, sha=source: helper.inspect_native_installed(manifest, path, sha)
            refuses(lambda: inspect(root / 'absent'), AssertionError, 'Installed consumer')
            native = consumer / 'node_modules' / native_name / 'bin/actql-native-client'
            native.write_bytes(b'changed installed payload')
            refuses(inspect, AssertionError, 'Installed payload differs')
            native.write_bytes(authored[native_name]['bin/actql-native-client'])
            native.unlink()
            target = root / 'linked-data'
            target.write_bytes(authored[native_name]['bin/actql-native-client'])
            native.symlink_to(target)
            refuses(inspect, ValueError, 'Expected installed regular payload')
            native.unlink()
            native.write_bytes(authored[native_name]['bin/actql-native-client'])
            native.chmod(0o644)
            alias = root / 'consumer-alias'
            alias.symlink_to(consumer, target_is_directory=True)
            refuses(lambda: inspect(alias), AssertionError, 'Installed consumer')
            refuses(lambda: inspect(sha='b' * 40), AssertionError)
            assert native_calls == 0
            result = dict(verifiedPackages=2, refusedControls=rejected, childExecutions=native_calls)
            if retained is not None:
                result['fixture'] = dict(manifest=str(manifest), consumer=str(consumer), source=source, observation=observed)
            return result
    finally:
        subprocess.Popen = original


if __name__ == '__main__':
    assert len(sys.argv) in (2, 3)
    print(json.dumps(run(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) == 3 else None)))
