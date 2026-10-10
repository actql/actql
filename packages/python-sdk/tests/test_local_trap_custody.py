"""Interrupted Core calls prohibit fresh work and preserve physical custody."""
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, _Input, _NativeAttempt, _Output


class TrapCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._native_loans = {}
        core._native_observers = {}
        core._next_ticket = 1
        core._closed = False
        core._retired = False
        core._closing = False
        core._invoking = False
        core._nonce = 1
        core._store = object()
        calls = []
        def interrupted(*args):
            calls.append(args)
            raise RuntimeError('Independent Core trap after entering Wasm')
        core._exports = {'actql_buffer_reserve': interrupted}
        return core, calls

    def test_trap_preserves_original_physical_ticket_and_blocks_fresh_reservation(self):
        core, calls = self.bridge()
        payload = b'e\xcc\x81\r\nNULL'
        cleanup = []
        with self.assertRaises(RuntimeError):
            core.reserve_input(payload, cleanup=lambda: cleanup.append(1) or True,
                               stopped=lambda _: False)
        self.assertTrue(core._closing)
        self.assertFalse(core._retired)
        self.assertFalse(core._closed)
        self.assertFalse(core._invoking)
        self.assertIs(core._inputs[1].payload, payload)
        self.assertEqual(cleanup, [])
        with self.assertRaises(ValueError):
            core.reserve_input(b'new', cleanup=lambda: True, stopped=lambda _: True)
        self.assertEqual(len(calls), 1)
        self.assertEqual(core._next_ticket, 2)
        self.assertEqual(list(core._inputs), [1])

    def test_closing_instance_rejects_producers_but_allows_exact_loan_retirement(self):
        core, calls = self.bridge()
        core._closing = True
        input = _Input(core._identity, 1, 13, 7)
        output = _Output(core._identity, 2, 19, 100_000, 'source')
        attempt = _NativeAttempt(core._identity, 17)
        core._loans = {1: input, 2: output}
        core._native_loans = {17: attempt}
        core._native_observers = {17: (lambda: False, lambda: True, lambda: True)}
        for action in (lambda: core.fill_input(input, 0, 1),
                       lambda: core.seal_input(input),
                       lambda: core.produce_native_command(output),
                       lambda: core.start_native_attempt(attempt),
                       lambda: core.accept_native_event(attempt, 4, input)):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(calls, [])
        core._exports['actql_source_close_attempt'] = lambda *args: calls.append(args) or 0
        self.assertTrue(core.close_native_attempt(attempt))
        self.assertEqual(calls, [(core._store, 1, 17)])
        self.assertNotIn(17, core._native_observers)
        self.assertIs(core._loans[input.ticket], input)


if __name__ == '__main__':
    unittest.main()
