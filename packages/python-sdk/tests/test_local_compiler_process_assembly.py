"""Ordinary compiler composition faults; no native binary, Engine or image executes."""
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import python_compiler_process as transport
import python_compiler_program as program
import test_local_compiler_parent as parent_tests
from actql_sdk._local_distribution import LocalInstallationError

compiler = parent_tests.compiler


def report(**changes):
    return json.dumps(dict(compilation_status=0, image_bytes=5, handles_close=0, leave=0,
        holding_close=-3, holding_closed=False, runtime_retained=True, config_attempted=True,
        engine_attempted=True, module_attempted=True, instance=False, physical_acceptance=False,
        ) | changes).encode()


class CompilerProcessAssemblyTests(unittest.TestCase):
    def setUp(self):
        self.original = parent_tests.CompilerParentTests()
        self.original.setUp(); self.addCleanup(self.original.doCleanups)
        self.original.body['child'] = dict(kind='initial_execution_domain',work=2,attempts=1,holdings=1,transfer=3)
        self.original.write_original()
        self.root = self.original.fixture.case.root.resolve()
        self.destination = self.root / 'ordinary-compiler'
        self.prepared = self.original.fixture.fixture.preparation(self.original.original)
        self.parent = SimpleNamespace(_closed=False, runtime=object())
        self.order = []
        self.stack = self.enterContext(ExitStack())
        self.stack.enter_context(patch.object(compiler, 'prepare_compiler_runtime', return_value=self.prepared))
        self.prepare = self.stack.enter_context(patch.object(program, 'prepare_program', side_effect=self.prepare_program))
        self.acquire = self.stack.enter_context(patch.object(compiler, '_acquire_compiler_parent', side_effect=self.acquire_parent))
        self.invoke = self.stack.enter_context(patch.object(transport, 'invoke_original_compiler', side_effect=self.invoke_program))
        self.stack.enter_context(patch.object(compiler, '_acquire_compiler_holding', side_effect=AssertionError('Unbound acquire')))
        self.stack.enter_context(patch.object(compiler, 'compile_image', side_effect=AssertionError('In-process Engine')))
        self.stack.enter_context(patch.object(compiler, 'CDLL', side_effect=AssertionError('Real Native load')))

    def prepare_program(self, original, **options):
        self.order.append('program')
        directory = options['destination']; directory.mkdir()
        executable = directory / 'compiler-image'; executable.write_bytes(b'fixed selected executable')
        executable.chmod(0o700)
        return program._CompilerProgram(original['source'],original['module_sha256'],
            original['core_receipt_sha256'],hashlib.sha256(original['recipe'].engine_body).hexdigest(),
            directory,(str(executable),executable.stat().st_size,hashlib.sha256(executable.read_bytes()).hexdigest()),())

    def acquire_parent(self, original, selected, descriptor):
        self.order.append('parent')
        self.assertEqual(original['provider_library'],self.prepared.directory /
            'actql_local_runtime/_wasmtime/darwin-aarch64/libactql_native_control.dylib')
        self.assertEqual(descriptor.closed,False)
        self.parent.descriptor = descriptor
        return self.parent

    def invoke_program(self, parent, **options):
        self.order.append('child')
        self.assertIs(parent,self.parent)
        self.assertFalse(parent.descriptor.close_attempted)
        self.assertEqual(options['nonce'],self.original.selected.generation)
        self.assertEqual(options['module'],self.original.original['module'])
        options['destination'].write_bytes(b'image')
        parent._closed = True  # Scalar double of the existing typed retirement helper only.
        return report()

    def compile(self, **changes):
        options=dict(bindings_source=self.root/'bindings',native_libraries=self.root/'libraries',
            preparation=self.root/'preparation',c_api_headers=self.root/'headers',
            clang=self.root/'clang',sdk=self.root/'sdk',seconds=20)
        options.update(changes)
        return compiler.compile_from_original(self.original.fixture.case.module_file,
            self.original.fixture.case.head,self.destination,**options)

    def test_ordinary_path_uses_verified_program_same_parent_and_retains_runtime_aliases(self):
        result=self.compile()
        self.assertEqual(self.order,['program','parent','child'])
        self.assertIs(result.parent,self.parent)
        self.assertIs(result.preparation,self.prepared)
        self.assertTrue(self.parent.descriptor.closed)
        self.assertEqual(result.receipt['image_sha256'],hashlib.sha256(b'image').hexdigest())
        self.assertIs(result.receipt['compiled'],True)
        observation=json.loads((self.destination/'compiler-process-receipt.json').read_text())
        self.assertIs(observation['compilation_observation']['runtime_retained'],True)
        self.assertIs(observation['parent_runtime_retirement_ACK'],False)
        self.assertIs(observation['physical_acceptance'],False)
        self.assertIsNone(observation['normal_profile'])

    def test_bad_budget_or_missing_tools_refuses_before_staging_program_or_native(self):
        for values in ({'seconds':True},{'seconds':0},{'seconds':float('inf')},{'c_api_headers':None}):
            with self.subTest(values=values),self.assertRaises(ValueError):self.compile(**values)
        self.prepare.assert_not_called();self.acquire.assert_not_called();self.invoke.assert_not_called()
        self.assertFalse(self.destination.exists())

    def test_missing_original_parent_cannot_fall_back_to_old_unbound_holding(self):
        self.original.path.unlink()
        case=self.original.fixture.case
        case.commit();case.core['source_sha']=case.head;case.write_receipts()
        with self.assertRaisesRegex(ValueError,'compiler parent is unavailable'):self.compile()
        self.assertFalse(self.destination.exists());self.acquire.assert_not_called()

    def test_program_preparation_failure_never_acquires_a_parent(self):
        primary=ValueError('Original actual C input refused')
        self.prepare.side_effect=primary
        with self.assertRaises(ValueError) as caught:self.compile()
        self.assertIs(caught.exception,primary);self.acquire.assert_not_called();self.invoke.assert_not_called()

    def test_partial_parent_and_same_descriptor_survive_acquire_response_loss(self):
        def lost(original,selected,descriptor):
            self.parent.descriptor=descriptor
            raise compiler.CompilerParentAcquisitionError(self.parent)
        self.acquire.side_effect=lost
        with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:self.compile()
        failure=caught.exception
        self.assertIs(failure.cleanup_parent,self.parent)
        self.assertIs(failure.cleanup_descriptor,self.parent.descriptor)
        self.assertFalse(failure.cleanup_descriptor.close_attempted)
        failure.cleanup_descriptor.close()  # Scalar-only fixture; no Native acquire occurred.
        self.invoke.assert_not_called()

    def test_partial_control_runtime_is_not_discarded_or_reinitialized(self):
        runtime=SimpleNamespace(slot=object())
        self.acquire.side_effect=compiler.CompilerControlInitializationError(runtime)
        with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:self.compile()
        self.assertIs(caught.exception.cleanup_runtime,runtime)
        self.assertFalse(caught.exception.cleanup_descriptor.close_attempted)
        caught.exception.cleanup_descriptor.close()  # Scalar-only fixture, no Native DLL.
        self.acquire.assert_called_once();self.invoke.assert_not_called()

    def test_transport_loss_keeps_original_parent_descriptor_and_partial_response(self):
        def lost(parent,**options):
            error=transport.CompilerChildProcessError(parent);error.response.extend(b'partial report');raise error
        self.invoke.side_effect=lost
        with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:self.compile()
        self.assertIs(caught.exception.cleanup_parent,self.parent)
        self.assertEqual(caught.exception.response,b'partial report')
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.parent.descriptor.close()  # Scalar-only fixture, no actual child.
        self.invoke.assert_called_once()

    def test_report_bytes_cannot_substitute_for_original_physical_cleanup(self):
        self.invoke.side_effect=lambda *args,**kwargs:report()
        with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:self.compile()
        self.assertRegex(str(caught.exception.primary),'cleanup is unconfirmed')
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.parent.descriptor.close()  # Scalar-only fixture.
        self.assertFalse((self.destination/'image-receipt.json').exists())

    def test_failed_descriptor_close_is_one_shot_and_does_not_publish_image(self):
        close=compiler._OriginalDescriptor.close;calls=[]
        def lost(descriptor):
            calls.append(descriptor)
            if descriptor is self.parent.descriptor:raise OSError('descriptor close reply lost')
            return close(descriptor)
        with patch.object(compiler._OriginalDescriptor,'close',side_effect=None,autospec=True) as closed:
            closed.side_effect=lost
            with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:self.compile()
        self.assertEqual(calls,[self.parent.descriptor])
        self.assertIs(caught.exception.cleanup_descriptor,self.parent.descriptor)
        self.assertFalse((self.destination/'image-receipt.json').exists())
        close(self.parent.descriptor)  # Test double did not attempt a real close.

    def test_bad_closed_report_is_not_success_even_after_typed_region_cleanup(self):
        original=self.invoke_program
        def bad(parent,**options):original(parent,**options);return b'{"compilation_status":0}'
        self.invoke.side_effect=bad
        with self.assertRaises(compiler.CompilerProcessAssemblyError):self.compile()
        self.assertTrue(self.parent.descriptor.closed)
        self.assertFalse((self.destination/'image-receipt.json').exists())


class CompilerProcessReportTests(unittest.TestCase):
    def test_closed_report_preserves_runtime_retained_and_rejects_boolean_numeric_fields(self):
        self.assertTrue(compiler._compiler_process_report(report(),64)['runtime_retained'])
        for field,value in [('compilation_status',True),('image_bytes',True),('image_bytes',0),
                            ('image_bytes',65),('holding_close',-1),('holding_closed',True),
                            ('runtime_retained',False),('config_attempted',False),
                            ('instance',True),('physical_acceptance',True)]:
            body=json.loads(report());body[field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                compiler._compiler_process_report(json.dumps(body).encode(),64)

    def test_duplicate_unknown_and_oversized_report_refuse(self):
        raw=report()
        for changed in [raw[:-1]+b',"instance":false}',raw[:-1]+b',"grant":true}',b' '*4097]:
            with self.subTest(changed=changed[:30]),self.assertRaises((ValueError,LocalInstallationError)):
                compiler._compiler_process_report(changed,64)
