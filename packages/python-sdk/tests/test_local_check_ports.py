"""Local reporting-port and input-custody checks, not installed execution."""
from copy import copy, deepcopy
import unittest
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from types import SimpleNamespace

from actql_sdk._diagnostics import bind_check
from actql_sdk import get_check_input, resolve_check_location
from actql_sdk._local_check import OriginalLocalCheck
from actql_sdk._local_core import _Input, _Output
from actql_sdk._values import wire_bytes
from fixtures import check_report
import test_local_product_operation_port as operation_fixture
from actql_sdk import AsyncClient


class CheckPortFixture(OriginalLocalCheck):
    def __init__(self):
        self.host = SimpleNamespace(_nominal=lambda: None)
        super().__init__(self.host)
        self.requests = []
        self.reply_mutation = lambda report: None
        report = check_report()
        self.metadata = {'compiler': '{"compiler":"original"}',
            'checking_context': '{"profiles":{"rela":true}}',
            'reason_schema_cid': report['reason_schema_cid'],
            'outcome_schema_cid': report['outcome_schema_cid'],
            'audience': 'original-caller', 'connection': 'local'}

    def _project(self, kind, packet):
        self._nominal()
        if kind == 0:
            return wire_bytes(self.metadata)
        self.requests.append(deepcopy(packet))
        report = check_report(byte_length=len(packet['document'].encode('utf-8')))
        report['report']['context_ref'] = packet['context']
        report['report']['scope']['kind'] = packet['scope']
        report['report']['inputs'][0]['revision'] = packet['revision']
        report['report']['reasons'][0]['location']['revision'] = packet['revision']
        self.reply_mutation(report)
        return wire_bytes(report)


BODY = {'kind': 'text', 'scope': 'bound_input',
        'input': {'text': '0123456789', 'format': 'sql'}, 'parameters': None}


class LocalCheckPortTests(unittest.TestCase):
    def test_same_input_revision_and_context_keep_distinct_attempt_correlations(self):
        checker = CheckPortFixture()
        first = bind_check(json.loads(checker.report(BODY)), BODY)
        checker.report(BODY)
        left, right = checker.requests
        self.assertEqual(left['revision'], right['revision'])
        self.assertEqual(left['context'], right['context'])
        self.assertNotEqual(left['correlation'], right['correlation'])
        self.assertEqual(get_check_input(first, 'source')['text'], '0123456789')
        self.assertEqual(resolve_check_location(first, first.report.reasons[0].location)['text'], '0123')

    def test_public_context_changes_without_revising_same_input_and_other_host_is_distinct(self):
        checker = CheckPortFixture()
        checker.report(BODY)
        checker.metadata['audience'] = 'another-caller'
        checker.report(BODY)
        checker.metadata['checking_context'] = '{"profiles":{"rela":false}}'
        checker.report(BODY)
        other = CheckPortFixture()
        other.report(BODY)
        requests = checker.requests + other.requests
        self.assertEqual(len({item['context'] for item in requests}), 4)
        self.assertEqual(len({item['revision'] for item in checker.requests}), 1)
        self.assertNotEqual(checker.requests[0]['revision'], other.requests[0]['revision'])

    def test_template_absence_and_exact_source_spelling_remain_distinct(self):
        checker = CheckPortFixture()
        body = {'kind': 'text', 'scope': 'template_only',
                'input': {'text': '0123456789', 'format': 'sql'}}
        checker.report(body)
        self.assertNotIn('parameters', checker.requests[0])
        self.assertNotIn('parameters_revision', checker.requests[0])
        self.assertEqual(checker.requests[0]['scope'], 'template_only')
        self.assertNotEqual(checker._revision('source', 'é\r\n'), checker._revision('source', 'e\u0301\n'))
        self.assertNotEqual(checker._revision('source', '{}'), checker._revision('parameters', '{}'))

    def test_other_original_context_input_scope_or_attempt_never_binds_a_report(self):
        for mutate in [
            lambda report: report['report'].__setitem__('context_ref', 'ctx:foreign'),
            lambda report: report['report']['scope'].__setitem__('kind', 'template_only'),
            lambda report: report['report']['inputs'][0].__setitem__('byte_length', 11),
            lambda report: report.update(outcome='failed', correlation_ref='corr:foreign',
                partial_report=report.pop('report'), problem={'code': 'implementation_failure'}),
        ]:
            with self.subTest(mutation=mutate):
                checker = CheckPortFixture()
                checker.reply_mutation = mutate
                with self.assertRaisesRegex(ValueError, 'Foreign original Local Check'):
                    checker.report(BODY)

    def test_copied_receiver_cannot_issue_or_retire_original_custody(self):
        checker = CheckPortFixture()
        other = copy(checker)
        with self.assertRaisesRegex(ValueError, 'Copied original Local Check'):
            other.report(BODY)
        with self.assertRaisesRegex(ValueError, 'Copied original Local Check'):
            other.close()
        self.assertEqual(checker.requests, [])

    def test_failed_child_cleanup_keeps_original_input_until_separate_return(self):
        state = {'output': False, 'input': False}
        source = _Input(object(), 1, 2, 2)
        output = _Output(object(), 3, 4, 1048576, 'check')
        core = SimpleNamespace(close_client_check=lambda _: state['output'],
                               close_input=lambda _: state['input'])
        host = SimpleNamespace(_nominal=lambda: None, _core=core, _inputs=[source])
        checker = OriginalLocalCheck(host)
        checker._outputs.append(output)
        checker._inputs.append(source)
        self.assertFalse(checker.close())
        self.assertEqual(checker._outputs, [output])
        self.assertEqual(checker._inputs, [source])
        state['output'] = True
        self.assertFalse(checker.close())
        self.assertEqual(checker._outputs, [])
        self.assertEqual(host._inputs, [source])
        state['input'] = True
        self.assertTrue(checker.close())
        self.assertEqual(host._inputs, [])


class LocalCheckDispatchTests(unittest.IsolatedAsyncioTestCase):
    async def test_public_local_check_uses_same_host_response_and_does_not_submit(self):
        fixture = operation_fixture.LocalOperationPortTests()
        self.addCleanup(fixture.doCleanups)
        with TemporaryDirectory(prefix='actql-local-check-port-') as directory:
            host, core, events, _ = fixture.host(Path(directory))
            checker = CheckPortFixture()
            with patch.object(host._client_check, 'report', side_effect=checker.report):
                client = await AsyncClient._connect_local(host)
                result = await client.check('0123456789', kind='text', format='sql',
                                            scope='bound_input')
                self.assertEqual(result.report.verdict, 'invalid')
                self.assertEqual(get_check_input(result, 'source')['text'], '0123456789')
                self.assertEqual(len(checker.requests), 1)
                self.assertFalse(host._response_streams)
                self.assertFalse(host._run_loans)
                self.assertFalse(any(family in ('task', 'compute', 'publication')
                                     or (family == 'run' and name.startswith('prepare'))
                                     for family, name in events))
                await client.aclose()
                self.assertTrue(core._closed)


if __name__ == '__main__':
    unittest.main()
