"""Independent non-executable image metadata; no adopted product capacity."""
import hashlib
import json
import struct

ENGINE = {'target': 'aarch64-apple-darwin', 'cpu_features': ['aarch64-baseline'],
    'consume_fuel': True, 'strategy': 'cranelift', 'parallel_compilation': False,
    'allocation': 'pooling', 'wasm_gc': False, 'wasm_component_model': False,
    'async_support': False, 'memory_reservation': 16777216, 'memory_guard_size': 0,
    'memory_reservation_for_growth': 0, 'max_wasm_stack': 524288, 'pooling': {'total_core_instances': 1, 'total_memories': 1,
    'max_memories_per_module': 1, 'max_memory_size': 16777216, 'max_core_instance_size': 65536,
    'total_tables': 1, 'max_tables_per_module': 1, 'table_elements': 64, 'total_gc_heaps': 0, 'total_component_instances': 0, 'total_stacks': 0}}
# Header-only fixture, explicitly never compiled or deserialized.
IMAGE = b'\x7fELF\x02\x01\x01' + b'\0' * 11 + b'\xb7\x00' + b'\0' * 44
RUNTIME_HASH = hashlib.sha256(b'independent runtime library fixture').hexdigest()
PROVIDER = b'independent original native provider fixture'
PROVIDER_HASH = hashlib.sha256(PROVIDER).hexdigest()
ORIGINAL = json.dumps({'wasmtime_version': '38.0.0', 'runtime_library_sha256': RUNTIME_HASH,
                      'runtime_library_bytes': len(b'independent runtime library fixture'),
                      'provider_library_sha256': PROVIDER_HASH, 'provider_library_bytes': len(PROVIDER),
                      'engine_body': ENGINE, 'image_bytes_limit': 1024}, indent=2).encode()


def descriptor(source, version, module_hash):
    return {'source_sha': source, 'package_version': version, 'module_sha256': module_hash,
        'core_abi': 88, 'wasmtime_version': '38.0.0', 'runtime_library_sha256': RUNTIME_HASH,
        'provider_library_sha256': PROVIDER_HASH,
        'platform': 'darwin-arm64', 'engine_body': json.loads(json.dumps(ENGINE)),
        'engine_sha256': hashlib.sha256(json.dumps(ENGINE, sort_keys=True,
            separators=(',', ':')).encode()).hexdigest(), 'file': 'client_host_wasm.cwasm',
        'bytes': len(IMAGE), 'sha256': hashlib.sha256(IMAGE).hexdigest()}


def table_module(minimum=64, maximum=64):
    """Independent metadata-only Wasm; no Core ABI, instance or image evidence."""
    def u32(value):
        out = bytearray()
        while value >= 128:
            out.append((value & 127) | 128)
            value >>= 7
        out.append(value)
        return bytes(out)
    table = b'\x01\x70\x01' + u32(minimum) + u32(maximum)
    return b'\0asm\x01\0\0\0\x04' + u32(len(table)) + table + b'\x05\x05\x01\x01\x01\x80\x02'


def linux_version_library(names=('GLIBC_2.25', 'GLIBCXX_3.4.22', 'CXXABI_1.3.8'), *, symbol_bytes=0):
    """Independent ELF64 requirement records, never executable shared code.

    Four section headers: NULL, dynstr, verneed and an unrelated versym table.
    These literal layouts are fixtures, not product-generated expectations.
    """
    strings = bytearray(b'\0libc.so.6\0')
    offsets = []
    for name in names:
        offsets.append(len(strings))
        strings.extend(name.encode('ascii') + b'\0')
    needs = bytearray(struct.pack('<HHIII', 1, len(names), 1, 16, 0))
    for index, offset in enumerate(offsets):
        needs.extend(struct.pack('<IHHII', 0, 0, 2 + index, offset,
                                 16 if index + 1 < len(names) else 0))
    start = 64 + 4 * 64
    header = bytearray(b'\x7fELF\x02\x01\x01' + b'\0' * 9 +
                       struct.pack('<HHI', 3, 62, 1) + b'\0' * 40)
    struct.pack_into('<Q', header, 40, 64)
    struct.pack_into('<H', header, 52, 64)
    struct.pack_into('<HH', header, 58, 64, 4)
    sections = b'\0' * 64
    sections += struct.pack('<IIQQQQIIQQ', 0, 3, 0, 0, start, len(strings), 0, 0, 1, 0)
    sections += struct.pack('<IIQQQQIIQQ', 0, 0x6ffffffe, 0, 0, start + len(strings),
                            len(needs), 1, 1, 4, 0)
    sections += struct.pack('<IIQQQQIIQQ', 0, 0x6fffffff, 0, 0,
                            start + len(strings) + len(needs), symbol_bytes, 0, 0, 2, 2)
    return bytes(header) + sections + bytes(strings) + bytes(needs) + b'\0' * symbol_bytes
