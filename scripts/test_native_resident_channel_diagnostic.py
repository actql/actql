"""Explicit GDB ports exercise observation and privacy, not Native execution."""
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest

SPEC = importlib.util.spec_from_file_location(
    "channel_observer", Path(__file__).with_name("fixtures") / "native-resident-channel-gdb.py")
OBSERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVER)


class Event:
    def __init__(self):
        self.callbacks = []

    def connect(self, callback):
        self.callbacks.append(callback)


class GdbPorts:
    def __init__(self):
        self.registers, self.regions, self.breakpoints, self.finishes = {}, {}, {}, []
        self.events = types.SimpleNamespace(new_objfile=Event(), exited=Event())
        owner = self

        class Breakpoint:
            def __init__(self, symbol, internal=False):
                owner.breakpoints[symbol] = self

        class FinishBreakpoint:
            def __init__(self, frame, internal=False):
                self.return_value = None
                owner.finishes.append(self)
        self.Breakpoint, self.FinishBreakpoint = Breakpoint, FinishBreakpoint

    def selected_thread(self):
        return types.SimpleNamespace(global_num=1)

    def newest_frame(self):
        return object()

    def selected_inferior(self):
        return self

    def read_memory(self, address, count):
        wire = self.regions[address]
        if len(wire) < count:
            raise ValueError("private memory unavailable")
        return wire[:count]

    def parse_and_eval(self, expression):
        return self.registers[expression[1:]]

    def execute(self, command, to_string=False):
        return ""

    def returned(self, breakpoint, value):
        breakpoint.return_value = value
        self.assert_continued(breakpoint.stop())

    @staticmethod
    def assert_continued(value):
        if value is not False:
            raise AssertionError("An observer must never stop the inferior")


class ChannelDiagnosticTest(unittest.TestCase):
    def test_release_minimal_symbol_without_debug_prototype_is_observed(self):
        with tempfile.TemporaryDirectory() as directory:
            gdb = GdbPorts()
            name = "actql_slot_NativeHolderChannel_send"
            gdb.execute = lambda *args, **kwargs: "Non-debugging symbols:\n0x1234 " + name + "\n"
            OBSERVER.install(gdb, str(Path(directory) / "report.json"), "not-a-live-entry")
            self.assertIn(name, gdb.breakpoints)

    def test_requested_method_and_actual_write_nonprogress_remain_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            report = str(Path(directory) / "report.json")
            gdb = GdbPorts()
            name = "actql_slot_NativeHolderChannel_send"
            gdb.execute = lambda *args, **kwargs: "bool " + name + "(void*, void*);"
            OBSERVER.install(gdb, report, "not-a-live-entry")
            gdb.regions[4000] = "consumer private-request".encode("utf-16-le")
            gdb.registers.update(rsi=4000)
            gdb.breakpoints[name].stop()
            send_return = gdb.finishes[-1]
            gdb.regions[1000] = b"consumer private-request"
            gdb.registers.update(rdi=51, rsi=50, rdx=1000, rcx=8192, r8=4096)
            gdb.breakpoints["actql_executor_slot_channel_write"].stop()
            channel_return = gdb.finishes[-1]
            gdb.registers.update(rdi=51)
            gdb.breakpoints["write"].stop()
            gdb.returned(gdb.finishes[-1], -1)
            gdb.returned(channel_return, -2)
            gdb.returned(send_return, 0)
            value = json.loads(Path(report).read_text())
            self.assertEqual(value["last"]["requestedKind"], "consumer")
            self.assertEqual(value["last"]["selectedKind"], "consumer")
            self.assertEqual(value["last"]["ioctl"], "not-entered")
            self.assertEqual(value["last"]["write"], "nonprogress")
            self.assertEqual(value["last"]["channelReturn"], "busy")
            self.assertEqual(value["sendReturns"], {"consumer/false": 1})
            self.assertNotIn("private", Path(report).read_text())

    def test_actual_busy_then_partial_write_and_wait_results_keep_no_private_data(self):
        with tempfile.TemporaryDirectory() as directory:
            report, entry = str(Path(directory) / "report.json"), str(Path(directory) / "entry")
            Path(entry).write_text("private producer\n")
            gdb = GdbPorts()
            OBSERVER.install(gdb, report, entry)
            gdb.regions[1000] = b"consumer private-body-that-must-never-appear"
            gdb.registers.update(rdi=51, rsi=50, rdx=1000, rcx=8192, r8=0)
            self.assertIs(gdb.breakpoints["actql_executor_slot_channel_write"].stop(), False)
            channel_return = gdb.finishes[-1]
            gdb.regions[2000] = (7).to_bytes(4, "little")
            gdb.registers.update(rdi=50, rsi=0x541b, rdx=2000)
            self.assertIs(gdb.breakpoints["ioctl"].stop(), False)
            gdb.returned(gdb.finishes[-1], 0)
            gdb.returned(channel_return, -2)
            value = json.loads(Path(report).read_text())
            self.assertEqual(value["last"]["ioctl"], "busy")
            self.assertEqual(value["last"]["unreadBytes"], 7)
            self.assertEqual(value["last"]["channelReturn"], "busy")
            self.assertFalse(value["consumerExecutorEntered"])
            Path(entry).write_text("private producer\nprivate consumer\n")
            gdb.registers.update(rdi=51, rsi=50, rdx=1000, rcx=8192, r8=4096)
            gdb.breakpoints["actql_executor_slot_channel_write"].stop()
            channel_return = gdb.finishes[-1]
            gdb.registers.update(rdi=51, rsi=1000, rdx=4096)
            gdb.breakpoints["write"].stop()
            gdb.returned(gdb.finishes[-1], 4096)
            gdb.returned(channel_return, 4096)
            gdb.breakpoints["actql_executor_slot_wait"].stop()
            gdb.returned(gdb.finishes[-1], -1)
            value = json.loads(Path(report).read_text())
            self.assertEqual(value["last"]["selectedKind"], "consumer")
            self.assertEqual(value["last"]["requestedKind"], "unobserved")
            self.assertEqual(value["last"]["offset"], 4096)
            self.assertEqual(value["last"]["returnedBytes"], 4096)
            self.assertEqual(value["last"]["write"], "progress")
            self.assertEqual(value["waitCounts"], {"error": 1})
            self.assertTrue(value["consumerExecutorEntered"])
            wire = Path(report).read_text()
            self.assertNotIn("private", wire)
            self.assertNotIn("descriptor", wire)
            self.assertEqual(Path(report).stat().st_mode & 0o777, 0o600)

    def test_invalid_bounds_and_missing_method_are_explicitly_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            report = str(Path(directory) / "report.json")
            gdb = GdbPorts()
            OBSERVER.install(gdb, report, "not-a-live-entry")
            gdb.registers.update(rcx=0, r8=0)
            gdb.breakpoints["actql_executor_slot_channel_write"].stop()
            for callback in gdb.events.exited.callbacks:
                callback(None)
            value = json.loads(Path(report).read_text())
            self.assertEqual(value["channelCalls"], 0)
            self.assertEqual(set(value["conditions"]), {
                "frame-bounds-unavailable", "requested-kind-unavailable", "channel-not-observed"})

    def test_fixed_prefixes_and_bounded_group_retention(self):
        self.assertEqual(OBSERVER.frame_kind(b"effect-review\n"), "effect-review")
        self.assertEqual(OBSERVER.frame_kind(b"effect-review-private"), "other")
        self.assertEqual(OBSERVER.frame_kind(b"private credentials"), "other")
        self.assertEqual(OBSERVER.signed32(0xfffffffe), -2)
        with tempfile.TemporaryDirectory() as directory:
            report = str(Path(directory) / "report.json")
            owner = OBSERVER.Observations(report, "not-a-live-entry")
            for offset in range(100):
                owner.record({"offset": offset})
            value = json.loads(Path(report).read_text())
            self.assertEqual(value["channelCalls"], 100)
            self.assertEqual(len(value["observations"]), 64)
            self.assertEqual(value["droppedGroups"], 36)
            self.assertEqual(value["last"], {"offset": 99})


if __name__ == "__main__":
    unittest.main()
