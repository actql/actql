"""Private bundle closure counterexamples. Synthetic bytes never establish ABI use."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('sqlite_bundle',
    Path(__file__).with_name('produce-python-sqlite-component.py'))
assert SPEC and SPEC.loader
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
from actql_sdk._local_distribution import LocalInstallationError  # noqa: E402
SOURCE, PROVIDER_SOURCE = '1' * 40, '2' * 40
UPSTREAM = '2025-11-04 19:38:17 fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b'


def dylib_command(code, name):
    raw = name + b'\0'
    length = (24 + len(raw) + 3) & ~3
    return struct.pack('<6I', code, length, 24, 0, 0, 0) + raw.ljust(length - 24, b'\0')


def binary(name, dependencies=(), rpath=None):
    commands = [struct.pack('<6I', 0x32, 24, 1, 11 << 16, 26 << 16, 0),
                dylib_command(0xd, name)]
    commands += [dylib_command(0xc, dep) for dep in dependencies]
    if rpath is not None:
        raw = rpath + b'\0'
        length = (12 + len(raw) + 3) & ~3
        commands.append(struct.pack('<3I', 0x8000001c, length, 12) + raw.ljust(length - 12, b'\0'))
    body = b''.join(commands)
    return struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 6, len(commands), len(body), 0, 0) + body


def member(name, raw):
    return {'file': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


class SQLiteBundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.library = binary(('@rpath/' + P.LIBRARY).encode(),
                              (('@loader_path/' + P.PROVIDER).encode(),))
        self.provider = binary(('@rpath/' + P.PROVIDER).encode())
        self.body = {'version': 'actql-python-sqlite-component-candidate/0.1',
            'source_sha': SOURCE, 'provider_source_sha': PROVIDER_SOURCE,
            'platform': 'darwin-arm64', 'deployment_target': '11.0', 'component_api_abi': 3,
            'upstream_source_id': UPSTREAM,
            'recipe_sha256': hashlib.sha256((P.SOURCE / 'source.json').read_bytes()).hexdigest(),
            'library': member(P.LIBRARY, self.library), 'provider': member(P.PROVIDER, self.provider),
            'notice': member(P.NOTICE, b'original public domain notice\n'),
            'cohort_compatible': False, 'normal_profile': None, 'loaded': False, 'initialized': False}
        for name, raw in [(P.LIBRARY, self.library), (P.PROVIDER, self.provider),
                           (P.NOTICE, b'original public domain notice\n')]:
            (self.root / name).write_bytes(raw)
        self.persist()

    def persist(self):
        (self.root / 'sqlite-component.json').write_text(json.dumps(self.body))

    def verify(self):
        return P.verify_bundle(self.root, source=SOURCE, provider_source=PROVIDER_SOURCE,
                               provider_sha256=hashlib.sha256(self.provider).hexdigest())

    def provider_record(self):
        return {'source': SOURCE, 'target': 'aarch64-apple-darwin', 'deployment_target': '11.0',
                'normal_numeric_profile': None, 'initializer_calls': 0,
                'allocator_source': {'kind': 'derived-scoped-read', 'outputs': {
                    'owned_capacity.h': P.identity(P.ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536)}},
                'library': {'path': str(self.root / P.PROVIDER), **{
                    key: self.body['provider'][key] for key in ('bytes', 'sha256')}}}

    def test_same_source_default_and_retained_source_are_separate(self):
        original = self.provider_record()
        self.assertEqual(P.selected_provider(original, SOURCE, None)[0], self.root / P.PROVIDER)
        with self.assertRaisesRegex(ValueError, 'exact source'):
            P.selected_provider(original, PROVIDER_SOURCE, None)
        self.assertEqual(P.selected_provider(original, PROVIDER_SOURCE, SOURCE)[0], self.root / P.PROVIDER)
        with self.assertRaisesRegex(ValueError, 'exact source'):
            P.selected_provider(original, PROVIDER_SOURCE, '3' * 40)

    def test_original_provider_requires_matching_scoped_abi_before_build(self):
        original = self.provider_record()
        variants = []
        for field, value in [('target', 'x86_64-apple-darwin'), ('initializer_calls', False),
                             ('initializer_calls', 1), ('normal_numeric_profile', 64)]:
            variants.append(original | {field: value})
        changed = copy.deepcopy(original)
        changed['allocator_source']['kind'] = 'selected-stock'; variants.append(changed)
        changed = copy.deepcopy(original)
        changed['allocator_source']['outputs']['owned_capacity.h']['sha256'] = '0' * 64; variants.append(changed)
        changed = copy.deepcopy(original)
        changed['library']['path'] = '../foreign'; variants.append(changed)
        for variant in variants:
            with self.subTest(variant=variant):
                with self.assertRaises(ValueError): P.selected_provider(variant, SOURCE, None)

    def test_relocatable_bundle_is_inspection_not_library_loading(self):
        result = self.verify()
        self.assertIs(result['cohort_compatible'], False)
        self.assertIsNone(result['normal_profile'])
        self.assertIs(result['loaded'], False)
        self.assertIs(result['initialized'], False)

    def test_source_abi_and_no_authority_flags_cannot_be_relabelled(self):
        original = copy.deepcopy(self.body)
        for key, value in [('source_sha', PROVIDER_SOURCE), ('component_api_abi', True),
                           ('component_api_abi', 1), ('component_api_abi', 2), ('upstream_source_id', 'stock'),
                           ('recipe_sha256', '0' * 64), ('loaded', 0), ('initialized', True),
                           ('normal_profile', 64), ('cohort_compatible', True), ('extra', 'ignored')]:
            with self.subTest(key=key, value=value):
                self.body = original | {key: value}; self.persist()
                with self.assertRaises(ValueError): self.verify()

    def test_wrong_provider_body_is_not_the_original_provider(self):
        self.body['provider']['sha256'] = '0' * 64; self.persist()
        with self.assertRaises((ValueError, LocalInstallationError)): self.verify()

    def test_member_corruption_and_truncation_refuse(self):
        for name in (P.LIBRARY, P.PROVIDER, P.NOTICE):
            path = self.root / name; raw = path.read_bytes()
            for changed in (b'x' * len(raw), raw[:-1]):
                with self.subTest(name=name, changed=changed[:5]):
                    path.write_bytes(changed)
                    with self.assertRaises((ValueError, LocalInstallationError)): self.verify()
            path.write_bytes(raw)

    def test_member_name_and_symlink_do_not_escape_owned_bundle(self):
        for key in ('library', 'provider', 'notice'):
            original = copy.deepcopy(self.body)
            self.body[key]['file'] = '../outside'; self.persist()
            with self.assertRaisesRegex(ValueError, 'descriptor'): self.verify()
            self.body = original; self.persist()
        path = self.root / P.LIBRARY; path.unlink()
        outside = self.root / 'outside'; outside.write_bytes(self.library); path.symlink_to(outside)
        with self.assertRaises(OSError): self.verify()

    def test_matching_hash_does_not_admit_development_rpath(self):
        wrong = binary(('@rpath/' + P.LIBRARY).encode(),
                       (('@loader_path/' + P.PROVIDER).encode(),), b'/private/development-provider')
        (self.root / P.LIBRARY).write_bytes(wrong)
        self.body['library'] = member(P.LIBRARY, wrong); self.persist()
        with self.assertRaisesRegex(ValueError, 'search path'): self.verify()

    def test_matching_hash_does_not_admit_provider_search_or_extra_rpath(self):
        for dependency, rpath in ((('@rpath/' + P.PROVIDER).encode(), b'@loader_path'),
                                   (('@loader_path/' + P.PROVIDER).encode(), b'@loader_path')):
            with self.subTest(dependency=dependency, rpath=rpath):
                wrong = binary(('@rpath/' + P.LIBRARY).encode(), (dependency,), rpath)
                (self.root / P.LIBRARY).write_bytes(wrong)
                self.body['library'] = member(P.LIBRARY, wrong)
                self.persist()
                with self.assertRaises(ValueError): self.verify()

    def test_duplicate_manifest_field_refuses(self):
        path = self.root / 'sqlite-component.json'
        path.write_text(json.dumps(self.body)[:-1] + ', "loaded": false}')
        with self.assertRaises((ValueError, LocalInstallationError)): self.verify()

    def test_copy_never_overwrites_original_or_existing_output(self):
        source, target = self.root / P.NOTICE, self.root / 'copy'
        expected = self.body['notice']
        P.checked_copy(source, target, expected, 1024)
        self.assertEqual(target.read_bytes(), source.read_bytes())
        with self.assertRaises(FileExistsError): P.checked_copy(source, target, expected, 1024)
        with self.assertRaises(FileExistsError): P.checked_copy(source, source, expected, 1024)
        self.assertEqual(source.read_bytes(), b'original public domain notice\n')

    def test_sdk_dependency_records_in_sdk_alias_only(self):
        sdk = self.root / 'selected-sdk'; sdk.mkdir()
        header = sdk / 'pthread'; header.mkdir()
        actual = header / 'pthread.h'; actual.write_bytes(b'selected header\n')
        alias = sdk / 'pthread.h'; alias.symlink_to('pthread/pthread.h')
        observed = P.compiled_input(alias, sdk)
        self.assertEqual(observed, {'resolved_path': str(actual),
                                   **P.identity(actual, 1024)})
        alias.unlink(); alias.symlink_to(self.root / P.NOTICE)
        with self.assertRaisesRegex(ValueError, 'escapes selected SDK'):
            P.compiled_input(alias, sdk)

    def test_non_sdk_dependency_keeps_no_follow_rule(self):
        alias = self.root / 'source.h'; alias.symlink_to(self.root / P.NOTICE)
        sdk = self.root / 'other-sdk'; sdk.mkdir()
        with self.assertRaises(OSError):
            P.compiled_input(alias, sdk)


if __name__ == '__main__':
    unittest.main()
