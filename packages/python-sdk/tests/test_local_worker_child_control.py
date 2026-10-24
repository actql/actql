"""Original Core/Native/pipe counters only; actual Wasmtime/VM/worker = 0."""
import copy
from contextlib import ExitStack
from ctypes import c_void_p
from dataclasses import replace
import os
import pickle
import select
import stat
from threading import Thread
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore, LocalCoreError, LocalCoreInitializationError
from actql_sdk._local_native_holding import _NativeHoldingLease
from actql_sdk._local_worker_slot import _OriginalDescriptor
from actql_sdk._local_worker_child_control import _OriginalChildControlPipe, _OriginalChildControlPending
import actql_sdk._local_worker_control_frames as frames
from test_local_native_control_custody import Function
from test_local_native_domain_borrow import BorrowFixture
import test_local_installed_image as image_fixture


class ChildControlFixture:
    def __init__(self, test, physical=None):
        self.physical = physical
        self.real_read, self.real_write = os.read, os.write
        real_stat = os.fstat
        self.patches = ExitStack(); test.addCleanup(self.patches.close)
        self.native = BorrowFixture(); self.native.descriptor.value = 4
        values = list(self.native.material.scalars)
        values[3] = 16777216 + 16384; values[5] = 16777216 + 8192
        values[7] = values[14] = 16777216 + 8192
        self.native.material = replace(self.native.material, scalars=tuple(values))
        def capacity(pointer, out): out._obj.value = 16777216 + 4096; return 0
        self.native.functions.capacity = Function(capacity)
        self.borrow = self.native.take()
        self.holding = _NativeHoldingLease._from_original_borrow(self.borrow)
        self.read, self.write = _OriginalDescriptor(0), _OriginalDescriptor(1)
        self.status = (lambda fd:real_stat(physical[fd])) if physical is not None else (
            lambda fd: SimpleNamespace(st_mode=stat.S_IFIFO | 0o600,
                st_uid=os.geteuid(), st_dev=2, st_ino=fd + 100))
        self.patches.enter_context(patch('actql_sdk._local_worker_child_control.os.fstat', side_effect=lambda fd:self.status(fd)))
        self.patches.enter_context(patch('actql_sdk._local_worker_child_control.os.get_blocking', return_value=True))
        self.patches.enter_context(patch('actql_sdk._local_worker_child_control.fcntl.fcntl', side_effect=lambda fd,op:os.O_RDONLY if fd==0 else os.O_WRONLY))
        self.control = _OriginalChildControlPipe._capture(self.borrow, self.read, self.write)
        self.requests, self.pending, self.sent = [], bytearray(), bytearray()
        self.result = {}; self.reply_hook = None; self.write_hook = None; self.read_hook = None
        self.reply_transform = lambda data:data
        self.patches.enter_context(patch('actql_sdk._local_worker_child_control.os.write', side_effect=self.write_bytes))
        self.patches.enter_context(patch('actql_sdk._local_worker_child_control.os.read', side_effect=self.read_bytes))
        self.case = image_fixture.InstalledImageTests(); self.case.setUp()
        self.callbacks = {}; self.calls = []

    def write_bytes(self, fd, data):
        if self.physical is not None:return self.real_write(self.physical[fd],data)
        if self.write_hook: return self.write_hook(fd, data)
        assert fd == 1
        self.sent.extend(data)
        magic, operation, serial, nonce = frames._HEADER.unpack(self.sent[:frames._HEADER.size])
        assert magic == b'ALC1' and len(self.sent) == frames._HEADER.size + frames._SIZES[operation]
        payload = bytes(self.sent[frames._HEADER.size:]); self.sent.clear()
        self.requests.append((operation, serial, nonce, payload))
        result = self.result.get(operation, 0)
        if operation == frames._LIMIT:
            result = (10, 8, 8, 12582912, 0, 16777216 + 4096)[frames._ORDINAL.unpack(payload)[0]]
        if operation == frames._CAPACITY:
            result = (16777216, 4096)[frames._ORDINAL.unpack(payload)[0]]
        reply = frames._RESPONSE.pack(b'ALC1', operation, serial, nonce, result)
        self.pending.extend(self.reply_transform(reply))
        if self.reply_hook: self.reply_hook()
        return len(data)

    def read_bytes(self, fd, maximum):
        if self.physical is not None:return self.real_read(self.physical[fd],maximum)
        if self.read_hook: return self.read_hook(fd, maximum)
        assert fd == 0
        result = bytes(self.pending[:maximum]); del self.pending[:maximum]
        return result

    def construct(self, *, open_status=0, exercise_imports=False, fail_close=0):
        c = self.case
        linker = image_fixture.Handle('linker', c.events)
        linker.define_func = lambda namespace,name,signature,callback,**kwargs:self.callbacks.__setitem__(name,(callback,kwargs))
        c.wasmtime.Linker = lambda engine:linker
        c.wasmtime.ValType = SimpleNamespace(i32=lambda:'i32',i64=lambda:'i64')
        c.wasmtime.FuncType = lambda *args:args
        c.ffi.dll = self.holding._library
        c.store._context = lambda:c_void_p(345)
        c.wasmtime.Caller = type('Caller',(),{})
        memory_type = SimpleNamespace(is_64=False,is_shared=False,limits=SimpleNamespace(min=1,max=256),close=lambda:None)
        class Memory:
            def type(self,store):return memory_type
            def data_ptr(self,store):return c_void_p(234)
        c.wasmtime.Memory = Memory; self.memory = Memory()
        self.caller = c.wasmtime.Caller()
        self.caller._context = lambda:c_void_p(345)
        self.caller.get = lambda name:self.memory if name=='memory' else None
        def opened(store,*args):
            self.calls.append(('open_live',args))
            if exercise_imports:
                nonce = args[0]
                assert self.callbacks['execution_child_admit'][0](self.caller,nonce)==0
                assert self.callbacks['execution_child_current'][0](self.caller,nonce)==0
                for i in range(6):self.callbacks['execution_child_limit'][0](self.caller,nonce,i)
                for i in range(2):self.callbacks['execution_child_capacity'][0](self.caller,nonce,i)
            return open_status
        def closed(store,*args):self.calls.append(('close',args));return 0
        linker.instantiate = lambda store,module:SimpleNamespace(exports=lambda store:{
            'memory':self.memory,'actql_host_abi_version':lambda store:image_fixture.LOCAL_CORE_ABI,
            'actql_buffer_open':lambda *args:(_ for _ in ()).throw(AssertionError('No scalar fallback')),
            'actql_buffer_open_live':opened,'actql_buffer_close_pool':closed})
        c.store.failures = fail_close
        with patch('actql_sdk._local_core.import_module',side_effect=c.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'), \
                patch('actql_sdk._local_core._validate_core_module'):
            self.core = LocalCore(None,digest='b'*64,transfer_capacity=65536,
                resources=replace(image_fixture.RESOURCES,execution_bytes=16777216+65536+4096),
                _compiled_image=c.image,_host_capacity_bytes=4096,
                _physical_holding=self.holding,_child_control=self.control)
        return self.core

    def callback(self, name, *args):
        return self.callbacks['execution_child_'+name][0](self.caller,self.core._nonce,*args)


class WorkerChildControlTests(unittest.TestCase):
    def test_core_binds_actual_observation_before_open_live_without_scalar_root(self):
        f = ChildControlFixture(self); core = f.construct(exercise_imports=True)
        self.assertEqual(f.calls,[('open_live',(core._nonce,65536,32,1048576))])
        self.assertEqual(f.requests[0][:3],(frames._BIND,1,core._nonce))
        span = frames._SPAN.unpack(f.requests[0][3])
        self.assertEqual(span[:2],(b'0'*40,b'r'*32))
        self.assertEqual(span[-2:],(4096,16777216))
        self.assertIs(core._physical_child_control,f.control)
        self.assertIs(f.control._core,core)
        self.assertIs(f.control._observation,core._physical_vm_observation)
        for name in ('admit','current','limit','capacity','report','stop'):
            callback, options = f.callbacks['execution_child_'+name]
            self.assertIs(callback.__self__,f.control);self.assertEqual(options,{'access_caller':True})
        self.assertEqual([args for op,serial,nonce,args in f.requests if op==frames._LIMIT],
                         [frames._ORDINAL.pack(i) for i in range(6)])
        self.assertTrue(core.close())

    def test_exact_signed_usage_and_native_int64_values_are_transported_without_accounting(self):
        f=ChildControlFixture(self);core=f.construct()
        usage=(1,2,3,2**53+1,0,0,0,0,0,16777216,4,5,6)
        self.assertEqual(f.callback('report',*usage),0)
        self.assertEqual(frames._USAGE.unpack(f.requests[-1][3]),usage)
        self.assertEqual(f.callback('limit',3),12582912)
        self.assertEqual(f.callback('capacity',0),16777216)
        self.assertFalse(f.control._retired)
        self.assertFalse(f.borrow._closed)

    def test_foreign_caller_store_memory_nonce_and_ordinal_never_send_bytes(self):
        f=ChildControlFixture(self);core=f.construct();before=list(f.requests)
        for nonce in (True,core._nonce+1):
            with self.assertRaises(ValueError):f.control.current(f.caller,nonce)
        for context in (None,c_void_p(346)):
            f.caller._context=lambda:context
            with self.assertRaises(ValueError):f.callback('current')
        f.caller._context=lambda:c_void_p(345)
        f.caller.get=lambda name:None
        with self.assertRaises(ValueError):f.callback('current')
        f.caller.get=lambda name:f.memory
        for name,ordinal in (('limit',True),('limit',6),('capacity',2)):
            with self.assertRaises(ValueError):f.callback(name,ordinal)
        self.assertEqual(f.requests,before)

    def test_unknown_reply_stays_same_control_and_returns_typed_unknown_without_resend(self):
        f=ChildControlFixture(self);core=f.construct();f.result[frames._ADMIT]=-41
        self.assertEqual(f.callback('admit'),-41)
        before=list(f.requests)
        self.assertEqual(f.callback('current'),-41)
        self.assertEqual(f.requests,before)
        self.assertEqual(frames._RESPONSE.unpack(f.control._response_bytes)[-1],-41)
        self.assertIs(core._physical_holding,f.holding)
        self.assertFalse(f.borrow._closed)

    def test_known_refusal_remains_negative_without_borrow_stop_or_fd_close(self):
        f=ChildControlFixture(self);core=f.construct();f.result[frames._ADMIT]=-42
        self.assertEqual(f.callback('admit'),-42)
        self.assertIsNone(f.control._unknown)
        self.assertFalse(f.borrow._closed)
        self.assertFalse(f.read.close_attempted or f.write.close_attempted)
        self.assertIs(core._physical_holding,f.holding)

    def test_invalid_header_or_response_status_retains_raw_and_never_retries(self):
        transforms=(lambda b:b'xxxx'+b[4:],
                    lambda b:frames._RESPONSE.pack(b'ALC1',frames._STOP,2,1,0),
                    lambda b:b[:-8]+(2).to_bytes(8,'big',signed=True))
        for transform in transforms:
            with self.subTest(transform=transform):
                f=ChildControlFixture(self);core=f.construct();f.reply_transform=transform
                self.assertEqual(f.callback('admit'),-41)
                before=list(f.requests);self.assertEqual(f.callback('current'),-41)
                self.assertEqual(f.requests,before);self.assertTrue(f.control._response_bytes)

    def test_partial_read_retains_original_bytes_and_eof_is_not_cleanup_or_stop(self):
        f=ChildControlFixture(self);core=f.construct();raw=[]
        def read(fd,maximum):
            if not raw:
                part=bytes(f.pending[:4]);del f.pending[:4];raw.append(part);return part
            return b''
        f.read_hook=read
        self.assertEqual(f.callback('current'),-41)
        self.assertEqual(f.control._response_bytes,raw[0])
        self.assertFalse(f.borrow._closed)
        self.assertFalse(f.control._retired)
        self.assertFalse(f.read.closed)

    def test_lost_write_retains_frame_and_forbids_a_second_physical_attempt(self):
        f=ChildControlFixture(self);core=f.construct();writes=[]
        def lost(fd,data):writes.append(data);raise OSError('lost physical write return')
        f.write_hook=lost
        self.assertEqual(f.callback('admit'),-41)
        self.assertEqual(f.callback('current'),-41)
        self.assertEqual(len(writes),1)
        self.assertEqual(writes[0],f.control._request_bytes)
        self.assertEqual(f.control._written,0)

    def test_fd_material_library_or_original_descriptor_mutation_is_not_permission(self):
        for target in ('read','write','backing','material','library'):
            with self.subTest(target=target):
                f=ChildControlFixture(self);core=f.construct();before=list(f.requests)
                if target=='read':f.read.value=9
                if target=='write':f.write.close_attempted=True
                if target=='backing':f.borrow._descriptor=_OriginalDescriptor(4)
                if target=='material':f.borrow._material=replace(f.borrow._material,source='1'*40)
                if target=='library':f.borrow._functions.library=object()
                self.assertEqual(f.callback('current'),-41)
                self.assertEqual(f.requests,before)
                self.assertIs(core._physical_holding,f.holding)

    def test_closing_allows_only_original_current_report_stop_without_fd_retirement(self):
        f=ChildControlFixture(self);core=f.construct();core._closing=True
        before=list(f.requests)
        self.assertEqual(f.callback('admit'),-42)
        self.assertEqual(f.callback('limit',0),-42)
        self.assertEqual(f.requests,before)
        f.result[frames._CURRENT]=1
        self.assertEqual(f.callback('current'),1)
        self.assertEqual(f.callback('report',*([0]*13)),0)
        self.assertEqual(f.callback('stop'),0)
        self.assertFalse(f.borrow._closed or f.read.closed or f.write.closed)

    def test_store_close_failure_keeps_same_control_and_root_until_original_retry(self):
        f=ChildControlFixture(self);core=f.construct(fail_close=1)
        with self.assertRaises(OSError):core.close()
        self.assertIs(f.control._core,core)
        self.assertIs(core._physical_child_control,f.control)
        self.assertIs(core._physical_holding,f.holding)
        self.assertFalse(f.control._retired or f.borrow._closed)
        self.assertTrue(core.close())
        self.assertTrue(f.control._retired)
        self.assertIsNone(core._physical_child_control)
        self.assertFalse(f.read.closed or f.write.closed)
        self.assertEqual([e for e in f.calls if e[0]=='close'],[('close',(core._nonce,))])

    def test_native_close_failure_keeps_same_control_after_store_then_retries_only_holding(self):
        f=ChildControlFixture(self);core=f.construct();f.native.close_code=-2
        with self.assertRaises(Exception):core.close()
        self.assertIsNone(core._store)
        self.assertIs(core._physical_child_control,f.control)
        self.assertIs(f.control._core,core)
        self.assertFalse(f.control._retired)
        f.native.close_code=0
        self.assertTrue(core.close())
        self.assertTrue(f.control._retired)
        self.assertEqual([e for e in f.case.events if e==('close','store')],[('close','store')])

    def test_bind_refusal_does_not_use_scalar_open_and_cannot_bind_another_core(self):
        f=ChildControlFixture(self);f.result[frames._BIND]=-42
        with self.assertRaises(RuntimeError):f.construct()
        self.assertEqual(f.calls,[])
        self.assertTrue(f.control._bound_attempted)
        self.assertTrue(f.control._retired)
        self.assertFalse(f.read.close_attempted or f.write.close_attempted)
        with self.assertRaises(ValueError):f.construct()
        self.assertEqual(len(f.requests),1)

    def test_open_live_refusal_does_not_fall_back_or_reserve_a_fresh_root(self):
        f=ChildControlFixture(self)
        with self.assertRaises(LocalCoreError) as caught:f.construct(open_status=-42)
        self.assertEqual(caught.exception.operation,'open_live')
        self.assertEqual([name for name,args in f.calls],['open_live'])
        self.assertTrue(f.control._retired)

    def test_copy_serialization_and_second_capture_never_create_original_control(self):
        f=ChildControlFixture(self)
        for copy_method in (copy.copy,copy.deepcopy,pickle.dumps):
            with self.assertRaises(TypeError):copy_method(f.control)
        with self.assertRaises(ValueError):_OriginalChildControlPipe._capture(f.borrow,f.read,f.write)
        self.assertIs(f.borrow._child_control_original,f.control)

    def test_real_pipes_carry_child_bind_current_report_stop_with_no_async_caller_transfer(self):
        # Real pipe bytes with descriptor-number redirects; native/Core/parent
        # facts remain independent doubles, no subprocess or real VM involved.
        from_child, child_out = os.pipe()
        child_in, to_child = os.pipe()
        real_read, real_write, real_close = os.read, os.write, os.close
        for fd in (from_child,child_out,child_in):self.addCleanup(real_close,fd)
        parent = {'requests':[], 'errors':[], 'closed':False}
        def finish_parent():
            if not parent['closed']:
                real_close(to_child);parent['closed']=True
        self.addCleanup(finish_parent)
        def exact(length):
            raw=b''
            while len(raw)<length:
                if not select.select([from_child],[],[],2)[0]:raise TimeoutError('bounded diagnostic peer')
                chunk=real_read(from_child,length-len(raw))
                if not chunk:raise EOFError('diagnostic peer')
                raw+=chunk
            return raw
        def respond():
            try:
                for expected in (frames._BIND,frames._CURRENT,frames._REPORT,frames._STOP):
                    header=exact(frames._HEADER.size)
                    magic,operation,serial,nonce=frames._HEADER.unpack(header)
                    assert magic==b'ALC1' and operation==expected
                    payload=exact(frames._SIZES[operation])
                    parent['requests'].append((operation,serial,nonce,payload))
                    reply=frames._RESPONSE.pack(b'ALC1',operation,serial,nonce,0)
                    assert real_write(to_child,reply)==len(reply)
            except BaseException as error:parent['errors'].append(error)
            finally:finish_parent()
        f=ChildControlFixture(self,{0:child_in,1:child_out})
        peer=Thread(target=respond);peer.start()
        core=f.construct()
        self.assertEqual(f.callback('current'),0)
        usage=(0,0,0,2**53+1,0,0,0,0,0,0,1,2,3)
        self.assertEqual(f.callback('report',*usage),0)
        self.assertEqual(f.callback('stop'),0)
        peer.join(3)
        self.assertFalse(peer.is_alive())
        self.assertEqual(parent['errors'],[])
        self.assertEqual([x[1] for x in parent['requests']],[1,2,3,4])
        self.assertEqual(frames._USAGE.unpack(parent['requests'][2][3]),usage)
        self.assertIs(f.control._core,core)
        self.assertFalse(f.read.closed or f.write.closed or f.borrow._closed)
        self.assertTrue(core.close())

    def test_reentrant_callback_cannot_send_second_request_or_return_outer_success(self):
        f=ChildControlFixture(self);core=f.construct();nested=[]
        f.reply_hook=lambda:nested.append(f.callback('current'))
        before=len(f.requests)
        self.assertEqual(f.callback('admit'),-41)
        self.assertEqual(nested,[-41])
        self.assertEqual(len(f.requests),before+1)
        self.assertTrue(f.control._request_bytes)
        self.assertIs(core._physical_holding,f.holding)

    def test_post_response_core_change_keeps_same_reply_without_success_or_resend(self):
        f=ChildControlFixture(self);core=f.construct()
        f.reply_hook=lambda:setattr(core,'_nonce',core._nonce+1)
        self.assertEqual(f.callback('admit'),-41)
        before=list(f.requests)
        self.assertTrue(f.control._written)
        self.assertEqual(f.requests,before)
        self.assertIs(core._physical_child_control,f.control)
        self.assertIsNotNone(f.control._unknown)

    def test_invalid_physical_write_progress_never_reaches_read_or_reissues_frame(self):
        for count in (True,0,-1,1000):
            with self.subTest(count=count):
                f=ChildControlFixture(self);core=f.construct();attempts=[]
                f.write_hook=lambda fd,data:attempts.append(data) or count
                f.read_hook=lambda *args:(_ for _ in ()).throw(AssertionError('no read'))
                self.assertEqual(f.callback('admit'),-41)
                self.assertEqual(f.callback('current'),-41)
                self.assertEqual(len(attempts),1)

    def test_foreign_thread_cannot_send_even_with_original_nonce_and_fd_numbers(self):
        f=ChildControlFixture(self);core=f.construct();before=list(f.requests);errors=[]
        def foreign():
            try:f.callback('current')
            except BaseException as error:errors.append(error)
        t=Thread(target=foreign);t.start();t.join()
        self.assertEqual(f.requests,before)
        self.assertEqual(len(errors),1)
        self.assertIsInstance(errors[0],ValueError)
        self.assertIsNone(f.control._unknown)


if __name__=='__main__':unittest.main()
