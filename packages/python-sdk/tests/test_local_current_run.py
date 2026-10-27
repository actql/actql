"""Independent scalar coupling fixtures; not actual Wasm or public admission."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import _Output, _PhysicalInput, LocalCoreError, _RUN_SIGNATURES
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_storage import LocalByteStore, _NamespaceReader
from test_local_journal_port import scalar_reader_check
from test_local_run import RunCustodyTests


class CurrentRunConfigurationTests(unittest.TestCase):
    def fixture(self):
        # Reuse the existing neutral scalar Core double; its return values do
        # not prove Account validation, adoption, Run admission or execution.
        core, _, custody, inputs, _, _, _, calls, codes = RunCustodyTests().bridge()
        directory = TemporaryDirectory(prefix='actql-current-run-')
        self.addCleanup(directory.cleanup)
        store = LocalByteStore(Path(directory.name) / 'original.sqlite', max_records=4,
                               max_record_bytes=128, max_payload_bytes=512)
        self.addCleanup(store.close)
        core._inputs = {6: _PhysicalInput(b'', lambda: True, lambda _: True,
                                        journal=_JournalCallbacks(lambda: None, store))}
        current = _Output(core._identity, 6, 50, 1024, 'current')
        core._loans[6] = current
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        return core, custody, inputs[2], current, reader, calls, codes

    def test_only_original_frame_and_setup_reach_typed_core_configuration(self):
        core, custody, source, current, reader, calls, _ = self.fixture()
        with core.host_current_frame(current, reader):
            configuration = custody.install_current_configuration(current, source)
        self.assertEqual(calls[-1], ('run', 'install_current_configuration', (50, 13)))
        self.assertIs(configuration.input, source)
        self.assertIs(configuration.current, current)
        self.assertFalse(any(name in ('reserve_dispatch', 'confirm_physical_start', 'produce')
                             for _, name, _ in calls))

    def test_outside_frame_or_copied_parent_or_setup_refuses_before_core(self):
        core, custody, source, current, reader, calls, _ = self.fixture()
        before = len(calls)
        with self.assertRaises(ValueError):
            custody.install_current_configuration(current, source)
        with core.host_current_frame(current, reader):
            for left, right in ((copy.copy(current), source), (current, copy.copy(source))):
                with self.assertRaises(ValueError):
                    custody.install_current_configuration(left, right)
        self.assertEqual(len(calls), before)

    def test_core_fence_refusal_keeps_original_input_and_current_for_cleanup(self):
        core, custody, source, current, reader, _, codes = self.fixture()
        for result in (-41, -32, -35, -30):
            codes['run', 'install_current_configuration'] = result
            with core.host_current_frame(current, reader):
                with self.assertRaises(LocalCoreError) as raised:
                    custody.install_current_configuration(current, source)
            self.assertEqual(raised.exception.code, result)
            self.assertIs(core._loans[6], current)
            self.assertIs(core._loans[source.ticket], source)

    def test_retired_current_parent_cannot_supply_later_configuration_custody(self):
        core, custody, source, current, reader, _, _ = self.fixture()
        with core.host_current_frame(current, reader):
            configuration = custody.install_current_configuration(current, source)
        del core._loans[6]
        with self.assertRaises(ValueError):
            custody._configuration(configuration)
        self.assertEqual(_RUN_SIGNATURES['install_current_configuration'], ('i64 i32 i32', 'i32'))

    def test_failed_current_or_closing_core_refuses_before_scalar_issuer_and_retains_loans(self):
        # This exercises the real Python physical-loan caller with a scalar
        # Core double. It does not execute the Wasm caller guards.
        for closing in (False, True):
            with self.subTest(closing=closing):
                core, custody, source, current, reader, calls, _ = self.fixture()
                original_calls = len(calls)
                original_input = core._loans[source.ticket]
                failure = OSError('original current supplier unavailable')
                if closing:
                    core._closing = True
                    with self.assertRaises(RuntimeError):
                        custody.install_current_configuration(current, source)
                else:
                    callbacks = core._journal_callbacks(current.ticket)
                    self.assertIsNotNone(callbacks)
                    callbacks.current = lambda: (_ for _ in ()).throw(failure)
                    with self.assertRaises(OSError) as raised:
                        with core.host_current_frame(current, reader):
                            custody.install_current_configuration(current, source)
                    self.assertIs(raised.exception, failure)
                    self.assertIsNone(callbacks.reader)
                self.assertEqual(len(calls), original_calls)
                self.assertIs(core._loans[source.ticket], original_input)
                self.assertIs(core._loans[current.ticket], current)


if __name__ == '__main__':
    unittest.main()
