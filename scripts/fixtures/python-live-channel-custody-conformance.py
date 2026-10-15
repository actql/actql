"""Actual ctypes/C negative custody; funding/durable/spawn are diagnostic doubles.

This does not launch a child. Self PID is intentionally refused by the actual
Native provider; no VM, Host startup, Run, ordinary supplier or product E2E.
The dependent fixture DLL must resolve the same selected provider addresses.
"""
from pathlib import Path
import ctypes
import hashlib
import json
import os
import sys
import tempfile
import asyncio
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreResources
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainMaterialFunctions, _OriginalDomainError,
)
from actql_sdk._local_native_live_channel import (
    _OriginalLiveChannelCustody, _OriginalLiveChannelFunctions, _OriginalLiveChannelError,
)
from actql_sdk._local_native_vm import _OriginalVMSpanData
from actql_sdk._local_worker_funding import _WorkerFundingSupplier, OriginalWorkerFunding
from actql_sdk._local_worker_slot import _OriginalDescriptor, OriginalWorkerSlot
from actql_sdk._local_worker_process import OriginalWorkerProcess
from actql_sdk._local_worker_channel import OriginalWorkerPipeChannel, _InstalledWorkerControl

# Existing independent metadata fixture only; no installed product declaration.
import test_local_worker_funding as funding_fixture


class DiagnosticFunding(_WorkerFundingSupplier):
    """Same arena carrier, but NO complete pre-spawn/Store funding claim."""
    def __init__(self, domain):
        super().__init__()
        self.domain, self.durable, self.no_child = domain, object(), object()
        self.settlements = 0
    def acquire_pre_spawn(self, components): return self.domain
    def original_ledger(self, physical):
        assert physical is self.domain
        return self.domain._owner
    def reserve_execution_delegation(self, ledger, limits, retained, execution):
        assert ledger is self.domain._owner
        # Existing Native domain already retains its actual arena ticket. This
        # diagnostic neither reserves twice nor claims other domains are funded.
        return self.domain
    def preserve_original_delegation(self, physical, ledger, delegation): return self.durable
    def require_launch_originals(self, physical, ledger, delegation, durable):
        assert physical is delegation is self.domain and ledger is self.domain._owner and durable is self.durable
        assert self.domain.current().issue_family == 0
    def report_execution_delegation(self, ledger, delegation, usage): raise AssertionError('No generic report')
    def require_scoped_stop(self, physical, ledger, delegation, durable, observation):
        assert physical is delegation is self.domain and observation is self.no_child
        # The test replaces posix_spawn with self PID. No child was acquired;
        # this counter must never be advertised as an actual worker-stop proof.
    def settle_execution_delegation(self, ledger, delegation, final_usage):
        self.settlements += 1
        raise AssertionError('No diagnostic settlement')
    def close_original_funding(self, physical, ledger, delegation, durable):
        raise AssertionError('No complete production funding supplier')


class NeverStartedControl(_InstalledWorkerControl):
    def prepare_original_bootstrap(self, process): raise AssertionError('No startup')
    async def start_original_host(self, process, pipe, bootstrap): raise AssertionError('No startup')
    def require_current_original(self, process): raise AssertionError('No Host')
    async def exchange_original_wire(self, process, pipe, operation, payload): raise AssertionError('No Wire')
    async def close_original_host(self, process, pipe, bootstrap):
        assert bootstrap is None
        # No child or Host was started in this diagnostic, rather than inferring
        # successful Store cleanup from a child exit or empty pipe.
        return None


parameters = json.loads(Path(sys.argv[1]).read_text())
root = Path(parameters['root'])
lib = ctypes.CDLL(parameters['library'])
helper = ctypes.CDLL(parameters['helper'])
for name in ('actql_native_owned_current', 'actql_native_owned_allocate', 'actql_live_channel_prepare_into'):
    assert ctypes.cast(getattr(helper, name), ctypes.c_void_p).value == ctypes.cast(getattr(lib, name), ctypes.c_void_p).value
init = lib.actql_original_control_initialize
init.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]; init.restype = ctypes.c_int
assert init(1, (ctypes.c_char_p * 1)(b'original-channel-diagnostic')) == 0
prepare = helper.actql_fixture_worker_prepare_into
prepare.argtypes = [ctypes.POINTER(ctypes.c_void_p)]; prepare.restype = ctypes.c_int
control, backing = _OriginalControlFunctions(lib), _OriginalBackingFunctions(lib)
domain_functions, live = _OriginalDomainFunctions(lib), _OriginalLiveChannelFunctions(lib)
cases = ['actual dependent DLL resolves the same original provider addresses']
loaded = []
for name in ('_local_native_live_channel', '_local_native_domain_custody', '_local_worker_pipe'):
    path = Path(sys.modules['actql_sdk.' + name].__file__).resolve()
    assert path == (root / 'packages/python-sdk/src/actql_sdk' / (name + '.py')).resolve()
    loaded.append({'path': str(path), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})

with tempfile.TemporaryDirectory(prefix='actql-live-channel-') as directory:
    reply = ctypes.c_void_p(); assert prepare(ctypes.byref(reply)) == 0
    owner = _OriginalControlCustody._take_original_reply(control, reply)
    fd = _OriginalDescriptor(os.open(str(Path(directory, 'backing')), os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600))
    page = os.sysconf('SC_PAGESIZE'); os.ftruncate(fd.value, 64 * page)
    assert owner.acquire_fd(fd).issue_family == 0
    scope = _OriginalBackingCustody._borrow_original(owner, backing)
    with scope._physical_scope():
        domain = _OriginalDomainCustody._prepare_original(owner, scope, fd, domain_functions,
            size=24 * page, work=2, attempts=1, holdings=1, transfer=3, retained=0, execution=24 * page)
    domain.transfer()
    metadata = domain._project_original_material(_OriginalDomainMaterialFunctions(lib))
    funding_case = funding_fixture.WorkerFundingTests(); funding_case.setUp()
    try:
        components = funding_case.components
        supplier = DiagnosticFunding(domain)
        # Existing independent interface fixture, not the Native domain's
        # numerical allowance. Complete production funding is not supplied and
        # no real child is spawned. Native 64/24-page limits remain unchanged.
        funding = OriginalWorkerFunding(components, supplier,
            limits=funding_case.limits, retained=5, execution=6)
        slot = OriginalWorkerSlot(funding, Path(directory, 'slot'))
        slot.open(); assert slot.try_acquire()
        process = OriginalWorkerProcess(funding, slot, executable=Path(sys.executable).absolute(),
            executable_image=Path(sys.executable).absolute(), executable_link=None,
            executable_bytes=1, executable_sha256='a' * 64, environment=(('LANG', 'C.UTF-8'),))
        channel = OriginalWorkerPipeChannel(funding, process, NeverStartedControl())
        # Actual owned pipes and descriptor closes. Only executable verification
        # and the spawn syscall are replaced; no interpreter or child is run.
        with patch.object(OriginalWorkerProcess, '_verify_executable'), \
                patch('actql_sdk._local_worker_process.os.posix_spawn', return_value=os.getpid()) as spawn:
            process.spawn()
            assert spawn.call_count == 1
        try:
            _OriginalLiveChannelCustody._capture_original(domain, process, channel._pipe, live, nonce=7)
        except _OriginalLiveChannelError as failure:
            original = failure.cleanup_channel
            assert not failure.unknown and failure.fact.issue_family == 6
        else: raise AssertionError('Self PID became an original child')
        assert original._channel.value is not None and domain._live_channel_original is original
        cases.append('actual C rejects self PID and Python retains the same pending native channel')

        for operation in (original.state, original.limits):
            try: operation()
            except _OriginalLiveChannelError as failure:
                assert not failure.unknown and failure.fact.issue_family == 1
            else: raise AssertionError('Pending capture projected admission state')
        cases.append('actual pending state and limits remain typed refusal rather than zero facts')

        span = _OriginalVMSpanData(metadata.source, metadata.recipe, metadata.scalars, 7, 0, 16777216)
        try: original.bind_original_vm(span)
        except _OriginalLiveChannelError as failure:
            assert not failure.unknown and failure.fact.issue_family == 6
        else: raise AssertionError('No child/VM binding became available')
        try: original.bind_original_vm(span)
        except ValueError: pass
        else: raise AssertionError('Original failed binding repeated')
        cases.append('actual bind callback refuses absent VM and the same Python carrier never reissues it')

        for operation in (original.admit, lambda: original.report((0, 0, 0, 2**53 + 1, 0, 0, 0, 0, 0, 0)), original.stop):
            try: operation()
            except _OriginalLiveChannelError as failure:
                assert not failure.unknown and failure.fact.issue_family == 1
            else: raise AssertionError('Pending capture gained an imported child operation')
        cases.append('actual admission cumulative Int64 report and logical stop refuse without a live child')

        try: domain.close_after_stop()
        except _OriginalDomainError as failure:
            assert not failure.unknown and failure.fact.issue_family == 8
        else: raise AssertionError('Pending metadata lost domain responsibility')
        asyncio.run(channel.close_original())
        assert process._parent_closed and all(x.closed for x in process._descriptors)
        original.retire_after_owner_ack(channel, supplier.no_child)
        assert original._closed and all(x.value is None for x in
            (original._host, original._native_domain, original._channel, original._reply))
        assert supplier.settlements == 0 and not domain._closed and not owner._closed
        cases.append('same partial metadata retires after diagnostic no-child Host and actual parent FD cleanup')

        try: domain.close_after_stop()
        except _OriginalDomainError as failure:
            assert not failure.unknown and failure.fact.issue_family == 5
        else: raise AssertionError('Original backing borrow was silently returned')
        scope.return_after_stop(); domain.close_after_stop(); owner.close()
        assert owner._closed and domain._closed and scope._closed
        os.fstat(fd.value); fd.close()
        cases.append('actual original loan domain Host and caller FD retire independently in order')
    finally:
        funding_case.doCleanups()

assert len(cases) == len(set(cases)) == 7
result = {'success': True, 'discovered': 7, 'executed': 7, 'passed': 7, 'failed': 0,
          'cases': cases, 'loaded_modules': loaded, 'actual_ctypes_C': True,
          'actual_pipe_FDs': True, 'funding_durable_spawn_doubles': True,
          'actual_spawn': 0, 'actualVM': 0, 'wheel': 0, 'publicE2E': 0}
print(json.dumps(result), flush=True)
