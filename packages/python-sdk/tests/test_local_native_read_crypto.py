"""Independent out-slot/entry faults; actual provider execution is separate."""
import copy
import pickle
from threading import Thread
import unittest

from test_local_native_control_custody import Function
from test_local_native_host_resources import PairFixture
from actql_sdk._local_native_read_crypto import (
    _OriginalReadCryptoCustody, _OriginalReadCryptoFunctions, _OriginalReadCryptoError,
    _RETIRED_READ_CRYPTO_DATA,
)


class CryptoFixture(PairFixture):
    def __init__(self):
        super().__init__()
        self.p = self.pair()
        self.crypto_events, self.crypto_replies = [], {}
        self.crypto_issues, self.crypto_faults = {}, {}
        self.component_present, self.library_present = True, True
        self.library_serial = 1200
        self.foreign = False
        self.reply_override = None
        calls = {
            'prepare_into': self.crypto_prepare,
            'load_utf16_into': self.crypto_load,
            'operate_into': self.crypto_operate,
            'hmac_into': self.crypto_hmac,
            'verify_into': self.crypto_verify,
            'originals_into': self.crypto_originals,
            'operation': lambda r: self.crypto_replies[r.value][0],
            'issue_origin': lambda r: self.crypto_replies[r.value][1],
            'issue_family': lambda r: self.crypto_replies[r.value][2],
            'close_confirmed': lambda r: int(self.crypto_replies[r.value][0] in (4, 5)
                and self.crypto_replies[r.value][1] == 0),
            'verification': lambda r: 0,
            'copy_output': self.crypto_output,
            'drop_reply': self.crypto_drop,
            'finish_closed_data': self.crypto_finish,
            'finish_refused_prepare': self.crypto_finish,
            'finish_refused_library': self.crypto_finish,
        }
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_read_crypto_' + name, Function(call))
        self.crypto_functions = _OriginalReadCryptoFunctions(self.host._functions.library)

    def crypto_result(self, op, output, library=None):
        assert self.host._busy
        assert self.r._crypto_original is not None
        issue = self.crypto_issues.get(op, (0, 0))
        reply = 1400 + len(self.crypto_replies)
        self.crypto_replies[reply] = op, *issue, library
        self.crypto_events.append(op)
        output._obj.value = reply
        if op in self.crypto_faults:
            raise self.crypto_faults[op]
        return 0

    def crypto_prepare(self, h, p, r, output):
        assert (h.value, p.value, r.value) == (101, 801, 701)
        assert self.p._phase is None
        return self.crypto_result(1, output)

    def crypto_load(self, h, p, r, c, path, units, heap, diagnostic, output):
        assert self.p._phase == 'read'
        assert c.value == 1101
        return self.crypto_result(2, output)

    def crypto_operate(self, h, p, r, c, library, op, output):
        assert self.p._phase == 'read'
        assert c.value == 1101
        if op == 3:
            self.library_serial += 1
            return self.crypto_result(op, output, self.library_serial if self.library_present else None)
        return self.crypto_result(op, output, library.value)

    def crypto_hmac(self, *args):
        return self.crypto_result(6, args[-1], args[4].value)

    def crypto_verify(self, *args):
        return self.crypto_result(7, args[-1], args[4].value)

    def crypto_originals(self, reply, *outputs):
        values = [101, 801, 701, 1101 if self.component_present else None,
                  self.crypto_replies[reply.value][3]]
        if self.foreign:
            values[2] = 999
        for out, value in zip(outputs, values):
            assert out._obj.value is None
            out._obj.value = value
        return 0

    def crypto_drop(self, reply, *originals):
        assert len(originals) == 5
        reply._obj.value = None
        if 'drop' in self.crypto_faults:
            raise self.crypto_faults['drop']
        return 0

    def crypto_output(self, reply, *args):
        output, capacity, length = args[-3:]
        assert capacity == 32
        for i in range(32):
            output[i] = i
        length._obj.value = 32
        return 0

    def crypto_finish(self, *outputs):
        for out in outputs:
            out._obj.value = None
        if 'finish' in self.crypto_faults:
            raise self.crypto_faults['finish']
        return 0

    def crypto(self):
        return _OriginalReadCryptoCustody._prepare_original(self.p, self.crypto_functions)

    def loaded(self):
        c = self.crypto()
        self.p._call(3)
        c.load(path='/selected/component', heap_bytes=32768, diagnostic_ceiling=128)
        return c


class OriginalReadCryptoTests(unittest.TestCase):
    def test_two_original_libraries_keep_parent_until_separate_acks(self):
        f = CryptoFixture(); c = f.loaded(); a = c.open_library(); b = c.open_library()
        self.assertNotEqual(a._library.value, b._library.value)
        self.assertEqual(a.hmac_sha256(b'key', b'data'), bytes(range(32)))
        self.assertFalse(b.verify_hmac_sha256(b'key', b'data', b'wrong'))
        with self.assertRaises(ValueError): c.close()
        with self.assertRaises(ValueError): f.p.close()
        a.close()
        with self.assertRaises(ValueError): c.close()
        b.close(); c.close()
        self.assertIs(f.r._crypto_original, _RETIRED_READ_CRYPTO_DATA)
        self.assertFalse(f.r._closed or f.p._closed or f.host._closed)
        self.assertTrue(all(v.value is None for v in (*a._slots(), *b._slots(), *c._slots())))
        self.assertEqual(f.crypto_events, [1, 2, 3, 3, 6, 7, 4, 4, 5])
        before = list(f.crypto_events); c.close(); a.close(); self.assertEqual(f.crypto_events, before)
        f.p.leave_scope(); f.p.close()

    def test_partial_load_retains_original_close_only_and_no_second_load(self):
        f = CryptoFixture(); c = f.crypto(); f.p._call(3); f.crypto_issues[2] = (5, 3)
        with self.assertRaises(_OriginalReadCryptoError) as error:
            c.load(path='/selected/component', heap_bytes=1, diagnostic_ceiling=1)
        self.assertFalse(error.exception.unknown)
        self.assertIs(f.r._crypto_original, c)
        with self.assertRaises(ValueError): c.load(path='/selected/component', heap_bytes=1, diagnostic_ceiling=1)
        with self.assertRaises(ValueError): c.open_library()
        c.close(); self.assertEqual(f.crypto_events, [1, 2, 5])

    def test_partial_library_keeps_exact_child_for_cleanup(self):
        f = CryptoFixture(); c = f.loaded(); f.crypto_issues[3] = (5, 9)
        with self.assertRaises(_OriginalReadCryptoError) as error: c.open_library()
        child = error.exception.cleanup_crypto
        self.assertIs(c._libraries[0], child)
        self.assertIsNotNone(child._library.value)
        with self.assertRaises(ValueError): c.close()
        child.close(); c.close()

    def test_no_library_refusal_retires_only_that_reply(self):
        f = CryptoFixture(); c = f.loaded(); f.crypto_issues[3] = (5, 2); f.library_present = False
        with self.assertRaises(_OriginalReadCryptoError) as error: c.open_library()
        self.assertTrue(error.exception.cleanup_crypto._closed)
        self.assertFalse(c._closed); c.close()

    def test_refused_prepare_remains_one_shot_without_component_ack(self):
        f = CryptoFixture(); f.crypto_issues[1] = (1, 2); f.component_present = False
        with self.assertRaises(_OriginalReadCryptoError) as error: f.crypto()
        self.assertFalse(error.exception.unknown)
        self.assertTrue(error.exception.cleanup_crypto._closed)
        self.assertIs(f.r._crypto_original, _RETIRED_READ_CRYPTO_DATA)
        with self.assertRaises(ValueError): f.crypto()
        self.assertEqual(f.crypto_events, [1])

    def test_response_loss_keeps_slots_and_fences_no_resend_or_parent_close(self):
        for op in (1, 2, 3, 4, 5, 6, 7):
            with self.subTest(op=op):
                f = CryptoFixture()
                if op == 1:
                    f.crypto_faults[op] = OSError('lost original reply')
                    action = f.crypto
                else:
                    c = f.loaded()
                    a = c.open_library() if op in (4, 6, 7) else None
                    f.crypto_faults[op] = OSError('lost original reply')
                    action = {2: lambda: None, 3: c.open_library, 4: lambda: a.close(),
                              5: c.close, 6: lambda: a.hmac_sha256(b'k', b'd'),
                              7: lambda: a.verify_hmac_sha256(b'k', b'd', b's')}[op]
                    if op == 2:
                        # Use a fresh unconsumed original for the load loss.
                        f = CryptoFixture(); c = f.crypto(); f.p._call(3)
                        f.crypto_faults[2] = OSError('lost original reply')
                        action = lambda: c.load(path='/selected/component', heap_bytes=1, diagnostic_ceiling=1)
                with self.assertRaises(_OriginalReadCryptoError) as error: action()
                original = error.exception.cleanup_crypto
                self.assertTrue(error.exception.unknown)
                self.assertIsNotNone(original._reply.value)
                before = list(f.crypto_events)
                with self.assertRaises(_OriginalReadCryptoError): original.close()
                with self.assertRaises(_OriginalReadCryptoError): f.p.close()
                self.assertEqual(f.crypto_events, before)

    def test_busy_thread_and_wrong_phase_preflight_do_not_consume_registration(self):
        f = CryptoFixture(); f.host._busy = True
        with self.assertRaises(ValueError): f.crypto()
        self.assertIsNone(f.r._crypto_original)
        f.host._busy = False
        errors = []
        def foreign_thread():
            try: f.crypto()
            except BaseException as error: errors.append(error)
        thread = Thread(target=foreign_thread); thread.start(); thread.join()
        self.assertEqual(len(errors), 1); self.assertIsNone(f.r._crypto_original)
        c = f.crypto()
        with self.assertRaises(ValueError): c.load(path='/selected/component', heap_bytes=1, diagnostic_ceiling=1)
        self.assertFalse(c._attempted); self.assertIsNone(c._unknown)
        f.p._call(3); c.load(path='/selected/component', heap_bytes=1, diagnostic_ceiling=1)
        c.close()

    def test_foreign_original_capture_is_sticky_and_not_reissued(self):
        f = CryptoFixture(); f.foreign = True
        with self.assertRaises(_OriginalReadCryptoError) as error: f.crypto()
        self.assertTrue(error.exception.unknown)
        self.assertIs(f.r._crypto_original, error.exception.cleanup_crypto)
        before = list(f.crypto_events)
        with self.assertRaises(ValueError): f.crypto()
        self.assertEqual(f.crypto_events, before)

    def test_copy_pickle_and_retired_calls_cannot_gain_original(self):
        f = CryptoFixture(); c = f.loaded(); a = c.open_library()
        for value in (c, a):
            for operation in (copy.copy, copy.deepcopy, pickle.dumps):
                with self.assertRaises(TypeError): operation(value)
        a.close(); c.close()
        with self.assertRaises(ValueError): a.hmac_sha256(b'k', b'd')
        with self.assertRaises(ValueError): c.open_library()

    def test_close_response_loss_never_uses_cleared_slots_as_ack(self):
        f = CryptoFixture(); c = f.loaded(); f.crypto_faults['finish'] = OSError('lost data acknowledgment')
        with self.assertRaises(_OriginalReadCryptoError) as error: c.close()
        self.assertTrue(error.exception.unknown)
        self.assertFalse(c._closed)
        self.assertTrue(all(v.value is None for v in c._slots()))
        with self.assertRaises(_OriginalReadCryptoError): f.p.close()


if __name__ == '__main__':
    unittest.main()
