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
