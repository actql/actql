"""Actual same-provider Python custody; private profile, not normal funding."""
from __future__ import annotations

import ctypes as c
import hashlib
import json
import os
from pathlib import Path
import sys

from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions,
)
from actql_sdk._local_native_host_resources import (
    _OriginalHostResourcesCustody, _OriginalHostResourcesFunctions, _OriginalHostResourcesError,
)
from actql_sdk._local_native_original_read import _OriginalParentReadCustody, _OriginalParentReadFunctions
from actql_sdk._local_native_sqlite import _OriginalSqliteCustody, _OriginalSqliteFunctions
from actql_sdk._local_native_shim_abi import bind
from actql_sdk._local_native_read_crypto import (
    _OriginalReadCryptoCustody, _OriginalReadCryptoFunctions, _OriginalReadCryptoError,
)
from actql_sdk._local_worker_slot import _OriginalDescriptor


def main() -> None:
    if len(sys.argv) != 6:
        raise ValueError('Expected source, exact pair bundle, Crypto component, fresh fixture and mode')
    source, bundle_arg, crypto_arg, fixture_arg, mode = sys.argv[1:]
    if mode not in ('ready', 'partial'):
        raise ValueError('Unknown physical Read Crypto case')
    bundle, fixture = Path(bundle_arg), Path(fixture_arg)
    fixture.mkdir(mode=0o700, exist_ok=False)
    (fixture / 'original-attempt.json').write_text(json.dumps(dict(
        source=source, pid=os.getpid(), mode=mode, profile='private original pair',
        normal_profile=None, passed=False)) + '\n')
    library = c.CDLL(str(bundle / 'libactql_native_control.dylib'), mode=c.RTLD_GLOBAL)
    initializer = library.actql_original_control_initialize
    initializer.argtypes, initializer.restype = [c.c_int, c.POINTER(c.c_char_p)], c.c_int
    arguments = (c.c_char_p * 2)(b'original-read-crypto-conformance', None)
    assert initializer(1, arguments) == 0
    control_functions = _OriginalControlFunctions(library)
    backing_functions = _OriginalBackingFunctions(library)
    domain_functions = _OriginalDomainFunctions(library)
    read_functions = _OriginalDomainReadFunctions(library)
    parent_functions = _OriginalParentReadFunctions(library)
    sqlite_functions = _OriginalSqliteFunctions(library)
    pair_functions = _OriginalHostResourcesFunctions(library)
    crypto_functions = _OriginalReadCryptoFunctions(library)
    capacity = bind(library, 'actql_host_resources_capacity_scalar')
    cases: list[str] = []

    def step(name: str) -> None:
        cases.append(name)
        print(f'case:{len(cases)}:{name}', flush=True)

    page = os.sysconf('SC_PAGESIZE')
    descriptor = _OriginalDescriptor(os.open(fixture / 'backing',
        os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600))
    os.ftruncate(descriptor.value, 8192 * page)
    host = _OriginalControlCustody._prepare_original(control_functions,
        source=source, recipe=bytes([17]) * 32, generation=1, size=8192 * page,
        work=20, attempts=8, holdings=4, transfer=30, retained=0,
        execution=8192 * page, envelope=65536)
    assert host.acquire_fd(descriptor).issue_family == 0
    control_bytes = capacity(host._original, 1)
    backing = _OriginalBackingCustody._borrow_original(host, backing_functions)
    domains = []
    with backing._physical_scope():
        for pages, holdings, retained, execution in [(7168, 2, 32, 6144), (48, 1, 0, 48)]:
            domain = _OriginalDomainCustody._prepare_original(host, backing, descriptor,
                domain_functions, size=pages * page, work=2, attempts=2,
                holdings=holdings, transfer=3, retained=retained * page,
                execution=execution * page)
            domain.transfer()
            domains.append(domain)
    read_domain, sql_domain = domains
    assert capacity(host._original, 1) == control_bytes + (7168 + 48) * page
    for domain in domains:
        domain._prepare_read_context(read_functions)
    read = _OriginalParentReadCustody._prepare_original(read_domain, parent_functions,
        bootstrap_retained=16 * page, bootstrap_execution=16 * page,
        workspace_execution=4096 * page, read_retained=16 * page, read_execution=1024 * page)
    sqlite = _OriginalSqliteCustody._prepare_original(sql_domain, sqlite_functions,
        path=str(bundle / 'libactql_sqlite_component.dylib'), heap_bytes=32 * page,
        diagnostic_ceiling=128)
    pair = _OriginalHostResourcesCustody._bind_original(read, sqlite, pair_functions)
    assert pair.claim_read(16 * page, 1024 * page).operation == 9
    crypto = _OriginalReadCryptoCustody._prepare_original(pair, crypto_functions)
    assert not read._scope_open and pair._phase is None
    assert crypto._component.value and read._crypto_original is crypto
    step('same claimed pair registers its original component before first Read entry')
    with pair.scope('read'):
        try:
            crypto.load(path=crypto_arg if mode == 'ready' else str(fixture / 'absent-component'),
                heap_bytes=32 * page, diagnostic_ceiling=128)
        except _OriginalReadCryptoError as error:
            assert mode == 'partial' and not error.unknown and error.cleanup_crypto is crypto
            assert error.fact and error.fact.operation == 2 and error.fact.issue_origin == 5
            assert error.fact.issue_family == 3
            step('actual failed module load preserves the same close-only component')
        else:
            assert mode == 'ready'
            step('actual component loads inside the same entered original Read')
        try:
            _OriginalReadCryptoCustody._prepare_original(pair, crypto_functions)
            raise AssertionError('A second component registration was issued')
        except ValueError:
            pass
        assert read._crypto_original is crypto and not host._closed
        if mode == 'ready':
            first, second = crypto.open_library(), crypto.open_library()
            assert first._component.value == second._component.value == crypto._component.value
            assert first._library.value != second._library.value
            key, data = b'key', b'The quick brown fox jumps over the lazy dog'
            expected = bytes.fromhex('f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8')
            assert first.hmac_sha256(key, data) == expected
            assert second.verify_hmac_sha256(key, data, expected)
            assert not second.verify_hmac_sha256(key, data, bytes(32))
            step('two original Libraries compute and verify the independent HMAC vector')
            for close in (crypto.close, read.close, pair.close):
                try:
                    close()
                    raise AssertionError('A child Library became a parent cleanup acknowledgment')
                except ValueError:
                    pass
            first.close()
            try:
                crypto.close()
                raise AssertionError('One Library ACK retired another Library')
            except ValueError:
                pass
            second.close()
            step('separate Library acknowledgments retain the original component and parents')
        crypto.close()
        assert crypto._closed and not read._closed and not pair._closed and not host._closed
        before = capacity(host._original, 1)
        crypto.close()
        assert capacity(host._original, 1) == before
        step('component and managed DATA ACKs leave original Read domain and Host unretired')
    pair.close()
    assert pair._closed and read._closed and sqlite._closed
    backing.return_after_stop()
    for domain in domains:
        domain.close_after_stop()
    assert capacity(host._original, 1) == control_bytes
    host.close()
    assert host._closed and backing._closed and all(domain._closed for domain in domains)
    descriptor.close()
    assert descriptor.closed
    step('separate Read SQLite context domain loan Host and descriptor acknowledgments complete')
    loaded = {}
    for name, module in list(sys.modules.items()):
        if name == 'actql_sdk' or name.startswith('actql_sdk.'):
            path = Path(module.__file__)
            loaded[name] = dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    result = dict(source=source, mode=mode, discovered=len(cases), executed=len(cases),
        passed=len(cases), failed=0, cases=cases, all_originals_closed=True,
        initializer=1, normal_profile=None, public_e2e=0, loaded=loaded,
        actual_control_bytes=control_bytes)
    (fixture / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
