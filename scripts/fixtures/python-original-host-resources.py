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
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseCustody, _OriginalDatabaseFunctions
from actql_sdk._local_native_shim_abi import bind
from actql_sdk._local_worker_slot import _OriginalDescriptor


def main() -> None:
    source, bundle_arg, helper_arg, fixture_arg = sys.argv[1:]
    bundle, fixture = Path(bundle_arg), Path(fixture_arg)
    fixture.mkdir(mode=0o700, exist_ok=False)
    root_path = fixture / 'root'
    root_path.mkdir(mode=0o700)
    (root_path / 'one').write_bytes(b'original')
    library = c.CDLL(str(bundle / 'libactql_native_control.dylib'))
    helper = c.CDLL(helper_arg)
    initializer = library.actql_original_control_initialize
    initializer.argtypes, initializer.restype = [c.c_int, c.POINTER(c.c_char_p)], c.c_int
    arguments = (c.c_char_p * 2)(b'original-host-resource-conformance', None)
    assert initializer(1, arguments) == 0
    control_functions = _OriginalControlFunctions(library)
    backing_functions = _OriginalBackingFunctions(library)
    domain_functions = _OriginalDomainFunctions(library)
    read_functions = _OriginalDomainReadFunctions(library)
    parent_functions = _OriginalParentReadFunctions(library)
    sqlite_functions = _OriginalSqliteFunctions(library)
    database_functions = _OriginalDatabaseFunctions(library)
    pair_functions = _OriginalHostResourcesFunctions(library)
    capacity = bind(library, 'actql_host_resources_capacity_scalar')
    helper.actql_fixture_root_into.argtypes = [c.c_char_p, c.c_int32,
        c.POINTER(c.c_void_p), c.POINTER(c.c_void_p)]
    helper.actql_fixture_root_into.restype = c.c_int
    helper.actql_fixture_root_close.argtypes = [c.c_void_p]
    helper.actql_fixture_root_close.restype = c.c_int
    helper.actql_fixture_drop_root_alias.argtypes = [c.POINTER(c.c_void_p)]
    helper.actql_fixture_drop_root_alias.restype = c.c_int
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
    step('original Host binds one Python pair with the same provider and distinct domains')
    calls: list[int] = []
    native_operate = pair_functions.operate

    def counted_operate(h: object, p: object, op: int, out: object) -> int:
        calls.append(op)
        return native_operate(h, p, op, out)

    pair_functions.operate = counted_operate
    acquisition, root = c.c_void_p(), c.c_void_p()
    path_bytes = os.fsencode(root_path)
    with read.scope():
        assert read._scope_open and pair._phase == 'read'
        try:
            with sql_domain._read_scope(read_functions):
                raise AssertionError('Nested foreign phase was entered')
        except ValueError:
            pass
        assert helper.actql_fixture_root_into(path_bytes, len(path_bytes),
            c.byref(acquisition), c.byref(root)) == 0
        assert root.value and acquisition.value is None
    step('real managed Root uses the original Read and nested SQLite entry refuses')
    database_path = fixture / 'original.db'
    fd = os.open(database_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
    stat = os.fstat(fd)
    os.close(fd)
    database = _OriginalDatabaseCustody._open_original(sqlite, database_functions,
        read_functions, path=str(database_path), max_body_bytes=4096,
        ownership=(stat.st_dev, stat.st_ino))
    assert database.transaction(7).issue_family == 0
    assert database.insert('pair', 'one', b'\x00A\xff').revision == 0
    assert database.transaction(8).issue_family == 0
    output = bytearray([9] * 4)
    fact, size = database.read_into('pair', 'one', output)
    assert fact.has_row and size == 3 and output == b'\x00A\xff\x09'
    step('same Library Database performs actual BEGIN INSERT COMMIT and bounded read')
    before = list(calls)
    try:
        pair.close()
        raise AssertionError('Live Database was retired by its parent')
    except ValueError:
        pass
    assert calls == before and not pair._closed and not sqlite._closed
    database.close()
    assert database._closed
    step('pending Database data refuses parent close before a foreign call')

    def pending() -> None:
        try:
            pair.close()
            raise AssertionError('Root alias became a cleanup acknowledgment')
        except _OriginalHostResourcesError as error:
            assert not error.unknown and error.fact and error.fact.operation == 8
            assert error.fact.issue_origin == 2 and not pair._closed
            assert error.cleanup_resources is pair and host._host_resources_original is pair

    pending()
    step('same pending Read survives independent SQLite cleanup')
    with read.scope(cleanup=True):
        assert helper.actql_fixture_root_close(root) == 0
    pending()
    step('physical Root FD close is distinct from the live managed Root alias')
    assert helper.actql_fixture_drop_root_alias(c.byref(root)) == 0 and root.value is None
    pair.close()
    assert pair._closed and read._closed and sqlite._closed
    assert all(slot.value is None for slot in pair._slots())
    assert read._original.value is None and sqlite._original.value is None
    step('last alias permits pair ACK and separate Python parent data retirement')
    before = list(calls)
    pair.close()
    assert calls == before
    try:
        _OriginalHostResourcesCustody._bind_original(read, sqlite, pair_functions)
        raise AssertionError('A retired binding was recreated')
    except ValueError:
        pass
    step('repeat cleanup does not repeat Native pair close or rebind retired inputs')
    backing.return_after_stop()
    for domain in domains:
        domain.close_after_stop()
    assert capacity(host._original, 1) == control_bytes
    host.close()
    assert host._closed and backing._closed and all(domain._closed for domain in domains)
    descriptor.close()
    assert descriptor.closed
    step('original loan domains Host and descriptor retire only after their own ACKs')
    loaded = {}
    for name in ['_local_native_host_resources', '_local_native_control_custody',
                 '_local_native_original_read', '_local_native_domain_custody']:
        module = sys.modules['actql_sdk.' + name]
        path = Path(module.__file__)
        loaded[name] = dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    result = dict(source=source, discovered=len(cases), executed=len(cases),
        passed=len(cases), failed=0, cases=cases, all_originals_closed=True,
        initializer=1, normal_profile=None, public_e2e=0, loaded=loaded,
        actual_control_bytes=control_bytes, native_pair_operations=calls)
    (fixture / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
