"""Closed physical projection only; no Core issuance, COMMIT or success."""
import copy
import json
import unittest

from actql_sdk._local_sdk_delivery_storage import _physical_terminal_plan


class SDKTerminalPlanTests(unittest.TestCase):
    def rows(self):
        return [
            {'table': 'publication_contract', 'key': 'sha256:' + 'a' * 64,
             'revision': None, 'body': 'opaque receipt e\u0301\r\n\x00'},
            {'table': 'publication_contract', 'key': 'sha256:' + 'b' * 64,
             'revision': None, 'body': 'opaque successor'},
            {'table': 'delivery_record_head', 'key': 'sha256:' + 'c' * 64,
             'revision': 0, 'body': 'opaque successor'},
        ]

    def test_original_three_cas_fields_preserve_exact_unicode_and_head_revision(self):
        writes = _physical_terminal_plan(json.dumps(self.rows(), ensure_ascii=False).encode())
        self.assertEqual([(row.key, row.expected_generation, row.payload) for row in writes], [
            ('namespace:20:publication_contract:sha256:' + 'a' * 64,
             None, b'opaque receipt e\xcc\x81\r\n\x00'),
            ('namespace:20:publication_contract:sha256:' + 'b' * 64,
             None, b'opaque successor'),
            ('namespace:20:delivery_record_head:sha256:' + 'c' * 64,
             0, b'opaque successor'),
        ])

    def test_wrong_table_count_unknown_duplicate_or_boolean_fields_are_not_proposals(self):
        rows = self.rows()
        variants = [rows[:-1], rows + [rows[-1]], {"rows": rows}]
        for edit in ('unknown', 'table', 'body', 'key'):
            changed = copy.deepcopy(rows)
            if edit == 'unknown': changed[0]['extra'] = 1
            elif edit == 'table': changed[0]['table'] = 'delivery_attempt'
            elif edit == 'body': changed[1]['body'] = None
            else: changed[1]['key'] = changed[0]['key']
            variants.append(changed)
        for current in variants:
            with self.assertRaises(ValueError):
                _physical_terminal_plan(json.dumps(current).encode())
        raw = json.dumps(rows).replace('"revision": 0', '"revision": 0, "revision": 0')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            _physical_terminal_plan(raw.encode())

    def test_head_generation_and_new_contract_revisions_are_not_relaxed(self):
        for value in (None, True, False, 1, -1, 0.0, "0"):
            rows = self.rows()
            rows[2]['revision'] = value
            with self.assertRaises(ValueError):
                _physical_terminal_plan(json.dumps(rows).encode())
        for ordinal in (0, 1):
            for value in (0, 1, True):
                rows = self.rows()
                rows[ordinal]['revision'] = value
                with self.assertRaises(ValueError):
                    _physical_terminal_plan(json.dumps(rows).encode())
