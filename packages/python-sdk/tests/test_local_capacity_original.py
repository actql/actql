"""Independent scalar capacity originals and actual file/ZIP checks; no Engine."""
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock, patch
import zipfile

from actql_sdk._local_capacity_original import (_capacity_from_source,
    _decode_installed_capacity, _encode_installed_capacity, _selected_capacity_original)
from actql_sdk._local_core import LocalCore
from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_distribution as fixture

ROOT = Path(__file__).resolve().parents[3]


class CapacityOriginalTests(unittest.TestCase):
    def setUp(self):
        case = fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        self.directory = case.directory
        self.components = case.inspect()
        # These independent scalar values exercise correspondence only. They
        # are not a product profile, physical allocator or adopted capacity.
        self.body = {'platform': 'darwin-arm64', 'backend': 'wasmtime-precompiled-pooling',
            'allocation_domain': 'host-owned-reserved-capacity',
            'engine_recipe_sha256': self.components.engine_recipe_sha256,
            'host_capacity_bytes': 4096, 'bootstrap_execution_bytes': 16781312,
            'root': {'planning_work': 5, 'attempts': 20, 'holdings': 64,
                'transfer_bytes': 8388608, 'retained_bytes': 16777216, 'execution_bytes': 44445696}}

    def original(self):
        return (json.dumps(self.body, indent=2) + '\n').encode('utf-8')

    def installed(self):
        return _encode_installed_capacity(self.original(), self.components)

    def stage(self):
        encoded = self.installed()
        (self.directory / '_local_host_capacity.json').write_bytes(encoded)
        binding = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0', 'core_abi': 74,
            'artifact_sha256': hashlib.sha256((self.directory / 'artifact.json').read_bytes()).hexdigest(),
            'host_capacity_sha256': hashlib.sha256(encoded).hexdigest()}
        (self.directory / '_local_release_binding.json').write_text(json.dumps(binding))
        return binding

    def test_exact_original_bytes_and_existing_six_field_projection(self):
        encoded = self.installed()
        self.assertEqual(json.loads(encoded)['original'].encode(), self.original())
        original = _decode_installed_capacity(encoded, self.components)
        self.assertEqual((original.host_capacity_bytes, original.bootstrap_execution_bytes), (4096, 16781312))
        self.assertEqual(original.resources.execution_bytes, 44445696)
        self.assertEqual(original.resources.attempts, 20)
        with self.assertRaises(AttributeError): original.host_capacity_bytes = 1

    def test_unknown_zero_wrong_domain_or_unfunded_bootstrap_refuses(self):
        changes = [('host_capacity_bytes', None), ('host_capacity_bytes', 0), ('host_capacity_bytes', True),
            ('bootstrap_execution_bytes', None), ('bootstrap_execution_bytes', 44445697),
            ('backend', 'jit'), ('allocation_domain', 'universal-rss'),
            ('platform', 'linux-x64'), ('engine_recipe_sha256', 'b' * 64), ('extra', 0)]
        for field, value in changes:
            with self.subTest(field=field, value=value):
                body = {**self.body, field: value}
                with self.assertRaises(LocalInstallationError):
                    _capacity_from_source(json.dumps(body).encode(), self.components)
        for field, value in [('execution_bytes', 44445695), ('attempts', 2), ('holdings', True)]:
            body = {**self.body, 'root': {**self.body['root'], field: value}}
            with self.subTest(field=field), self.assertRaises(LocalInstallationError):
                _capacity_from_source(json.dumps(body).encode(), self.components)

    def test_foreign_release_context_duplicate_fields_and_wrong_revision_refuse(self):
        encoded = self.installed(); body = json.loads(encoded)
        for field, value in [('source_sha', 'b' * 40), ('package_version', 'foreign'), ('core_abi', 72),
                ('core_abi', True), ('module_sha256', 'a' * 64), ('engine_recipe_sha256', 'c' * 64)]:
            with self.subTest(field=field), self.assertRaises(LocalInstallationError):
                _decode_installed_capacity(json.dumps({**body, field: value}).encode(), self.components)
        with self.assertRaises(LocalInstallationError):
            _capacity_from_source(b'{"host_capacity_bytes":4096,' + self.original()[1:], self.components)
        with self.assertRaises(LocalInstallationError):
            _decode_installed_capacity(b'{"source_sha":"' + b'a' * 40 + b'",' + encoded[1:], self.components)

    def test_disjoint_bootstrap_and_installation_use_the_maximum_not_the_sum(self):
        self.body['bootstrap_execution_bytes'] = 44445696
        original = _capacity_from_source(self.original(), self.components)
        self.assertEqual(original.resources.execution_bytes, 44445696)
        self.assertEqual(original.host_capacity_bytes, 4096)
        # The bootstrap peak may exceed VM plus the later resident baseline.
        # Both phases fit the original ceiling independently; there is no
        # simultaneous bootstrap + installation reservation in this fixture.
        self.assertGreater(original.bootstrap_execution_bytes, 16777216 + 4096)
        self.body['root']['execution_bytes'] = 44445695
        with self.assertRaises(LocalInstallationError):
            _capacity_from_source(self.original(), self.components)
        self.body['root']['execution_bytes'] = 44445696
        self.body['bootstrap_execution_bytes'] = 44445697
        with self.assertRaises(LocalInstallationError):
            _capacity_from_source(self.original(), self.components)

    def test_installed_original_digest_symlink_and_component_binding_are_fenced(self):
        self.stage()
        with patch('actql_sdk._local_capacity_original.resources.files', return_value=self.directory):
            self.assertEqual(_selected_capacity_original(self.components).host_capacity_bytes, 4096)
            raw = (self.directory / '_local_host_capacity.json').read_bytes()
            (self.directory / '_local_host_capacity.json').write_bytes(raw + b' ')
            with self.assertRaises(LocalInstallationError): _selected_capacity_original(self.components)
            (self.directory / '_local_host_capacity.json').unlink()
            (self.directory / '_local_host_capacity.json').symlink_to(self.directory / 'engine-recipe.json')
            with self.assertRaises(LocalInstallationError): _selected_capacity_original(self.components)
            with self.assertRaises(LocalInstallationError):
                _selected_capacity_original(replace(self.components, source_sha='c' * 40))

    def test_public_capacity_declaration_cannot_replace_physical_worker_funding(self):
        from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
        self.stage(); core = Mock()
        with patch('actql_sdk._local_capacity_original.resources.files', return_value=self.directory), \
                patch('actql_sdk._local_product.installed_local_components', return_value=self.components) as resolve, \
                patch.object(LocalCore, '_from_installed_image', return_value=core) as construct, \
                patch('actql_sdk._local_product._default_directory', return_value=self.directory), \
                patch.object(InstalledLocalHost, '__init__', return_value=None):
            with self.assertRaises(LocalWorkerFundingUnavailable): InstalledLocalHost.installed()
        resolve.assert_not_called()
        # Independently valid release-bound declaration, but no actual physical
        # supplier. No Engine/Root may be constructed from these numbers alone.
        original = _capacity_from_source(self.original(), self.components)
        self.assertEqual(original.host_capacity_bytes, 4096)
        construct.assert_not_called()

    def test_missing_or_foreign_original_refuses_before_vm_and_store(self):
        self.stage(); (self.directory / '_local_host_capacity.json').unlink()
        with patch('actql_sdk._local_capacity_original.resources.files', return_value=self.directory), \
                patch('actql_sdk._local_product.installed_local_components', return_value=self.components) as resolve, \
                patch.object(LocalCore, '_from_installed_image', side_effect=AssertionError('VM')) as construct, \
                patch('actql_sdk._local_product._default_directory', side_effect=AssertionError('Store')) as store:
            with self.assertRaises(LocalInstallationError): _selected_capacity_original(self.components)
            with self.assertRaises(LocalWorkerFundingUnavailable): InstalledLocalHost.installed()
        resolve.assert_not_called()
        self.assertEqual((construct.call_count, store.call_count), (0, 0))

    def script(self):
        spec = importlib.util.spec_from_file_location('capacity_cohort_recipe', ROOT / 'scripts/build-python-product-wheels.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    def test_wheel_capacity_member_is_exact_and_not_an_engine_acceptance(self):
        script = self.script(); encoded = self.installed()
        with TemporaryDirectory() as directory:
            wheel = Path(directory) / 'independent-fixture.whl'
            for value in (encoded, encoded + b' ', b'foreign'):
                with zipfile.ZipFile(wheel, 'w') as archive:
                    archive.writestr('actql_sdk/_local_host_capacity.json', value)
                if value == encoded: script.sdk_host_capacity(wheel, encoded)
                else:
                    with self.assertRaises(ValueError): script.sdk_host_capacity(wheel, encoded)

    def test_recipe_requires_exact_committed_original_before_any_wheel_build(self):
        script = self.script()
        with TemporaryDirectory() as directory, patch.object(script, 'ROOT', Path(directory)):
            path = Path(directory) / 'packages/python-local-runtime/selected-host-capacity.json'
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                script.host_capacity_original('a' * 40, self.components)
            path.parent.mkdir(parents=True); path.write_bytes(self.original())
            with patch.object(script.subprocess, 'check_output', side_effect=[b'original-blob', b'foreign-blob']):
                with self.assertRaisesRegex(ValueError, 'committed'):
                    script.host_capacity_original('a' * 40, self.components)
            with patch.object(script.subprocess, 'check_output', return_value=b'original-blob'):
                self.assertEqual(script.host_capacity_original('a' * 40, self.components), self.installed())
