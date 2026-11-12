import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('native_ci_artifact', Path(__file__).with_name('native-ci-artifact.py'))
artifact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact)


class NativeSoftwareTransfer(unittest.TestCase):
    def fixture(self, directory):
        parent = Path(directory)
        preparation = parent / 'native-scoped-preparation'
        preparation.mkdir(mode=0o700)
        (preparation / 'preparation.json').write_text(json.dumps({'source': 'a' * 40, 'target': 'linux-x64'}))
        (preparation / 'original.exe').write_bytes(b'original compiled software')
        (preparation / 'original.exe').chmod(0o700)
        (preparation / 'alias').symlink_to('original.exe')
        selected = {'source': 'a' * 40, 'run': '12', 'attempt': '2',
                    'workspace': '/same/checkout', 'target': ['Linux', 'x86_64'],
                    'toolchain': 'b' * 64, 'image': 'exact-image'}
        output = parent / 'artifact'
        artifact.seal(preparation, output, selected)
        preparation.rename(parent / 'retained-original')
        return parent, output, selected

    def test_exact_software_paths_bytes_modes_and_internal_links(self):
        with tempfile.TemporaryDirectory() as directory:
            parent, output, selected = self.fixture(directory)
            restored = artifact.restore(output, parent, selected)
            self.assertEqual(restored.name, 'native-scoped-preparation')
            for name in ['preparation.json', 'original.exe']:
                original = parent / 'retained-original' / name
                self.assertEqual((restored / name).read_bytes(), original.read_bytes())
                self.assertEqual((restored / name).stat().st_mode, original.stat().st_mode)
            self.assertEqual((restored / 'alias').readlink(), Path('original.exe'))
            with self.assertRaisesRegex(ValueError, 'already exists'):
                artifact.restore(output, parent, selected)

    def test_source_attempt_platform_toolchain_workspace_and_image_cannot_be_substituted(self):
        with tempfile.TemporaryDirectory() as directory:
            parent, output, selected = self.fixture(directory)
            for field in selected:
                changed = copy.deepcopy(selected)
                changed[field] = ['other'] if field == 'target' else 'other'
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'identity mismatch'):
                    artifact.restore(output, parent, changed)
                self.assertFalse((parent / 'native-scoped-preparation').exists())
            with (output / 'software.tar.gz').open('ab') as stream:
                stream.write(b'changed archive')
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                artifact.restore(output, parent, selected)

    def test_unsafe_members_and_link_traversal_refuse_before_extraction(self):
        for name, target in [('../outside', None), ('/outside', None),
                             ('native-scoped-preparation/../outside', None),
                             ('native-scoped-preparation//ambiguous', None),
                             ('native-scoped-preparation/alias', '/outside'),
                             ('native-scoped-preparation/alias', '../outside')]:
            with self.subTest(name=name, target=target), tempfile.TemporaryDirectory() as directory:
                parent, output, selected = self.fixture(directory)
                archive = output / 'software.tar.gz'
                with tarfile.open(archive, 'w:gz') as stream:
                    member = tarfile.TarInfo(name)
                    if target:
                        member.type = tarfile.SYMTYPE
                        member.linkname = target
                        stream.addfile(member)
                        child = tarfile.TarInfo(name + '/child')
                        child.size = 1
                        stream.addfile(child, io.BytesIO(b'x'))
                    else:
                        member.size = 1
                        stream.addfile(member, io.BytesIO(b'x'))
                manifest_path = output / 'manifest.json'
                manifest = json.loads(manifest_path.read_text())
                manifest.update(bytes=archive.stat().st_size, sha256=artifact.digest(archive))
                manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises((ValueError, tarfile.FilterError)):
                    artifact.restore(output, parent, selected)
                self.assertFalse((parent / 'native-scoped-preparation').exists())


if __name__ == '__main__':
    unittest.main()
