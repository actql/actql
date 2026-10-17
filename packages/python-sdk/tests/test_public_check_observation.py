"""Public attribute reads keep the generated check wire and original custody."""
from copy import copy, deepcopy
from dataclasses import asdict, FrozenInstanceError, is_dataclass
import unittest

from actql_sdk import ClientError, get_check_input, resolve_check_location
from actql_sdk._diagnostics import bind_check
from fixtures import check_report

BODY = {'kind': 'text', 'scope': 'bound_input',
        'input': {'text': '0123456789', 'format': 'sql'}, 'parameters': None}


class PublicCheckObservationTests(unittest.TestCase):
    def test_guide_attribute_reads_keep_exact_mapping_and_original_location(self):
        raw = check_report()
        outcome = bind_check(raw, BODY)
        self.assertEqual(outcome.report.verdict, 'invalid')
        reason = outcome.report.reasons[0]
        self.assertEqual(reason.code, 'query_lexical_invalid')
        self.assertEqual(dict(reason.location), raw['report']['reasons'][0]['location'])
        self.assertEqual(resolve_check_location(outcome, reason.location)['text'], '0123')
        self.assertEqual(outcome.to_dict(), raw)
        self.assertEqual(outcome['report']['reasons'][0]['code'], reason.code)

    def test_dataclass_projection_and_nested_values_are_detached_immutable_data(self):
        outcome = bind_check(check_report(), BODY)
        self.assertTrue(is_dataclass(outcome))
        self.assertTrue(is_dataclass(outcome.report))
        self.assertTrue(is_dataclass(outcome.report.reasons[0]))
        with self.assertRaises((FrozenInstanceError, AttributeError)):
            outcome.report.verdict = 'verified'
        with self.assertRaises((FrozenInstanceError, AttributeError)):
            outcome.report.reasons[0].code = 'unknown'
        with self.assertRaises(TypeError):
            outcome.report.reasons[0].location['start_byte'] = 8
        detached = asdict(outcome)
        detached['report']['reasons'][0]['location']['start_byte'] = 8
        self.assertEqual(outcome.report.reasons[0].location['start_byte'], 0)
        self.assertNotIn('partial_report', outcome)
        self.assertIsNone(outcome.partial_report)

    def test_copy_and_reconstruction_do_not_acquire_original_input_custody(self):
        original = bind_check(check_report(), BODY)
        for other in [copy(original), deepcopy(original), type(original)(original.to_dict())]:
            self.assertIsNot(other, original)
            self.assertEqual(other.to_dict(), original.to_dict())
            self.assertIsNone(get_check_input(other, 'source'))
            self.assertIsNone(resolve_check_location(other, original.report.reasons[0].location))
        self.assertEqual(get_check_input(original, 'source')['text'], '0123456789')

    def test_failed_partial_report_and_unavailable_stay_distinct(self):
        completed = check_report()
        failed = {k: v for k, v in completed.items() if k not in ('report', 'outcome')}
        failed.update(outcome='failed', partial_report=completed['report'],
                      problem={'code': 'implementation_failure'}, correlation_ref='original-correlation')
        observed = bind_check(failed, BODY)
        self.assertIsNone(observed.report)
        self.assertEqual(observed.partial_report.verdict, 'invalid')
        self.assertEqual(observed.outcome, 'failed')
        self.assertEqual(observed.to_dict(), failed)
        unavailable = {k: v for k, v in failed.items() if k != 'partial_report'} | {'outcome': 'unavailable'}
        observed = bind_check(unavailable, BODY)
        self.assertIsNone(observed.report)
        self.assertIsNone(observed.partial_report)
        self.assertEqual(observed.to_dict(), unavailable)
        self.assertIsNone(get_check_input(observed, 'source'))

    def test_reinitializing_original_cannot_replace_its_bound_check(self):
        outcome = bind_check(check_report(), BODY)
        replacement = check_report()
        replacement['report']['context_ref'] = 'different-context'
        with self.assertRaises(AttributeError):
            outcome.__init__(replacement)
        self.assertEqual(outcome.report.context_ref, 'ctx:independent-python')
        self.assertEqual(get_check_input(outcome, 'source')['text'], '0123456789')

    def test_mutating_response_or_input_does_not_change_admitted_snapshot(self):
        raw, body = check_report(), deepcopy(BODY)
        outcome = bind_check(raw, body)
        raw['report']['reasons'][0]['location']['start_byte'] = 8
        body['input']['text'] = 'changed'
        self.assertEqual(outcome.report.reasons[0].location['start_byte'], 0)
        self.assertEqual(get_check_input(outcome, 'source')['text'], '0123456789')

    def test_generated_admission_and_input_binding_refuse_before_presentation(self):
        raw = check_report()
        del raw['report']['runnable']
        with self.assertRaises(ClientError) as caught:
            bind_check(raw, BODY)
        self.assertEqual(caught.exception.code, 'InvalidHostCheckOutcome')
        with self.assertRaises(ClientError) as caught:
            bind_check(check_report(), BODY | {'input': {'text': 'short', 'format': 'sql'}})
        self.assertEqual(caught.exception.code, 'InvalidHostCheckInputBinding')

    def test_malformed_values_keep_the_original_generated_admission_error(self):
        for value in [check_report() | {'unknown': object()},
                      check_report() | {'outcome_schema_cid': object()}]:
            with self.subTest(value=list(value)), self.assertRaises(ClientError) as caught:
                bind_check(value, BODY)
            self.assertEqual(caught.exception.code, 'InvalidHostCheckOutcome')

    def test_old_reason_identity_is_rejected_with_current_outcome_identity(self):
        raw = check_report()
        raw['reason_schema_cid'] = 'sha256:1aa2b591972a9cd816826b6500f62ea38f8a4f5282e016b0d1153f8bb68e0742'
        with self.assertRaises(ClientError) as caught:
            bind_check(raw, BODY)
        self.assertEqual(caught.exception.code, 'InvalidHostCheckOutcome')

    def test_old_outcome_identity_is_rejected_with_current_reason_identity(self):
        raw = check_report()
        raw['outcome_schema_cid'] = 'sha256:b82a51998a31b6b6cb469fa366a497cea1b48a8b92ac73a5046dffb622b8bdce'
        with self.assertRaises(ClientError) as caught:
            bind_check(raw, BODY)
        self.assertEqual(caught.exception.code, 'InvalidHostCheckOutcome')


class PublicAsyncCheckTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_async_check_exposes_guide_attributes_without_another_request(self):
        import httpx
        from actql_sdk import AsyncClient
        from fixtures import PROFILE
        calls = []
        def respond(request):
            calls.append(request.url.path.rsplit('/', 1)[-1])
            return httpx.Response(200, json=PROFILE if calls[-1] == 'connect' else check_report())
        client = await AsyncClient.connect('https://host.test', 'owner-token',
                                           transport=httpx.MockTransport(respond))
        try:
            outcome = await client.check('0123456789', kind='text', format='sql', scope='bound_input')
            self.assertEqual(outcome.report.reasons[0].code, 'query_lexical_invalid')
            self.assertEqual(outcome.report.verdict, 'invalid')
            self.assertEqual(get_check_input(outcome, 'source')['text'], '0123456789')
            self.assertEqual(calls, ['connect', 'check'])
        finally:
            await client.aclose()


class PublicSyncCheckTests(unittest.TestCase):
    def test_actual_sync_check_exposes_guide_attributes_without_another_request(self):
        import httpx
        from actql_sdk import Client
        from fixtures import PROFILE
        calls = []
        def respond(request):
            calls.append(request.url.path.rsplit('/', 1)[-1])
            return httpx.Response(200, json=PROFILE if calls[-1] == 'connect' else check_report())
        with Client.connect('https://host.test', 'owner-token', transport=httpx.MockTransport(respond)) as client:
            outcome = client.check('0123456789', kind='text', format='sql', scope='bound_input')
            self.assertEqual(outcome.report.reasons[0].code, 'query_lexical_invalid')
            self.assertEqual(resolve_check_location(outcome, outcome.report.reasons[0].location)['text'], '0123')
            self.assertEqual(calls, ['connect', 'check'])
