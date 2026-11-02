import io
import json
import struct
import unittest
from unittest.mock import patch

from process_worker import (MAX_BYTES, PROTOCOL, ProtocolRefusal, read_frame,
                            serve, write_frame)


def encoded(text):
    data = text.encode("utf-8")
    return struct.pack(">I", len(data)) + data


class Fragmented(io.BytesIO):
    def readinto(self, buffer):
        return super().readinto(buffer[:1])


class PartialOutput(io.BytesIO):
    def write(self, data):
        return super().write(data[:1])


class Duplex:
    def __init__(self, incoming):
        self.incoming = io.BytesIO(incoming)
        self.outgoing = io.BytesIO()

    def readinto(self, buffer):
        return self.incoming.readinto(buffer)

    def write(self, value):
        return self.outgoing.write(value)

    def flush(self):
        pass


class ProcessTests(unittest.TestCase):
    def test_fragmented_frame_and_partial_writes_preserve_exact_values(self):
        expected = {"value": "e\u0301\r\n", "rows": [{"id": 1}, {"id": 2, "p": None}]}
        output = PartialOutput()
        write_frame(output, expected)
        self.assertEqual(read_frame(Fragmented(output.getvalue())), expected)

    def test_announced_byte_bound_precedes_body_read(self):
        stream = io.BytesIO(struct.pack(">I", MAX_BYTES + 1))
        with self.assertRaisesRegex(ProtocolRefusal, "TableProcessByteLimit"):
            read_frame(stream)
        self.assertEqual(stream.tell(), 4)

    def test_duplicate_keys_nonfinite_and_invalid_unicode_rejected(self):
        for text in ('{"p":1,"p":2}', '{"p":NaN}', '{"p":1e999}', '{"p":"\\ud800"}'):
            with self.subTest(text=text), self.assertRaises((ValueError, UnicodeError)):
                read_frame(io.BytesIO(encoded(text)))

    def test_deep_input_rejected_before_parser(self):
        with self.assertRaisesRegex(ProtocolRefusal, "TableProcessShapeLimit"):
            read_frame(io.BytesIO(encoded("[" * 33 + "]" * 33)))

    def test_truncated_frames_rejected(self):
        for frame in (b"\0\0", struct.pack(">I", 3) + b"{}"):
            with self.subTest(frame=frame), self.assertRaises(EOFError):
                read_frame(io.BytesIO(frame))

    def test_handshake_and_stop_do_not_open_catalog(self):
        hello = {"protocol": PROTOCOL, "session": "session", "run": "run",
                 "kind": "hello", "sequence": 0, "body": None}
        stop = {**hello, "kind": "stop"}
        stream = Duplex(encoded(json.dumps(hello)) + encoded(json.dumps(stop)))
        def unopened(*_):
            self.fail("Handshake must not open or write a Catalog")
        serve(stream, unopened)
        stream.outgoing.seek(0)
        self.assertEqual(read_frame(stream.outgoing), {**hello, "kind": "ready"})

    def test_constructor_geometry_uses_same_host_call_before_original_dispatch_continues(self):
        hello = {"protocol": PROTOCOL, "session": "original-session", "run": "original-run",
                 "kind": "hello", "sequence": 0, "body": None}
        execute = {**hello, "kind": "execute", "sequence": 1,
                   "body": {"construction_observations": True}}
        continuations = [{**hello, "kind": "host-reply", "sequence": 1,
                          "body": {"call": index, "value": None}} for index in (1, 2)]
        stop = {**hello, "kind": "stop", "sequence": 1}
        stream = Duplex(b"".join(encoded(json.dumps(value))
                                 for value in [hello, execute, *continuations, stop]))
        seen = []
        def original_dispatch(body, catalog_factory, before_materialization=None):
            self.assertEqual(body, execute["body"])
            self.assertTrue(callable(before_materialization))
            for geometry in ({"phase": "metadata-wire", "bytes": 19, "rows": 0, "columns": 0},
                             {"phase": "arrow-rows", "bytes": 23, "rows": 2, "columns": 3}):
                before_materialization(geometry)
                seen.append(geometry)
            return {"ok": True, "result": "same-dispatch"}
        with patch("process_worker.dispatch", side_effect=original_dispatch):
            serve(stream)
        self.assertEqual(len(seen), 2)
        stream.outgoing.seek(0)
        self.assertEqual(read_frame(stream.outgoing), {**hello, "kind": "ready"})
        for index, geometry in enumerate(seen, 1):
            self.assertEqual(read_frame(stream.outgoing),
                {**hello, "kind": "host-request", "sequence": 1,
                 "body": {"call": index, "payload": geometry}})
        self.assertEqual(read_frame(stream.outgoing),
            {**hello, "kind": "reply", "sequence": 1,
             "body": {"ok": True, "result": "same-dispatch"}})
        self.assertEqual(stream.incoming.tell(), len(stream.incoming.getvalue()))

    def test_constructor_foreign_or_value_continuation_cannot_start_material(self):
        hello = {"protocol": PROTOCOL, "session": "session", "run": "run",
                 "kind": "hello", "sequence": 0, "body": None}
        execute = {**hello, "kind": "execute", "sequence": 1,
                   "body": {"construction_observations": True}}
        valid = {**hello, "kind": "host-reply", "sequence": 1,
                 "body": {"call": 1, "value": None}}
        for invalid in ({**valid, "session": "foreign"}, {**valid, "sequence": True},
                        {**valid, "body": {"call": True, "value": None}},
                        {**valid, "body": {"call": 2, "value": None}},
                        {**valid, "body": {"call": 1, "value": {"bytes": 999}}},
                        {**valid, "body": {"call": 1, "value": None, "allow": True}},
                        {**valid, "kind": "reply"}):
            with self.subTest(invalid=invalid):
                started = []
                def original_dispatch(body, catalog_factory, before_materialization=None):
                    before_materialization({"phase": "metadata-wire", "bytes": 19, "rows": 0, "columns": 0})
                    started.append(True)
                    return None
                stream = Duplex(b"".join(encoded(json.dumps(value)) for value in [hello, execute, invalid]))
                with patch("process_worker.dispatch", side_effect=original_dispatch):
                    serve(stream)
                self.assertEqual(started, [])
                stream.outgoing.seek(0)
                self.assertEqual(read_frame(stream.outgoing)["kind"], "ready")
                self.assertEqual(read_frame(stream.outgoing)["kind"], "host-request")
                failure = read_frame(stream.outgoing)
                self.assertEqual(failure["kind"], "failed")
                self.assertEqual(failure["body"], {"code": "TablePhysicalUnknown"})

    def test_original_host_stop_during_constructor_continuation_has_no_success_reply(self):
        hello = {"protocol": PROTOCOL, "session": "session", "run": "run",
                 "kind": "hello", "sequence": 0, "body": None}
        execute = {**hello, "kind": "execute", "sequence": 1,
                   "body": {"construction_observations": True}}
        stop = {**hello, "kind": "stop", "sequence": 1}
        started = []
        def original_dispatch(body, catalog_factory, before_materialization=None):
            before_materialization({"phase": "arrow-rows", "bytes": 23, "rows": 2, "columns": 3})
            started.append(True)
            return None
        stream = Duplex(b"".join(encoded(json.dumps(value)) for value in [hello, execute, stop]))
        with patch("process_worker.dispatch", side_effect=original_dispatch):
            serve(stream)
        self.assertEqual(started, [])
        stream.outgoing.seek(0)
        self.assertEqual(read_frame(stream.outgoing)["kind"], "ready")
        self.assertEqual(read_frame(stream.outgoing)["kind"], "host-request")
        self.assertEqual(stream.outgoing.read(), b"", "stop is not a material, result or resource acknowledgement")

    def test_foreign_or_budgeted_handshake_rejected_without_dispatch(self):
        hello = {"protocol": PROTOCOL, "session": "session", "run": "run",
                 "kind": "hello", "sequence": 0, "body": None}
        for corrupt in ({**hello, "body": {"resourceLimits": {}}},
                        {**hello, "sequence": False}, {**hello, "extra": 1}):
            with self.subTest(corrupt=corrupt), self.assertRaises(ProtocolRefusal):
                serve(Duplex(encoded(json.dumps(corrupt))))
        foreign = {**hello, "kind": "execute", "run": "other", "sequence": 1, "body": {}}
        with self.assertRaisesRegex(ProtocolRefusal, "TableProcessForeignMessage"):
            serve(Duplex(encoded(json.dumps(hello)) + encoded(json.dumps(foreign))))


if __name__ == "__main__":
    unittest.main()
