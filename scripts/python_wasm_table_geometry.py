"""Read only defined wasm32 funcref table bounds, without loading a runtime.

Other section payloads and the Core ABI remain the existing compiler's job.
This is bounded module metadata, never an allocation or execution admission.
"""
from __future__ import annotations


MAX_MODULE_BYTES = 32 * 1024 * 1024


def defined_table_limits(module: bytes) -> tuple[tuple[int, int], ...]:
    if (type(module) is not bytes or not 8 <= len(module) <= MAX_MODULE_BYTES
            or module[:8] != b'\0asm\x01\0\0\0'):
        raise ValueError('Invalid original Wasm module header or extent')
    position = 8

    def u32(end: int) -> int:
        nonlocal position
        value = 0
        for shift in range(0, 35, 7):
            if position >= end:
                raise ValueError('Truncated Wasm table geometry')
            byte = module[position]
            position += 1
            if shift == 28 and byte & 0xf0:
                raise ValueError('Overflowing Wasm table geometry')
            value |= (byte & 0x7f) << shift
            if byte < 0x80:
                return value
        raise ValueError('Invalid Wasm table geometry integer')

    tables: tuple[tuple[int, int], ...] | None = None
    while position < len(module):
        section = module[position]
        position += 1
        length = u32(len(module))
        end = position + length
        if section > 13 or end > len(module):
            raise ValueError('Invalid Wasm section extent')
        if section != 4:
            position = end
            continue
        if tables is not None or u32(end) != 1:
            raise ValueError('Select one original Core table section')
        if position >= end or module[position] != 0x70:
            raise ValueError('Select the original wasm32 funcref table')
        position += 1
        # Only an explicit finite maximum, without shared/table64 flags.
        if u32(end) != 1:
            raise ValueError('Original Core table must have finite wasm32 bounds')
        minimum, maximum = u32(end), u32(end)
        if not 0 <= minimum <= maximum or maximum == 0 or position != end:
            raise ValueError('Invalid original Core table bounds')
        tables = ((minimum, maximum),)
    if tables is None:
        raise ValueError('Original Core table geometry is unavailable')
    return tables
