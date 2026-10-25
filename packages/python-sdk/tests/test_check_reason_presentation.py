"""Reason presentation follows matching catalog variants before optional defaults."""
import unittest

from actql_sdk._diagnostics import explain_check_reason


class CheckReasonPresentationTests(unittest.TestCase):
    def test_binding_json_variant_without_default(self):
        reason = {'code': 'binding_json_invalid',
                  'facts': {'document': 'parameters', 'issue': 'unexpected_end'}}
        result = explain_check_reason(reason)
        self.assertEqual(result['kind'], 'known')
        self.assertIn('ends before a value is complete', result['summary'])
        self.assertIn('closing delimiters', result['hint'])
        self.assertEqual(reason['facts']['issue'], 'unexpected_end')
        with self.assertRaises(TypeError):
            result['summary'] = 'changed'

    def test_graph_variant_without_default(self):
        result = explain_check_reason({'code': 'graph_operation_invalid',
            'facts': {'operation': 'components', 'issue': 'invalid_kind'}})
        self.assertEqual(result['kind'], 'known')
        self.assertIn('weak or strong', result['hint'])

    def test_missing_or_unmatched_facts_without_default_are_unknown(self):
        for reason in [
            {'code': 'binding_json_invalid'},
            {'code': 'graph_operation_invalid', 'facts': {}},
            {'code': 'binding_json_invalid', 'facts': {'document': 'parameters', 'issue': 'future_issue'}},
            {'code': 'graph_operation_invalid', 'facts': {'operation': 'components', 'issue': 'future_issue'}},
            {'code': 'future_reason'},
        ]:
            with self.subTest(reason=reason):
                self.assertEqual(dict(explain_check_reason(reason)), {
                    'kind': 'unknown',
                    'summary': 'No supported explanation is available for this reason.',
                })

    def test_existing_default_and_variant_remain_available(self):
        default = explain_check_reason({'code': 'query_syntax_invalid'})
        self.assertEqual(default['kind'], 'known')
        self.assertIn('query syntax', default['summary'])
        lexical = explain_check_reason({'code': 'query_lexical_invalid',
                                       'facts': {'issue': 'unterminated_comment'}})
        self.assertIn('block comment', lexical['summary'])
        self.assertIn('closing', lexical['hint'])
        fallback = explain_check_reason({'code': 'query_lexical_invalid', 'facts': {'issue': 'future_issue'}})
        self.assertEqual(fallback['kind'], 'known')
        self.assertIn('lexical syntax', fallback['summary'])


if __name__ == '__main__':
    unittest.main()
