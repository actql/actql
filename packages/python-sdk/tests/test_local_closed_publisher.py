"""Original publisher fences on real SQLite/Wasmtime memory, not Account admission.

The publication Owner remains a scalar double. The tiny Wasm module supplies an
actual same-instance Caller/Memory to exercise the closed physical copy port.
"""
import copy
import json
import sys
import unittest
from unittest.mock import patch

import wasmtime

from actql_sdk._local_core import (
    _Input, _Output, _PhysicalInput, _PUBLISHER_LIMIT, _MEMORY_LIMIT,
)
from actql_sdk._local_host_binding import (
    OriginalHostBinding, _OriginalPublisherPort, _InvocationObservation,
)
from test_local_closed_invocation import ClosedInvocationTests


class ClosedPublisherTests(unittest.TestCase):
    def fixture(self):
        fixture = ClosedInvocationTests()
        self.addCleanup(fixture.doCleanups)
        core, binding, store, path, journal_current = fixture.fixture()
        scalar = core._call
        reservations = []
        def call(family, name, *args):
            if family == 'publisher' and name == 'reserve':
                reservations.append(args)
                return 100 + args[2]
            return scalar(family, name, *args)
        core._call = call
        engine = wasmtime.Engine()
        core._store = wasmtime.Store(engine)
        action = [lambda caller: 7]
        dispatch = wasmtime.Func(core._store,
            wasmtime.FuncType([], [wasmtime.ValType.i32()]),
            lambda caller: action[0](caller), access_caller=True)
        module = wasmtime.Module(engine, f'''(module
            (import "test" "dispatch" (func $dispatch (result i32)))
            (memory (export "memory") 1 {_MEMORY_LIMIT // 65536})
            (func (export "run") (result i32) call $dispatch))''')
        core._instance = wasmtime.Instance(core._store, module, [dispatch])
        exports = core._instance.exports(core._store)
        core._exports = {'memory': exports['memory'],
                         'actql_probe_run': lambda *_: exports['run'](core._store)}
        core._observe_platform_vm(wasmtime)
        return core, binding, store, path, journal_current, action, reservations

    def publisher(self, core, binding, *, current=None, authorize=None):
        ticket = core._next_ticket
        core._next_ticket += 2
        preflight = _Output(core._identity, ticket, 100 + ticket, 8192, 'publication_preflight')
        request = _Input(core._identity, ticket + 1, 101 + ticket, 2)
        core._loans[ticket], core._loans[ticket + 1] = preflight, request
        core._inputs[ticket + 1] = _PhysicalInput(b'{}', lambda: True, lambda _: True)
        physical = _OriginalPublisherPort(binding) if current is None else None
        output = core.reserve_publisher(preflight, request,
            current=physical.current_callback if physical else current,
            authorize=physical.authorize_callback if physical else authorize,
            cleanup=lambda: True, original=physical)
        return output, physical

    def imports(self, core):
        return {name: core._observation_import('publisher_' + name,
                getattr(core, '_publisher_' + name)) for name in ('current', 'begin', 'copy', 'finish')}

    def wire(self, stage='request', namespace='local'):
        return json.dumps({'stage': stage, 'namespace_id': namespace,
            'authority_scope_cid': 'scope', 'run_definition_cid': 'definition',
            'publication_request_cid': 'request',
            'public_index_entry_cid': None if stage == 'request' else 'index'},
            separators=(',', ':')).encode()

    def transfer(self, core, imports, caller, ticket, payload):
        core._exports['memory'].write(core._store, payload, 64)
        self.assertEqual(imports['begin'](ticket, len(payload)), 0)
        self.assertEqual(imports['copy'](caller, ticket, 0, 64, len(payload)), len(payload))
        return imports['finish'](ticket)

    def run_export(self, core, binding, actions, action):
        actions[0] = action
        returned = []
        binding.inspect(lambda _: returned.append(core._call('probe', 'run')))
        return returned

    def test_nineteen_cycles_keep_every_callback_with_only_entry_effect_exit_graphs(self):
        core, binding, _, _, _, actions, _ = self.fixture()
        output, physical = self.publisher(core, binding)
        imports = self.imports(core)
        graphs, currents, spans, stops, callback_calls = [], [], [], [], []
        original_graph = OriginalHostBinding._physical_current
        original_profile = sys.getprofile()
        def profile(frame, event, arg):
            if event == 'call' and frame.f_code in (
                    _OriginalPublisherPort.current.__code__, _OriginalPublisherPort.authorize.__code__):
                callback_calls.append(frame.f_code.co_name)
        def graph(receiver):
            graphs.append(receiver)
            return original_graph(receiver)
        stop = core._observation_import('reader_stop', lambda: stops.append(True) or 0)
        def action(caller):
            before = len(graphs)
            spans.append(core._invocation_observation)
            for _ in range(19):
                currents.append(imports['current'](output.ticket))
                self.assertEqual(self.transfer(core, imports, caller, output.ticket, self.wire()), 0)
                currents.append(imports['current'](output.ticket))
            self.assertEqual(len(graphs) - before, 1)
            self.assertEqual(stop(), 0)
            self.assertEqual(len(graphs) - before, 3)
            self.assertIs(core._invocation_observation.publisher, physical)
            return 7
        with patch.object(OriginalHostBinding, '_physical_current', graph):
            def consume(_):
                before = len(graphs)
                actions[0] = action
                sys.setprofile(profile)
                try:
                    self.assertEqual(core._call('probe', 'run'), 7)
                finally:
                    sys.setprofile(original_profile)
                self.assertEqual(len(graphs) - before, 4)
            binding.inspect(consume)
        self.assertEqual(currents, [0] * 38)
        self.assertEqual(callback_calls.count('current'), 38)
        self.assertEqual(callback_calls.count('authorize'), 19)
        self.assertEqual(stops, [True])
        self.assertIsNone(spans[0].publisher)
        self.assertIsNone(spans[0].publisher_buffer)
        self.assertIsNone(physical.callbacks.buffer)

    def test_all_stages_preserve_namespace_denial_without_reusing_grants(self):
        core, binding, _, _, _, actions, _ = self.fixture()
        output, _ = self.publisher(core, binding)
        imports = self.imports(core)
        def action(caller):
            for stage in ('request', 'commit', 'return_committed'):
                for namespace, code in (('local', 0), ('foreign', -1), ('local', 0)):
                    self.assertEqual(self.transfer(core, imports, caller, output.ticket,
                                                  self.wire(stage, namespace)), code)
            self.assertIsNone(core._invocation_observation.failure)
            return 7
        self.assertEqual(self.run_export(core, binding, actions, action), [7])

    def test_arbitrary_callbacks_keep_original_order_and_effect_fences(self):
        core, binding, _, _, journal_current, actions, _ = self.fixture()
        events = []
        def current():
            self.assertTrue(core._invocation_observation.suspended)
            events.append('current')
            binding.current()
            return True
        def authorize(fact):
            self.assertTrue(core._invocation_observation.suspended)
            events.append(('authorize', fact.namespace_id))
            binding.current()
            return fact.namespace_id == 'allowed'
        output, _ = self.publisher(core, binding, current=current, authorize=authorize)
        imports = self.imports(core)
        def action(caller):
            self.assertEqual(journal_current(), 0)
            for namespace, code in (('allowed', 0), ('denied', -1)):
                self.assertEqual(imports['current'](output.ticket), 0)
                self.assertEqual(self.transfer(core, imports, caller, output.ticket,
                                              self.wire(namespace=namespace)), code)
                self.assertEqual(imports['current'](output.ticket), 0)
            self.assertIsNone(core._invocation_observation.publisher)
            return 7
        self.assertEqual(self.run_export(core, binding, actions, action), [7])
        self.assertEqual(events, ['current', ('authorize', 'allowed'), 'current',
                                  'current', ('authorize', 'denied'), 'current'])

    def test_second_original_publisher_uses_effects_without_expanding_the_pin(self):
        core, binding, _, _, _, actions, _ = self.fixture()
        first, first_port = self.publisher(core, binding)
        second, _ = self.publisher(core, binding)
        imports, suspended = self.imports(core), []
        original = OriginalHostBinding._physical_current
        def graph(receiver):
            span = core._invocation_observation
            if span is not None:
                suspended.append(span.suspended)
            return original(receiver)
        def action(caller):
            self.assertEqual(imports['current'](first.ticket), 0)
            self.assertEqual(imports['current'](second.ticket), 0)
            self.assertEqual(self.transfer(core, imports, caller, second.ticket, self.wire()), 0)
            self.assertIs(core._invocation_observation.publisher, first_port)
            return 7
        with patch.object(OriginalHostBinding, '_physical_current', graph):
            self.assertEqual(self.run_export(core, binding, actions, action), [7])
        self.assertIn(True, suspended)

    def test_custom_memory_before_selection_keeps_the_legacy_publisher_path(self):
        core, binding, _, _, _, actions, _ = self.fixture()
        output, _ = self.publisher(core, binding)
        imports = self.imports(core)
        memory = core._exports['memory']
        original = memory.read
        memory.read = lambda *args: original(*args)
        def action(caller):
            self.assertEqual(imports['current'](output.ticket), 0)
            self.assertEqual(self.transfer(core, imports, caller, output.ticket, self.wire()), 0)
            self.assertIsNone(core._invocation_observation.publisher)
            return 7
        try:
            self.assertEqual(self.run_export(core, binding, actions, action), [7])
        finally:
            del memory.read

    def test_post_selection_identity_changes_refuse_before_effect_and_remain_latched(self):
        for mode in ('port_copy', 'binding_copy', 'callback', 'collector', 'collector_count',
                     'physical_copy', 'output_copy', 'callbacks_copy', 'retired', 'memory'):
            with self.subTest(mode=mode):
                core, binding, _, _, _, actions, _ = self.fixture()
                output, port = self.publisher(core, binding)
                callbacks = port.callbacks
                imports, failures, effects = self.imports(core), [], []
                effect = core._observation_import('future_unknown_import', lambda: effects.append(True))
                def action(caller):
                    self.assertEqual(imports['current'](output.ticket), 0)
                    self.assertEqual(imports['begin'](output.ticket, 3), 0)
                    target, key, replacement = {
                        'port_copy': (callbacks, 'original', copy.copy(port)),
                        'binding_copy': (port, 'binding', copy.copy(binding)),
                        'callback': (callbacks, 'current', lambda: effects.append(True) or True),
                        'collector': (callbacks, 'buffer', bytearray(3)),
                        'collector_count': (callbacks, 'received', 1),
                        'physical_copy': (core._inputs, output.ticket, copy.copy(port.physical)),
                        'output_copy': (core._loans, output.ticket, copy.copy(output)),
                        'callbacks_copy': (port.physical, 'publisher', copy.copy(callbacks)),
                        'retired': (core._inputs, output.ticket, None),
                        'memory': (core._exports['memory'], 'read', lambda *_: bytearray(3)),
                    }[mode]
                    old = target.get(key) if type(target) is dict else getattr(target, key)
                    if type(target) is dict:
                        target[key] = replacement
                    else:
                        setattr(target, key, replacement)
                    try:
                        try:
                            if mode == 'memory':
                                imports['copy'](caller, output.ticket, 0, 64, 3)
                            else:
                                effect()
                        except ValueError as error:
                            failures.append(error)
                    finally:
                        if type(target) is dict:
                            target[key] = old
                        elif mode == 'memory':
                            delattr(target, key)
                        else:
                            setattr(target, key, old)
                    return 7
                with self.assertRaises(ValueError) as caught:
                    self.run_export(core, binding, actions, action)
                self.assertIs(caught.exception, failures[0])
                self.assertFalse(effects)
                self.assertIs(core._loans[output.ticket], output)

    def test_unknown_collector_or_copy_cannot_escape_after_export_swallows_it(self):
        for mode in ('begin', 'copy', 'finish', 'malformed'):
            with self.subTest(mode=mode):
                core, binding, _, _, _, actions, _ = self.fixture()
                output, _ = self.publisher(core, binding)
                imports, failures = self.imports(core), []
                def action(caller):
                    self.assertEqual(imports['current'](output.ticket), 0)
                    try:
                        if mode == 'begin':
                            imports['begin'](output.ticket, _PUBLISHER_LIMIT + 1)
                        else:
                            self.assertEqual(imports['begin'](output.ticket, 3), 0)
                            if mode == 'copy':
                                imports['copy'](caller, output.ticket, 1, 64, 3)
                            elif mode == 'finish':
                                imports['finish'](output.ticket)
                            else:
                                core._exports['memory'].write(core._store, b'bad', 64)
                                self.assertEqual(imports['copy'](caller, output.ticket, 0, 64, 3), 3)
                                imports['finish'](output.ticket)
                    except ValueError as error:
                        failures.append(error)
                    return 7
                with self.assertRaises(ValueError) as caught:
                    self.run_export(core, binding, actions, action)
                self.assertIs(caught.exception, failures[0])
                self.assertIs(core._loans[output.ticket], output)

    def test_current_adapter_cannot_swallow_original_failure_or_reentry(self):
        for mode in ('failure', 'reentry'):
            with self.subTest(mode=mode):
                core, binding, _, _, _, actions, _ = self.fixture()
                output, port = self.publisher(core, binding)
                imports, failures = self.imports(core), []
                error = ValueError('original publisher failure')
                def action(caller):
                    self.assertEqual(imports['current'](output.ticket), 0)
                    if mode == 'failure':
                        port.failure = error
                    else:
                        try:
                            core._call('probe', 'run')
                        except RuntimeError as failure:
                            failures.append(failure)
                    # Exercise the raw ABI adapter which deliberately returns
                    # Unknown instead of propagating a Python exception.
                    self.assertEqual(core._publisher_current(output.ticket), -2)
                    return 7
                with self.assertRaises((ValueError, RuntimeError)) as caught:
                    self.run_export(core, binding, actions, action)
                self.assertIs(caught.exception, error if mode == 'failure' else failures[0])
                self.assertIs(core._loans[output.ticket], output)

    def test_port_copies_and_foreign_callbacks_refuse_before_reservation(self):
        core, binding, _, _, _, _, reservations = self.fixture()
        output, port = self.publisher(core, binding)
        preflight = next(value for value in core._loans.values()
                         if type(value) is _Output and value.family == 'publication_preflight')
        request = core._loans[preflight.ticket + 1]
        before = len(reservations)
        with self.assertRaises(ValueError):
            _OriginalPublisherPort(copy.copy(binding))
        for original, current, authorize in (
                (copy.copy(port), port.current_callback, port.authorize_callback),
                (_OriginalPublisherPort(binding), lambda: True, lambda _: True)):
            with self.assertRaises(ValueError):
                core.reserve_publisher(preflight, request, current=current, authorize=authorize,
                                       cleanup=lambda: True, original=original)
        self.assertEqual(len(reservations), before)
        self.assertIs(core._loans[output.ticket], output)

    def test_metadata_is_charged_and_failed_bind_keeps_issued_output_and_input(self):
        core, binding, _, _, _, _, reservations = self.fixture()
        output, port = self.publisher(core, binding)
        base = (128 * _PUBLISHER_LIMIT + 4096 + sys.getsizeof(port.callbacks)
                + sys.getsizeof(port.physical))
        self.assertEqual(reservations[-1][-1], base + sys.getsizeof(port)
            + sys.getsizeof(port.current_callback) + sys.getsizeof(port.authorize_callback))
        self.assertGreaterEqual(sys.getsizeof(object.__new__(_InvocationObservation)),
                                len(_InvocationObservation.__slots__) * 8)
        bind = _OriginalPublisherPort._bind
        captured = []
        def fail(receiver, value, physical, callbacks):
            bind(receiver, value, physical, callbacks)
            captured.append((value, physical))
            raise ValueError('bind failed after original issuance')
        with patch.object(_OriginalPublisherPort, '_bind', fail):
            with self.assertRaisesRegex(ValueError, 'bind failed'):
                self.publisher(core, binding)
        value, physical = captured[0]
        self.assertIs(core._loans[value.ticket], value)
        self.assertIs(core._inputs[value.ticket], physical)
        self.assertEqual(core._cleanup(value.ticket), 0)
        self.assertIs(core._loans[value.ticket], value)


if __name__ == '__main__':
    unittest.main()
