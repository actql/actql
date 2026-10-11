"""Light fixture assembly checks; the common Owner admits the actual wire."""
import json
import ast
from pathlib import Path
import unittest
from python_local_publication_policy import publication_policy


class RetentionFixtureTests(unittest.TestCase):
    def test_uses_contract_self_identity_without_changing_the_fixed_preimage(self):
        root = Path(__file__).resolve().parents[2]
        expected, wire = publication_policy(root)
        value = json.loads(wire)
        cid = 'sha256:92241f901b8ffbd5d2b692e2619fb66c9cbe9c18fde9692ebe25d2746a17a82a'
        self.assertEqual(expected['retention_policy_cid'], cid)
        self.assertEqual(value.pop('effective_retention_policy_cid'), cid)
        self.assertNotIn('retention_policy_cid', value)
        self.assertEqual(value, json.loads(expected['retention_preimage']))
        self.assertEqual(expected['result_rows'], [{'next': 5}])
        self.assertEqual(expected['result_fields'], ['next'])
        self.assertEqual(expected['source_queries'], 3)

    def test_wire_names_match_the_existing_closed_contract(self):
        root = Path(__file__).resolve().parents[2]
        _, wire = publication_policy(root)
        schema = json.loads((root / 'spec/contracts/actql-run-publication.json').read_text())['schemas']['result_retention_policy']
        self.assertFalse(schema['additionalProperties'])
        self.assertEqual(set(json.loads(wire)), set(schema['required']))

    def test_publication_assertion_reports_the_actual_status_without_retry(self):
        root = Path(__file__).resolve().parents[2]
        tree = ast.parse((root / 'scripts/fixtures/python-local-native-result-abi.py').read_text())
        helper = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'assert_status')
        calls = []

        def call(*args):
            calls.append(args)
            return -32

        scope = {'call': call}
        exec(compile(ast.Module(body=[helper], type_ignores=[]), '<fixture assertion>', 'exec'), scope)
        with self.assertRaises(AssertionError) as failure:
            scope['assert_status']('publication', 'prepare', 0, 7, 9)
        self.assertEqual(failure.exception.args, (('publication', 'prepare', 'expected', 0, 'actual', -32),))
        self.assertEqual(calls, [('publication', 'prepare', 7, 9)])

    def test_budget_refusal_remains_an_assertion_success_only_for_exact_status(self):
        root = Path(__file__).resolve().parents[2]
        tree = ast.parse((root / 'scripts/fixtures/python-local-native-result-abi.py').read_text())
        helper = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'assert_status')
        scope = {'call': lambda *args: -32}
        exec(compile(ast.Module(body=[helper], type_ignores=[]), '<fixture assertion>', 'exec'), scope)
        scope['assert_status']('publication', 'advance', -32, 7, 9, 1)
        with self.assertRaises(AssertionError):
            scope['assert_status']('publication', 'advance', -31, 7, 9, 1)


if __name__ == '__main__':
    unittest.main()
