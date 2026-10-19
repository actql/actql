"""Independent typed Library/input transport faults, not Native open execution."""
import unittest

from test_local_native_control_custody import Function
from test_local_native_read_crypto import CryptoFixture
from test_local_native_adoption import AdoptionFixture
from actql_sdk._local_native_adoption import (
    _OriginalAdoptionCustody, _OriginalAdoptionError, _OriginalAdoptionFunctions, _RETIRED_ADOPTION_DATA,
)


class AdoptionCryptoFixture(CryptoFixture):
    fault = AdoptionFixture.fault
    prepare_adoption = AdoptionFixture.prepare_adoption
    assert_registered = AdoptionFixture.assert_registered
    adoption_operate = AdoptionFixture.adoption_operate
    adoption_result = AdoptionFixture.adoption_result
    adoption_journal = AdoptionFixture.adoption_journal
    adoption_drop_originals = AdoptionFixture.adoption_drop_originals
    adoption_drop = AdoptionFixture.adoption_drop
    adoption_finish = AdoptionFixture.adoption_finish
    def __init__(self):
        super().__init__()
        self.component = self.loaded()
        self.crypto = self.component.open_library()
        self.p.leave_scope()
        self.transport = []
        self.adoption_events, self.adoption_facts = [], {}
        self.adoption_faults, self.adoption_issues = {}, {}
        self.session = self.journal = None
        self.original_override = self.tag_override = self.issue_override = None
        calls = {'operate_into': self.adoption_operate,
                 'capture_journal_into': self.adoption_journal,
                 'originals_into': self.adoption_originals,
                 'drop_originals': self.adoption_drop_originals,
                 'operation': lambda r: self.adoption_facts[r.value][0],
                 'issue_family': lambda r: self.adoption_facts[r.value][1],
                 'drop_reply': self.adoption_drop, 'finish_closed_data': self.adoption_finish}
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_local_adoption_' + name, Function(call))
        self.adoption_functions = _OriginalAdoptionFunctions(self.host._functions.library)
        self.host._functions.library.actql_local_adoption_prepare_utf16_into = Function(self.prepare_utf16)

    @staticmethod
    def text(buffer, units):
        raw = b''.join(int(buffer[i]).to_bytes(2, 'little') for i in range(units))
        return raw.decode('utf-16-le')

    def prepare_utf16(self, *args):
        assert self.host._busy
        assert (args[0].value, args[1].value, args[2].value, args[3].value) == (101, 801, 701, self.crypto._library.value)
        assert self.crypto._adoption_original is self.r._adoption_original
        self.transport.append(args)
        return self.prepare_adoption(args[-1])

    def adoption_originals(self, original, *outputs):
        self.adoption_events.append(('originals',))
        values = [101, 801, 701, self.crypto._library.value, self.session, self.journal]
        if self.original_override is not None:
            values[self.original_override] = 999
        for slot, value in zip(outputs, values):
            assert slot._obj.value is None
            slot._obj.value = value
        self.fault('originals')
        return 0

    def adopt(self, **changes):
        values = dict(parent_path='/原/😀', state_name='state', source_path='/source',
            source_name='source', account_id='account', configuration_files=('a😀', 'b'),
            managed_root_path=None, diagnostic_ceiling=128)
        values.update(changes)
        return _OriginalAdoptionCustody._open_from_original_library(
            self.p, self.adoption_functions, self.crypto, **values)


class OriginalAdoptionCryptoTests(unittest.TestCase):
    def test_exact_original_utf16_and_child_ack_before_library_close(self):
        f = AdoptionCryptoFixture(); a = f.adopt()
        args = f.transport[0]
        self.assertEqual(f.text(args[4], args[5]), '/原/😀')
        self.assertEqual(args[5], 5)
        self.assertEqual([f.text(args[i], args[i + 1]) for i in (6, 8, 10, 12)],
            ['state', '/source', 'source', 'account'])
        self.assertEqual(f.text(args[14], args[15]), 'a😀b')
        self.assertEqual(list(args[16]), [3, 1])
        self.assertEqual((args[17], args[19], args[20], args[21]), (2, 0, 0, 128))
        self.assertIs(f.crypto._adoption_original, a)
        with self.assertRaises(ValueError): f.crypto.close()
        self.assertIsNone(f.crypto._unknown)
        a.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608)
        self.assertEqual(a.current().operation, 2)
        a.close()
        self.assertIs(f.crypto._adoption_original, _RETIRED_ADOPTION_DATA)
        with f.p.scope('read'):
            f.crypto.close(); f.component.close()
        self.assertTrue(f.crypto._closed)

    def test_managed_path_and_empty_configuration_are_exact(self):
        f = AdoptionCryptoFixture(); a = f.adopt(configuration_files=(), managed_root_path='/managed😀')
        args = f.transport[0]
        self.assertEqual((args[15], args[17], args[20]), (0, 0, 1))
        self.assertEqual(f.text(args[18], args[19]), '/managed😀')
        a.close()

    def test_local_input_and_busy_refusal_register_nothing(self):
        for change in [dict(configuration_files=['a']), dict(configuration_files=('a',) * 9),
                dict(configuration_files=('x' * 4097,)), dict(parent_path='😀' * 2049),
                dict(managed_root_path=''), dict(diagnostic_ceiling=True), dict(account_id='')]:
            f = AdoptionCryptoFixture()
            with self.assertRaises(ValueError): f.adopt(**change)
            self.assertIsNone(f.crypto._adoption_original)
            self.assertIsNone(f.r._adoption_original)
            self.assertFalse(f.transport)
        f = AdoptionCryptoFixture(); f.host._busy = True
        with self.assertRaises(ValueError): f.adopt()
        self.assertTrue(f.host._busy)
        self.assertIsNone(f.crypto._adoption_original)
        f.host._busy = False
        f.adopt().close()

    def test_foreign_library_pair_and_closed_library_are_not_prepared(self):
        f = AdoptionCryptoFixture(); other = AdoptionCryptoFixture()
        with self.assertRaises(ValueError):
            _OriginalAdoptionCustody._open_from_original_library(f.p, f.adoption_functions,
                other.crypto, parent_path='/p', state_name='s', source_path='/r', source_name='r',
                account_id='a', configuration_files=(), managed_root_path=None, diagnostic_ceiling=128)
        with f.p.scope('read'): f.crypto.close()
        with self.assertRaises(ValueError): f.adopt()
        self.assertFalse(f.transport)

    def test_lost_prepare_keeps_original_borrow_and_never_repeats(self):
        f = AdoptionCryptoFixture(); f.adoption_faults['prepare'] = OSError('lost')
        with self.assertRaises(_OriginalAdoptionError) as caught: f.adopt()
        a = caught.exception.cleanup_adoption
        self.assertTrue(caught.exception.unknown)
        self.assertIs(f.crypto._adoption_original, a)
        with self.assertRaises(_OriginalAdoptionError): a.close()
        with self.assertRaises(_OriginalAdoptionError): f.p._call(3)
        with self.assertRaises(ValueError): f.crypto.close()
        with self.assertRaises(ValueError): f.adopt()
        self.assertEqual(len(f.transport), 1)

    def test_foreign_native_crypto_alias_keeps_unknown_custody(self):
        f = AdoptionCryptoFixture(); f.original_override = 3
        with self.assertRaises(_OriginalAdoptionError) as caught: f.adopt()
        self.assertTrue(caught.exception.unknown)
        self.assertIs(f.crypto._adoption_original, caught.exception.cleanup_adoption)
        self.assertEqual(len(f.transport), 1)

    def test_failed_child_close_keeps_original_library_and_phase_fenced(self):
        f = AdoptionCryptoFixture()
        with f.p.scope('read'): sibling = f.component.open_library()
        a = f.adopt(); f.adoption_issues[3] = 4
        with self.assertRaises(_OriginalAdoptionError) as caught: a.close()
        self.assertFalse(caught.exception.unknown)
        with self.assertRaises(ValueError): f.p._call(3)
        with self.assertRaises(ValueError): f.crypto.close()
        self.assertIsNone(sibling._adoption_original)
        self.assertFalse(f.crypto._closed)
        f.adoption_issues[3] = 0; a.close()
        with f.p.scope('read'): sibling.close(); f.crypto.close(); f.component.close()


if __name__ == '__main__': unittest.main()
