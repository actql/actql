"""Physical CAS failure is not permission to execute or resend."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input
from actql_sdk._local_dispatch import (DispatchAction, LocalDispatchUnknown,
                                      reserve_dispatch)
from actql_sdk._local_storage import LocalByteStore, LocalStorageError


class DispatchJournalTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=4096,
                              max_payload_bytes=8192)

    def test_original_bytes_and_core_reconciliation_survive_lost_write_ack(self):
        original = '{"e\u0301/~":"😀\\r\\n","missing":{},"null":null}'
        seen = []
        def decide(raw):
            seen.append(raw)
            return 2 if json.loads(raw)['reserved'] else 1
        with TemporaryDirectory(prefix='actql-python-dispatch-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                exchange = store.compare_exchange
                def lose_ack(*args):
                    self.assertEqual(exchange(*args), 0)
                    raise OSError('Independent lost commit acknowledgement')
                with patch.object(store, 'compare_exchange', lose_ack):
                    with self.assertRaises(LocalDispatchUnknown):
                        reserve_dispatch(store, 'original', request=original,
                                         definition_cid='original-definition', decide=decide)
                self.assertEqual(len(seen), 1)
                self.assertEqual(json.loads(store.read('original').payload)['request'], original)
            with self.store(Path(directory) / 'core.sqlite') as reopened:
                observation = reserve_dispatch(reopened, 'original', request=original,
                                               definition_cid='original-definition', decide=decide)
                self.assertIs(observation.action, DispatchAction.RECONCILE)
                self.assertEqual(observation.retained.generation, 0)
                self.assertEqual(json.loads(observation.retained.payload)['request'], original)
                self.assertEqual(len(seen), 2)

    def test_competing_cas_is_unknown_without_owner_or_storage_retry(self):
        calls = []
        with TemporaryDirectory(prefix='actql-python-dispatch-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as first, self.store(path) as second:
                def decide(raw):
                    calls.append(raw)
                    facts = json.loads(raw)
                    facts['reserved'] = True
                    self.assertEqual(second.compare_exchange('original', None,
                                     json.dumps(facts).encode()), 0)
                    return 1
                with self.assertRaises(LocalDispatchUnknown):
                    reserve_dispatch(first, 'original', request='request',
                                     definition_cid='definition', decide=decide)
                self.assertEqual(len(calls), 1)
                self.assertEqual(first.read('original').generation, 0)

    def test_denial_bad_projection_and_missing_record_do_not_write(self):
        with TemporaryDirectory(prefix='actql-python-dispatch-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                def denied(_):
                    raise LocalCoreError('dispatch_action', -32)
                for decide in (denied, lambda _: True, lambda _: 0, lambda _: 2):
                    with self.assertRaises((LocalCoreError, LocalStorageError)):
                        reserve_dispatch(store, 'original', request='request',
                                         definition_cid='definition', decide=decide)
                    self.assertIsNone(store.read('original'))

    def test_bridge_rejects_copied_foreign_and_invalid_input_before_wasm(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        facts = _Input(core._identity, 1, 7, 30)
        core._loans = {1: facts}
        calls = []
        core._call = lambda *args: calls.append(args) or 2
        self.assertEqual(core.dispatch_action(11, 12, facts), 2)
        for candidate in (copy.copy(facts), _Input(object(), 1, 7, 30)):
            with self.assertRaises(ValueError):
                core.dispatch_action(11, 12, candidate)
        for run, config in ((True, 12), (11, True), (0, 12), (11, 2**31)):
            with self.assertRaises(ValueError):
                core.dispatch_action(run, config, facts)
        core._closing = True
        with self.assertRaises(ValueError):
            core.dispatch_action(11, 12, facts)
        self.assertEqual(calls, [('run', 'dispatch_action', 11, 12, 7)])
