"""Existing Submission Owner identity through real Wasm and durable key custody."""
import copy
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from unittest.mock import patch

from python_local_run_inputs import CONFIGURATION, encode

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore, LocalCoreError, LocalCoreResources
from actql_sdk._local_storage import LocalByteStore
from actql_sdk._local_submission import LocalSubmissionAuthority, LocalSubmissionIdentityError

module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
scope = 'sha256:' + 'a' * 64
# Existing independently fixed logical_request_scope/submission_test.mbt vectors.
epoch_cid = 'sha256:864dc9b8f1f801ba4e70683c04a5a0e66146a9ec38e74d93797f8b1bf29d600a'
request_id = 'sha256:cdf4c7466562674bab239a1a938f6a8784cc9efc07472edeb5f3efe44d7e3c27'
# Independently HMACed fixed Owner preimage with 32 bytes of 0xcc.
authenticator = '43685bd216e423bf5e6208e3d0041a9250c0f6e97fe68b969e5b54ff0ca3398c'
cases = []


class Session:
    def __init__(self, config=None):
        self.core = LocalCore(module, digest=digest, transfer_capacity=65536, slots=32,
                              resources=LocalCoreResources(100000, 64, 64, 32000000,
                                                           200000000, 16 * 1024 * 1024 + 65536))
        self.inputs = []
        self.outputs = []
        self.configuration = self.core._call('run', 'install_configuration',
                                             self.loan(config or {**CONFIGURATION,
                                                                  'authority_scope_cid': scope}).handle)
        assert self.configuration > 0

    def loan(self, payload, stopped=lambda _: True):
        wire = payload if type(payload) is bytes else encode(payload)
        source = self.core.reserve_input(wire, cleanup=lambda: True, stopped=stopped)
        self.inputs.append(source)
        for start in range(0, len(wire), 16384):
            self.core.fill_input(source, start, min(16384, len(wire) - start))
        self.core.seal_input(source)
        return source

    def project(self, kind, payload):
        source = self.loan(payload)
        output = self.core.reserve_submission_projection(self.configuration, source, kind,
                                                         cleanup=lambda: True)
        self.outputs.append(output)
        assert self.core._call('run', 'close_configuration', self.configuration) == -9
        self.core.produce_submission_projection(output)
        wire = self.core.read_submission_projection(output)
        assert self.core.read_submission_projection(output) is wire
        assert self.core.close_submission_projection(output)
        self.outputs.remove(output)
        return wire

    def close(self):
        for output in self.outputs:
            assert self.core.close_submission_projection(output)
        assert self.core._call('run', 'close_configuration', self.configuration) == 0
        for source in self.inputs:
            assert self.core.close_input(source)
        assert self.core.close()


with TemporaryDirectory(prefix='actql-python-submission-') as temporary:
    path = Path(temporary) / 'core.sqlite'
    session = Session()
    try:
        with LocalByteStore(path, max_records=8, max_record_bytes=4096,
                            max_payload_bytes=32768) as store:
            with patch('actql_sdk._local_submission.secrets.token_hex',
                       side_effect=['c' * 64, 'b' * 64]):
                authority = LocalSubmissionAuthority(store, session.project,
                                                     now=lambda: 1800000000000, ttl_ms=1000)
                epoch = authority.issue_epoch(scope)
            assert epoch['authenticator'] == authenticator
            reference = {'epoch': epoch, 'nonce': 'request-1'}
            identity = authority.identity(reference)
            assert identity.request_id == request_id and identity.epoch_cid == epoch_cid
            assert identity.validity == 'admissible'
            cases += ['independent_epoch_authenticator', 'original_request_identity']
    finally:
        session.close()

    # Reopen durable authority and a new Wasm instance, retaining exact identity.
    session = Session()
    try:
        with LocalByteStore(path, max_records=8, max_record_bytes=4096,
                            max_payload_bytes=32768) as store:
            authority = LocalSubmissionAuthority(store, session.project, now=lambda: 1)
            assert authority.identity(copy.deepcopy(reference)) == identity
            cases.append('reopened_key_and_nonrewinding_clock')
            forged = copy.deepcopy(reference)
            forged['epoch']['authenticator'] = '0' * 64
            try:
                authority.identity(forged)
            except LocalSubmissionIdentityError:
                pass
            else:
                raise AssertionError('Forged epoch acquired Submission identity')
            cases.append('forged_authenticator_refused')
            authority._now = lambda: 1800000001000
            expired = authority.identity(reference)
            assert expired.request_id == request_id and expired.validity == 'expired'
            cases.append('expired_identity_is_not_admission')
            raw = {'authority_scope_cid': scope, 'epoch_nonce': 'b' * 64,
                   'not_before': 1800000000000, 'expires_at': 1800000001000,
                   'caller_nonce': 'request-1', 'now': 1799999999999}
            assert json.loads(session.project(2, encode(raw)))['validity'] == 'not_yet_valid'
            cases.append('owner_half_open_interval')
            for invalid in ({**raw, 'unknown': None}, {**raw, 'not_before': None},
                            {**raw, 'caller_nonce': 'e\u0301'}):
                try:
                    session.project(2, encode(invalid))
                except LocalCoreError as error:
                    assert error.code == -31
                else:
                    raise AssertionError('Malformed Core input exposed identity')
            cases.append('closed_input_and_owner_nonce_validation')
    finally:
        session.close()

    for config in ({**CONFIGURATION, 'authority_scope_cid': 'sha256:' + 'd' * 64},
                   {**CONFIGURATION, 'authority_scope_cid': scope, 'principal': 'revoked-user'}):
        session = Session(config)
        try:
            with LocalByteStore(path, max_records=8, max_record_bytes=4096,
                                max_payload_bytes=32768) as store:
                authority = LocalSubmissionAuthority(store, session.project, now=lambda: 1800000001000)
                try:
                    authority.identity(reference)
                except LocalCoreError as error:
                    assert error.code == -32
                else:
                    raise AssertionError('Foreign scope or revoked Account exposed identity')
        finally:
            session.close()
    cases += ['foreign_scope_refused', 'current_account_revocation_refused']

session = Session()
try:
    stop = [False]
    cleanup = [False]
    calls = []
    source = session.loan({'authority_scope_cid': scope, 'epoch_nonce': 'b' * 64,
                           'not_before': 1800000000000, 'expires_at': 1800000001000},
                          stopped=lambda _: stop[0])
    output = session.core.reserve_submission_projection(session.configuration, source, 1,
        cleanup=lambda: calls.append('cleanup') or cleanup[0])
    session.outputs.append(output)
    session.core.produce_submission_projection(output)
    try:
        session.core.read_submission_projection(copy.copy(output))
    except ValueError:
        pass
    else:
        raise AssertionError('Copied output acquired private custody')
    assert not session.core.close_submission_projection(output)
    cleanup[0] = True
    assert not session.core.close_submission_projection(output)
    assert session.core._call('run', 'close_configuration', session.configuration) == -9
    stop[0] = True
    assert session.core.close_submission_projection(output)
    assert calls == ['cleanup', 'cleanup']
    session.outputs.remove(output)
    cases += ['copied_output_refused', 'cleanup_retry_retains_configuration_and_input']
finally:
    session.close()

assert len(cases) == 11
print(json.dumps({'success': True, 'module_sha256': digest, 'cases': cases,
                  'fuel_per_instance': 100000000, 'fuel_refills': 0,
                  'source_model_effect_calls': 0, 'public_local_acceptance': False,
                  'durable_run_acceptance': False}))
