"""Original identity DATA domains through the actual lightweight SDK consumer."""
from copy import deepcopy
import json
import unittest

from actql_sdk import ClientError, Signer
from actql_sdk._checkpoints import signed_answer

CID = lambda digit: 'sha256:' + digit * 64
SUMMARY = {'checkpointId': 'checkpoint-original', 'checkpointCid': CID('1'),
    'kind': 'run_scope', 'phase': 'preflight',
    'subject': {'kind': 'prepare_attempt', 'prepareAttemptId': 'preparation-original',
                'requestId': 'request-original'},
    'requiredArtifact': {'type': 'prepared_invocation', 'cid': CID('2')},
    'reviewProjectionCid': CID('3'), 'requirements': ['invocation_scope_approved'],
    'createdAt': '2026-11-18T00:00:00.000Z', 'expiresAt': '2026-11-19T00:00:00.000Z',
    'humanSummary': 'Display only'}
DECIDED_AT = '2026-11-18T01:00:00.000Z'


class CandidateBoundaryTests(unittest.IsolatedAsyncioTestCase):
    async def test_original_noncanonical_identities_refuse_before_signing(self):
        variants = [dict(SUMMARY, checkpointId='e\u0301'),
            dict(SUMMARY, subject=dict(SUMMARY['subject'], prepareAttemptId='e\u0301')),
            dict(SUMMARY, subject=dict(SUMMARY['subject'], requestId='e\u0301')),
            dict(SUMMARY, kind='read_access',
                 subject={'kind': 'run_unit', 'runId': 'e\u0301', 'runDefinitionCid': CID('4')},
                 requiredArtifact={'type': 'read_scope', 'cid': CID('5')})]
        for summary in variants:
            original = deepcopy(summary)
            signatures = []
            signer = Signer('fixture-key', 'fixture-reviewer',
                            lambda raw: signatures.append(raw) or bytes(64))
            with self.assertRaises(ClientError) as failure:
                await signed_answer(summary, 'rejected', signer, DECIDED_AT)
            self.assertEqual(failure.exception.code, 'InvalidCheckpointAnswer')
            self.assertEqual(signatures, [])
            self.assertEqual(summary, original)

    async def test_canonical_originals_and_display_data_keep_exact_preimages(self):
        summary = dict(SUMMARY, checkpointId=' id-é ',
                       subject=dict(SUMMARY['subject'], prepareAttemptId='préparation-original'))
        before, after = [], []
        first = await signed_answer(summary, 'approved',
            Signer('fixture-key', 'fixture-reviewer', lambda raw: before.append(raw) or bytes(64)), DECIDED_AT)
        shown = await signed_answer(dict(summary, humanSummary='e\u0301\r\n'), 'approved',
            Signer('fixture-key', 'fixture-reviewer', lambda raw: after.append(raw) or bytes(64)), DECIDED_AT)
        self.assertEqual(after, before)
        self.assertEqual(shown, first)
        self.assertEqual(len(after), 2)
        resolution = json.loads(shown['resolutionWire'])
        self.assertEqual(resolution['checkpoint_id'], summary['checkpointId'])
        self.assertEqual(resolution['prepare_attempt_id'], summary['subject']['prepareAttemptId'])
