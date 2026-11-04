"""Independent binary table vectors; no Wasmtime import, compiler or instance."""
import unittest
from python_wasm_table_geometry import defined_table_limits

HEADER = b'\0asm\x01\0\0\0'


def section(payload):
    assert len(payload) < 128
    return b'\x04' + bytes([len(payload)]) + payload


class TableGeometryTests(unittest.TestCase):
    def test_actual_finite_minimum_and_maximum_are_read_without_a_constant_ceiling(self):
        # 1952=0x0f*128+0x20; 2000=0x0f*128+0x50.
        self.assertEqual(defined_table_limits(HEADER + section(b'\x01\x70\x01\xa0\x0f\xa0\x0f')), ((1952, 1952),))
        self.assertEqual(defined_table_limits(HEADER + section(b'\x01\x70\x01\xa0\x0f\xd0\x0f')), ((1952, 2000),))
        # Existing custom sections are framed/skipped; they are not table DATA.
        custom = b'\x00\x02\x01x'
        table = section(b'\x01\x70\x01\x01\x02')
        self.assertEqual(defined_table_limits(HEADER + custom + table + custom), ((1, 2),))

    def test_unbounded_shared_table64_wrong_type_count_and_reversed_bounds_refuse(self):
        for payload in (b'\x01\x70\x00\x01', b'\x01\x70\x03\x01\x02',
                        b'\x01\x70\x05\x01\x02', b'\x01\x6f\x01\x01\x02',
                        b'\x00', b'\x02', b'\x01\x70\x01\x02\x01',
                        b'\x01\x70\x01\x00\x00'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                defined_table_limits(HEADER + section(payload))

    def test_malformed_header_section_extent_integer_and_trailing_table_data_refuse(self):
        table = section(b'\x01\x70\x01\x01\x02')
        for module in (b'', b'\0asm\x02\0\0\0' + table, HEADER,
                       HEADER + table + table, HEADER + b'\x04\x80',
                       HEADER + b'\x04\x08\x01\x70', HEADER + b'\x04\xff\xff\xff\xff\x10',
                       HEADER + section(b'\x01\x70\x01\x80'),
                       HEADER + section(b'\x01\x70\x01\xff\xff\xff\xff\x10\x01'),
                       HEADER + section(b'\x01\x70\x01\x01\x02\x00'),
                       HEADER + b'\x7f\x00' + table):
            with self.subTest(module=module), self.assertRaises(ValueError):
                defined_table_limits(module)


if __name__ == '__main__':
    unittest.main()
