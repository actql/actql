"""Same concrete LocalByteStore on an original Native Database; retained component mixed diagnostic.

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
from actql_sdk._local_native_store import _open_original_native_store
from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_storage import LocalByteStore, ByteWrite, StoredBytes, LocalStorageCommitUnknown

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case == 'native-store-values'
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
path = directory/'original.sqlite3'
file_root = LocalFileRoot(directory, max_files=1, max_chunk_bytes=64)
file = file_root.create_writer(path.name, 0)
original_stat = path.stat()
store = _open_original_native_store(path, file_root, library=library,
    functions=database, read=read, max_records=4, max_record_bytes=4096,
    max_payload_bytes=8192, new_file=file)
assert type(store) is LocalByteStore and store.claim_creation() is True
assert store.claim_creation() is False and file.store_claimed
key = store.namespaced_key('sdk/原', 'e\u0301/😀')
assert store.compare_exchange(key, None, b'\0\xff\r\n') == 0
assert store.read(key) == StoredBytes(0, b'\0\xff\r\n')
assert store.compare_exchange(key, 9, b'wrong') is None
write = ByteWrite(key, 0, b'original-next')
actual_transaction = database.calls['transaction_into']
commits = []
def lose_commit(host_slot, original, operation, reply):
    code = actual_transaction(host_slot, original, operation, reply)
    if operation == 8:
        commits.append(1)
        assert code == 0 and reply._obj.value is not None
        raise OSError('Injected after original physical COMMIT')
    return code
database.calls['transaction_into'] = lose_commit
try:
    store.compare_exchange_many_fenced((write,), (), current=lambda: None)
except LocalStorageCommitUnknown as error:
    assert error.cleanup_store is store
else:
    raise AssertionError('Lost COMMIT ACK accepted')
assert commits == [1]
observed = store.read_exchange_many_fenced((write,), (), current=lambda: None)
assert observed == (StoredBytes(1, b'original-next'),)
assert commits == [1] and store._physical._original._write_unknown is not None
try:
    store.compare_exchange(key, 1, b'no replay')
except _OriginalDatabaseError as error:
    assert error is store._physical._original._write_unknown
else:
    raise AssertionError('Snapshot cleared original write fence')
store.close(); store.close()
assert file_root.close_writer(file) is True
restored = _open_original_native_store(path, file_root, library=library,
    functions=database, read=read, max_records=4, max_record_bytes=4096,
    max_payload_bytes=8192)
assert restored.claim_creation() is False
assert restored.read(key) == StoredBytes(1, b'original-next')
restored.close(); library.close(); library.close()
assert file_root.close() is True
domain._close_read_context(read)
original_backing.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not descriptor.close_attempted
os.fstat(descriptor.value); descriptor.close()
assert path.stat().st_ino == original_stat.st_ino
print(json.dumps({'case': case, 'pass': True, 'originals_closed': True,
    'same_database': True, 'same_file_restore': True, 'lost_commit_calls': len(commits),
    'initializer_calls': 1, 'provider_source': plan['retained_provider_source'],
    'python_source': plan['python_source'],
    'component_helper_source': plan['retained_component_and_helper_source'],
    'normal_profile': None, 'VM': 0, 'worker': 0, 'wheel': 0, 'public_E2E': 0}), flush=True)
