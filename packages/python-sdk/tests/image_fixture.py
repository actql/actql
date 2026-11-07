"""Independent non-executable image metadata; no adopted product capacity."""
import hashlib
import json

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
        'core_abi': 83, 'wasmtime_version': '38.0.0', 'runtime_library_sha256': RUNTIME_HASH,
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
