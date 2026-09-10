import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("calendar_fixture", Path(__file__).with_name("generate-calendar-fixture.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def tzif(times, indices, offsets):
    def block(width):
        header = b"TZif2" + bytes(15) + struct.pack(">6I", 0, 0, 0, len(times), len(offsets), 2)
        return (header + struct.pack(f">{len(times)}{'q' if width == 8 else 'i'}", *times)
                + bytes(indices) + b"".join(struct.pack(">iBB", o, 0, 0) for o in offsets) + b"X\0")
    # First block is unused, but must remain structurally sound.
    first = b"TZif2" + bytes(15) + struct.pack(">6I", 0, 0, 0, 0, 1, 2) + struct.pack(">iBB", 0, 0, 0) + b"X\0"
    return first + block(8) + b"\n\n"


class CalendarFixtureTest(unittest.TestCase):
    def test_initial_state_and_redundant_offsets(self):
        data = tzif([fixture.START, 0, 1, fixture.END], [0, 0, 1, 0], [30, -60])
        self.assertEqual(fixture.table(data), {"initial_offset_seconds": 30, "transitions": [{"at_ms": 1000, "offset_seconds": -60}]})

    def test_missing_coverage_is_not_extrapolated(self):
        with self.assertRaisesRegex(ValueError, "sentinels"):
            fixture.table(tzif([0], [0], [0]))

    def test_unsorted_times(self):
        with self.assertRaisesRegex(ValueError, "unordered"):
            fixture.table(tzif([fixture.START, 1, 0, fixture.END], [0] * 4, [0]))

    def test_bad_index(self):
        with self.assertRaisesRegex(ValueError, "invalid TZif block"):
            fixture.table(tzif([fixture.START, fixture.END], [0, 1], [0]))

    def test_truncation(self):
        with self.assertRaises((ValueError, struct.error)):
            fixture.table(tzif([fixture.START, fixture.END], [0, 0], [0])[:-10])
