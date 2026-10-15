"""Retained same-provider DLL with current Python custody; mixed-source diagnostic.

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

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('rows-and-cas', 'restore-same-file', 'lost-commit', 'lost-begin', 'partial-open', 'scan-order-and-bounds', 'scan-copy-current', 'capacity-same-transaction', 'capacity-lost-commit')
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
try: library.close()
except ValueError: pass
else: raise AssertionError('Parent closed before original Database')

observations, transactions = [], []
actual_transaction = database.calls['transaction_into']
def transaction(host_slot, original, operation, reply):
    transactions.append(operation)
    return actual_transaction(host_slot, original, operation, reply)
database.calls['transaction_into'] = transaction

def row(key, expected, *, unconfirmed=False):
    output = bytearray(4096)
    fact, length = (db.lookup_unconfirmed_into if unconfirmed else db.read_into)('sdk/原', key, output)
    assert fact.has_row and bytes(output[:length]) == expected, (fact, length)
    observations.append({'operation':fact.operation, 'revision':fact.revision, 'bytes':length})

if case == 'rows-and-cas':
    db.transaction(7)
    assert db.insert('sdk/原', 'e\u0301/😀', b'\0\xff\r\n').revision == 0
    assert db.insert('sdk/原', 'empty', b'').revision == 0
    db.transaction(8)
    row('e\u0301/😀', b'\0\xff\r\n'); row('empty', b'')
    try: db.read_into('sdk/原', 'missing', bytearray(4096))
    except _OriginalDatabaseError as error:
        assert not error.unknown and error.fact.issue_family == 15 and not error.fact.has_row
    else: raise AssertionError('Missing row was accepted')
    db.transaction(7)
    assert db.compare_exchange('sdk/原', 'e\u0301/😀', 0, b'updated').revision == 1
    try: db.compare_exchange('sdk/原', 'e\u0301/😀', 0, b'rejected')
    except _OriginalDatabaseError as error: assert not error.unknown and error.fact.issue_family == 16
    else: raise AssertionError('Stale revision accepted')
    db.transaction(8); row('e\u0301/😀', b'updated')
    Path(plan['saved_path_file']).write_text(str(path))
elif case == 'restore-same-file':
    row('e\u0301/😀', b'updated'); row('empty', b'')
    assert transactions == []
elif case in ('capacity-same-transaction', 'capacity-lost-commit'):
    def usage(expected_bytes, expected_objects, *, unconfirmed=False):
        fact=(db.lookup_unconfirmed_capacity_usage if unconfirmed else db.capacity_usage)('capacity/原')
        assert (fact.reserved_bytes,fact.reserved_objects)==(expected_bytes,expected_objects),fact
        observations.append({'reserved_bytes':fact.reserved_bytes,'reserved_objects':fact.reserved_objects})
    def refuse(action, family):
        try: action()
        except _OriginalDatabaseError as error:
            assert not error.unknown and error.fact.issue_family==family,error.fact
        else: raise AssertionError('Original capacity refusal was lost')
    usage(0,0)
    refuse(lambda:db.reserve_capacity_in_transaction('capacity/原','e\u0301',8,1,64,2),20)
    refuse(lambda:db.release_capacity_in_transaction('capacity/原','e\u0301',8,1),20)
    db.transaction(7)
    assert db.reserve_capacity_in_transaction('capacity/原','e\u0301',8,1,64,2).capacity_changed is True
    assert db.reserve_capacity_in_transaction('capacity/原','e\u0301',8,1,64,2).capacity_changed is False
    refuse(lambda:db.reserve_capacity_in_transaction('capacity/原','other',60,1,64,2),19)
    db.insert('sdk/原','capacity-row',b'private')
    usage(8,1)
    db.transaction(9)
    usage(0,0)
    refuse(lambda:db.read_into('sdk/原','capacity-row',bytearray(4096)),15)
    db.transaction(7)
    assert db.reserve_capacity_in_transaction('capacity/原','e\u0301',8,1,64,2).capacity_changed is True
    db.insert('sdk/原','capacity-row',b'committed')
    if case=='capacity-lost-commit':
        def lost_commit(host_slot, original, operation, reply):
            code=transaction(host_slot,original,operation,reply)
            assert operation==8 and code==0 and reply._obj.value is not None
            raise OSError('Injected after original capacity+row COMMIT publication')
        database.calls['transaction_into']=lost_commit
        try:db.transaction(8)
        except _OriginalDatabaseError as error:
            original_error=error;assert error.unknown
        else:raise AssertionError('Lost original capacity COMMIT accepted')
        usage(8,1,unconfirmed=True)
        row('capacity-row',b'committed',unconfirmed=True)
        usage(8,1,unconfirmed=True)
        for action in (lambda:db.transaction(8),lambda:db.reserve_capacity_in_transaction('capacity/原','other',1,0,64,2),lambda:db.release_capacity_in_transaction('capacity/原','e\u0301',8,1)):
            try:action()
            except _OriginalDatabaseError as error:assert error is original_error
            else:raise AssertionError('Unknown capacity operation was replayed')
        assert transactions.count(8)==1 and db._write_unknown is original_error
    else:
        db.transaction(8);usage(8,1)
        db.transaction(7)
        refuse(lambda:db.release_capacity_in_transaction('capacity/原','e\u0301',9,1),16)
        assert db.release_capacity_in_transaction('capacity/原','e\u0301',8,1).capacity_changed is True
        assert db.compare_exchange('sdk/原','capacity-row',0,b'private-retirement').revision==1
        usage(0,0);db.transaction(9)
        usage(8,1);row('capacity-row',b'committed')
        db.transaction(7)
        assert db.release_capacity_in_transaction('capacity/原','e\u0301',8,1).capacity_changed is True
        assert db.compare_exchange('sdk/原','capacity-row',0,b'retired').revision==1
        db.transaction(8);usage(0,0);row('capacity-row',b'retired')
        db.transaction(7)
        assert db.release_capacity_in_transaction('capacity/原','e\u0301',8,1).capacity_changed is False
        db.transaction(9)
elif case in ('scan-order-and-bounds', 'scan-copy-current'):
    db.transaction(7)
    for key, body in [('A', b'large'), ('e\u0301/😀', b''), ('é', b'\0\xff')]:
        assert db.insert('sdk/原', key, body).revision == 0
    db.transaction(8)
    key_output = bytearray(512)
    try: db.scan_after_into('sdk/原', '', key_output, bytearray(4))
    except _OriginalDatabaseError as error:
        assert not error.unknown and error.fact.issue_family == 18
        assert key_output == bytearray(512)
    else: raise AssertionError('Scan skipped or copied oversized original row')
    cursor = ''
    for expected_key, expected_body in [('A', b'large'), ('e\u0301/😀', b''), ('é', b'\0\xff')]:
        body_output = bytearray(len(expected_body))
        fact, key_length, body_length = db.scan_after_into('sdk/原', cursor, key_output, body_output)
        assert bytes(key_output[:key_length]) == expected_key.encode('utf-8')
        assert bytes(body_output[:body_length]) == expected_body
        assert fact.operation == 12 and fact.revision == 0
        observations.append({'key_hex':bytes(key_output[:key_length]).hex(), 'bytes':body_length})
        cursor = expected_key
    try: db.scan_after_into('sdk/原', cursor, key_output, bytearray())
    except _OriginalDatabaseError as error: assert not error.unknown and error.fact.issue_family == 15
    else: raise AssertionError('End of original query was fabricated as a row')
    if case == 'scan-copy-current':
        scope_bytes = 'sdk/原'.encode('utf-16-le')
        scope = (C.c_uint16*(len(scope_bytes)//2)).from_buffer_copy(scope_bytes)
        with domain._read_scope(read):
            assert database.calls['scan_utf16_into'](db._host, db._original, scope,
                len(scope_bytes)//2, None, 0, 4096, C.byref(db._reply)) == 0
            assert database.calls['operation'](db._reply) == 12
        try: host.close()
        except _OriginalControlError as error: assert not error.unknown and error.fact.issue_family == 5
        else: raise AssertionError('Host closed with retained scan row')
        with domain._read_scope(read, cleanup=True):
            buffer = (C.c_ubyte*512)()
            for name in ('copy_key', 'copy_row'):
                size = C.c_int64(-1)
                code = database.calls[name](db._reply, db._host, db._native_library,
                    db._original, buffer, 512, C.byref(size))
                assert code != 0 and size.value == -1 and bytes(buffer) == bytes(512)
                observations.append({'closed_copy':name, 'status':code, 'length':size.value})
            assert database.calls['drop_reply'](C.byref(db._reply), db._host,
                db._native_library, db._original) == 0 and db._reply.value is None
elif case in ('lost-commit', 'lost-begin'):
    loss = 8 if case == 'lost-commit' else 7
    if loss == 8:
        db.transaction(7); db.insert('sdk/原', 'original', b'committed')
    def lose(host_slot, original, operation, reply):
        code = transaction(host_slot, original, operation, reply)
        assert operation == loss and code == 0 and reply._obj.value is not None
        raise OSError('Injected after original SQL reply publication')
    database.calls['transaction_into'] = lose
    try: db.transaction(loss)
    except _OriginalDatabaseError as error:
        original_error = error
        assert error.unknown and db._reply.value is not None
    else: raise AssertionError('Lost response accepted')
    for _ in range(2):
        try: db.transaction(loss)
        except _OriginalDatabaseError as error: assert error is original_error
        else: raise AssertionError('Original SQL replayed')
    if loss == 8:
        row('original', b'committed', unconfirmed=True)
        row('original', b'committed', unconfirmed=True)
    else:
        try: db.lookup_unconfirmed_into('sdk/原', 'absent', bytearray(4096))
        except _OriginalDatabaseError as error:
            assert not error.unknown and error.fact.issue_family == 20
        else: raise AssertionError('Active transaction accepted as committed lookup')
    assert db._write_unknown is original_error and transactions.count(loss) == 1
elif case != 'partial-open':
    raise AssertionError('Unselected case')

# Close is physical cleanup, never an inference about the original SQL outcome.
db.close(); db.close(); assert db._closed and db._library._database_original is not db
library.close(); library.close(); domain._close_read_context(read)
original_backing.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not descriptor.close_attempted
os.fstat(descriptor.value); descriptor.close()
assert path.stat().st_ino == original_stat.st_ino
print(json.dumps({'case':case, 'pass':True, 'transactions':transactions, 'rows':observations,
    'originals_closed':True, 'initializer_calls':1, 'normal_profile':None,
    'retained_provider_source':plan['retained_provider_source'], 'python_source':plan['python_source'],
    'new_DLL':0, 'VM':0, 'wheel':0, 'public_E2E':0}), flush=True)
