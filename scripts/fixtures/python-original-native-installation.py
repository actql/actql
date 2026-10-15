"""Physical installed-original custody with scalar Core and real Native SQL; retained component mixed diagnostic.

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
from actql_sdk._local_storage import LocalByteStore, ByteWrite, ByteFence, StoredBytes, LocalStorageCommitUnknown

plan = json.loads(Path(sys.argv[1]).read_bytes())
case = sys.argv[2]
assert case in ('native-installation-fresh', 'native-installation-restore')
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
# Test support is independently pinned by the diagnostic consumer plan.
# It supplies opaque Core transport only: no real Account/Policy/Run validation.
import test_local_finite_installation as scalar
from actql_sdk._local_native_store import _OriginalNativeStoreSelection
from actql_sdk._local_installation import OriginalLocalInstallation

path = (Path(Path(plan['saved_path_file']).read_text())
        if case == 'native-installation-restore' else directory/'installation')
if case == 'native-installation-fresh':
    path.mkdir(mode=0o700)
core, calls, workspaces = scalar.FiniteInstallationTests().core()
core._retired = False
selection = _OriginalNativeStoreSelection(core, library, database, read)
installation = OriginalLocalInstallation(core, path,
    observed_at='2026-10-12T00:00:00.000Z', now=lambda: 0,
    project_epoch=lambda *_: (_ for _ in ()).throw(AssertionError('No epoch issue')),
    sdk_finite=True, native_store=selection)
assert installation._native_store is selection
store = installation._store
assert store is not None and type(store) is LocalByteStore
assert store._physical._original is library._database_original
assert store._physical._original._library is library
assert len(installation.binding._selected) == 8
installation.binding.inspect(lambda _: None)
original = store.read('submission-epoch-authority')
assert original is not None and original.generation == 0
facts = {
    'store_generation': list(store.observe_generation()),
    'authority_generation': original.generation,
    # Never print or copy the authentication key into the receipt.
    'authority_sha256': hashlib.sha256(original.payload).hexdigest(),
    'files': {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in path.rglob('*.json')},
    'selected_names': sorted(value.name for value in installation.binding._selected),
}
saved = Path(plan['output'])/'original-facts.json'
if case == 'native-installation-fresh':
    saved.write_text(json.dumps(facts,sort_keys=True)+'\n')
    saved.chmod(0o600)
    Path(plan['saved_path_file']).write_text(str(path))
    assert sum(family=='bootstrap' and name=='produce_sdk' for family,name,_ in calls)==1
    assert not any(family=='bootstrap' and name=='produce' for family,name,_ in calls)
else:
    assert facts == json.loads(saved.read_text())
    assert not any(family.startswith('bootstrap') for family,_,_ in calls)
assert not any(family in ('run','task','model','effect') for family,_,_ in calls)
assert installation.close() is True and installation.close() is True
assert store._closed
library.close(); library.close()
domain._close_read_context(read)
original_backing.return_after_stop(); domain.close_after_stop(); host.close()
assert host._closed and domain._closed and not descriptor.close_attempted
os.fstat(descriptor.value); descriptor.close()
print(json.dumps({'case':case,'pass':True,'originals_closed':True,
    'scalar_Core':True,'actual_SQLite':True,'selected_count':8,
    'existing_only_restore':case=='native-installation-restore',
    'initializer_calls':1,'provider_source':plan['retained_provider_source'],
    'python_source':plan['python_source'],
    'component_helper_source':plan['retained_component_and_helper_source'],
    'normal_profile':None,'VM':0,'worker':0,'wheel':0,'public_E2E':0}),flush=True)
