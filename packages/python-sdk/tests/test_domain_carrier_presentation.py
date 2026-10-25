"""Closed domain/carrier diagnostics retain truthful advice without private text."""
import unittest
from actql_sdk._diagnostics import explain_check_reason
from actql_sdk._wire_codec import CONTRACT, check_outcome


def outcome(reason):
    return {'version': 'actql-check-outcome/0.1', 'outcome': 'completed',
        'reason_schema_cid': CONTRACT['check_reason_schema_cid'],
        'outcome_schema_cid': CONTRACT['check_outcome_schema_cid'],
        'report': {'context_ref': 'ctx:synthetic', 'scope': {'kind': 'bound_input'},
            'verdict': 'invalid', 'runnable': {'verdict': 'no', 'reasons': [{'code': reason['code']}]},
            'inputs': [{'document_id': 'source', 'revision': 'rev:' + 'a' * 64,
                        'kind': 'text', 'byte_length': 8}],
            'coverage': {'limits': [], 'unresolved': []}, 'reasons': [reason], 'requirements': []}}


class DomainCarrierPresentationTests(unittest.TestCase):
    def test_closed_domain_and_carrier_variants(self):
        for reason, expected in [
            ({'code': 'expression_domain_mismatch', 'facts': {'domain': 'key_comparable_operands'}}, 'incompatible types'),
            ({'code': 'expression_domain_mismatch', 'facts': {'domain': 'matching_numeric_domains'}}, 'numeric domain'),
            ({'code': 'carrier_mismatch', 'facts': {'expected_carrier': 'vectors', 'actual_carrier': 'relation'}}, 'Vectors input'),
            ({'code': 'carrier_mismatch', 'facts': {'expected_carrier': 'relation', 'actual_carrier': 'vectors'}}, 'Relation input'),
        ]:
            with self.subTest(reason=reason):
                self.assertTrue(check_outcome(outcome(reason)))
                result = explain_check_reason(reason)
                self.assertEqual(result['kind'], 'known')
                self.assertIn(expected, result['summary'])
                with self.assertRaises(TypeError):
                    result['summary'] = 'changed'

    def test_missing_and_future_predicates_are_unknown(self):
        for reason in [
            {'code': 'expression_domain_mismatch'},
            {'code': 'expression_domain_mismatch', 'facts': {'domain': 'future_domain'}},
            {'code': 'carrier_mismatch'},
            {'code': 'carrier_mismatch', 'facts': {'expected_carrier': 'future_carrier', 'actual_carrier': 'relation'}},
        ]:
            self.assertEqual(explain_check_reason(reason)['kind'], 'unknown')
            self.assertFalse(check_outcome(outcome(reason)))

    def test_private_text_and_equal_carriers_are_refused(self):
        reason = {'code': 'carrier_mismatch', 'facts': {'expected_carrier': 'vectors',
                  'actual_carrier': 'relation', 'private_message': 'SYNTHETIC_PRIVATE_TOKEN'}}
        self.assertFalse(check_outcome(outcome(reason)))
        self.assertNotIn('SYNTHETIC_PRIVATE_TOKEN', str(dict(explain_check_reason(reason))))
        for carrier in ['relation', 'vectors']:
            self.assertFalse(check_outcome(outcome({'code': 'carrier_mismatch',
                'facts': {'expected_carrier': carrier, 'actual_carrier': carrier}})))


if __name__ == '__main__':
    unittest.main()
