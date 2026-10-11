"""Physical authentication fixtures, independent of the real Core consumer."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalByteStore, LocalStorageError
from actql_sdk._local_submission import LocalSubmissionAuthority, LocalSubmissionIdentityError

# Owner's published independent identity vectors, not Python product output.
SCOPE = 'sha256:' + 'a' * 64
WIRE = ('{"authority_scope_cid":"' + SCOPE + '","epoch_nonce":"' + 'b' * 64 +
        '","expires_at":1800000001000,"not_before":1800000000000,'
        '"version":"actql-submission-epoch/0.1"}')
EPOCH_CID = 'sha256:864dc9b8f1f801ba4e70683c04a5a0e66146a9ec38e74d93797f8b1bf29d600a'
REQUEST_ID = 'sha256:cdf4c7466562674bab239a1a938f6a8784cc9efc07472edeb5f3efe44d7e3c27'


class LocalSubmissionAuthenticationTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=4096, max_payload_bytes=32768)

    def projector(self, kind, payload):
        body = json.loads(payload)
        self.assertEqual(body['authority_scope_cid'], SCOPE)
        self.assertEqual(body['epoch_nonce'], 'b' * 64)
        self.assertEqual(body['not_before'], 1800000000000)
        self.assertEqual(body['expires_at'], 1800000001000)
        result = {'epoch_wire': WIRE, 'epoch_cid': EPOCH_CID}
        if kind == 2:
            self.assertEqual(body['caller_nonce'], 'request-1')
            result |= {'request_id': REQUEST_ID, 'validity': 'admissible'}
        return json.dumps(result).encode()

    def test_original_reference_survives_reopen_without_an_execution(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store, patch('actql_sdk._local_submission.secrets.token_hex',
                                                 side_effect=['c' * 64, 'b' * 64]):
                authority = LocalSubmissionAuthority(store, self.projector,
                                                     now=lambda: 1800000000000, ttl_ms=1000)
                ref = {'epoch': authority.issue_epoch(SCOPE), 'nonce': 'request-1'}
                original = copy.deepcopy(ref)
                result = authority.identity(ref)
                self.assertEqual(result.request_id, REQUEST_ID)
                self.assertEqual(result.epoch_cid, EPOCH_CID)
            with self.store(path) as store:
                # A backwards wall clock does not rewind the durable observation.
                authority = LocalSubmissionAuthority(store, self.projector, now=lambda: 1)
                self.assertEqual(authority.identity(original), result)
                self.assertEqual(store.read('submission-epoch-authority').generation, 1)
                forged = copy.deepcopy(original)
                forged['epoch']['authenticator'] = '0' * 64
                with self.assertRaisesRegex(LocalSubmissionIdentityError, 'authentication failed'):
                    authority.identity(forged)
                self.assertEqual(original, ref)

    def test_missing_key_on_reopen_or_after_bootstrap_is_not_recreated(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path):
                pass
            with self.store(path) as store:
                with self.assertRaisesRegex(LocalSubmissionIdentityError, 'custody is missing'):
                    LocalSubmissionAuthority(store, self.projector, now=lambda: 0)
                self.assertIsNone(store.read('submission-epoch-authority'))
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            LocalSubmissionAuthority(store, self.projector, now=lambda: 0)
            store._connection.execute('DELETE FROM core_bytes')
            with self.assertRaisesRegex(LocalSubmissionIdentityError, 'custody is missing'):
                LocalSubmissionAuthority(store, self.projector, now=lambda: 0)

    def test_lost_cas_acknowledgement_never_retries_or_replaces_custody(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = store.compare_exchange
            calls = []
            def lost(*args):
                calls.append(args)
                original(*args)
                raise LocalStorageError('Independent lost commit acknowledgement')
            with patch.object(store, 'compare_exchange', side_effect=lost):
                with self.assertRaisesRegex(LocalSubmissionIdentityError, 'creation is unknown'):
                    LocalSubmissionAuthority(store, self.projector, now=lambda: 0)
            self.assertEqual(len(calls), 1)
            retained = store.read('submission-epoch-authority')
            authority = LocalSubmissionAuthority(store, self.projector, now=lambda: 0)
            with patch.object(store, 'compare_exchange', side_effect=lost):
                authority._now = lambda: 10
                with self.assertRaisesRegex(LocalSubmissionIdentityError, 'persistence is unknown'):
                    authority.issue_epoch(SCOPE)
            self.assertEqual(len(calls), 2)
            self.assertEqual(json.loads(store.read('submission-epoch-authority').payload)['authentication_key'],
                             json.loads(retained.payload)['authentication_key'])

    def test_closed_projection_and_wire_reject_before_identity_is_exposed(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            authority = LocalSubmissionAuthority(store, self.projector, now=lambda: 1800000000000,
                                                 ttl_ms=1000)
            with patch('actql_sdk._local_submission.secrets.token_hex', return_value='b' * 64):
                ref = {'epoch': authority.issue_epoch(SCOPE), 'nonce': 'request-1'}
            for invalid in ({**ref, 'unknown': None}, {'epoch': ref['epoch'], 'nonce': 'e\u0301'},
                            {'epoch': ref['epoch'], 'nonce': None}):
                with self.assertRaises(LocalSubmissionIdentityError):
                    authority.identity(invalid)
            for raw in (b'{"epoch_wire":"x","epoch_wire":"y"}',
                        json.dumps({'epoch_wire': WIRE, 'epoch_cid': EPOCH_CID,
                                    'request_id': REQUEST_ID, 'validity': 'success'}).encode(),
                        json.dumps({'epoch_wire': WIRE.replace('1800000001000', '1800000002000'),
                                    'epoch_cid': EPOCH_CID, 'request_id': REQUEST_ID,
                                    'validity': 'admissible'}).encode()):
                authority._project = lambda kind, payload, raw=raw: raw
                with self.assertRaises(LocalSubmissionIdentityError):
                    authority.identity(ref)
