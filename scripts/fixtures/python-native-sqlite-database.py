"""Real same-provider Database conformance, not ordinary Local product funding."""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainReadFunctions
from actql_sdk._local_native_sqlite import _OriginalSqliteCustody, _OriginalSqliteFunctions, _OriginalSqliteError
from actql_sdk._local_worker_slot import _OriginalDescriptor

plan = json.loads(Path(sys.argv[1]).read_bytes())
name = sys.argv[2]
root, bundle = Path(plan['root']), Path(plan['bundle'])
for item in plan['files']:
    raw = Path(item['path']).read_bytes()
    assert len(raw) == item['bytes'] and hashlib.sha256(raw).hexdigest() == item['sha256']
lib = C.CDLL(str(bundle / 'libactql_native_control.dylib'))
helper = C.CDLL(plan['helper'])
for symbol in ('actql_native_owned_current', 'actql_native_owned_allocate', 'actql_bootstrap_current_read_context'):
    assert C.cast(getattr(lib, symbol), C.c_void_p).value == C.cast(getattr(helper, symbol), C.c_void_p).value
initialize = lib.actql_original_control_initialize
initialize.argtypes = [C.c_int, C.POINTER(C.c_char_p)]; initialize.restype = C.c_int
assert initialize(1, (C.c_char_p * 1)(b'private-original-sqlite-database')) == 0
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
domain_functions, read = _OriginalDomainFunctions(lib), _OriginalDomainReadFunctions(lib)
sqlite = _OriginalSqliteFunctions(lib)
prepare = helper.actql_fixture_read_preparation_into
prepare.argtypes = [C.POINTER(C.c_void_p)]; prepare.restype = C.c_int
page = os.sysconf('SC_PAGE_SIZE')
directory = Path(tempfile.mkdtemp(prefix='actql-native-sqlite-db-' + name + '-', dir='/private/tmp'))
Path(plan['output'], name + '-start.json').write_text(json.dumps({
    'pid': os.getpid(), 'fixture_directory': str(directory), 'parent_pages': 64,
    'payload_pages': 48, 'heap_pages': 32, 'normal_profile': None}) + '\n')

P, PP = C.c_void_p, C.POINTER(C.c_void_p)
U16 = C.POINTER(C.c_uint16)
U8 = C.POINTER(C.c_ubyte)
I, I64, U64 = C.c_int32, C.c_int64, C.c_uint64


def bind(suffix, args, result=C.c_int):
    fn = getattr(lib, 'actql_sqlite_database_' + suffix)
    fn.argtypes = args; fn.restype = result
    return fn


restore = bind('restore_utf16_into', [P, P, U16, I, I64, PP])
owned = bind('initialize_utf16_into', [P, P, U16, I, I64, U64, U64, PP])
originals = bind('originals_into', [P, PP, PP, PP])
drop = bind('drop_reply', [PP, P, P, P])
finish = bind('finish_closed_data', [PP, PP, PP, PP])
refused = bind('finish_refused_open', [PP, PP, PP])
close = bind('close_into', [P, P, PP])
fence = bind('fence_into', [P, P, PP])
observe = bind('observe_into', [P, P, PP])
transaction = bind('transaction_into', [P, P, I, PP])
select = bind('read_utf16_into', [P, P, U16, I, U16, I, I64, PP])
insert = bind('insert_utf16_into', [P, P, U16, I, U16, I, U8, I64, PP])
compare = bind('compare_utf16_into', [P, P, U16, I, U16, I, I64, U8, I64, PP])
copy_row = bind('copy_row', [P, P, P, P, U8, I64, C.POINTER(I64)])
operation = bind('operation', [P], I)
stage = bind('stage', [P], I)
issue = bind('issue_family', [P], I)
after = bind('after_issue_family', [P], I)
has_row = bind('has_row', [P], I)
revision = bind('revision', [P], I64)
bound = bind('body_bound', [P], I64)


def text(value):
    raw = value.encode('utf-16-le')
    return (C.c_uint16 * (len(raw)//2)).from_buffer_copy(raw), len(raw)//2


reply = P(); assert prepare(C.byref(reply)) == 0
host = _OriginalControlCustody._take_original_reply(control, reply)
descriptor = _OriginalDescriptor(os.open(str(directory / 'backing'), os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
os.ftruncate(descriptor.value, 64 * page); host.acquire_fd(descriptor)
backing_original = _OriginalBackingCustody._borrow_original(host, backing)
with backing_original._physical_scope():
    domain = _OriginalDomainCustody._prepare_original(host, backing_original, descriptor, domain_functions,
        size=48 * page, work=2, attempts=1, holdings=1, transfer=3, retained=0, execution=48 * page)
domain.transfer(); domain._prepare_read_context(read)
library = _OriginalSqliteCustody._prepare_original(domain, sqlite,
    path=str(bundle/'libactql_sqlite_component.dylib'), heap_bytes=32 * page, diagnostic_ceiling=128)
h, l, db, r = P(), P(), P(), P()
facts = []


def fact(expected):
    data = {'operation': operation(r), 'stage': stage(r), 'issue': issue(r),
            'after': after(r), 'has_row': has_row(r), 'revision': revision(r), 'bound': bound(r)}
    facts.append(data)
    assert data['operation'] == expected, data
    return data


def release_reply():
    assert drop(C.byref(r), h, l, db) == 0 and r.value is None


def ok(expected):
    data = fact(expected)
    assert data['issue'] == data['after'] == 0, data
    release_reply()
    return data


def query(scope, key, expected_body, expected_issue=0):
    s, sn = text(scope); k, kn = text(key)
    with domain._read_scope(read):
        assert select(h, db, s, sn, k, kn, 4096, C.byref(r)) == 0
        data = fact(4)
        assert data['issue'] == expected_issue and data['after'] == 0, data
        if expected_body is not None:
            assert data['has_row'] == 1
            raw = (C.c_ubyte * 4096)(); size = I64(-1)
            assert copy_row(r, h, l, db, raw, 4096, C.byref(size)) == 0
            assert bytes(raw[:size.value]) == expected_body
        else:
            assert data['has_row'] == 0
        release_reply()
    return data


def write(key, body, expected=None):
    s, sn = text('sdk/原'); k, kn = text(key)
    b = (C.c_ubyte * len(body)).from_buffer_copy(body)
    with domain._read_scope(read):
        if expected is None:
            assert insert(h, db, s, sn, k, kn, b, len(body), C.byref(r)) == 0
            result = fact(5)
        else:
            assert compare(h, db, s, sn, k, kn, expected, b, len(body), C.byref(r)) == 0
            result = fact(6)
        release_reply()
    return result


def tx(op):
    with domain._read_scope(read):
        assert transaction(h, db, op, C.byref(r)) == 0
        return ok(op)


def finish_all():
    assert close(h, db, C.byref(r)) == 0
    data = fact(10); assert data['stage'] == 3 and data['issue'] == data['after'] == 0, data
    assert finish(C.byref(h), C.byref(l), C.byref(db), C.byref(r)) == 0
    assert all(x.value is None for x in (h, l, db, r))
    library.close(); library.close()
    domain._close_read_context(read)
    backing_original.return_after_stop(); domain.close_after_stop(); host.close()
    assert host._closed and domain._closed and not descriptor.close_attempted
    os.fstat(descriptor.value); descriptor.close()


path = directory / 'store.sqlite3'
if name == 'restore-committed':
    path = Path(plan['saved_database'])
else:
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
    file_stat = os.fstat(fd); os.close(fd)
    if name == 'partial-owned-refusal':
        path.write_bytes(b'original nonempty ownership refusal')
path_before = path.stat()
p, pn = text(str(path))
if name == 'restore-committed':
    assert restore(library._host, library._original, p, pn, 4096, C.byref(r)) == 0
    opened = fact(1)
else:
    assert owned(library._host, library._original, p, pn, 4096,
                 file_stat.st_dev, file_stat.st_ino, C.byref(r)) == 0
    opened = fact(2)
assert originals(r, C.byref(h), C.byref(l), C.byref(db)) == 0
assert h.value == library._host.value and l.value == library._original.value and db.value is not None
release_reply()
try:
    try: library.close()
    except _OriginalSqliteError as error:
        assert not error.unknown and error.fact.issue_family == 5
    else: raise AssertionError('Library closed before its original Database')
    if name == 'owned-schema-and-cas':
        assert opened['issue'] == 0 and opened['stage'] == 1
        tx(7)
        assert write('e\u0301/😀', b'\x00\xff\x01')['revision'] == 0
        assert write('NULL', b'')['revision'] == 0
        tx(8)
        query('sdk/原', 'e\u0301/😀', b'\x00\xff\x01')
        query('sdk/原', 'NULL', b'')
        query('sdk/原', 'missing', None, expected_issue=15)
        tx(7)
        assert write('e\u0301/😀', b'updated', expected=0)['revision'] == 1
        conflict = write('e\u0301/😀', b'wrong', expected=0)
        assert conflict['issue'] == 16 and conflict['revision'] == -1, conflict
        tx(8)
        query('sdk/原', 'e\u0301/😀', b'updated')
        # Outside the same managed caller scope no row operation is entered.
        s, sn = text('sdk/原'); k, kn = text('NULL')
        assert select(h, db, s, sn, k, kn, 4096, C.byref(r)) != 0 and r.value is None
        with domain._read_scope(read):
            # Over-bound input keeps the original Observe, never an Insert ACK.
            body = (C.c_ubyte * 4097)()
            assert insert(h, db, s, sn, k, kn, body, 4097, C.byref(r)) == 0
            assert fact(3)['bound'] == 4096
            release_reply()
        Path(plan['saved_path_file']).write_text(str(path))
    elif name == 'restore-committed':
        assert opened['issue'] == 0
        query('sdk/原', 'e\u0301/😀', b'updated')
        query('sdk/原', 'NULL', b'')
        assert path.stat().st_ino == path_before.st_ino
    elif name == 'partial-owned-refusal':
        assert opened['issue'] != 0 and opened['stage'] == 1
        assert path.read_bytes() == b'original nonempty ownership refusal'
        with domain._read_scope(read):
            assert observe(h, db, C.byref(r)) == 0
            refused_fact = fact(3); assert refused_fact['issue'] != 0 and refused_fact['stage'] == 0
            release_reply()
    elif name == 'unconfirmed-transaction-fence':
        assert opened['issue'] == 0
        tx(7); assert write('unconfirmed', b'private')['issue'] == 0
        with domain._read_scope(read):
            assert fence(h, db, C.byref(r)) == 0; ok(11)
        # A live transaction's private writes cannot reconcile a lost ACK.
        query('sdk/原', 'unconfirmed', None, expected_issue=20)
        refused_write = write('replay', b'not sent')
        assert refused_write['issue'] == 20, refused_write
    else:
        raise AssertionError('Unknown selected case')
finally:
    # Do not force cleanup or replace original slots on a failed assertion.
    # The original fixture directory and failure log stay as custody evidence.
    pass
finish_all()
assert path.stat().st_ino == path_before.st_ino
print(json.dumps({'case': name, 'pass': True, 'initializer_calls': 1, 'facts': facts,
                  'same_originals_closed': True, 'normal_profile': None,
                  'VM': 0, 'worker': 0, 'wheel': 0, 'public_E2E': 0}), flush=True)
