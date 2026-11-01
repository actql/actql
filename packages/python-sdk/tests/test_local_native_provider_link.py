"""Independent loaded-address doubles and real file integrity, not VM funding."""
from ctypes import CDLL, CFUNCTYPE, c_int, c_void_p
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
import os
from collections import Counter
from unittest.mock import patch

from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_engine import (
    _InstalledImageFileInput, _InstalledImageInput, _ORIGINAL_PROVIDER_SYMBOLS,
    _verify_original_provider_link,
)
from actql_sdk._local_native_holding import _NativeHoldingLease
from actql_sdk._local_image_recipe import _recipe_from_original
from image_fixture import IMAGE, ORIGINAL, PROVIDER


class Library(CDLL):
    def __init__(self,path):
        # An address-query double only; this does not load code or call an ABI.
        self._name=str(path)


class NativeProviderLinkTests(unittest.TestCase):
    def test_one_linkage_observation_hashes_each_original_file_once(self):
        opens, read_bytes, descriptors = Counter(), Counter(), {}
        physical_open, physical_read = os.open, os.read
        selected = {str(self.runtime_path), str(self.provider_path)}
        def opened(path, *args, **options):
            descriptor = physical_open(path, *args, **options)
            if str(path) in selected:
                opens[str(path)] += 1
                descriptors[descriptor] = str(path)
            return descriptor
        def read(descriptor, count):
            block = physical_read(descriptor, count)
            if descriptor in descriptors:
                read_bytes[descriptors[descriptor]] += len(block)
            return block
        with patch('actql_sdk._local_distribution.os.open', side_effect=opened), \
                patch('actql_sdk._local_distribution.os.read', side_effect=read):
            _verify_original_provider_link(self.image, self.runtime, self.provider)
        self.assertEqual(opens, {str(self.runtime_path): 1, str(self.provider_path): 1})
        self.assertEqual(read_bytes, {str(self.runtime_path): len(b'independent runtime library fixture'),
                                     str(self.provider_path): len(PROVIDER)})
        self.assertEqual(self.calls, [])

    def setUp(self):
        tmp=TemporaryDirectory();self.addCleanup(tmp.cleanup)
        self.root=Path(tmp.name)/'_wasmtime';self.platform=self.root/'darwin-aarch64'
        self.platform.mkdir(parents=True)
        self.runtime_path=self.platform/'_libwasmtime.dylib'
        self.provider_path=self.platform/'libactql_native_control.dylib'
        self.runtime_path.write_bytes(b'independent runtime library fixture')
        self.provider_path.write_bytes(PROVIDER)
        self.recipe=_recipe_from_original(ORIGINAL,source_sha='a'*40,
            package_version='0.0.0.dev0',module_sha256='b'*64)
        self.image=_InstalledImageFileInput(self.root/'client_host_wasm.cwasm',len(IMAGE),'c'*64,
            self.recipe,self.runtime_path)
        self.runtime,self.provider=Library(self.runtime_path),Library(self.provider_path)
        self.calls=[];self.functions=[]
        for suffix in _ORIGINAL_PROVIDER_SYMBOLS:
            callback=CFUNCTYPE(c_int)(lambda:self.calls.append('called') or 0)
            self.functions.append(callback)
            for library in (self.runtime,self.provider):
                setattr(library,'actql_native_owned_'+suffix,callback)
        self.provider.actql_owned_try_close=CFUNCTYPE(c_int,c_void_p)(lambda slot:0)
        self.holding=_NativeHoldingLease(c_void_p(123),self.provider,generation=7,recipe=b'r'*32)

    def test_separate_selected_libraries_share_exact_all_provider_addresses_without_calling_them(self):
        self.assertIsNot(self.runtime,self.provider)
        _verify_original_provider_link(self.image,self.runtime,self.provider)
        self.holding._verify_library(self.runtime,_installed_image=self.image)
        self.assertEqual(self.calls,[])
        self.assertEqual(self.holding._pointer.value,123)
        self.assertIs(self.holding._library,self.provider)

    def test_pre_fix_object_identity_gate_rejects_the_matching_two_library_shape(self):
        # The earlier gate was exactly this object-identity condition. The new
        # installed-only branch proves linkage instead of weakening that gate.
        self.assertIsNot(self.runtime,self.holding._library)
        with self.assertRaises(ValueError):self.holding._verify_library(self.runtime)
        self.holding._verify_library(self.runtime,_installed_image=self.image)

    def test_any_different_provider_symbol_rejects_copied_allocator_or_tls(self):
        for suffix in _ORIGINAL_PROVIDER_SYMBOLS:
            name='actql_native_owned_'+suffix;original=getattr(self.runtime,name)
            foreign=CFUNCTYPE(c_int)(lambda:0)
            setattr(self.runtime,name,foreign)
            with self.subTest(symbol=name),self.assertRaises(LocalInstallationError):
                self.holding._verify_library(self.runtime,_installed_image=self.image)
            setattr(self.runtime,name,original)
        self.assertEqual(self.calls,[])
        self.assertIs(self.holding._library,self.provider)

    def test_missing_or_null_symbol_is_not_a_system_fallback(self):
        for value in (None,c_void_p(),object()):
            self.runtime.actql_native_owned_current=value
            with self.assertRaises(LocalInstallationError):
                _verify_original_provider_link(self.image,self.runtime,self.provider)
        self.assertEqual(self.calls,[])

    def test_altered_runtime_or_provider_file_rejects_even_when_addresses_match(self):
        for path in (self.runtime_path,self.provider_path):
            original=path.read_bytes();path.write_bytes(b'x'*len(original))
            with self.subTest(path=path),self.assertRaises(LocalInstallationError):
                _verify_original_provider_link(self.image,self.runtime,self.provider)
            path.write_bytes(original)
        self.assertEqual(self.calls,[])

    def test_symlinked_provider_or_directory_rejects_before_address_observation(self):
        self.provider_path.unlink()
        alternate=Path(self.root.parent)/'alternate';alternate.write_bytes(PROVIDER)
        self.provider_path.symlink_to(alternate)
        with self.assertRaises((LocalInstallationError,OSError)):
            _verify_original_provider_link(self.image,self.runtime,self.provider)
        self.provider_path.unlink();self.provider_path.write_bytes(PROVIDER)
        moved=self.platform.with_name('original-platform');self.platform.rename(moved)
        self.platform.symlink_to(moved,target_is_directory=True)
        with self.assertRaises(LocalInstallationError):
            _verify_original_provider_link(self.image,self.runtime,self.provider)

    def test_foreign_path_or_non_dll_object_does_not_acquire_original_binding(self):
        for runtime,provider in ((Library('/foreign/runtime'),self.provider),
                (self.runtime,Library('/foreign/provider')),
                (SimpleNamespace(_name=str(self.runtime_path)),self.provider)):
            with self.subTest(runtime=runtime,provider=provider),self.assertRaises(LocalInstallationError):
                _verify_original_provider_link(self.image,runtime,provider)

    def test_raw_image_or_no_image_cannot_opt_in_to_two_library_binding(self):
        raw=_InstalledImageInput(IMAGE,'c'*64,self.recipe,self.runtime_path)
        for image in (None,raw,True):
            with self.subTest(image=image),self.assertRaises(ValueError):
                self.holding._verify_library(self.runtime,_installed_image=image)
        self.assertEqual(self.calls,[])

    def test_retired_or_unknown_holding_never_reaches_library_observation(self):
        self.holding._pointer.value=None
        with patch('actql_sdk._local_engine._verify_original_provider_link') as check:
            with self.assertRaises(ValueError):self.holding._verify_library(self.runtime,_installed_image=self.image)
            check.assert_not_called()
        self.holding._pointer.value=123;unknown=OSError('original cleanup unknown')
        self.holding._close_failure=unknown
        with patch('actql_sdk._local_engine._verify_original_provider_link') as check:
            with self.assertRaises(OSError) as caught:self.holding._verify_library(self.runtime,_installed_image=self.image)
            self.assertIs(caught.exception,unknown);check.assert_not_called()

    def test_holding_replacement_during_verification_cannot_return_success(self):
        def change(*args):self.holding._library=object()
        with patch('actql_sdk._local_engine._verify_original_provider_link',side_effect=change):
            with self.assertRaises(ValueError):self.holding._verify_library(self.runtime,_installed_image=self.image)
        self.assertEqual(self.holding._pointer.value,123)

    def test_existing_exact_library_diagnostic_needs_no_installed_dependency_branch(self):
        self.holding._verify_library(self.provider)
        self.assertEqual(self.calls,[])
        self.assertEqual(self.holding._pointer.value,123)


if __name__=='__main__':unittest.main()
