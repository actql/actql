"""Selected real instruction exhaustion at the Host bridge; no Native ACK."""
from threading import RLock
from threading import Event
import unittest

import wasmtime

from actql_sdk._local_core import (LocalCore, _Output, _NORMAL_HOST_BOOTSTRAP_FUEL,
                                   _NORMAL_HOST_OPERATION_FUEL, _NORMAL_HOST_CLEANUP_FUEL)
from actql_sdk._local_work import OriginalLocalWork


class LocalHostFuelTests(unittest.TestCase):
    def test_installed_negative_control_reads_the_original_c_api_fuel_code(self):
        import importlib.util
        from pathlib import Path
        path = Path(__file__).with_name('fixtures') / 'ci-python-installed-fuel.py'
        spec = importlib.util.spec_from_file_location('installed_fuel_control', path)
        fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fixture)
        core = self.core()
        with self.assertRaises(wasmtime.Trap) as caught:
            with core._host_operation():
                core._store.set_fuel(1_000)
                core._call('probe', 'exhaust')
        self.assertEqual(fixture.fuel_trap_code(caught.exception), 12)
        # An unrelated real trap must not pass the fuel classification.
        other = self.core('''(module
          (func (export "actql_probe_exhaust") (param i64) (result i32) unreachable))''')
        with self.assertRaises(wasmtime.Trap) as unrelated:
            with other._host_operation():
                other._call('probe', 'exhaust')
        with self.assertRaises(AssertionError):
            fixture.fuel_trap_code(unrelated.exception)

    def core(self, wat=None, imports=()):
        config = wasmtime.Config()
        config.consume_fuel = True
        engine = wasmtime.Engine(config)
        store = wasmtime.Store(engine)
        store.set_fuel(_NORMAL_HOST_BOOTSTRAP_FUEL)
        module = wasmtime.Module(engine, wat or '''(module
          (func (export "actql_probe_value") (param i64) (result i32) i32.const 7)
          (func (export "actql_probe_exhaust") (param i64) (result i32)
            (loop br 0) i32.const 0))''')
        instance = wasmtime.Instance(store, module, list(imports))
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._ordinary_host = True
        core._host_fuel_phase = None
        core._host_initial_claimed = False
        core._closed = core._retired = core._closing = core._invoking = False
        core._nonce = 1
        core._physical_holding = None
        core._store = store
        core._exports = instance.exports(store)
        core._identity = object()
        core._loans = {}
        self.addCleanup(engine.close)
        self.addCleanup(module.close)
        self.addCleanup(store.close)
        return core

    def saved_original(self, core):
        original = _Output(core._identity, 11, 13, 1024, 'submission_lookup')
        core._loans[original.ticket] = original
        return original

    def test_new_operation_gets_finite_budget_but_private_and_nested_calls_do_not(self):
        core = self.core()
        for _ in range(2):
            with core._host_operation():
                self.assertEqual(core._store.get_fuel(), _NORMAL_HOST_OPERATION_FUEL)
                self.assertEqual(core._call('probe', 'value'), 7)
                remaining = core._store.get_fuel()
                self.assertLess(remaining, _NORMAL_HOST_OPERATION_FUEL)
                with self.assertRaises(RuntimeError):
                    with core._host_operation():
                        self.fail('Nested operation acquired another budget')
                self.assertEqual(core._store.get_fuel(), remaining)
                self.assertEqual(core._call('probe', 'value'), 7)
                self.assertLess(core._store.get_fuel(), remaining)
        with self.assertRaises(RuntimeError):
            core._call('probe', 'value')

    def test_initial_factory_keeps_constructor_consumption_and_cannot_begin_again(self):
        core = self.core()
        core._store.set_fuel(_NORMAL_HOST_BOOTSTRAP_FUEL - 123)
        with core._host_operation(initial=True):
            self.assertEqual(core._store.get_fuel(), _NORMAL_HOST_BOOTSTRAP_FUEL - 123)
            self.assertEqual(core._call('probe', 'value'), 7)
        with self.assertRaises(RuntimeError):
            with core._host_operation(initial=True):
                self.fail('Repeated original bootstrap')

    def test_actual_exhaustion_fences_normal_work_and_allows_only_separate_cleanup(self):
        core = self.core()
        original_store = core._store
        with self.assertRaises(wasmtime.Trap):
            with core._host_operation():
                core._call('probe', 'exhaust')
        self.assertTrue(core._closing)
        self.assertEqual(core._store.get_fuel(), 0)
        with self.assertRaises(RuntimeError):
            with core._host_operation():
                self.fail('Exhausted operation revived')
        with core._host_cleanup():
            self.assertEqual(core._store.get_fuel(), _NORMAL_HOST_CLEANUP_FUEL)
            self.assertEqual(core._call('probe', 'value'), 7)
            remaining = core._store.get_fuel()
            with core._host_cleanup():
                self.assertEqual(core._store.get_fuel(), remaining)
                self.assertEqual(core._call('probe', 'value'), 7)
            self.assertLess(core._store.get_fuel(), remaining)
        self.assertIs(core._store, original_store)
        self.assertTrue(core._closing)
        self.assertFalse(core._closed)

    def test_cancellation_does_not_ack_or_replenish_the_interrupted_scope(self):
        import asyncio
        core = self.core()
        with self.assertRaises(asyncio.CancelledError):
            with core._host_operation():
                core._call('probe', 'value')
                remaining = core._store.get_fuel()
                raise asyncio.CancelledError()
        self.assertEqual(core._store.get_fuel(), remaining)
        self.assertFalse(core._closed)
        self.assertIsNone(core._host_fuel_phase)

    def test_live_worker_keeps_actual_store_fuel_after_caller_cancellation(self):
        import asyncio
        core = self.core()
        entered, resume = Event(), Event()
        observations = []

        def invoke():
            with core._lock:
                observations.append(core._call('probe', 'value'))
            entered.set()
            if not resume.wait(2):
                raise TimeoutError('Original worker was not resumed')
            with core._lock:
                observations.append(core._call('probe', 'value'))

        work = OriginalLocalWork(invoke, on_exit=core._finish_work_operation)
        with self.assertRaises(asyncio.CancelledError):
            with core._host_operation():
                original = core._host_operation_id
                core._retain_work_operation(work)
                work.start()
                self.assertTrue(entered.wait(1))
                remaining = core._store.get_fuel()
                raise asyncio.CancelledError()
        try:
            self.assertEqual(core._host_operation_id, original)
            self.assertFalse(work.stopped)
            with self.assertRaises(RuntimeError):
                with core._host_operation():
                    self.fail('A live worker received fresh instruction fuel')
            self.assertEqual(core._store.get_fuel(), remaining)
            import copy
            with self.assertRaises(ValueError):
                with core._borrow_work_operation(copy.copy(work)):
                    self.fail('A copied worker borrowed original control custody')
            with self.assertRaises(RuntimeError):
                with core._borrow_work_operation(OriginalLocalWork(lambda: None)):
                    self.fail('A different original worker borrowed this operation')
            self.assertEqual(core._store.get_fuel(), remaining)
            with core._borrow_work_operation(work) as borrowed:
                self.assertTrue(borrowed)
                self.assertEqual(core._host_operation_id, original)
                self.assertEqual(core._call('probe', 'value'), 7)
            control_remaining = core._store.get_fuel()
            self.assertLess(control_remaining, remaining)
            resume.set()
            asyncio.run(work.wait())
            self.assertEqual(observations, [7, 7])
            self.assertLess(core._store.get_fuel(), control_remaining)
            self.assertEqual(core._host_operation_id, 0)
            self.assertIsNone(core._host_fuel_phase)
        finally:
            resume.set()
            asyncio.run(work.wait_stopped())

    def test_retired_store_does_not_block_remaining_original_physical_cleanup(self):
        core = self.core()
        core._retired = True
        core._closing = True
        core._store = None
        with core._host_cleanup():
            self.assertFalse(core._closed)
            self.assertTrue(core._retired)
        with self.assertRaises(RuntimeError):
            core._call('probe', 'value')

    def test_saved_cleanup_requires_same_original_after_unwind_and_cleanup_entry(self):
        import copy
        core = self.core('''(module
          (func (export "actql_submission_begin_cleanup") (param i64 i32) (result i32)
            local.get 1 i32.const 13 i32.eq if (result i32) i32.const 0 else i32.const -2 end))''')
        original = self.saved_original(core)
        with self.assertRaises(RuntimeError):
            core.begin_saved_read_cleanup(original)
        core._closing = True
        with self.assertRaises(RuntimeError):
            core.begin_saved_read_cleanup(original)
        with core._host_cleanup():
            with self.assertRaises(ValueError):
                core.begin_saved_read_cleanup(copy.copy(original))
            core._invoking = True
            with self.assertRaises(RuntimeError):
                core.begin_saved_read_cleanup(original)
            core._invoking = False
            core.begin_saved_read_cleanup(original)
            self.assertIs(core._loans[original.ticket], original)
        with self.assertRaises(RuntimeError):
            with core._host_operation():
                self.fail('Terminal cleanup revived normal work')

    def test_real_trap_cleanup_entry_does_not_retire_original_descriptor(self):
        import os
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, write_fd)
        self.addCleanup(lambda: os.close(read_fd) if not state['closed'] else None)
        state = {'closed': False, 'ready': False, 'attempts': 0}
        core = self.core('''(module
          (global $pending (mut i32) (i32.const 0))
          (func (export "actql_probe_exhaust") (param i64) (result i32)
            i32.const 1 global.set $pending (loop br 0) i32.const 0)
          (func (export "actql_submission_begin_cleanup") (param i64 i32) (result i32)
            i32.const 0 global.set $pending i32.const 0)
          (func (export "actql_probe_close") (param i64) (result i32)
            global.get $pending if (result i32) i32.const -9 else i32.const 0 end))''')
        original_store = core._store
        original = self.saved_original(core)
        with self.assertRaises(wasmtime.Trap):
            with core._host_operation():
                # Small diagnostic instruction selection; no product budget is changed.
                core._store.set_fuel(1000)
                core._call('probe', 'exhaust')
        with core._host_cleanup():
            self.assertEqual(core._call('probe', 'close'), -9)
            core.begin_saved_read_cleanup(original)
            os.fstat(read_fd)
            self.assertFalse(state['closed'])
            self.assertIs(core._store, original_store)
            def physical_close():
                state['attempts'] += 1
                if not state['ready']:
                    return False
                os.close(read_fd)
                state['closed'] = True
                return True
            self.assertEqual(core._call('probe', 'close'), 0)
            self.assertFalse(physical_close())
            os.fstat(read_fd)
            state['ready'] = True
            self.assertTrue(physical_close())
            self.assertEqual(state['attempts'], 2)
        self.assertTrue(core._closing)
        self.assertFalse(core._closed)
        self.assertIs(core._loans[original.ticket], original)


if __name__ == '__main__':
    unittest.main()
