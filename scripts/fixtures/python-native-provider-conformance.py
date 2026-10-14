"""Original provider conformance with sticky close; no Engine/VM execution.

Derived from original0bf private12 fixture. Image operations precede retirement;
closing does not reopen execution, and only original cleanup is retried.
"""
import ctypes,hashlib,json,os,sys,tempfile,copy,pickle
from pathlib import Path
from actql_sdk._local_native_control_custody import _OriginalControlCustody,_OriginalControlFunctions,_OriginalControlError
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody,_OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import _OriginalDomainCustody,_OriginalDomainFunctions,_OriginalDomainError,_OriginalDomainMaterialFunctions
from actql_sdk._local_worker_slot import _OriginalDescriptor
from actql_sdk._local_native_holding import _NativeHoldingLease,NativeHoldingRetirementError
from actql_sdk._local_native_domain_borrow import _OriginalDomainBorrow,_OriginalDomainBorrowFunctions,_OriginalDomainBorrowError
p=json.loads(Path(sys.argv[1]).read_text())
for i in p['files']:
 b=Path(i['path']).read_bytes();assert len(b)==i['bytes'] and hashlib.sha256(b).hexdigest()==i['sha256']
for i in json.loads(Path(p['build'],'linked-artifacts.json').read_text()):
 b=Path(i['path']).read_bytes();assert len(b)==i['bytes'] and hashlib.sha256(b).hexdigest()==i['sha256']
loaded_modules=[]
for name in ('_local_native_control_custody','_local_native_domain_custody',
             '_local_native_holding','_local_native_domain_borrow'):
 module=sys.modules['actql_sdk.'+name]
 actual=Path(module.__file__).resolve()
 assert actual==Path(p['root'],'packages/python-sdk/src/actql_sdk',name+'.py').resolve()
 loaded_modules.append({'module':name,'path':str(actual),'sha256':hashlib.sha256(actual.read_bytes()).hexdigest()})
Path(p['build'],'actual-python-modules.json').write_text(json.dumps(loaded_modules,indent=2)+'\n')
lib=ctypes.CDLL(str(Path(p['build'],'libactql_native_control.dylib')))
fixture=ctypes.CDLL(str(Path(p['build'],'libactql_fixture_supplier.dylib')))
init=lib.actql_original_control_initialize;init.argtypes=[ctypes.c_int,ctypes.POINTER(ctypes.c_char_p)];init.restype=ctypes.c_int
assert init(1,(ctypes.c_char_p*1)(b'private-domain'))==0
control=_OriginalControlFunctions(lib);backing=_OriginalBackingFunctions(lib);functions=_OriginalDomainFunctions(lib);material_functions=_OriginalDomainMaterialFunctions(lib);borrow_functions=_OriginalDomainBorrowFunctions(lib)
prepare=fixture.actql_fixture_preparation_reply_into;prepare.argtypes=[ctypes.POINTER(ctypes.c_void_p)];prepare.restype=ctypes.c_int
cases=[];owners=[];domains=[];fds=[]
# Resolve through an actual dependent dylib, not a second C/TLS provider.
for name in ('actql_native_owned_current','actql_native_owned_allocate','actql_native_owned_capture_image_fd','actql_native_domain_borrow_open'):
 assert ctypes.cast(getattr(fixture,name),ctypes.c_void_p).value==ctypes.cast(getattr(lib,name),ctypes.c_void_p).value
cases.append('dependent DLL resolves the same original provider addresses')
with tempfile.TemporaryDirectory(prefix='actql-domain-DLL-') as directory:
 def host():
  reply=ctypes.c_void_p();assert prepare(ctypes.byref(reply))==0
  h=_OriginalControlCustody._take_original_reply(control,reply)
  fd=_OriginalDescriptor(os.open(str(Path(directory,str(len(fds)))),os.O_RDWR|os.O_CREAT|os.O_EXCL,0o600))
  os.ftruncate(fd.value,64*os.sysconf('SC_PAGE_SIZE'));fds.append(fd)
  assert h.acquire_fd(fd).issue_family==0;owners.append(h)
  return h,fd,_OriginalBackingCustody._borrow_original(h,backing)
 def domain(h,fd,scope,size):
  with scope._physical_scope():
   try:d=_OriginalDomainCustody._prepare_original(h,scope,fd,functions,size=size,work=2,attempts=1,holdings=1,transfer=3,retained=0,execution=size)
   except _OriginalDomainError as e:
    domains.append(e.cleanup_domain);raise
  domains.append(d);return d
 def pending_close(d):
  try:d.close_after_stop()
  except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==5
  else:raise AssertionError('Separate original control borrow was ignored')
 page=os.sysconf('SC_PAGE_SIZE')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);assert d.current().issue_family==0
 try:d._project_original_material(material_functions)
 except _OriginalDomainError as e:assert not e.unknown and e.fact.operation==7 and e.fact.issue_family==1
 else:raise AssertionError('Untransferred domain produced material')
 d.transfer()
 material=d._project_original_material(material_functions);original=os.fstat(fd.value)
 assert material.source=='0123456789012345678901234567890123456789' and material.recipe==bytes([17])*32
 assert material.scalars==(1,original.st_dev,original.st_ino,64*page,page,16*page,0,16*page,1,2,1,1,3,0,16*page)
 assert d._project_original_material(material_functions)==material
 with d._physical_scope():assert d.current().issue_family==0
 pending_close(d);assert not d._closed and d._domain.value is not None
 scope.return_after_stop();d.close_after_stop();d.close_after_stop();assert d._closed and not fd.close_attempted
 h.close();os.fstat(fd.value);fd.close();cases.append('actual same domain scope and pending original cleanup ordering')
 h,fd,scope=host()
 try:domain(h,fd,scope,page)
 except _OriginalDomainError as e:
  assert not e.unknown and e.fact.issue_family==6;d=e.cleanup_domain
 else:raise AssertionError('Payload with no room for control acquired a domain')
 try:d.current()
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==6
 else:raise AssertionError('Partial domain handle became current success')
 scope.return_after_stop();d.close_after_stop();h.close();fd.close();cases.append('actual partial physical domain never becomes current success')
 h,fd,scope=host()
 try:domain(h,fd,scope,0)
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==1;d=e.cleanup_domain
 else:raise AssertionError('Invalid preparation created a domain')
 assert d._closed and d._host.value is None and d._domain.value is None
 scope.return_after_stop();h.close();fd.close();cases.append('actual no-domain refusal only retires data references')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer()
 try:d.transfer()
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==3
 else:raise AssertionError('Original domain transfer repeated')
 for action in (copy.copy,copy.deepcopy,pickle.dumps):
  try:action(d)
  except TypeError:pass
  else:raise AssertionError('Domain custody copied')
 foreign=_OriginalDomainFunctions(ctypes.CDLL(str(Path(p['build'],'libactql_native_control.dylib'))))
 try:_OriginalDomainCustody._prepare_original(h,scope,fd,foreign,size=16*page,work=2,attempts=1,holdings=1,transfer=3,retained=0,execution=16*page)
 except ValueError:pass
 else:raise AssertionError('Foreign component gained original custody')
 scope.return_after_stop();d.close_after_stop();h.close();fd.close();cases.append('actual duplicate transfer and copied/foreign component refusal')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer()
 other,other_fd,other_scope=host()
 reply=ctypes.c_void_p();assert material_functions.project(other._original,d._domain,ctypes.byref(reply))==0
 assert functions.operation(reply)==7 and functions.issue(reply)==2
 source=(ctypes.c_ubyte*40)();recipe=(ctypes.c_ubyte*32)();values=(ctypes.c_int64*15)()
 assert material_functions.read(reply,d._host,d._domain,source,recipe,values)!=0
 assert functions.drop(ctypes.byref(reply),d._host,d._domain)==0 and reply.value is None
 other_scope.return_after_stop();other.close();other_fd.close()
 scope.return_after_stop();d.close_after_stop();h.close();fd.close();cases.append('actual foreign target retains true originals and cannot copy material')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer();material=d._project_original_material(material_functions)
 try:h.close()
 except _OriginalControlError as e:assert not e.unknown and e.fact.issue_family==5
 else:raise AssertionError('Parent close ignored original domain')
 try:d._project_original_material(material_functions)
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==4
 else:raise AssertionError('Old material bypassed closing current')
 try:d._project_original_material(copy.copy(material))
 except ValueError:pass
 else:raise AssertionError('Copied material became native original authority')
 scope.return_after_stop();d.close_after_stop();h.close();fd.close();cases.append('actual closing revalidation refuses old or copied material and retains cleanup')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer();material=d._project_original_material(material_functions)
 try:_OriginalDomainBorrow._map_original(borrow_functions,fd,material)
 except _OriginalDomainBorrowError as e:
  assert not e.unknown and e.code==-5;partial=e.cleanup_borrow;partial.close();assert partial._closed
 else:raise AssertionError('Creator alias became a child borrow')
 assert d.current().issue_family==0
 scope.return_after_stop();d.close_after_stop();h.close();fd.close();cases.append('actual partial creator map cleanup leaves original domain usable and FD separate')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer();material=d._project_original_material(material_functions)
 ready=os.pipe();resume=os.pipe();sys.stdout.flush();child=os.fork()
 if child==0:
  os.close(ready[0]);os.close(resume[1]);borrow=None;child_fd=_OriginalDescriptor(fd.value)
  result={'actor_pid':os.getpid(),'parent_pid':os.getppid(),'cases':[],'FD_closed':False}
  try:
   # Physical fixture only. No inherited managed Owner is called in the child,
   # and the selected DLL initializer runs once in the parent, not here.
   borrow=_OriginalDomainBorrow._map_original(borrow_functions,child_fd,material)
   borrow.require_physical_current();result['cases'].append('original child map and physical current')
   try:copy.copy(borrow)
   except TypeError:pass
   else:raise AssertionError('Copied original record')
   os.write(ready[1],b'R');assert os.read(resume[0],1)==b'C'
   pointer=ctypes.c_void_p();assert borrow_functions.pointer(borrow._pointer,ctypes.byref(pointer))==0 and pointer.value
   allocate=lib.actql_native_owned_allocate;allocate.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];allocate.restype=ctypes.c_int
   retire=lib.actql_native_owned_retire;retire.argtypes=[ctypes.c_void_p,ctypes.c_void_p];retire.restype=ctypes.c_int
   value=ctypes.c_void_p()
   with borrow._scope():
    assert allocate(pointer,page,1,ctypes.byref(value))==0 and value.value
    try:borrow.close()
    except _OriginalDomainBorrowError as e:assert not e.unknown and e.code==-3
    else:raise AssertionError('Active scope retired')
   result['cases'].append('original provider allocation and active-scope cleanup refusal')
   try:borrow.close()
   except _OriginalDomainBorrowError as e:assert not e.unknown and e.code==-3
   else:raise AssertionError('Live allocation retired')
   assert retire(pointer,value)==0;borrow.close();before=borrow._closed;borrow.close();assert before and borrow._closed
   result['cases'].append('same record retires after original allocation with idempotent close')
   assert not child_fd.close_attempted;child_fd.close();result['FD_closed']=True;result['cases'].append('independent child FD close')
   os.write(ready[1],b'D');os.close(ready[1]);os.close(resume[0])
   Path(p['build'],'child-actual.json').write_text(json.dumps(result,indent=2)+'\n');os._exit(0)
  except BaseException as error:
   result['failure']=repr(error);result['borrow_closed']=borrow._closed if borrow is not None else False
   Path(p['build'],'child-actual.json').write_text(json.dumps(result,indent=2)+'\n');os._exit(1)
 os.close(ready[1]);os.close(resume[0]);assert os.read(ready[0],1)==b'R'
 try:
  with d._physical_scope():raise AssertionError('Parent used borrowed allocator')
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==6
 os.write(resume[1],b'C');assert os.read(ready[0],1)==b'D';observed,status=os.waitpid(child,0)
 assert observed==child and os.WIFEXITED(status) and os.WEXITSTATUS(status)==0
 child_result=json.loads(Path(p['build'],'child-actual.json').read_text());assert child_result['actor_pid']==child and len(child_result['cases'])==4 and child_result['FD_closed'] and 'failure' not in child_result
 os.close(ready[0]);os.close(resume[1]);scope.return_after_stop();d.close_after_stop();h.close();fd.close()
 cases.append('actual different-process original FD borrow with parent exclusion and separate final cleanup')
 h,fd,scope=host();d=domain(h,fd,scope,16*page);d.transfer();material=d._project_original_material(material_functions)
 ready=os.pipe();resume=os.pipe();sys.stdout.flush();child=os.fork()
 if child==0:
  os.close(ready[0]);os.close(resume[1]);borrow=None;child_fd=_OriginalDescriptor(fd.value)
  result={'actor_pid':os.getpid(),'parent_pid':os.getppid(),'cases':[],'FD_closed':False}
  try:
   # Physical fixture only. No inherited managed Owner is called in the child,
   # and the selected DLL initializer runs once in the parent, not here.
   borrow=_OriginalDomainBorrow._map_original(_OriginalDomainBorrowFunctions(fixture),child_fd,material)
   borrow.require_physical_current()
   holding=_NativeHoldingLease._from_original_borrow(borrow);identity=object();holding._bind_core(identity);holding._transfer_to_core(identity)
   assert holding._capacity_bytes()==16*page
   try:_NativeHoldingLease._from_original_borrow(borrow)
   except ValueError:pass
   else:raise AssertionError('Second holding acquired same borrow')
   result['cases'].append('original holding takes same child record once')
   try:copy.copy(borrow)
   except TypeError:pass
   else:raise AssertionError('Copied original record')
   os.write(ready[1],b'R');assert os.read(resume[0],1)==b'C'
   pointer=ctypes.c_void_p();assert borrow_functions.pointer(borrow._pointer,ctypes.byref(pointer))==0 and pointer.value
   allocate=lib.actql_native_owned_allocate;allocate.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)];allocate.restype=ctypes.c_int
   retire=lib.actql_native_owned_retire;retire.argtypes=[ctypes.c_void_p,ctypes.c_void_p];retire.restype=ctypes.c_int
   value=ctypes.c_void_p()
   with holding._scope():
    assert allocate(pointer,page,1,ctypes.byref(value))==0 and value.value
    holding._require_live_span(value,page)
   # The dependent component uses the very same TLS scope and original lease.
   capture=fixture.actql_native_owned_capture_image_fd
   capture.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_size_t,ctypes.c_size_t,ctypes.POINTER(ctypes.c_ubyte),ctypes.POINTER(ctypes.c_void_p)];capture.restype=ctypes.c_int
   image=Path(directory,'original-image');image.write_bytes(b'hello');image_fd=os.open(image,os.O_RDONLY)
   try:
    expected=(ctypes.c_ubyte*32).from_buffer_copy(bytes.fromhex('2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'))
    accepted=ctypes.c_void_p()
    with holding._scope():
     assert capture(pointer,image_fd,5,5,expected,ctypes.byref(accepted))==0 and accepted.value
     assert ctypes.string_at(accepted,5)==b'hello'
     assert os.lseek(image_fd,0,os.SEEK_CUR)==0
     assert retire(pointer,accepted)==0
    result['cases'].append('same provider captures known image digest under original borrowed scope')
    rejected=ctypes.c_void_p();wrong=(ctypes.c_ubyte*32)()
    with holding._scope():
     assert capture(pointer,image_fd,5,5,wrong,ctypes.byref(rejected))==-5 and rejected.value
     assert retire(pointer,rejected)==0
    result['cases'].append('wrong digest retains original cleanup pointer without accepting image')
   finally:os.close(image_fd)
   with holding._scope():
    try:holding.close()
    except NativeHoldingRetirementError as e:assert e.code==-3
    else:raise AssertionError('Active scope retired')
   result['cases'].append('original provider allocation and active-scope cleanup refusal')
   try:holding.close()
   except NativeHoldingRetirementError as e:assert e.code==-3
   else:raise AssertionError('Live allocation retired')
   try:
    with holding._scope():raise AssertionError('Closing holding reopened execution')
   except ValueError as error:assert str(error)=='Original child domain borrow is closing'
   result['cases'].append('closing child holding refuses new scope while retaining cleanup')
   assert retire(pointer,value)==0
   holding.close();before=borrow._closed;holding.close();assert before and borrow._closed and holding._pointer.value is None
   result['cases'].append('same holding clears slot after original allocation with idempotent close')
   assert not child_fd.close_attempted;child_fd.close();result['FD_closed']=True;result['cases'].append('independent child FD close')
   os.write(ready[1],b'D');os.close(ready[1]);os.close(resume[0])
   Path(p['build'],'holding-child-actual.json').write_text(json.dumps(result,indent=2)+'\n');os._exit(0)
  except BaseException as error:
   result['failure']=repr(error);result['borrow_closed']=borrow._closed if borrow is not None else False
   Path(p['build'],'holding-child-actual.json').write_text(json.dumps(result,indent=2)+'\n');os._exit(1)
 os.close(ready[1]);os.close(resume[0]);assert os.read(ready[0],1)==b'R'
 try:
  with d._physical_scope():raise AssertionError('Parent used borrowed allocator')
 except _OriginalDomainError as e:assert not e.unknown and e.fact.issue_family==6
 os.write(resume[1],b'C');assert os.read(ready[0],1)==b'D';observed,status=os.waitpid(child,0)
 assert observed==child and os.WIFEXITED(status) and os.WEXITSTATUS(status)==0
 child_result=json.loads(Path(p['build'],'holding-child-actual.json').read_text());assert child_result['actor_pid']==child and len(child_result['cases'])==7 and child_result['FD_closed'] and 'failure' not in child_result
 os.close(ready[0]);os.close(resume[1]);scope.return_after_stop();d.close_after_stop();h.close();fd.close()
 cases.append('actual existing holding uses same child domain and preserves original cleanup order')
 cases.extend(child_result['cases'][1:3])
 cases.append(child_result['cases'][4])
assert len(cases)==13 and all(d._closed for d in domains) and all(h._closed for h in owners) and all(fd.closed for fd in fds)
print(json.dumps({'discovered':13,'executed':13,'passed':13,'failed':0,'cases':cases,'initializer_calls':1,'scope':'mixed-source-private-domain-DLL','Engine':0,'VM':0,'worker':0,'wheel':0,'public_e2e':0}),flush=True)
