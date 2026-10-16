"""Same-provider original fenced read transport; mixed component diagnostic.

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
from actql_sdk._local_native_sqlite_lookup import _OriginalLookupError, _OriginalLookupFunctions

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('snapshot-values', 'snapshot-lost-start', 'snapshot-lost-finish', 'snapshot-active-refusal')
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

transactions, observations = [], []
actual_transaction = database.calls['transaction_into']
def transaction(host_slot, original, operation, reply):
    transactions.append(operation)
    return actual_transaction(host_slot, original, operation, reply)
database.calls['transaction_into'] = transaction

# Exercise the ordinary header/deferred-BEGIN and bounded reservation roots
# before fencing; neither is a read permission or a reconciliation decision.
assert db.begin_read().operation == 20
db.transaction(9)
db.transaction(7)
assert db.reserve_bounded_capacity('capacity/原', 'e\u0301', 8, 1, 64, 2, 2).capacity_changed is True
assert db.insert('sdk/原', 'A', b'\0\xff\r\n').revision == 0
assert db.insert('sdk/原', 'e\u0301/😀', b'').revision == 0
assert db.read_header('sdk/原', 'e\u0301/😀').header_body_bytes == 0
if case != 'snapshot-active-refusal':
    loss = 8
else:
    db.transaction(9)
    loss = 7

def lose_write(host_slot, original, operation, reply):
    code = transaction(host_slot, original, operation, reply)
    assert operation == loss and code == 0 and reply._obj.value is not None
    raise OSError('Injected after actual original transaction reply publication')
database.calls['transaction_into'] = lose_write
prior_loss_count = transactions.count(loss)
try: db.transaction(loss)
except _OriginalDatabaseError as error:
    original_error = error
    assert error.unknown and db._reply.value is not None
else: raise AssertionError('Lost original SQL response accepted')

if case == 'snapshot-lost-start':
    # Wrap only the transport after the real C call has filled BOTH original
    # slots. The original Core/SQLite start is not replaced by a scalar double.
    actual_start = lib.actql_sqlite_lookup_start_into
    _OriginalLookupFunctions(lib)
    def lose_start(*args):
        status = actual_start(*args)
        assert status == 0 and all(arg._obj.value is not None for arg in args[-2:])
        raise OSError('Injected after actual same-child start')
    lib.actql_sqlite_lookup_start_into = lose_start
    try: db.lookup_unconfirmed_snapshot()
    except _OriginalLookupError as error:
        assert error.unknown and error.operation == 22
        child = error.cleanup_lookup
    else: raise AssertionError('Lost start was accepted')
    lib.actql_sqlite_lookup_start_into = actual_start
    child.close()
    assert child._closed and db._lookup_original is None
elif case == 'snapshot-active-refusal':
    try: db.lookup_unconfirmed_snapshot()
    except _OriginalLookupError as error:
        assert not error.unknown and error.fact.issue_family == 20, error.fact
        child = error.cleanup_lookup
    else: raise AssertionError('Old active write transaction entered lookup')
    child.close()
    assert child._closed and db._lookup_original is None
else:
    child = db.lookup_unconfirmed_snapshot()
    assert child._database is db and db._lookup_original is child
    output, key = bytearray(4096), bytearray(512)
    fact, size = child.read_into('sdk/原', 'A', output)
    assert fact.operation == 24 and fact.revision == 0 and bytes(output[:size]) == b'\0\xff\r\n'
    header = child.read_header('sdk/原', 'e\u0301/😀')
    assert header.has_header and header.header_body_bytes == 0 and header.revision == 0
    fact, key_size, size = child.scan_after_into('sdk/原', 'A', key, output)
    assert bytes(key[:key_size]) == 'e\u0301/😀'.encode() and size == 0
    reservation = child.read_capacity('capacity/原', 'e\u0301')
    assert (reservation.reserved_bytes, reservation.reserved_objects) == (8, 1)
    usage = child.capacity_usage('capacity/原')
    assert (usage.reserved_bytes, usage.reserved_objects) == (8, 1)
    total = child.database_usage()
    assert (total.record_count, total.record_body_bytes, total.reservation_count) == (2, 4, 1)
    observations.append({'row_revision': fact.revision, 'header_bytes': header.header_body_bytes,
        'key_hex': bytes(key[:key_size]).hex(), 'totals': [2, 4, 1], 'reservation': [8, 1]})
    if case == 'snapshot-lost-finish':
        actual_finish = child._calls.calls['finish_into']
        finish_calls = []
        def lose_finish(*args):
            finish_calls.append(1)
            status = actual_finish(*args)
            assert status == 0 and args[-1]._obj.value is not None
            raise OSError('Injected after actual same-child stop')
        child._calls.calls['finish_into'] = lose_finish
        try: child.finish()
        except _OriginalLookupError as error: assert error.unknown and error.operation == 30
        else: raise AssertionError('Lost finish was accepted')
        child.close()
        assert finish_calls == [1]
    else:
        assert child.finish().operation == 30
    assert child._closed and db._lookup_original is None

assert db._write_unknown is original_error
for action in (lambda: db.transaction(loss), lambda: db.insert('sdk/原', 'replay', b'no')):
    try: action()
    except _OriginalDatabaseError as error: assert error is original_error
    else: raise AssertionError('Read cleanup cleared original Unknown or permitted replay')
assert transactions.count(loss) == prior_loss_count + 1
db.close(); db.close(); library.close(); library.close()
domain._close_read_context(read)
original_backing.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not descriptor.close_attempted
os.fstat(descriptor.value); descriptor.close()
assert path.stat().st_ino == original_stat.st_ino
print(json.dumps({'case': case, 'pass': True, 'transactions': transactions,
    'observations': observations, 'originals_closed': True, 'initializer_calls': 1,
    'provider_source': plan['retained_provider_source'], 'python_source': plan['python_source'],
    'component_helper_source': plan['retained_component_and_helper_source'],
    'normal_profile': None, 'VM': 0, 'worker': 0, 'wheel': 0, 'public_E2E': 0}), flush=True)
