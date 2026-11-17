"""Actual lightweight SDK/codec imports and independent canonical candidates."""
import copy
import importlib.abc
import json
from pathlib import Path
import subprocess
import sys
import unittest

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / 'packages/python-sdk/src'))


class RemoteOnly(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in {'wasmtime', 'duckdb', 'actql_local_runtime'}:
            raise AssertionError('Remote constructor attempted Local engine dependency')
        return None


def no_process(*args, **kwargs):
    raise AssertionError('Pure Python candidate attempted an external process')


sys.meta_path.insert(0, RemoteOnly())
subprocess.Popen = no_process
from actql_sdk import AsyncClient, Client, _values
from actql_sdk._checkpoint_answer_codec import create_checkpoint_answer_codec, CheckpointCandidateError

assert Client is not None and AsyncClient is not None
assert not {'wasmtime', 'duckdb', 'actql_local_runtime'} & sys.modules.keys()
corpus = json.loads((root / 'portability/corpus/checkpoint-answer-candidates.json').read_text())
limits = {'maxWireBytes': 16384, 'maxNodes': 1000, 'maxDepth': 16}


def actor(value):
    return {'keyId': value['keyId'], 'reviewerId': value['actor'],
            **({} if value['authorityScopeCid'] is None else {'authorityScopeCid': value['authorityScopeCid']})}


def codec():
    return create_checkpoint_answer_codec(_values.canonical_bytes, _values.bytes_cid)


def finish(selected, value, bounds=limits, summary=None):
    stage = selected.prepare_answer_candidate(value['summary'] if summary is None else summary,
        value['decision'], actor(value), value['decidedAt'], bounds)
    assert selected.answer_candidate_approval_preimage(stage) == value['approvalPreimage']
    result = selected.prepare_answer_resolution(stage, value['approvalSignature'])
    assert selected.answer_resolution_preimage(result) == value['resolutionPreimage']
    return selected.finish_answer_candidate(result, value['resolutionSignature'])


class CodecTests(unittest.TestCase):
    def test_identity_domains_display_and_year_zero(self):
        value = corpus['vectors'][0]
        run = next(item for item in corpus['vectors'] if item['summary']['subject']['kind'] == 'run_unit')
        for fixture, path in [(value, ['checkpointId']), (value, ['subject', 'prepareAttemptId']),
                              (value, ['subject', 'requestId']), (run, ['subject', 'runId'])]:
            summary = copy.deepcopy(fixture['summary'])
            parent = summary
            for key in path[:-1]:
                parent = parent[key]
            parent[path[-1]] = 'e\u0301'
            with self.assertRaises(CheckpointCandidateError) as caught:
                codec().prepare_answer_candidate(summary, fixture['decision'], actor(fixture), fixture['decidedAt'], limits)
            self.assertEqual((caught.exception.code, caught.exception.field), ('InvalidField', '.'.join(path)))
        for display in ['', 'e\u0301\r\narbitrary display']:
            self.assertEqual(finish(codec(), value, summary=dict(value['summary'], humanSummary=display))['resolutionWire'], value['resolutionWire'])
        selected = codec()
        stage = selected.prepare_answer_candidate(dict(value['summary'], createdAt='0000-01-01T00:00:00.000Z',
            expiresAt='0001-01-01T00:00:00.000Z'), value['decision'], actor(value), '0000-06-01T00:00:00.000Z', limits)
        self.assertRegex(selected.answer_candidate_approval_preimage(stage), r'^sha256:[0-9a-f]{64}$')
        for field in ['checkpointCid', 'reviewProjectionCid']:
            with self.assertRaises(CheckpointCandidateError):
                codec().prepare_answer_candidate(dict(value['summary'], **{field: value['summary'][field] + '\n'}),
                    value['decision'], actor(value), value['decidedAt'], limits)

    def test_snapshot_retains_original_key_and_data(self):
        value = corpus['vectors'][0]
        summary, original_actor = copy.deepcopy(value['summary']), actor(value)
        selected = codec()
        stage = selected.prepare_answer_candidate(summary, value['decision'], original_actor, value['decidedAt'], limits)
        summary['requiredArtifact']['cid'] = 'sha256:' + 'f' * 64
        original_actor['keyId'] = 'substituted'
        resolution = selected.prepare_answer_resolution(stage, value['approvalSignature'])
        self.assertEqual(selected.finish_answer_candidate(resolution, value['resolutionSignature'])['resolutionWire'], value['resolutionWire'])
        with self.assertRaises(CheckpointCandidateError):
            codec().prepare_answer_resolution(stage, value['approvalSignature'])

    def test_limits_profiles_and_signature_omissions(self):
        value = corpus['vectors'][0]
        selected = codec()
        stage = selected.prepare_answer_candidate(value['summary'], value['decision'], actor(value), value['decidedAt'], limits)
        for signature in [None, '', 'AAAA', 'A' * 85 + 'B==', value['approvalSignature'] + '\n']:
            with self.assertRaises(CheckpointCandidateError):
                selected.prepare_answer_resolution(stage, signature)
        rejected = next(item for item in corpus['vectors'] if item['decision'] == 'rejected')
        stage = selected.prepare_answer_candidate(rejected['summary'], rejected['decision'], actor(rejected), rejected['decidedAt'], limits)
        self.assertIsNone(selected.answer_candidate_approval_preimage(stage))
        with self.assertRaises(CheckpointCandidateError):
            selected.prepare_answer_resolution(stage, value['approvalSignature'])
        for bounds in [dict(limits, maxNodes=2), dict(limits, maxDepth=1), dict(limits, maxWireBytes=1)]:
            with self.assertRaises(CheckpointCandidateError):
                codec().prepare_answer_candidate(value['summary'], value['decision'], actor(value), value['decidedAt'], bounds)
        self.assertEqual(finish(codec(), value, dict(limits, maxWireBytes=930))['resolutionWire'], value['resolutionWire'])
        with self.assertRaises(CheckpointCandidateError) as caught:
            finish(codec(), value, dict(limits, maxWireBytes=929))
        self.assertEqual(caught.exception.code, 'Encoding')


for index, vector in enumerate(corpus['vectors']):
    def independent(self, value=vector):
        result = finish(codec(), value)
        self.assertEqual(result, {'checkpointCid': value['summary']['checkpointCid'],
            'resolutionWire': value['resolutionWire'], 'approvalEvidenceWire': value['evidenceWire']})
    setattr(CodecTests, 'test_independent_vector_' + str(index), independent)


suite = unittest.defaultTestLoader.loadTestsFromTestCase(CodecTests)
result = unittest.TextTestRunner(verbosity=2).run(suite)
counts = {'tests': result.testsRun, 'failed': len(result.failures) + len(result.errors), 'skipped': len(result.skipped)}
print('PYTHON_CHECKPOINT_CODEC_SUMMARY ' + json.dumps(counts))
sys.exit(0 if result.wasSuccessful() and result.testsRun > 0 and not result.skipped else 1)
