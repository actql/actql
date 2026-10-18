"""Actual original Read/Library into existing Native adoption; private profile."""
from __future__ import annotations

import ctypes as c
import hashlib
import hmac
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
from actql_sdk._local_native_read_crypto import _OriginalReadCryptoCustody, _OriginalReadCryptoFunctions

def main() -> None:
    if len(sys.argv) != 6:
        raise ValueError('Expected source, exact pair bundle, fresh seeded original, fixture and selected Crypto component')
    source, bundle_arg, seeded_arg, fixture_arg, crypto_arg = sys.argv[1:]
    bundle, seeded, fixture = Path(bundle_arg), Path(seeded_arg), Path(fixture_arg)
    fixture.mkdir(mode=0o700, exist_ok=False)
    library = c.CDLL(str(bundle / 'libactql_native_control.dylib'), mode=c.RTLD_GLOBAL)
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
    crypto_functions = _OriginalReadCryptoFunctions(library)
    (fixture / 'original-attempt.json').write_text(json.dumps({
        'source': source, 'pid': os.getpid(), 'seededOriginal': str(seeded),
        'selectedProvider': str(bundle / 'libactql_native_control.dylib'),
        'selectedCrypto': crypto_arg, 'normalFunding': False,
        'sameHostPages': 8192, 'readDomainPages': 7168, 'sqliteDomainPages': 48,
        'cryptoHeapPages': 32, 'claimIsExistingReadReservation': True,
    }, indent=2) + '\n')
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
    component = _OriginalReadCryptoCustody._prepare_original(pair, crypto_functions)
    with pair.scope('read'):
        component.load(path=crypto_arg, heap_bytes=32 * page, diagnostic_ceiling=128)
        crypto = component.open_library()
        message = b'The quick brown fox jumps over the lazy dog'
        assert crypto.hmac_sha256(b'key', message) == hmac.digest(b'key', message, 'sha256')
    step('actual component and original Library are acquired in the same claimed Read')
    adoption = _OriginalAdoptionCustody._open_from_original_library(
        pair, adoption_functions, crypto, parent_path=str(seeded),
        state_name='adoption-capture-journal.host', source_path=str(seeded),
        source_name='adoption-capture-journal.account.json', account_id='operator',
        configuration_files=(), managed_root_path=None, diagnostic_ceiling=128)
    assert adoption._session.value and not adoption._journal.value
    assert adoption._crypto.value == crypto._library.value
    assert read._adoption_original is adoption and crypto._adoption_original is adoption
    step('actual existing-only adoption Session is retained before the physical return')
    assert adoption.current().issue_family == 0
    step('parent current observes the same original Session and actual scoped Root')
    assert adoption.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608).operation == 5
    assert adoption._journal.value
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
    assert crypto._library.value and not crypto._closed
    step('original child DB Root and lock ACK retire only adoption managed DATA')
    adoption.close()
    try:
        adoption.current()
        raise AssertionError('Retired Session became current')
    except ValueError:
        pass
    step('acknowledged repeat cleanup performs no second prepare or open')
    try:
        with pair.scope('read'):
            raise AssertionError('Stopped original Read became available for normal work')
    except _OriginalHostResourcesError as error:
        assert not error.unknown and error.fact is not None and error.fact.issue_family > 0
    with pair.scope('read', cleanup=True):
        crypto.close()
        assert crypto._closed and all(slot.value is None for slot in crypto._slots())
        component.close()
        assert component._closed and all(slot.value is None for slot in component._slots())
    step('same original Library then component ACK retire in cleanup-only Read; parent physical ACKs remain separate')
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
        'controlBytes':control_bytes,'normalFunding':False,'operationalCryptoSupplier':False, 'actualSameReadLibrarySupplier':True,
        'profile':'existing private same-Host pair and selected Read Crypto; not ordinary installed startup'}))


if __name__ == '__main__':
    main()
