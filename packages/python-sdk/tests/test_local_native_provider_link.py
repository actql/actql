"""Independent loaded-address doubles and real file integrity, not VM funding."""
from ctypes import CDLL, CFUNCTYPE, c_int, c_void_p
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
import copy
import os
from collections import Counter
from unittest.mock import patch

from actql_sdk._local_distribution import LocalInstallationError, LocalComponentReadCleanupPending
from actql_sdk._local_engine import (
    _InstalledImageFileInput, _InstalledImageInput, _ORIGINAL_PROVIDER_SYMBOLS,
    _verify_original_provider_link, _verify_loaded_runtime, _InitializationLibraryFiles,
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

    def test_same_loader_and_holding_link_keep_one_hash_and_close_both_original_fds(self):
        opened, closed, count = [], [], Counter()
        real_open, real_close, real_read = os.open, os.close, os.read
        def acquire(path, *args):
            descriptor = real_open(path, *args)
            opened.append(descriptor)
            return descriptor
        def read(descriptor, size):
            block = real_read(descriptor, size)
            count[descriptor] += len(block)
            return block
        def retire(descriptor):
            closed.append(descriptor)
            return real_close(descriptor)
        with patch('actql_sdk._local_distribution.os.open', side_effect=acquire), \
                patch('actql_sdk._local_distribution.os.read', side_effect=read), \
                patch('actql_sdk._local_distribution.os.close', side_effect=retire):
            with _InitializationLibraryFiles(self.recipe, self.runtime_path) as originals:
                _verify_loaded_runtime(self.image, SimpleNamespace(filename=self.runtime_path, dll=self.runtime),
                                       _initialization_files=originals)
                self.holding._verify_library(self.runtime, _installed_image=self.image,
                                             _initialization_files=originals)
                self.assertEqual(closed, [])
                self.assertEqual([os.fstat(fd).st_size for fd in opened],
                                 [len(b'independent runtime library fixture'), len(PROVIDER)])
            self.assertEqual(closed, list(reversed(opened)))
            self.assertEqual([count[fd] for fd in opened],
                             [len(b'independent runtime library fixture'), len(PROVIDER)])
        self.assertEqual(self.calls, [])
        for fd in opened:
            with self.assertRaises(OSError): os.fstat(fd)

    def test_mutation_or_replacement_during_address_casts_refuses_and_closes_originals(self):
        from actql_sdk import _local_engine as engine
        for path in (self.runtime_path, self.provider_path):
            for replace_file in (False, True):
                original = path.read_bytes()
                real_cast = engine.cast
                called = []
                def cast_once(*args):
                    if not called:
                        called.append(True)
                        if replace_file:
                            replacement = path.with_suffix('.new')
                            replacement.write_bytes(original)
                            replacement.replace(path)
                        else:
                            path.write_bytes(b'x' * len(original))
                    return real_cast(*args)
                descriptors = []
                real_open = os.open
                def acquire(*args):
                    fd = real_open(*args); descriptors.append(fd); return fd
                with self.subTest(path=path, replace_file=replace_file), \
                        patch('actql_sdk._local_engine.cast', side_effect=cast_once), \
                        patch('actql_sdk._local_distribution.os.open', side_effect=acquire), \
                        self.assertRaises(LocalInstallationError):
                    _verify_original_provider_link(self.image, self.runtime, self.provider)
                for fd in descriptors:
                    with self.assertRaises(OSError): os.fstat(fd)
                path.write_bytes(original)
        self.assertEqual(self.calls, [])

    def test_copied_foreign_and_retired_initialization_scopes_refuse(self):
        with _InitializationLibraryFiles(self.recipe, self.runtime_path) as originals:
            originals.observe(self.recipe, self.runtime_path, provider=True)
            for scope, recipe, path in ((copy.copy(originals), self.recipe, self.runtime_path),
                    (originals, replace(self.recipe), self.runtime_path),
                    (originals, self.recipe, self.runtime_path.with_name('foreign'))):
                with self.assertRaises(LocalInstallationError):
                    scope.observe(recipe, path, provider=True)
        with self.assertRaises(LocalInstallationError):
            originals.observe(self.recipe, self.runtime_path, provider=True)
        with self.assertRaises(LocalInstallationError): originals.__enter__()

    def test_linkage_error_and_unconfirmed_file_close_keep_both_causes_and_other_fd_closes(self):
        opened, closed = [], []
        real_open, real_close = os.open, os.close
        cleanup = OSError('original file close unconfirmed')
        def acquire(*args):
            fd = real_open(*args); opened.append(fd); return fd
        def retire(fd):
            closed.append(fd)
            if fd == opened[1]: raise cleanup
            return real_close(fd)
        self.runtime.actql_native_owned_current = c_void_p()
        with patch('actql_sdk._local_distribution.os.open', side_effect=acquire), \
                patch('actql_sdk._local_distribution.os.close', side_effect=retire):
            with self.assertRaises(LocalComponentReadCleanupPending) as caught:
                _verify_original_provider_link(self.image, self.runtime, self.provider)
            pending = caught.exception
            self.assertIs(pending.cleanup_error, cleanup)
            self.assertIsInstance(pending.original_error, LocalInstallationError)
            self.assertEqual(closed, list(reversed(opened)))
            self.assertEqual(pending.cleanup_descriptor.value, opened[1])
            with self.assertRaises(RuntimeError): pending.cleanup_descriptor.close()
            self.assertEqual(closed, list(reversed(opened)))
            self.assertEqual(os.fstat(opened[1]).st_ino, self.provider_path.stat().st_ino)
            with self.assertRaises(OSError): os.fstat(opened[0])
        # This fixture's close explicitly did not execute; preserve production's
        # uncertain original carrier, and dispose only our known fresh fixture FD.
        real_close(opened[1])

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
