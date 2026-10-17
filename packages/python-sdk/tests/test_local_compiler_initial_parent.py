"""Original initial compiler-domain selection and custody; scalar Native ports."""
from pathlib import Path
import unittest
from unittest.mock import patch

import test_local_compiler_parent as original
from test_local_native_initial_domain import InitialDomainFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_domain_custody import _OriginalDomainMaterial
from test_local_native_process_custody import ProcessFixture
from actql_sdk._local_distribution import LocalInstallationError

compiler = original.compiler


class InitialCompilerParentTests(unittest.TestCase):
    def setUp(self):
        self.case = original.CompilerParentTests()
        self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.case.body['child'] = dict(kind='initial_execution_domain', work=2,
            attempts=1, holdings=1, transfer=3)
        self.case.write_original()

    def test_source_selection_contains_only_original_nonbyte_limits(self):
        selected = compiler._compiler_parent_original(self.case.original, self.case.selected)
        self.assertIs(type(selected.child), compiler._InitialCompilerDomainOriginal)
        self.assertEqual(selected.child, (2, 1, 1, 3))
        self.assertFalse(hasattr(selected.child, 'bytes'))
        self.assertEqual(selected.holding.capacity_bytes, self.case.selected.capacity_bytes)

    def test_closed_kind_extra_bytes_and_boolean_numbers_refuse_before_load(self):
        base = dict(self.case.body['child'])
        for changes in ({'kind': False}, {'kind': 'first_available'}, {'bytes': 0},
                        {'retained': 0}, {'execution': None}, {'work': True},
                        {'attempts': 2**31}, {'transfer': 2**63}):
            self.case.body['child'] = {**base, **changes}
            self.case.write_original()
            with self.subTest(changes=changes), patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')):
                with self.assertRaises((ValueError, LocalInstallationError)):
                    compiler._acquire_compiler_parent(self.case.original, self.case.selected, self.case.descriptor)

    def test_first_domain_uses_native_selection_without_old_size_port(self):
        fixture = InitialDomainFixture()
        parent = self.case.acquire(fixture)
        self.assertEqual(sum(event[0] == 'initial' for event in fixture.events), 1)
        self.assertFalse(any(event[0] == 'prepare' for event in fixture.events))
        self.assertIs(parent.domain._descriptor, self.case.descriptor)
        self.assertIs(parent.domain._owner, parent.host)
        parent.close_unstarted()
        self.assertTrue(parent._closed)
        self.assertFalse(self.case.descriptor.close_attempted)

    def test_missing_initial_abi_refuses_before_host_acquisition_without_fallback(self):
        fixture = InitialDomainFixture()
        del fixture.host._functions.library.actql_domain_prepare_initial_into
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as raised:
            self.case.acquire(fixture)
        parent = raised.exception.cleanup_parent
        self.assertIsNone(parent.host)
        self.assertIsNone(parent.backing)
        self.assertIsNone(parent.domain)
        self.assertFalse(any(event[0] == 'prepare' for event in fixture.backing.control.events))
        self.assertFalse(fixture.events)
        parent.close_unstarted()
        self.assertTrue(parent._closed)
        self.assertTrue(parent.runtime._initialized)

    def test_lost_initial_reply_keeps_the_same_partial_domain_and_backing(self):
        fixture = InitialDomainFixture()
        fixture.prepare_fault = OSError('lost original first-domain reply')
        with self.assertRaises(compiler.CompilerParentAcquisitionError) as raised:
            self.case.acquire(fixture)
        parent = raised.exception.cleanup_parent
        self.assertIsNotNone(parent.domain._reply.value)
        self.assertIs(parent.domain._scope, parent.backing)
        before = list(fixture.events)
        with self.assertRaises(type(parent.domain._unknown)):
            parent.close_unstarted()
        self.assertEqual(fixture.events, before)
        self.assertFalse(parent._closed or self.case.descriptor.close_attempted)

    def projected_parent(self):
        fixture = InitialDomainFixture()
        parent = self.case.acquire(fixture)
        native = ProcessFixture(original=fixture, domain=parent.domain)
        library = parent.library
        library.actql_domain_project_into = Function(lambda *args: 0)
        library.actql_domain_copy_material = Function(lambda *args: 0)
        # The independent Native observation is deliberately different from
        # both the parent capacity and any of the old fixed child estimates.
        scalars = (7, 2, 3, self.case.selected.capacity_bytes, 16384, 32768,
                   0, 32768, 1, 2, 1, 1, 3, 0, 32768)
        material = _OriginalDomainMaterial(parent.original.holding.source_sha,
            parent.original.recipe, scalars)
        return parent, native, material

    def test_process_uses_fresh_same_domain_projection_before_original_preparation(self):
        parent, native, material = self.projected_parent()
        with patch.object(type(parent.domain), '_project_original_material', return_value=material) as projected:
            process = parent.prepare_process(path='/private/compiler.slot', nonce=19)
        projected.assert_called_once()
        self.assertEqual(native.preparations, [(19, 0, 32768)])
        self.assertIs(process._domain, parent.domain)
        process.close_unstarted()
        parent.close_unstarted()
        self.assertTrue(parent._closed)

    def test_foreign_projection_refuses_before_registering_any_process(self):
        for field in ('source', 'recipe'):
            parent, native, material = self.projected_parent()
            foreign = _OriginalDomainMaterial('f'*40 if field == 'source' else material.source,
                b'f'*32 if field == 'recipe' else material.recipe, material.scalars)
            with self.subTest(field=field), patch.object(type(parent.domain), '_project_original_material', return_value=foreign):
                with self.assertRaisesRegex(ValueError, 'material changed'):
                    parent.prepare_process(path='/private/compiler.slot', nonce=19)
            self.assertFalse(native.preparations)
            self.assertIsNone(parent.domain._installed_process_original)
            parent.close_unstarted()

    def test_lost_projection_keeps_original_domain_unknown_without_process(self):
        parent, native, material = self.projected_parent()
        def lost(functions):
            raise parent.domain._mark_unknown()
        with patch.object(type(parent.domain), '_project_original_material', side_effect=lost) as projected:
            with self.assertRaises(type(parent.domain._unknown_carrier)) as raised:
                parent.prepare_process(path='/private/compiler.slot', nonce=19)
        projected.assert_called_once()
        unknown = parent.domain._unknown
        self.assertIs(raised.exception, unknown)
        self.assertFalse(native.preparations)
        self.assertIsNone(parent.domain._installed_process_original)
        with self.assertRaises(type(unknown)):
            parent.close_unstarted()
        self.assertFalse(parent._closed)
