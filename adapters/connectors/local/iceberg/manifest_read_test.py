"""Actual pinned Avro I/O/codec boundaries; not a Resource/Run admission."""
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch

from pyiceberg import manifest
from pyiceberg.avro import file as avro_file
from pyiceberg.avro.file import AvroFile, AvroOutputFile
from pyiceberg.avro.codecs.deflate import DeflateCodec
from pyiceberg.avro.codecs.bzip2 import BZip2Codec
from pyiceberg.avro.codecs.snappy_codec import SnappyCodec
from pyiceberg.avro.codecs.zstandard_codec import ZStandardCodec
from pyiceberg.io.pyarrow import PyArrowFileIO
from pyiceberg.schema import Schema
from pyiceberg.types import NestedField, StringType
from pyiceberg.typedef import Record

from manifest_read import observe_manifest_io, _decoded_size


class ManifestReadTests(unittest.TestCase):
    def write(self, codec, payload, corrupt=False):
        root = Path(tempfile.mkdtemp(prefix="actql-manifest-" + codec + "-"))
        print("Retained original Avro fixture:", root)
        location = (root / "original.avro").as_uri()
        io = PyArrowFileIO()
        schema = Schema(NestedField(1, "text", StringType(), required=True))
        if corrupt:
            selected = {"deflate": DeflateCodec, "bzip2": BZip2Codec}[codec]
            original = selected.compress
            def truncated(data):
                encoded, _ = original(data)
                return encoded[:1], 1
            with patch.object(selected, "compress", truncated):
                with AvroOutputFile(io.new_output(location), schema, "original", metadata={"avro.codec": codec}) as writer:
                    writer.write_block([Record(payload)])
        else:
            with AvroOutputFile(io.new_output(location), schema, "original", metadata={"avro.codec": codec}) as writer:
                writer.write_block([Record(payload), Record("second")])
                writer.write_block([Record("")])
        return io, location, schema

    def test_original_null_deflate_bzip2_blocks_keep_exact_rows_and_expanded_sizes(self):
        payload = "e\u0301\r\n" + "A" * 200000
        for codec in ("null", "deflate", "bzip2"):
            with self.subTest(codec=codec):
                io, location, schema = self.write(codec, payload)
                seen = []
                def observe(phase, size, rows=0, columns=0):
                    seen.append({"phase": phase, "bytes": size, "rows": rows, "columns": columns})
                selected = observe_manifest_io(io, observe)
                with manifest.AvroFile[Record](selected.new_input(location), schema) as reader:
                    self.assertEqual([row[0] for row in reader], [payload, "second", ""])
                blocks = [value for value in seen if value["phase"] == "manifest-block"]
                # Independent Avro String lengths: 200005 UTF8 bytes +3-byte
                # varint, then 6-byte 'second'+1; empty String is one zero byte.
                self.assertEqual(blocks, [
                    {"phase": "manifest-block", "bytes": 200015, "rows": 2, "columns": 1},
                    {"phase": "manifest-block", "bytes": 1, "rows": 1, "columns": 1}])
                self.assertEqual(seen[0], {"phase": "manifest-file", "bytes": len(io.new_input(location)),
                                           "rows": 0, "columns": 0})
                self.assertEqual(sum(value["phase"] == "manifest-" + codec for value in seen),
                                 0 if codec == "null" else 2)

    def test_original_block_refusal_precedes_codec_and_block_constructor(self):
        io, location, schema = self.write("deflate", "unchanged")
        primary = RuntimeError("OriginalManifestBlockRefusal")
        def observe(phase, *_):
            if phase == "manifest-block":
                raise primary
        selected = observe_manifest_io(io, observe)
        with patch.object(DeflateCodec, "decompress", side_effect=AssertionError("unfunded codec output")), \
                patch.object(avro_file, "Block", side_effect=AssertionError("unfunded Block constructor")):
            with self.assertRaises(RuntimeError) as failed:
                with manifest.AvroFile[Record](selected.new_input(location), schema) as reader:
                    list(reader)
        self.assertIs(failed.exception, primary)

    def test_original_file_refusal_closes_native_stream_before_header_decoder(self):
        io, location, schema = self.write("null", "unchanged")
        primary = RuntimeError("OriginalManifestFileRefusal")
        def observe(*_):
            raise primary
        selected = observe_manifest_io(io, observe).new_input(location)
        original_open = selected.delegate.open
        streams = []
        def opened(*args, **kwargs):
            original = original_open(*args, **kwargs)
            streams.append(original)
            return original
        with patch.object(selected.delegate, "open", opened), \
                patch.object(avro_file, "new_decoder", side_effect=AssertionError("unfunded header decoder")):
            with self.assertRaises(RuntimeError) as failed:
                with manifest.AvroFile[Record](selected, schema):
                    self.fail("refused input must not enter")
        self.assertIs(failed.exception, primary)
        self.assertEqual(len(streams), 1)
        self.assertTrue(streams[0].closed)

    def test_unobserved_original_reader_is_unchanged_after_stateless_entry_installation(self):
        io, location, schema = self.write("null", "original")
        observe_manifest_io(io, lambda *_: self.fail("unobserved reader used another input's callback"))
        with manifest.AvroFile[Record](io.new_input(location), schema) as reader:
            self.assertIs(type(reader), AvroFile)
            self.assertEqual([row[0] for row in reader], ["original", "second", ""])

    def test_truncated_codecs_do_not_turn_into_silent_Avro_EOF_success(self):
        for codec, failure in (("deflate", zlib.error), ("bzip2", ValueError)):
            with self.subTest(codec=codec):
                io, location, schema = self.write(codec, "original", corrupt=True)
                selected = observe_manifest_io(io, lambda *_: None)
                with self.assertRaises(failure):
                    with manifest.AvroFile[Record](selected.new_input(location), schema) as reader:
                        list(reader)

    def test_pinned_missing_optional_codecs_keep_their_original_ImportError(self):
        # The existing hash-locked environment has neither optional codec.
        # This proves original absence refusals, not their unexecuted positives.
        for codec, message in ((SnappyCodec, "Snappy support not installed"),
                               (ZStandardCodec, "Zstandard support not installed")):
            with self.subTest(codec=codec):
                with self.assertRaisesRegex(ImportError, message):
                    _decoded_size(codec, b"original")
