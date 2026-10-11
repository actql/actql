"""Light fixture assembly checks; the common Owner admits the actual wire."""
import json
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


if __name__ == '__main__':
    unittest.main()
