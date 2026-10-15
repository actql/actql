"""Same original Native byte port; retained component mixed diagnostic.

Fresh fixture files only. This proves neither ordinary Host funding nor a new
runtime cohort. Faults are injected after actual published SQL replies.
"""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions, _OriginalControlError
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions
from actql_sdk._local_native_sqlite import _OriginalSqliteCustody, _OriginalSqliteFunctions
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseCustody, _OriginalDatabaseFunctions, _OriginalDatabaseError
from actql_sdk._local_worker_slot import _OriginalDescriptor
from actql_sdk._local_native_storage import _NativeByteDatabase

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case == 'byte-port-values'
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256'], item['path']
lib = C.CDLL(str(Path(plan['bundle']) / 'libactql_native_control.dylib'))
helper = C.CDLL(plan['helper'])
for symbol in ('actql_native_owned_current', 'actql_native_owned_allocate', 'actql_bootstrap_current_read_context'):
    assert C.cast(getattr(lib, symbol), C.c_void_p).value == C.cast(getattr(helper, symbol), C.c_void_p).value
initialize = lib.actql_original_control_initialize
initialize.argtypes = [C.c_int, C.POINTER(C.c_char_p)]; initialize.restype = C.c_int
assert initialize(1, (C.c_char_p * 1)(b'private-python-database-custody')) == 0
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
functions, read = _OriginalDomainFunctions(lib), _OriginalDomainReadFunctions(lib)
sqlite, database = _OriginalSqliteFunctions(lib), _OriginalDatabaseFunctions(lib)
prepare = helper.actql_fixture_read_preparation_into
prepare.argtypes = [C.POINTER(C.c_void_p)]; prepare.restype = C.c_int
page = os.sysconf('SC_PAGE_SIZE')
directory = Path(tempfile.mkdtemp(prefix='actql-python-database-' + case + '-', dir='/private/tmp'))
Path(plan['output'], case + '-start.json').write_text(json.dumps({
    'pid': os.getpid(), 'directory': str(directory), 'parent_pages':64,
    'payload_pages':48, 'heap_pages':32, 'normal_profile':None}) + '\n')
r = C.c_void_p(); assert prepare(C.byref(r)) == 0
host = _OriginalControlCustody._take_original_reply(control, r)
descriptor = _OriginalDescriptor(os.open(directory/'backing', os.O_RDWR|os.O_CREAT|os.O_EXCL, 0o600))
os.ftruncate(descriptor.value, 64*page); host.acquire_fd(descriptor)
original_backing = _OriginalBackingCustody._borrow_original(host, backing)
with original_backing._physical_scope():
    domain = _OriginalDomainCustody._prepare_original(host, original_backing, descriptor, functions,
        size=48*page, work=2, attempts=1, holdings=1, transfer=3, retained=0, execution=48*page)
domain.transfer(); domain._prepare_read_context(read)
library = _OriginalSqliteCustody._prepare_original(domain, sqlite,
    path=str(Path(plan['bundle'])/'libactql_sqlite_component.dylib'), heap_bytes=32*page, diagnostic_ceiling=128)
if case == 'restore-same-file':
    path = Path(Path(plan['saved_path_file']).read_text())
    original_stat = path.stat()
    db = _OriginalDatabaseCustody._open_original(library, database, read,
        path=str(path), max_body_bytes=4096)
else:
    path = directory/'original.sqlite3'
    fd = os.open(path, os.O_RDWR|os.O_CREAT|os.O_EXCL, 0o600)
    original_stat = os.fstat(fd); os.close(fd)
    if case == 'partial-open': path.write_bytes(b'original nonempty file')
    try:
        db = _OriginalDatabaseCustody._open_original(library, database, read,
            path=str(path), max_body_bytes=4096, ownership=(original_stat.st_dev, original_stat.st_ino))
    except _OriginalDatabaseError as error:
        assert case == 'partial-open' and not error.unknown and error.fact.stage == 1
        db = error.cleanup_database
        assert db._original.value is not None and path.read_bytes() == b'original nonempty file'

port = _NativeByteDatabase(db)
key = 'namespace:6:原/😀:e\u0301'
empty = 'namespace:6:原/😀:empty'
port.begin_immediate()
assert port.reserve_capacity_in_transaction('capacity/原', 'held', 8, 1, 64, 2, 2) is True
assert port.write_record(key, None, b'\0\xff\r\n') == 0
assert port.write_record(empty, None, b'') == 0
port.commit()
port.begin_read()
assert port.read_row(key, 4) == (0, b'\0\xff\r\n', 'blob', 4)
assert port.read_row(empty, 0) == (0, b'', 'blob', 0)
assert port.read_header(key) == (0, 4)
assert port.read_capacity('capacity/原', 'held') == (8, 1)
assert port.capacity_usage('capacity/原') == (8, 1)
assert port.record_usage() == (2, 4) and port.reservation_count() == 1
prefix = 'namespace:6:原/😀:'
assert port.scan_range(prefix, prefix[:-1]+';', 4, inclusive=True, exact=False) == (
    empty, 0, b'', 'blob', 0)
assert port.scan_range(empty, prefix[:-1]+';', 4, inclusive=False, exact=False) == (
    key, 0, b'\0\xff\r\n', 'blob', 4)
assert port.read_row('absent', 4) is None
port.finish_read()
assert port.in_transaction is False
port.begin_immediate()
assert port.write_record(key, 0, b'changed') == 1
port.commit()
assert port.read_row(key, 8) == (1, b'changed', 'blob', 7)
port.close(); port.close(); library.close(); library.close()
domain._close_read_context(read)
original_backing.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not descriptor.close_attempted
os.fstat(descriptor.value); descriptor.close()
assert path.stat().st_ino == original_stat.st_ino
print(json.dumps({'case': case, 'pass': True, 'originals_closed': True,
    'same_database': True, 'initializer_calls': 1,
    'provider_source': plan['retained_provider_source'], 'python_source': plan['python_source'],
    'component_helper_source': plan['retained_component_and_helper_source'],
    'normal_profile': None, 'VM': 0, 'worker': 0, 'wheel': 0, 'public_E2E': 0}), flush=True)

