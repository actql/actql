"""Original mutable-slot cleanup counters; scalar calls, no Native allocation."""
from ctypes import POINTER, c_void_p, cast
from types import SimpleNamespace
import unittest

from actql_sdk._local_native_holding import (
    _NativeHoldingLease, NativeHoldingRetirementError,
)
import test_local_installed_image as fixture


class _CloseCall:
    def __init__(self, callback):
        self.callback = callback
        self.slots = []
        self.addresses = []

    def __call__(self, out):
        self.slots.append(out._obj)
        self.addresses.append(cast(out, POINTER(c_void_p))[0])
        return self.callback(out)


class NativeHoldingCloseTests(unittest.TestCase):
    def holding(self, callback):
        call = _CloseCall(callback)
        library = SimpleNamespace(actql_owned_try_close=call)
        lease = _NativeHoldingLease(c_void_p(123), library,
                                    generation=7, recipe=b'r' * 32)
        return lease, call

    def test_lost_return_preserves_original_slot_and_unknown_without_native_retry(self):
        for cleared in (False, True):
            with self.subTest(cleared=cleared):
                original = OSError('Original close return lost')
                def close(out):
                    if cleared:
                        cast(out, POINTER(c_void_p))[0] = None
                    raise original
                lease, call = self.holding(close)
                slot = lease._pointer
                for _ in range(2):
                    with self.assertRaises(OSError) as failure:
                        lease.close()
                    self.assertIs(failure.exception, original)
                self.assertIs(lease._pointer, slot)
                self.assertEqual(slot.value, None if cleared else 123)
                self.assertEqual(call.addresses, [123])
                self.assertIs(call.slots[0], slot)

    def test_malformed_or_mutated_failure_slot_never_becomes_ack_or_reclose(self):
        for code, address in ((True, None), (None, 123), (-2, None), (-2, 456)):
            with self.subTest(code=code, address=address):
                def close(out):
                    cast(out, POINTER(c_void_p))[0] = address
                    return code
                lease, call = self.holding(close)
                with self.assertRaises(NativeHoldingRetirementError) as first:
                    lease.close()
                with self.assertRaises(NativeHoldingRetirementError) as second:
                    lease.close()
                self.assertIs(first.exception, second.exception)
                self.assertEqual(lease._pointer.value, address)
                self.assertEqual(call.addresses, [123])

    def test_success_status_without_cleared_slot_retains_unknown(self):
        lease, call = self.holding(lambda out: 0)
        with self.assertRaises(NativeHoldingRetirementError) as first:
            lease.close()
        with self.assertRaises(NativeHoldingRetirementError) as second:
            lease.close()
        self.assertIs(first.exception, second.exception)
        self.assertEqual(call.addresses, [123])
        self.assertEqual(lease._pointer.value, 123)

    def test_known_nonzero_unchanged_slot_retries_only_same_original(self):
        replies = [-2, 0]
        def close(out):
            code = replies.pop(0)
            if code == 0:
                cast(out, POINTER(c_void_p))[0] = None
            return code
        lease, call = self.holding(close)
        slot = lease._pointer
        with self.assertRaises(NativeHoldingRetirementError):
            lease.close()
        self.assertIs(lease._pointer, slot)
        self.assertEqual(slot.value, 123)
        lease.close()
        lease.close()
        self.assertEqual(call.addresses, [123, 123])
        self.assertTrue(all(value is slot for value in call.slots))
        self.assertIs(lease._pointer, slot)
        self.assertIsNone(slot.value)

    def test_reentry_and_observation_cannot_use_inflight_original(self):
        def close(out):
            if len(call.addresses) == 1:
                with self.assertRaises(NativeHoldingRetirementError):
                    lease.close()
                with self.assertRaises(NativeHoldingRetirementError):
                    lease._capacity_bytes()
                with self.assertRaises(NativeHoldingRetirementError):
                    with lease._scope():
                        self.fail('In-flight holding entered')
            cast(out, POINTER(c_void_p))[0] = None
            return 0
        lease, call = self.holding(close)
        lease.close()
        lease.close()
        self.assertEqual(call.addresses, [123])

    def test_core_retains_same_unknown_cleanup_owner_even_after_slot_clears(self):
        case = fixture.InstalledImageTests()
        case.setUp()
        lease, _ = case._holding([(0, True)])
        core, _ = case._construct_with_baseline(holding=lease)
        original = OSError('Original close return lost')
        def close(out):
            cast(out, POINTER(c_void_p))[0] = None
            raise original
        call = _CloseCall(close)
        lease._try_close = call
        for _ in range(2):
            with self.assertRaises(OSError) as failure:
                core.close()
            self.assertIs(failure.exception, original)
            self.assertIs(core._physical_holding, lease)
            self.assertIsNone(core._store)
            self.assertFalse(core._closed)
            self.assertTrue(core._retired)
        self.assertEqual(call.addresses, [123])
        self.assertIsNone(lease._pointer.value)
        self.assertEqual(case.events.count(('close', 'store')), 1)

    def test_core_holding_only_retry_does_not_enter_native_closing_lease(self):
        case = fixture.InstalledImageTests()
        case.setUp()
        lease, library = case._holding([(0, True)])
        core, _ = case._construct_with_baseline(holding=lease)
        state = {'closing': False, 'enter_calls': 0}
        original_enter = library.actql_owned_enter
        def enter(pointer):
            state['enter_calls'] += 1
            # owned_capacity.c refuses entry after try_close has set closing,
            # including a known physical failure whose original slot survives.
            return -3 if state['closing'] else original_enter(pointer)
        library.actql_owned_enter = enter
        def close(out):
            state['closing'] = True
            if len(call.addresses) == 1:
                return -2
            cast(out, POINTER(c_void_p))[0] = None
            return 0
        call = _CloseCall(close)
        lease._try_close = call
        with self.assertRaises(NativeHoldingRetirementError):
            core.close()
        self.assertIsNone(core._store)
        self.assertIsNone(core._module)
        self.assertIsNone(core._engine)
        self.assertIs(core._physical_holding, lease)
        self.assertFalse(core._closed)
        before = state['enter_calls']
        self.assertTrue(core.close())
        self.assertEqual(state['enter_calls'], before)
        self.assertEqual(call.addresses, [123, 123])
        self.assertIsNone(core._physical_holding)
        self.assertTrue(core._closed)
