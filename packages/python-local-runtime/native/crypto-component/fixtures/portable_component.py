"""Physical Crypto conformance using synthetic evidence and a funded caller arena."""

from base64 import b64decode
import _ctypes
import ctypes
import json
import os
from pathlib import Path
import platform
import sys
from threading import Thread


class PortableCrypto:
    def __init__(self, path: Path) -> None:
        self.library = ctypes.CDLL(str(path.resolve()), mode=ctypes.RTLD_LOCAL)
        (
            self.begin, self.seal, self.open, self.inventory, self.close,
        ) = (getattr(self.library, 'actql_portable_crypto_' + action)
             for action in ('begin', 'seal', 'open', 'inventory', 'close'))
        pointer, size = ctypes.c_void_p, ctypes.c_size_t
        self.begin.argtypes = (pointer, size, ctypes.c_uint, ctypes.POINTER(ctypes.c_uint))
        self.seal.argtypes = (pointer, pointer, size, pointer, size, pointer, size, pointer, size)
        self.open.argtypes = self.seal.argtypes
        self.inventory.argtypes = (pointer, ctypes.POINTER(size))
        self.close.argtypes = self.inventory.argtypes

    def unload(self) -> None:
        _ctypes.dlclose(self.library._handle)


def qualify(path: Path) -> dict[str, object]:
    primitive = PortableCrypto(path)
    capacity = 512 * 1024
    arena = ctypes.create_string_buffer(capacity)
    other_arena = ctypes.create_string_buffer(capacity)
    census = (ctypes.c_size_t * 5)()
    custody = ctypes.c_uint()
    # FIPS-required or undeclared policy cannot acquire the original arena.
    assert primitive.begin(arena, capacity, 2, ctypes.byref(custody)) == 2
    assert custody.value == 0 and arena.raw == bytes(capacity)
    assert primitive.begin(arena, capacity - 16, 1, ctypes.byref(custody)) == 4
    assert custody.value == 0 and arena.raw == bytes(capacity)
    assert primitive.begin(arena, capacity, 1, ctypes.byref(custody)) == 0
    assert custody.value == 1
    assert primitive.inventory(arena, census) == 0
    cold = list(census)

    key = bytes(range(32))
    prefix = b'actql-private-publication-evidence/0.1\0'
    aad = prefix + b'model_raw_response\0sha256:' + b'a' * 64
    raw = b'{"http_status":429}\nAP+AoHgK'
    encrypted = ctypes.create_string_buffer(len(raw) + 28)

    def sealing(body, output, owner=arena):
        return primitive.seal(owner, key, len(key), aad, len(aad),
                              body, len(body), output, len(output))

    def opening(body, domain, output):
        return primitive.open(arena, key, len(key), domain, len(domain),
                              body, len(body), output, len(output))

    try:
        foreign = []
        worker = Thread(target=lambda: foreign.append(sealing(raw, encrypted)))
        worker.start()
        worker.join()
        assert foreign == [1] and encrypted.raw == bytes(len(encrypted))
        assert sealing(raw, encrypted, other_arena) == 1
        assert sealing(raw, ctypes.create_string_buffer(len(encrypted) - 1)) == 1
        assert sealing(raw, encrypted) == 0
        duplicate = ctypes.create_string_buffer(len(encrypted))
        assert sealing(raw, duplicate) == 0
        assert encrypted.raw[:12] != duplicate.raw[:12]

        output = ctypes.create_string_buffer(len(raw))
        assert opening(encrypted, aad, output) == 0 and output.raw == raw
        assert opening(encrypted, aad[:-1] + b'b', output) == 3
        assert output.raw == bytes(len(output))
        encrypted[-1] = encrypted[-1][0] ^ 1
        assert opening(encrypted, aad, output) == 3
        assert output.raw == bytes(len(output))

        # Independent Node AES-GCM vector used by the original Native reader.
        golden = (b64decode('AAECAwQFBgcICQoL') +
                  b64decode('KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==') +
                  b64decode('Kl0I/chTHRBRVhomWM83vQ=='))
        expected = b'native-private-evidence-fixture'
        decoded = ctypes.create_string_buffer(len(expected))
        assert opening(golden, prefix + b'effect_capture\0sha256:' + b'0' * 64, decoded) == 0
        assert decoded.raw == expected

        size = 1048576
        plain_max = bytes((0, 255, 128, 160)) * (size // 4)
        cipher_max = ctypes.create_string_buffer(size + 28)
        output_max = ctypes.create_string_buffer(size)
        assert sealing(plain_max, cipher_max) == 0
        assert opening(cipher_max, aad, output_max) == 0 and output_max.raw == plain_max
    finally:
        assert primitive.close(arena, census) == 0
        assert census[2] == census[3] == 0 and arena.raw == bytes(capacity)
        assert primitive.inventory(arena, census) == 1
        primitive.unload()
    return {'cold': cold, 'closed': list(census), 'first_close': True, 'maximum_plaintext': size}


if __name__ == '__main__':
    library = Path(sys.argv[1])
    environment = (os.environ.get('OPENSSL_CONF'), os.environ.get('OPENSSL_MODULES'))
    assert all(environment)
    observations = [qualify(library), qualify(library)]
    assert environment == (os.environ.get('OPENSSL_CONF'), os.environ.get('OPENSSL_MODULES'))
    print(json.dumps({'target': f'{platform.system()}-{platform.machine()}',
                      'python': platform.python_version(), 'observations': observations}))
