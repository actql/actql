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
from actql_sdk._local_worker_slot import _OriginalDescriptor


from actql_sdk._local_native_adoption import _OriginalAdoptionCustody, _OriginalAdoptionFunctions
from actql_sdk._local_native_runtime import _exact_utf16

def main() -> None:
    if len(sys.argv) != 7:
        raise ValueError('Expected source, exact pair bundle, Crypto helper, seeded original, fixture and Crypto Library')
    source, bundle_arg, helper_arg, seeded_arg, fixture_arg, crypto_arg = sys.argv[1:]
    bundle, seeded, fixture = Path(bundle_arg), Path(seeded_arg), Path(fixture_arg)
    fixture.mkdir(mode=0o700, exist_ok=False)
    library, helper = c.CDLL(str(bundle / 'libactql_native_control.dylib')), c.CDLL(helper_arg)
    initializer = library.actql_original_control_initialize
    initializer.argtypes, initializer.restype = [c.c_int, c.POINTER(c.c_char_p)], c.c_int
    arguments = (c.c_char_p * 2)(b'original-adoption-conformance', None)
    assert initializer(1, arguments) == 0
    control_functions = _OriginalControlFunctions(library)
    backing_functions = _OriginalBackingFunctions(library)
    domain_functions = _OriginalDomainFunctions(library)
    read_functions = _OriginalDomainReadFunctions(library)
    parent_functions = _OriginalParentReadFunctions(library)
    sqlite_functions = _OriginalSqliteFunctions(library)
    pair_functions = _OriginalHostResourcesFunctions(library)
    adoption_functions = _OriginalAdoptionFunctions(library)
    capacity = bind(library, 'actql_host_resources_capacity_scalar')
    helper.actql_fixture_adoption_crypto_into.argtypes = [c.c_char_p, c.c_int32, c.POINTER(c.c_void_p)]
    helper.actql_fixture_adoption_crypto_into.restype = c.c_int
    helper.actql_fixture_adoption_crypto_close.argtypes = [c.POINTER(c.c_void_p)]
    helper.actql_fixture_adoption_crypto_close.restype = c.c_int
    crypto = c.c_void_p()
    crypto_path = os.fsencode(crypto_arg)
    assert helper.actql_fixture_adoption_crypto_into(crypto_path, len(crypto_path), c.byref(crypto)) == 0
    assert crypto.value
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
    assert 0 < control_bytes < 8192 * page
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
    assert pair._phase is None and not read._scope_open


    step('one actual Host pair retains its original claimed Read and distinct SQLite domain')
    helper.actql_fixture_adoption_crypto_sha256.argtypes = [c.c_void_p]
    helper.actql_fixture_adoption_crypto_sha256.restype = c.c_int
    with pair.scope('read'):
        assert helper.actql_fixture_adoption_crypto_sha256(crypto) == 0
    step('same Library returns the exact SHA-256 vector and closed-hash refusal')
    prepare_call = bind(library, 'actql_local_adoption_prepare_utf16_into')
    texts = [_exact_utf16(str(seeded), 4096),
             _exact_utf16('adoption-capture-journal.host', 4096),
             _exact_utf16(str(seeded), 4096),
             _exact_utf16('adoption-capture-journal.account.json', 4096),
             _exact_utf16('operator', 4096)]
    empty_units, empty_lengths = (c.c_uint16 * 0)(), (c.c_int32 * 0)()
    attempts: list[int] = []
    def prepare(out: object) -> int:
        attempts.append(1)
        args: list[object] = []
        for text in texts:
            args.extend((text, len(text)))
        code: object = prepare_call(host._original, pair._original, read._original,
            crypto, *args, empty_units, 0, empty_lengths, 0, empty_units, 0, 0, 128, out)
        assert type(code) is int
        return code
    adoption = _OriginalAdoptionCustody._open_original(pair, adoption_functions, prepare=prepare)
    assert attempts == [1] and adoption._session.value and not adoption._journal.value
    assert adoption._crypto.value == crypto.value and read._adoption_original is adoption
    step('actual existing-only adoption Session is retained before the physical return')
    assert adoption.current().issue_family == 0
    step('parent current observes the same original Session and actual scoped Root')
    assert adoption.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608).operation == 5
    assert adoption._journal.value and attempts == [1]
    step('same retained Journal opens through its original serial Read and SQLite phases')
    assert adoption.current().issue_family == 0
    assert pair._phase is None and not read._scope_open
    step('parent current follows the child complete binding after actual Journal open')
    for call in (pair.close, read.close, sqlite.close):
        try:
            call()
            raise AssertionError('A child alias permitted parent retirement')
        except ValueError:
            pass
    step('same Python child registration blocks pair Read and Library retirement')
    adoption.close()
    assert adoption._closed and not pair._closed and not read._closed and not sqlite._closed
    assert all(slot.value is None for slot in adoption._original_slots())
    assert adoption._original.value is None and adoption._reply.value is None
    assert crypto.value
    step('original child DB Root and lock ACK retire only adoption managed DATA')
    adoption.close()
    assert attempts == [1]
    try:
        adoption.current()
        raise AssertionError('Retired Session became current')
    except ValueError:
        pass
    step('acknowledged repeat cleanup performs no second prepare or open')
    assert helper.actql_fixture_adoption_crypto_close(c.byref(crypto)) == 0 and not crypto.value
    step('fixture original Library Owner confirms its own separate close before dropping its alias')
    pair.close()
    assert pair._closed and read._closed and sqlite._closed
    backing.return_after_stop()
    for domain in domains:
        domain.close_after_stop()
    assert capacity(host._original, 1) == control_bytes
    host.close(); descriptor.close()
    assert host._closed and backing._closed and descriptor.closed
    assert all(domain._closed for domain in domains)
    step('original domains loan Host backing and descriptor confirm their separate retirement')
    assert len(cases) == 11
    loaded = {}
    for name, module in list(sys.modules.items()):
        if name == 'actql_sdk' or name.startswith('actql_sdk.'):
            path = Path(module.__file__)
            loaded[name] = {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    print(json.dumps({'source':source,'executed':len(cases),'passed':len(cases),
        'cases':cases,'loadedPython':loaded,'allOriginalsClosed':True,
        'controlBytes':control_bytes,'normalFunding':False,'operationalCryptoSupplier':False,
        'profile':'existing private same-Host pair; fixture-owned Crypto; not ordinary installed startup'}))


if __name__ == '__main__':
    main()
