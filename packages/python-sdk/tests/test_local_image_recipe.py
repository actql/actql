"""Independent image/recipe refusal fixtures; no Wasmtime compile or deserialize."""
from dataclasses import FrozenInstanceError, replace
import copy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LOCAL_CORE_ABI
from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_image_recipe import _SelectedImageRecipe, _image_descriptor, _load_selected_image, _recipe_from_original


class LocalImageRecipeTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.image = b'independent fixture image; not executable'
        (self.root / 'client_host_wasm.cwasm').write_bytes(self.image)
        # These scalar test values are not an adopted product capacity profile.
        from image_fixture import ENGINE
        self.engine = copy.deepcopy(ENGINE)
        encoded = json.dumps(self.engine, sort_keys=True, separators=(',', ':')).encode('ascii')
        self.recipe = _SelectedImageRecipe('a' * 40, '0.0.0.dev0', 'b' * 64,
                                         'c' * 64, encoded, len(self.image), len(b'independent runtime library fixture'),
                                         'd' * 64, 43)
        self.body = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0',
            'module_sha256': 'b' * 64, 'core_abi': LOCAL_CORE_ABI,
            'wasmtime_version': '38.0.0', 'runtime_library_sha256': 'c' * 64,
            'provider_library_sha256': 'd' * 64,
            'platform': 'darwin-arm64', 'engine_body': copy.deepcopy(self.engine),
            'engine_sha256': hashlib.sha256(encoded).hexdigest(),
            'file': 'client_host_wasm.cwasm', 'bytes': len(self.image),
            'sha256': hashlib.sha256(self.image).hexdigest()}

    def test_exact_bound_bytes_without_engine_or_jit(self):
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('No engine import')):
            self.assertEqual(_load_selected_image(self.root, self.body, self.recipe), self.image)
        with self.assertRaises(FrozenInstanceError): self.recipe.source_sha = 'd' * 40

    def test_platform_recipe_has_no_owned_provider_and_keeps_exact_image_binding(self):
        from image_fixture import ORIGINAL
        original = json.loads(ORIGINAL)
        original.update(runtime_allocation='platform', provider_library_sha256=None,
                        provider_library_bytes=None)
        recipe = _recipe_from_original(json.dumps(original).encode(), source_sha='a' * 40,
            package_version='0.0.0.dev0', module_sha256='b' * 64)
        self.assertEqual(recipe.runtime_allocation, 'platform')
        self.assertIsNone(recipe.provider_library_sha256)
        with self.assertRaises(LocalInstallationError): recipe.owned_provider()
        body = self.body | {'runtime_allocation': 'platform', 'provider_library_sha256': None,
                            'runtime_library_sha256': recipe.runtime_library_sha256}
        self.assertEqual(_load_selected_image(self.root, body, recipe), self.image)
        for changed in (body | {'provider_library_sha256': 'd' * 64},
                        body | {'runtime_allocation': 'native-owned'},
                        body | {'runtime_library_sha256': 'f' * 64}):
            with self.assertRaises(LocalInstallationError): _image_descriptor(changed, recipe)

    def test_platform_selection_cannot_hide_owned_provider_or_unknown_allocation(self):
        from image_fixture import ORIGINAL
        body = json.loads(ORIGINAL)
        for changes in ({'runtime_allocation': 'platform'},
                        {'runtime_allocation': 'native-owned'},
                        {'runtime_allocation': None}, {'runtime_allocation': 'system'},
                        {'runtime_allocation': 'platform', 'provider_library_bytes': 0,
                         'provider_library_sha256': None}):
            with self.subTest(changes=changes), self.assertRaises(LocalInstallationError):
                _recipe_from_original(json.dumps(body | changes).encode(), source_sha='a' * 40,
                    package_version='0.0.0.dev0', module_sha256='b' * 64)

    def test_platform_and_owned_image_descriptors_are_not_interchangeable(self):
        platform = replace(self.recipe, runtime_allocation='platform',
                           provider_library_sha256=None, provider_library_bytes=None)
        with self.assertRaises(LocalInstallationError): _image_descriptor(self.body, platform)
        body = self.body | {'runtime_allocation': 'platform', 'provider_library_sha256': None}
        with self.assertRaises(LocalInstallationError): _image_descriptor(body, self.recipe)

    def test_native_provider_original_cannot_be_missing_or_replaced_by_numbers(self):
        from image_fixture import ORIGINAL
        body = json.loads(ORIGINAL)
        for key, value in [('provider_library_sha256', None), ('provider_library_sha256', 'x' * 64),
                           ('provider_library_bytes', True), ('provider_library_bytes', 0)]:
            with self.subTest(key=key, value=value):
                changed = body | {key: value}
                with self.assertRaises(LocalInstallationError):
                    _recipe_from_original(json.dumps(changed).encode(), source_sha='a' * 40,
                        package_version='0.0.0.dev0', module_sha256='b' * 64)
        del body['provider_library_sha256']; del body['provider_library_bytes']
        with self.assertRaises(LocalInstallationError):
            _recipe_from_original(json.dumps(body).encode(), source_sha='a' * 40,
                package_version='0.0.0.dev0', module_sha256='b' * 64)

    def test_source_cohort_module_runtime_abi_target_cannot_be_rebound(self):
        for key, value in [('source_sha', 'd' * 40), ('package_version', 'foreign'),
                ('module_sha256', 'd' * 64), ('runtime_library_sha256', 'd' * 64),
                ('provider_library_sha256', 'e' * 64),
                ('wasmtime_version', '37.0.0'), ('core_abi', LOCAL_CORE_ABI - 1),
                ('platform', 'linux-arm64'), ('file', '../outside.cwasm')]:
            with self.subTest(key=key):
                body = self.body | {key: value}
                with patch('actql_sdk._local_image_recipe._read_file', side_effect=AssertionError('No file read')):
                    with self.assertRaises(LocalInstallationError): _load_selected_image(self.root, body, self.recipe)

    def test_config_cpu_and_boolean_differences_refuse_even_with_recomputed_digest(self):
        for key, value in [('target', 'aarch64-unknown-linux-gnu'),
                ('cpu_features', ['host-detected']), ('consume_fuel', 1),
                ('allocation', 'on-demand'), ('parallel_compilation', True)]:
            with self.subTest(key=key):
                body = copy.deepcopy(self.body); body['engine_body'][key] = value
                body['engine_sha256'] = hashlib.sha256(json.dumps(body['engine_body'],
                    sort_keys=True, separators=(',', ':')).encode()).hexdigest()
                with self.assertRaises(LocalInstallationError): _image_descriptor(body, self.recipe)

    def test_no_unknown_fields_or_missing_pool_limits_or_zero_unknowns(self):
        with self.assertRaises(LocalInstallationError): _image_descriptor(self.body | {'jit_fallback': True}, self.recipe)
        for value in (None, 0, True, -1):
            engine = copy.deepcopy(self.engine); engine['pooling']['max_core_instance_size'] = value
            selected = replace(self.recipe, engine_body=json.dumps(engine).encode())
            with self.assertRaises(LocalInstallationError): selected.validate()
        engine = copy.deepcopy(self.engine); del engine['pooling']['table_elements']
        with self.assertRaises(LocalInstallationError): replace(self.recipe, engine_body=json.dumps(engine).encode()).validate()

    def test_engine_digest_and_original_pool_memory_limit_stay_exact(self):
        with self.assertRaises(LocalInstallationError): _image_descriptor(self.body | {'engine_sha256': 'd' * 64}, self.recipe)
        engine = copy.deepcopy(self.engine); engine['pooling']['max_memory_size'] = 33554432
        with self.assertRaises(LocalInstallationError): replace(self.recipe, engine_body=json.dumps(engine).encode()).validate()

    def test_size_bool_and_unprovided_capacity_reject(self):
        for value in (True, 0, len(self.image) + 1):
            with self.assertRaises(LocalInstallationError): _image_descriptor(self.body | {'bytes': value}, self.recipe)
        for value in (True, 0, None):
            with self.assertRaises(LocalInstallationError): replace(self.recipe, image_bytes_limit=value).validate()

    def test_source_original_recipe_is_closed_and_not_a_runtime_allowance(self):
        from image_fixture import ORIGINAL
        recipe = _recipe_from_original(ORIGINAL, source_sha='a' * 40,
            package_version='0.0.0.dev0', module_sha256='b' * 64)
        self.assertEqual(recipe.source_sha, 'a' * 40)
        for original in (ORIGINAL[:-1] + b', "extra": true}',
                         ORIGINAL[:-1] + b', "wasmtime_version": "38.0.0"}',
                         ORIGINAL.replace(b'38.0.0', b'37.0.0')):
            with self.assertRaises(LocalInstallationError):
                _recipe_from_original(original, source_sha='a' * 40,
                    package_version='0.0.0.dev0', module_sha256='b' * 64)

    def test_changed_file_symlink_and_raw_wasm_do_not_trigger_fallback(self):
        path = self.root / 'client_host_wasm.cwasm'
        path.write_bytes(b'x' * len(self.image))
        (self.root / 'client_host_wasm.wasm').write_bytes(b'\0asm\x01\0\0\0')
        with self.assertRaises(LocalInstallationError): _load_selected_image(self.root, self.body, self.recipe)
        path.unlink(); path.symlink_to(self.root / 'client_host_wasm.wasm')
        with self.assertRaises(LocalInstallationError): _load_selected_image(self.root, self.body, self.recipe)
