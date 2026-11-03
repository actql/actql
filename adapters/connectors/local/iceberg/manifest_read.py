"""Before-call observations around the pinned original manifest reader.

No Avro header/schema/record parser, resource issuer or cleanup owner lives here.
The selected input keeps its own observer; the process-local entry retains no
Catalog, request or material. Unobserved inputs use the original reader class.
"""
import os as _os
import zlib as _zlib
from io import BytesIO as _BytesIO
from typing import TypeVar as _TypeVar

from pyiceberg import manifest as _manifest
from pyiceberg.avro.file import AvroFile as _OriginalAvroFile
from pyiceberg.avro.codecs import deflate as _deflate
from pyiceberg.avro.codecs import bzip2 as _bzip2
from pyiceberg.avro.codecs import snappy_codec as _snappy
from pyiceberg.avro.codecs import zstandard_codec as _zstandard
from pyiceberg.io import FileIO as _FileIO, InputFile as _InputFile


_QUANTUM = 65536
_T = _TypeVar("_T")


def _count_stream(stream):
    count = 0
    while block := stream.read(_QUANTUM):
        count += len(block)
    return count


def _decoded_size(codec, data):
    if codec is _deflate.DeflateCodec:
        # The original Avro codec uses RAW deflate, not a gzip stream/ISIZE.
        decoder = _zlib.decompressobj(-15)
        pending, count = data, 0
        while True:
            block = decoder.decompress(pending, _QUANTUM)
            count += len(block)
            if decoder.eof:
                return count
            pending = decoder.unconsumed_tail
            if not pending and len(block) < _QUANTUM:
                raise _zlib.error("incomplete or truncated Avro deflate stream")
    if codec is _bzip2.BZip2Codec:
        if not hasattr(_bzip2, "bz2"):
            codec.decompress(data)
            raise ValueError("MissingOriginalManifestCodecRefusal")
        # BZ2File streams all concatenated members with bounded output reads.
        try:
            with _bzip2.bz2.BZ2File(_BytesIO(data)) as stream:
                return _count_stream(stream)
        except EOFError as cause:
            # AvroFile treats EOFError as its end marker. A truncated codec
            # must keep the original bz2.decompress refusal category instead.
            raise ValueError("Compressed data ended before the end-of-stream marker was reached") from cause
    if codec is _zstandard.ZStandardCodec:
        if not hasattr(_zstandard, "ZstdDecompressor"):
            # The pinned optional-dependency refusal allocates no output.
            codec.decompress(data)
            raise ValueError("MissingOriginalManifestCodecRefusal")
        with _zstandard.ZstdDecompressor().stream_reader(_BytesIO(data)) as stream:
            return _count_stream(stream)
    if codec is _snappy.SnappyCodec:
        if not hasattr(_snappy, "snappy"):
            codec.decompress(data)
            raise ValueError("MissingOriginalManifestCodecRefusal")
        # The raw Snappy preamble declares the uint32 output length. This is
        # only a quantity: the SAME original codec still validates body/CRC.
        # https://github.com/google/snappy/blob/main/format_description.txt
        count = 0
        for index, byte in enumerate(data[:5]):
            count |= (byte & 127) << (7 * index)
            if byte < 128 and count <= 4294967295:
                return count
        raise ValueError("InvalidManifestSnappyLength")
    raise ValueError("ManifestCodecObservationUnavailable")


class _ObservedInput(_InputFile):
    def __init__(self, delegate, observe):
        super().__init__(delegate.location)
        self.delegate, self.observe = delegate, observe

    def __len__(self):
        return len(self.delegate)

    def exists(self):
        return self.delegate.exists()

    def open(self, *args, **kwargs):
        return self.delegate.open(*args, **kwargs)


class _ManifestSnapshot(_ObservedInput):
    def open(self, *args, **kwargs):
        with self.delegate.open(*args, **kwargs) as original:
            original.seek(0, _os.SEEK_END)
            size = original.tell()
            original.seek(0)
            self.observe("manifest-file", size)
            data = original.read(size)
            if len(data) != size or original.read(1):
                raise ValueError("TableManifestFileChanged")
            return _BytesIO(data)


class _BlockDecoder:
    def __init__(self, original):
        self.original = original
        self.records, self.raw = None, None

    def read(self, count):
        return self.original.read(count)

    def read_int(self):
        self.records = self.original.read_int()
        return self.records

    def read_bytes(self):
        self.raw = self.original.read_bytes()
        return self.raw


class _BlockCodec:
    def __init__(self, codec, decoder, observe, columns):
        self.codec, self.decompress_original = codec, codec.decompress
        self.decoder, self.observe, self.columns = decoder, observe, columns

    def decompress(self, data):
        phase = {_deflate.DeflateCodec: "manifest-deflate",
                 _bzip2.BZip2Codec: "manifest-bzip2",
                 _zstandard.ZStandardCodec: "manifest-zstandard",
                 _snappy.SnappyCodec: "manifest-snappy"}.get(self.codec)
        if phase is None:
            raise ValueError("ManifestCodecObservationUnavailable")
        # Codec identity is observation DATA, not a grant. The fixed output
        # quantum alone is not a bound on an opaque native codec's workspace.
        self.observe(phase, _QUANTUM)
        size = _decoded_size(self.codec, data)
        self.observe("manifest-block", size, self.decoder.records, self.columns)
        # Same selected original function and bytes, not a substitute decoder.
        return self.decompress_original(data)


class _BlockHeader:
    def __init__(self, original, decoder, observe, columns):
        self.original, self.decoder = original, decoder
        self.observe, self.columns = observe, columns

    @property
    def sync(self):
        return self.original.sync

    def compression_codec(self):
        codec = self.original.compression_codec()
        if codec is None:
            self.observe("manifest-block", len(self.decoder.raw), self.decoder.records, self.columns)
            return None
        return _BlockCodec(codec, self.decoder, self.observe, self.columns)


class _ObservedAvroFile(_OriginalAvroFile[_T]):
    def __enter__(self):
        original = self.input_file
        self.input_file = _ManifestSnapshot(original.delegate, original.observe)
        try:
            # Original header, schema resolution, read_types and read_enums.
            return super().__enter__()
        finally:
            self.input_file = original

    def _read_block(self):
        original_decoder, original_header = self.decoder, self.header
        self.decoder = _BlockDecoder(original_decoder)
        self.header = _BlockHeader(original_header, self.decoder, self.input_file.observe, len(self.schema.fields))
        try:
            # Original block count/sync/codec selection, Block and decoder.
            return super()._read_block()
        finally:
            self.decoder, self.header = original_decoder, original_header


class _AvroInputEntry:
    @classmethod
    def __class_getitem__(cls, _record_type):
        # The upstream callsite's generic argument is runtime annotation only;
        # its real read_schema/read_types/read_enums arguments pass unchanged.
        return cls

    def __new__(cls, input_file, *args, **kwargs):
        reader = _ObservedAvroFile if isinstance(input_file, _ObservedInput) else _OriginalAvroFile
        return reader(input_file, *args, **kwargs)


class _ObservedIO(_FileIO):
    def __init__(self, delegate, observe):
        super().__init__(delegate.properties)
        self.delegate, self.observe = delegate, observe

    def new_input(self, location):
        return _ObservedInput(self.delegate.new_input(location), self.observe)

    def new_output(self, location):
        return self.delegate.new_output(location)

    def delete(self, location):
        return self.delegate.delete(location)


def observe_manifest_io(delegate, observe):
    # Two existing upstream manifest entrances use this module-local symbol.
    # Keep a stateless process-local adapter; never install per-Request globals
    # or restore the entrance while the original executor may still be live.
    if _manifest.AvroFile not in (_OriginalAvroFile, _AvroInputEntry):
        raise ValueError("ForeignOriginalManifestReader")
    _manifest.AvroFile = _AvroInputEntry
    return _ObservedIO(delegate, observe)
