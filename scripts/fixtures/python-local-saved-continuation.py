"""One installed Saved Result with separate Core and File suspension controls."""
from __future__ import annotations

import asyncio
from collections.abc import Mapping
from contextlib import contextmanager
import errno
from hashlib import sha256
import json
import os
import re
import secrets
import stat
import sys
from pathlib import Path
from types import CodeType
from unittest.mock import patch

import httpx
from actql import AsyncClient
from actql_sdk import ClientError
from actql_sdk._local_core import LocalCore
from actql_sdk._local_files import LocalFileError, LocalFileRoot
from actql_sdk._local_host_binding import OriginalHostBinding
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_sdk_response import OriginalLocalSDKResponseStream
from actql_sdk._local_submission import LocalSubmissionAuthority


CONTINUATION_VALUE_BYTES = 16512
STREAM_PAYLOAD_BYTES = (1024, 16384, 262144)


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(child) for key, child in value.items()}
    if isinstance(value, (tuple, list)):
        return [plain(child) for child in value]
    return value


class PhysicalQueries:
    """Count calls to the installed Core's actual journal scan and point ports."""

    def __init__(self, host):
        binding = host._installation.binding
        self.original = host._core._journal_callbacks(binding._current.ticket)
        assert type(self.original) is _JournalCallbacks
        self.previous = sys.getprofile()
        self.query = _JournalCallbacks.query.__code__
        self.scans = self.points = self.cancel_scans = self.cancel_rows = 0
        self.cancel_scan_body_bytes = 0
        self.saved_run_points = 0
        self.saved_run_keys = set()
        self.scan_namespaces = {}

    def profile(self, frame, event, status):
        if event != 'return' or frame.f_code is not self.query or status not in (0, 1):
            return
        arguments = frame.f_locals
        if arguments.get('self') is self.original:
            mode = self.original.mode
            self.scans += mode == 0
            if mode == 0:
                namespace = arguments['namespace']
                self.scan_namespaces[namespace] = self.scan_namespaces.get(namespace, 0) + 1
            self.points += mode == 1
            if mode == 1 and status == 0 and arguments.get('namespace') == 'client_sqlite_saved_run_current':
                row = self.original.row
                assert row is not None and row[0] == arguments['key'].encode('utf-8') and len(row[1].payload) == 4
                self.saved_run_points += 1
                self.saved_run_keys.add(row[0])
            if mode == 0 and arguments.get('namespace') in (
                    'client_cancel_custody', 'client_cancellations', 'client_cancel_originals'):
                self.cancel_scans += 1
                if status == 0 and arguments['namespace'] == 'client_cancellations':
                    self.cancel_rows += 1
                    # One candidate for the census decoder and witness hash.
                    # Count its actual body length without retaining row data.
                    self.cancel_scan_body_bytes += len(self.original.row[1].payload)

    def __enter__(self):
        assert self.previous is None
        sys.setprofile(self.profile)
        return self

    def __exit__(self, _type, _value, _traceback):
        sys.setprofile(self.previous)


async def observe_read(host, result, stop_phase=None, *, totals=None, stop_receipt=None, selected_payload=None):
    reader = result.rows()

    async def consume():
        async with reader:
            return [row async for row in reader]

    core, store = host._core, host._core._store
    scope = carrier = source = None
    stopped_advance = None
    beats = []
    core_turns = 0
    async with asyncio.TaskGroup() as tasks:
        reading = tasks.create_task(consume())
        with PhysicalQueries(host) as queries:
            while not reading.done():
                await asyncio.sleep(0)
                preparing = [value for value in host._saved_result_reads if value._preparing]
                assert len(preparing) <= 1
                if not preparing or preparing[0]._source is None:
                    continue
                current, = preparing
                assert core._host_fuel_phase == 'operation' and core._host_operation_scope is not None
                assert core._store is store and not core._invoking and not core._lock._is_owned()
                installation = host._installation
                assert not installation._store._connection.in_transaction
                assert installation.binding._observed_reader is None
                if scope is None:
                    scope, carrier, source = core._host_operation_scope, current, current._source
                assert current is carrier and core._host_operation_scope is scope
                assert current._source is source and reader.rows_yielded == 0
                physical = current._reader
                phase = 'core' if physical is None else 'hash'
                if physical is not None:
                    assert physical.chunk is None and physical.offset > 0
                beat = {'phase': phase, 'offset': 0 if physical is None else physical.offset,
                        'fuel_remaining': store.get_fuel(), 'scan_calls': queries.scans,
                        'point_calls': queries.points, 'cancel_scan_calls': queries.cancel_scans,
                        'saved_run_points': queries.saved_run_points}
                if totals is not None:
                    beat['cancel_rows'] = queries.cancel_rows
                    beat['cancel_scan_body_bytes'] = queries.cancel_scan_body_bytes
                if physical is not None and physical.eof:
                    beat['physical_sha256'] = physical.hash.hexdigest()
                    if selected_payload is not None:
                        assert physical.identity is not None and physical.expected is not None
                        selected_payload.update(name=physical.name, device=str(physical.identity.device),
                                                inode=str(physical.identity.inode), bytes=physical.offset,
                                                sha256=beat['physical_sha256'])
                        assert physical.expected.physical_digest == 'sha256:' + selected_payload['sha256']
                if not beats or beats[-1] != beat:
                    if beats:
                        assert beat['fuel_remaining'] <= beats[-1]['fuel_remaining']
                    if phase == 'core':
                        core_turns += 1
                    if len(beats) < 32 or phase == 'hash':
                        beats.append(beat)
                    else:
                        beats[-1] = beat
                if phase == stop_phase:
                    if physical is not None:
                        assert not physical.eof
                    stopped_advance = reader._advance
                    assert stopped_advance is not None and not stopped_advance.done()
                    assert stopped_advance.cancelling() == 0
                    if stop_receipt is not None:
                        stop_receipt.update(cancellingBefore=stopped_advance.cancelling(),
                                            transferOffset=beat['offset'])
                    await reader.aclose()
                    assert reader._advance is stopped_advance and stopped_advance.done()
                    assert stopped_advance.cancelling() == 1
                    assert type(stopped_advance.exception()) is StopAsyncIteration
                    break
            if totals is not None:
                totals.update(scan_calls=queries.scans, point_calls=queries.points,
                              cancel_scan_calls=queries.cancel_scans, cancel_rows=queries.cancel_rows,
                              cancel_scan_body_bytes=queries.cancel_scan_body_bytes,
                              saved_run_points=queries.saved_run_points,
                              saved_run_keys=len(queries.saved_run_keys),
                              scan_namespaces=queries.scan_namespaces.copy())
    assert sys.getprofile() is None
    assert carrier is not None and scope is not None and beats[0]['phase'] == 'core'
    assert core._host_operation_scope is None
    assert carrier not in host._saved_result_reads
    receipt = plain(await reader.delivery_attempt())
    if stop_phase is not None:
        assert stopped_advance is not None
        assert reading.result() == [] and reader.rows_yielded == 0
        assert receipt == {'kind': 'not_found'}
        if stop_receipt is not None:
            stop_receipt.update(attemptId=reader.attempt_id, cancellingAfter=stopped_advance.cancelling(),
                                sameAdvance=reader._advance is stopped_advance,
                                advanceDone=stopped_advance.done(),
                                termination=type(stopped_advance.exception()).__name__,
                                rowsYielded=reader.rows_yielded, delivery=receipt['kind'],
                                scopeRetired=core._host_operation_scope is None,
                                carrierReleased=carrier not in host._saved_result_reads)
        return None, receipt, beats, core_turns, reader.attempt_id
    assert receipt['attempt']['attempt_id'] == reader.attempt_id
    return reading.result(), receipt, beats, core_turns, reader.attempt_id


def original_terminal_revision(creator):
    # Successful public RunState need not project control. This dedicated
    # fresh Store contains only the seed Run at this point. Borrow only its
    # storage revision through the current reader, never the row's contents.
    host = creator._local_host
    assert type(host) is InstalledLocalHost
    installation = host._active()
    binding, store = installation.binding, installation._store
    assert store is not None
    revisions = []

    def inspect(reader):
        rows = []

        def observe(row):
            assert row is not None
            key, original = row
            assert type(original.generation) is int and 0 <= original.generation < 2**31
            rows.append((key, original.generation))

        def end(row):
            assert row is None

        reader.scan_after('client_runs', '', observe)
        (key, revision), = rows
        reader.scan_after('client_runs', key, end)
        revisions.append(revision)

    # The scalar comes from the physical Store, outside any guest operation.
    # The subsequent public cancel still checks its own current and authority.
    with binding.fenced() as fences:
        store.inspect_namespaces(fences, inspect=inspect, current=binding._current_observer)
    revision, = revisions
    return revision


async def prepare_original(state_dir, report_wait_failure=None, *,
                           value_size=CONTINUATION_VALUE_BYTES, cancellation_records=None, query=None):
    assert not state_dir.exists()
    values = ['x' * value_size]
    expected = [{'s': value} for value in values]
    delivered_wire = b''.join(json.dumps(row, separators=(',', ':')).encode() + b'\n' for row in expected)
    if query is None:
        query = "SELECT '" + values[0] + "' AS s"
    async with await AsyncClient.open(state_dir=state_dir) as creator:
        if cancellation_records is not None:
            # History levels have the same number of Runs. Additional records
            # come from public AlreadyTerminal cancellations.
            assert cancellation_records in (0, 1, 10)
            control = await creator.start_source('SELECT 1 AS n', format='sql',
                                                 submission_ref=creator.new_submission())
            state = plain(await control.wait())
            assert state['status'] == 'succeeded'
            cancellations = []
            for _ in range(cancellation_records):
                revision = original_terminal_revision(creator)
                observed = plain(await control.cancel(expected_revision=revision))
                original = observed['cancellation']
                assert observed['kind'] == 'already_satisfied' and original['kind'] == 'already_terminal'
                assert original['ref'] == plain(control.ref)
                assert plain(await control.lookup_cancellation(original['cancelRef'])) == {
                    'kind': 'found', 'cancellation': original}
                assert plain(await control.status()) == state
                assert original['cancelRef'] not in cancellations
                cancellations.append(original['cancelRef'])
        submission = creator.new_submission()
        execution = await creator.start_source(query, format='sql', submission_ref=submission)
        try:
            assert (await execution.wait())['status'] == 'succeeded'
        except Exception as failure:
            if report_wait_failure is not None:
                try:
                    report_wait_failure(failure)
                except BaseException:
                    pass  # Optional evidence cannot replace the original failure.
            raise
        reference = plain(execution.ref)
    assert creator._local_host._core._closed
    return reference, expected, delivered_wire


class SavedStreamCalls:
    """Observe the installed ABI in one diagnostic thread without replacing a port."""

    def __init__(self, stream):
        self.reader = stream._reader
        self.core = stream._host._core
        self.host_import, = (code for code in LocalCore._observation_import.__code__.co_consts
                             if isinstance(code, CodeType) and code.co_name == 'invoke')
        self.export = LocalCore._call.__code__
        self.input_copy = LocalCore._input_copy.__code__
        self.output_block = LocalCore._read_output_block.__code__
        self.host_imports = {}
        self.scalar_exports = dict(fill=0, read_packed=0)
        self.input_blocks, self.output_blocks = [], []
        self.overflow = False
        self.task = None

    def add_block(self, blocks, start, length, returned):
        # No retained byte buffers. A repeated copy cannot grow the trace.
        if len(blocks) == 16:
            self.overflow = True
        else:
            blocks.append([start, length, returned])

    def owned_arguments(self, code, frame):
        if frame.f_code is not code:
            raise RuntimeError('Foreign CPython stream observation frame')
        args = frame.f_locals
        if args.get('self') is self.core and asyncio.current_task() is self.task:
            return args
        return None

    def enter(self, code, _offset):
        args = self.owned_arguments(code, sys._getframe(1))
        if args is None:
            return
        name = args['name']
        if code is self.host_import:
            self.host_imports[name] = self.host_imports.get(name, 0) + 1
        elif args['family'] == 'buffer' and name in self.scalar_exports:
            self.scalar_exports[name] += 1

    def leave(self, code, _offset, returned):
        args = self.owned_arguments(code, sys._getframe(1))
        if args is None:
            return
        value = self.reader._input
        if code is self.input_copy:
            if value is not None and args['ticket'] == value.ticket:
                self.add_block(self.input_blocks, args['start'], args['length'], returned)
        elif value is not None:
            # The receipt also reads an output from this Store. Only a
            # currently offered payload loan supplies a stream byte block.
            output = self.reader._storage._payload_outputs.get(self.reader._request.ticket)
            if output is not None and args['value'] is output:
                self.add_block(self.output_blocks, args['start'], args['length'],
                               len(returned) if type(returned) is bytes else None)

    @contextmanager
    def observe_advance(self):
        # Closed reconciliation checks gettrace/getprofile on entry and
        # before SQL. Observe just these code objects without either hook.
        assert sys.gettrace() is None and sys.getprofile() is None
        self.task = asyncio.current_task()
        assert self.task is not None
        monitoring = sys.monitoring  # The RC diagnostic interpreter is CPython 3.12.
        tool = monitoring.PROFILER_ID
        events = monitoring.events
        observed = ((self.host_import, events.PY_START), (self.export, events.PY_START),
                    (self.input_copy, events.PY_RETURN), (self.output_block, events.PY_RETURN))
        assert monitoring.get_tool(tool) is None
        monitoring.use_tool_id(tool, 'actql-original-saved-stream')
        try:
            monitoring.register_callback(tool, events.PY_START, self.enter)
            monitoring.register_callback(tool, events.PY_RETURN, self.leave)
            for code, event in observed:
                monitoring.set_local_events(tool, code, event)
            yield
        finally:
            for code, _ in observed:
                monitoring.set_local_events(tool, code, events.NO_EVENTS)
            monitoring.register_callback(tool, events.PY_START, None)
            monitoring.register_callback(tool, events.PY_RETURN, None)
            monitoring.free_tool_id(tool)
            self.task = None

    def take_blocks(self):
        blocks = dict(inputBlocks=self.input_blocks, outputBlocks=self.output_blocks)
        self.input_blocks, self.output_blocks = [], []
        return blocks


class ObserveSavedResponse(httpx.AsyncByteStream):
    """Forward original offers and the completion marker without confirming either."""

    def __init__(self, stream):
        assert type(stream) is OriginalLocalSDKResponseStream
        self.stream = stream
        self.chunk_bytes = stream._reader._root._max_chunk_bytes
        self.segments = []
        self.physical_hash, self.delivered_hash = sha256(), sha256()
        self.completion_markers = 0
        self.file = None
        self.calls = SavedStreamCalls(stream)

    async def __aiter__(self):
        iterator = aiter(self.stream)
        while True:
            with self.calls.observe_advance():
                try:
                    wire = await anext(iterator)
                except StopAsyncIteration:
                    break
            if wire == b'\x1e':
                self.completion_markers += 1
            else:
                reader = self.stream._reader
                source = reader._chunk
                assert source is not None and self.completion_markers == 0
                self.file = reader._reader
                assert self.file is not None and self.file.descriptor is not None
                self.segments.append(dict(physicalBytes=len(source.data), wireBytes=len(wire), eof=source.eof,
                                          **self.calls.take_blocks()))
                self.physical_hash.update(source.data)
                self.delivered_hash.update(wire)
            yield wire
        assert not self.calls.input_blocks and not self.calls.output_blocks

    async def aclose(self):
        await self.stream.aclose()


async def observe_public_stream(destination, identity):
    destination.mkdir(mode=0o700)
    print(json.dumps(dict(**identity, phase='installed', scope='public-saved-jsonl-stream', operation='warm-result',
                          sizes=STREAM_PAYLOAD_BYTES)), flush=True)
    for size in STREAM_PAYLOAD_BYTES:
        value_size = size - len(b'{"s":""}\n')
        query = f"SELECT REPEAT('x', {value_size}) AS s"
        state_dir = destination / str(size)
        print(json.dumps(dict(phase='seed', bytes=size, query=query)), flush=True)
        reference, expected, wire = await prepare_original(state_dir, value_size=value_size, query=query)
        assert len(wire) == size
        print(json.dumps(dict(phase='saved', bytes=size, originalRun=reference)), flush=True)
        async with await AsyncClient.open(state_dir=state_dir) as client:
            host = client._local_host
            assert type(host) is InstalledLocalHost and host._core._ordinary_host and sys.getprofile() is None
            run = await client.attach(reference)
            assert plain(run.ref) == reference
            original_open = client._open
            captured = []

            async def observe(operation, body):
                response = await original_open(operation, body)
                assert operation == 'read' and not captured
                wrapped = ObserveSavedResponse(response.stream)
                captured.append(wrapped)
                response.stream = wrapped
                return response

            with patch.object(client, '_open', observe):
                async with run.result('answer').rows() as reader:
                    assert [row async for row in reader] == expected
            wrapped, = captured
            assert wrapped.completion_markers == 1 and wrapped.stream._closed
            assert wrapped.file is not None and wrapped.file.descriptor is None
            assert wrapped.stream not in host._response_streams and not host._saved_result_reads
            delivery = plain(await reader.delivery_attempt())
            assert delivery['kind'] == 'found' and delivery['record']['state'] == 'succeeded'
            proof = delivery['hostReleaseReceipt']
            assert delivery['attempt']['attempt_id'] == reader.attempt_id
            assert proof['run_definition_cid'] == reference['runDefinitionCid']
            assert proof['delivered_byte_count'] == size
            assert proof['delivered_sha256'] == wrapped.delivered_hash.hexdigest() == sha256(wire).hexdigest()
        assert host._core._closed and host._installation is None
        physical = json.dumps(expected, separators=(',', ':')).encode()
        assert sha256(physical).hexdigest() == wrapped.physical_hash.hexdigest()
        print(json.dumps(dict(phase='closed', bytes=size, originalRun=reference, attemptId=reader.attempt_id,
                              rows=reader.rows_yielded, physicalBytes=len(physical), physicalSha256=wrapped.physical_hash.hexdigest(),
                              chunkBytes=wrapped.chunk_bytes, segments=wrapped.segments, completionMarkers=wrapped.completion_markers,
                              hostImports=wrapped.calls.host_imports, scalarBufferExports=wrapped.calls.scalar_exports,
                              transportObserver='cpython-local-code-monitor', transportOverflow=wrapped.calls.overflow,
                              deliveredSha256=proof['delivered_sha256'], delivery=delivery, firstClose=True)), flush=True)


class EndAfterFirstOffer(httpx.AsyncByteStream):
    """Cut this response at the sink without acknowledging its original offer."""

    def __init__(self, stream):
        assert type(stream) is OriginalLocalSDKResponseStream
        self.stream, self.saved = stream, stream._saved_read
        self.offer = self.file = None

    async def __aiter__(self):
        prefix = await anext(aiter(self.stream))
        reader = self.stream._reader
        chunk, output = reader._chunk, reader._output
        assert chunk is not None and chunk.eof is False and output is not None
        assert reader._confirmed is None and self.saved in self.stream._host._saved_result_reads
        assert self.stream._host._core._host_operation_scope is None
        self.file = reader._reader
        assert self.file.descriptor is not None
        self.offer = dict(sourceBytes=len(chunk.data), sourceEof=chunk.eof, prefixBytes=len(prefix),
                          output=output.ticket)
        yield prefix

    async def aclose(self):
        await self.stream.aclose()


async def observe_truncation(client, result):
    opened = []
    original_open = client._open

    async def end_after_offer(operation, body):
        assert operation == 'read' and not opened
        response = await original_open(operation, body)
        cut = EndAfterFirstOffer(response.stream)
        opened.append(cut)
        response.stream = cut
        return response

    reader = result.rows()
    with patch.object(client, '_open', end_after_offer):
        async with reader:
            try:
                async for _ in reader:
                    raise AssertionError('An incomplete row was published')
            except ClientError as failure:
                assert failure.code == 'IncompleteResultStream' and failure.attempt_id == reader.attempt_id
                assert failure.rows_yielded == 0 and getattr(failure, 'cleanup_error', None) is None
                refusal = dict(code=failure.code, attemptId=failure.attempt_id, rows=failure.rows_yielded)
            else:
                raise AssertionError('Transport truncation became a successful read')
    cut, = opened
    stream = cut.stream
    payload = stream._reader
    assert cut.offer is not None and cut.file is not None
    closed = dict(response=stream._closed, file=payload._reader is None and cut.file.descriptor is None
                  and id(cut.file) not in payload._root._original_readers,
                  chunk=payload._chunk is None and cut.file.chunk is None,
                  input=payload._input is None, output=payload._output is None, clock=stream._clock is None,
                  stream=stream not in stream._host._response_streams,
                  saved=cut.saved not in stream._host._saved_result_reads)
    assert all(closed.values())
    delivery = plain(await reader.delivery_attempt())
    assert delivery['kind'] == 'found' and delivery['attempt']['attempt_id'] == reader.attempt_id
    assert delivery['record']['state'] == 'streaming' and delivery['record']['sequence'] == 0
    assert delivery['record']['confirmed_byte_count'] == 0 and delivery['hostReleaseReceipt'] is None
    return reader, dict(refusal=refusal, offer=cut.offer, closed=closed, delivery=delivery)


def installation_snapshot(state):
    records = {}
    for path in sorted(state.rglob('*')):
        info = path.lstat()
        entry = dict(device=str(info.st_dev), inode=str(info.st_ino), mode=stat.S_IMODE(info.st_mode))
        if stat.S_ISREG(info.st_mode):
            entry.update(bytes=info.st_size, sha256=sha256(path.read_bytes()).hexdigest())
        else:
            assert stat.S_ISDIR(info.st_mode)
        records[path.relative_to(state).as_posix()] = entry
    return records


async def observe_missing_configuration(state, reference, expected):
    original_name = 'source/account.json'
    account, held = state / original_name, state.parent / 'held-account.json'
    before = installation_snapshot(state)
    assert not held.exists()
    account.rename(held)
    ports = {LocalCore.reserve_sdk_bootstrap.__code__: 'bootstrapReservation',
             LocalCore.produce_sdk_bootstrap.__code__: 'bootstrapProduction',
             OriginalHostBinding.__init__.__code__: 'hostBinding',
             LocalSubmissionAuthority.__init__.__code__: 'submissionAuthority',
             LocalSubmissionAuthority.issue_epoch.__code__: 'issueEpoch',
             LocalCore.produce_publication_sdk_read_grant.__code__: 'readGrant',
             secrets.token_hex.__code__: 'keyGeneration'}
    calls = dict.fromkeys(ports.values(), 0)

    def profile(frame, event, _value):
        if event == 'call' and frame.f_code in ports:
            calls[ports[frame.f_code]] += 1

    try:
        missing = installation_snapshot(state)
        assert missing == {name: row for name, row in before.items() if name != original_name}
        assert sys.getprofile() is None
        sys.setprofile(profile)
        try:
            unexpected = await AsyncClient.open(state_dir=state)
        except ClientError as failure:
            code = failure.code
            cleanup = failure.cleanup_client
            chain = []
            origin = failure.original_error
            while origin is not None:
                chain.append([type(origin).__name__, getattr(origin, 'errno', None)])
                origin = origin.__cause__
        else:
            await unexpected.aclose()
            raise AssertionError('Missing original Account configuration was accepted')
        finally:
            sys.setprofile(None)
        assert code == 'LocalClientInitializationCleanupPending' and cleanup is not None
        assert chain[-1] == ['FileNotFoundError', errno.ENOENT] and not any(calls.values())
        cleanup_host = cleanup._local_host
        assert cleanup_host._installation is not None and not cleanup_host._core._closed
        await cleanup.aclose()
        failed_reopen_close = cleanup_host._installation is None and cleanup_host._core._closed and cleanup._client_cleanup is None
        refused = installation_snapshot(state)
        assert failed_reopen_close and refused == missing
    finally:
        if not account.exists():
            held.rename(account)
    restored = installation_snapshot(state)
    assert restored == before
    async with await AsyncClient.open(state_dir=state) as saved:
        saved_host = saved._local_host
        run = await saved.attach(reference)
        saved_reference = plain(run.ref)
        rows = plain(await run.result('answer').all())
        assert saved_reference == reference and rows == expected
    assert saved_host._installation is None and saved_host._core._closed
    return dict(path=original_name, code=code, originalChain=chain, calls=calls, before=before, missing=missing,
                refused=refused, restored=restored, failedReopenClose=failed_reopen_close,
                savedRun=saved_reference, rows=rows, savedClose=saved_host._core._closed)


async def observe_changed_payload(state, reference, expected, physical_wire, selected):
    # This state and payload were created by this diagnostic. Change the used
    # file without replacing its inode, leaving the durable digest untouched.
    name = selected['name']
    assert re.fullmatch(r'payload-[0-9a-f]{64}', name)
    assert selected['bytes'] == len(physical_wire) and selected['sha256'] == sha256(physical_wire).hexdigest()
    offset = physical_wire.index(b'x')
    changed = physical_wire[:offset] + b'y' + physical_wire[offset + 1:]
    assert json.loads(changed) != expected
    failures = []
    observe_original = LocalFileRoot.observe_original

    def observe(root, reader):
        # Record the original owner's refusal before the transport redacts it.
        try:
            return observe_original(root, reader)
        except LocalFileError as failure:
            failures.append((reader, str(failure)))
            raise

    directory = os.open(state / 'source/results', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        file = os.open(name, os.O_RDWR | os.O_NOFOLLOW, dir_fd=directory)
        try:
            def file_observation(payload):
                info = os.fstat(file)
                assert stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                assert os.pread(file, len(payload) + 1, 0) == payload
                return dict(name=name, device=str(info.st_dev), inode=str(info.st_ino),
                            bytes=info.st_size, sha256=sha256(payload).hexdigest())

            assert file_observation(physical_wire) == selected
            try:
                assert os.pwrite(file, b'y', offset) == 1
                damaged = file_observation(changed)
                async with await AsyncClient.open(state_dir=state) as client:
                    host = client._local_host
                    run = await client.attach(reference)
                    assert plain(run.ref) == reference and (await run.status())['status'] == 'succeeded'
                    reader = run.result('answer').rows()
                    try:
                        with patch.object(LocalFileRoot, 'observe_original', observe):
                            async with reader:
                                async for _ in reader:
                                    raise AssertionError('Changed Saved material reached the caller')
                    except ClientError as failure:
                        code = failure.code
                        assert code == 'ClientTransportUnknown' and failure.attempt_id == reader.attempt_id
                    else:
                        raise AssertionError('Changed Saved material was accepted')
                    (opened, digest_error), = failures
                    observed = dict(name=opened.name, device=str(opened.identity.device), inode=str(opened.identity.inode),
                                    bytes=opened.offset, sha256=opened.hash.hexdigest())
                    assert observed == damaged and opened.expected.physical_digest == 'sha256:' + selected['sha256']
                    assert digest_error == 'Saved Local payload content differs from its recorded digest'
                    assert opened.invalid and opened.eof and reader.rows_yielded == 0
                    refused = plain(await reader.delivery_attempt())
                    assert refused == {'kind': 'not_found'}
                    original_status = (await run.status())['status']
                    assert original_status == 'succeeded'
                closed = opened.descriptor is None and opened.chunk is None and not host._saved_result_reads
                assert closed
                assert host._installation is None and host._core._closed
            finally:
                assert os.pwrite(file, b'x', offset) == 1
                restored = file_observation(physical_wire)
                assert restored == selected
        finally:
            os.close(file)
    finally:
        os.close(directory)

    async with await AsyncClient.open(state_dir=state) as saved:
        saved_host = saved._local_host
        run = await saved.attach(reference)
        saved_reference = plain(run.ref)
        rows = plain(await run.result('answer').all())
        assert saved_reference == reference and rows == expected
    assert saved_host._installation is None and saved_host._core._closed
    return dict(selected=selected, damaged=damaged, observed=observed, restored=restored, offset=offset, code=code,
                digestErrors=[digest_error], rowsYielded=reader.rows_yielded, delivery=refused,
                attemptId=reader.attempt_id, originalStatus=original_status, payloadClosed=closed,
                firstClose=host._core._closed, savedRun=saved_reference, rows=rows, savedClose=saved_host._core._closed)


def require_targeted_saved_read(totals, beats):
    # Initial Local adoption retains its existing inspection. All later turns
    # use only the selected Run's keyed current row, independent of history.
    assert totals['scan_calls'] == totals['scan_namespaces'].get('client_local_adoption', 0), totals
    assert totals['scan_calls'] == beats[0]['scan_calls'], totals
    assert totals['cancel_scan_calls'] == totals['cancel_rows'] == totals['cancel_scan_body_bytes'] == 0, totals
    assert totals['saved_run_points'] > 0 and totals['saved_run_keys'] == 1, totals
    assert beats[-1]['saved_run_points'] > beats[0]['saved_run_points'], beats


async def exercise(state_dir, **identity):
    reference, expected, delivered_wire = await prepare_original(state_dir)
    physical_wire = json.dumps(expected, separators=(',', ':')).encode()
    physical_digest = sha256(physical_wire).hexdigest()
    async with await AsyncClient.open(state_dir=state_dir) as client:
        original = await client.attach(reference)
        attached = plain(original.ref)
        assert attached == reference
        state = plain(await original.status())
        result = original.result('answer')
        host = client._local_host
        assert type(host) is InstalledLocalHost and type(host._core) is LocalCore
        assert host._core._ordinary_host and 'advance_and_read_saved_result' not in vars(host._core)
        controls, stops, attempts = {}, {}, set()
        for phase in ('core', 'hash'):
            stops[phase] = {}
            _, _, controls[phase], _, attempt = await observe_read(host, result, phase, stop_receipt=stops[phase])
            attempts.add(attempt)
            observed_status = plain(await original.status())
            assert observed_status == state
            stops[phase]['originalStatus'] = observed_status['status']
        truncated_reader, truncation = await observe_truncation(client, result)
        attempts.add(truncated_reader.attempt_id)
        assert plain(await original.status()) == state
        delivered_digest = sha256(delivered_wire).hexdigest()
        successful, selected = [], {}
        for _ in range(2):
            totals = {}
            observed, receipt, beats, core_turns, attempt = await observe_read(
                host, result, totals=totals, selected_payload=selected)
            attempts.add(attempt)
            assert observed == expected
            hash_beats = [beat for beat in beats if beat['phase'] == 'hash']
            assert [beat['offset'] for beat in hash_beats] == [16384, len(physical_wire)]
            assert hash_beats[-1]['physical_sha256'] == physical_digest
            assert core_turns >= 2
            require_targeted_saved_read(totals, beats)
            assert beats[-1]['point_calls'] > beats[0]['point_calls']
            proof = receipt['hostReleaseReceipt']
            assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
            assert proof['run_definition_cid'] == reference['runDefinitionCid']
            assert proof['delivered_byte_count'] == len(delivered_wire)
            assert proof['delivered_sha256'] == delivered_digest
            assert plain(await original.status()) == state
            successful.append({'turns': beats, 'core_turns': core_turns, 'attemptId': attempt,
                               'delivery': receipt, 'read_totals': totals})
        truncation['deliveryAfterReadback'] = plain(await truncated_reader.delivery_attempt())
        assert truncation['deliveryAfterReadback'] == truncation['delivery']
        assert len(attempts) == 5
    configuration = await observe_missing_configuration(state_dir, reference, expected)
    changed_payload = await observe_changed_payload(state_dir, reference, expected, physical_wire, selected)
    print(json.dumps({**identity, 'core_cancellation': controls['core'],
                      'hash_cancellation': controls['hash'],
                      'boundary': {'protocol': {'kind': 'installed-python-saved-continuation/4',
                                                'facade': 'AsyncClient', 'resultName': 'answer',
                                                'valueBytes': CONTINUATION_VALUE_BYTES,
                                                'stopPhases': ['core', 'hash', 'response-before-confirm', 'missing-configuration',
                                                               'changed-payload']},
                                   'originalRun': reference, 'attachedRun': attached,
                                   'stops': stops, 'truncation': truncation, 'configuration': configuration,
                                   'changedPayload': changed_payload},
                      'successful_reads': successful, 'rows': len(expected), 'bytes': len(delivered_wire),
                      'sha256': delivered_digest, 'physical_bytes': len(physical_wire),
                      'physical_sha256': physical_digest, 'first_close': True}))


async def measure_history(destination, levels, *, chunk_counts=(1, 2)):
    destination.mkdir(mode=0o700)
    for cancellation_records in levels:
        for chunk_count in chunk_counts:
            # The one-row canonical array has ten framing bytes. A single
            # extra byte changes the physical read from one chunk to two.
            state_dir = destination / f'c{cancellation_records}-k{chunk_count}'
            reference, expected, delivered = await prepare_original(
                state_dir, value_size=16373 + chunk_count, cancellation_records=cancellation_records)
            physical = json.dumps(expected, separators=(',', ':')).encode()
            assert len(physical) == 16383 + chunk_count
            async with await AsyncClient.open(state_dir=state_dir) as client:
                execution = await client.attach(reference)
                assert plain(execution.ref) == reference
                host = client._local_host
                assert type(host) is InstalledLocalHost and type(host._core) is LocalCore
                assert host._core._ordinary_host and 'advance_and_read_saved_result' not in vars(host._core)
                totals = {}
                rows, receipt, beats, core_turns, attempt = await observe_read(
                    host, execution.result('answer'), totals=totals)
                assert rows == expected and core_turns >= 2
                require_targeted_saved_read(totals, beats)
                hash_beats = [beat for beat in beats if beat['phase'] == 'hash']
                assert [beat['offset'] for beat in hash_beats] == (
                    [16384] if chunk_count == 1 else [16384, 16385])
                assert hash_beats[-1]['physical_sha256'] == sha256(physical).hexdigest()
                assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
                assert receipt['attempt']['attempt_id'] == attempt
                proof = receipt['hostReleaseReceipt']
                assert proof['run_definition_cid'] == reference['runDefinitionCid']
                assert proof['delivered_byte_count'] == len(delivered)
                assert proof['delivered_sha256'] == sha256(delivered).hexdigest()
            print(json.dumps({'cancellation_records': cancellation_records, 'physical_chunks': chunk_count,
                              'core_turns': core_turns, 'beats': beats, 'read_totals': totals,
                              'delivered_bytes': len(delivered), 'physical_bytes': len(physical),
                              'first_close': True}), flush=True)


def installed_identity(source):
    import actql
    from actql_sdk._local_distribution import installed_local_components
    if not Path(actql.__file__).is_relative_to(Path(sys.prefix)):
        raise ValueError('Installed public facade required')
    original = installed_local_components()
    if original.source_sha != source:
        raise ValueError('Foreign installed Saved fixture source')
    return {'source': original.source_sha, 'module': original.module_sha256,
            'image': original.image_sha256, 'pid': os.getpid()}


async def warm_interruption(directory, identity):
    state_dir = directory / 'fresh-public-state' / '.actql'
    state_dir.parent.mkdir()
    reference, _, _ = await prepare_original(state_dir, value_size=1)
    with (directory / 'fresh-original-reference.json').open('x') as receipt:
        json.dump({'stateDir': str(state_dir), 'warmPID': identity['pid'],
                   'reference': reference, 'resultName': 'answer'}, receipt)
    print(json.dumps({**identity, 'phase': 'warm', 'first_close': True}))


async def recover_interrupted(directory, identity):
    original = json.loads((directory / 'fresh-original-reference.json').read_text())
    state_dir = directory / 'fresh-public-state' / '.actql'
    assert original['stateDir'] == str(state_dir) and original['warmPID'] != identity['pid']
    assert state_dir.is_dir() and original['resultName'] == 'answer'
    async with await AsyncClient.open(state_dir=state_dir) as client:
        run = await client.attach(original['reference'])
        assert plain(run.ref) == original['reference']
        assert (await run.status())['status'] == 'succeeded'
        result = run.result('answer')
        async with result.rows() as reader:
            assert [row async for row in reader] == [{'s': 'x'}]
        receipt = plain(await reader.delivery_attempt())
        proof = receipt['hostReleaseReceipt']
        assert receipt['kind'] == 'found' and receipt['record']['state'] == 'succeeded'
        assert receipt['attempt']['attempt_id'] == reader.attempt_id
        assert proof['run_definition_cid'] == original['reference']['runDefinitionCid']
        expected = b'{"s":"x"}\n'
        assert proof['delivered_byte_count'] == len(expected)
        assert proof['delivered_sha256'] == sha256(expected).hexdigest()
    print(json.dumps({**identity, 'phase': 'recover', 'same_saved': True,
                      'replayed': False, 'first_close': True,
                      'bytes': len(expected), 'sha256': sha256(expected).hexdigest()}))


if __name__ == '__main__':
    state_dir = Path(sys.argv[1]).resolve()
    if len(sys.argv) == 3 and sys.argv[2] in ('--measure-history', '--measure-nonempty-history'):
        levels = (1,) if sys.argv[2] == '--measure-nonempty-history' else (0, 1)
        asyncio.run(measure_history(state_dir, levels))
    elif len(sys.argv) == 4 and sys.argv[2] in (
            '--installed-continuation', '--warm-interruption', '--recover-interruption', '--observe-public-stream'):
        identity = installed_identity(sys.argv[3])
        if sys.argv[2] == '--installed-continuation':
            asyncio.run(exercise(state_dir, **identity))
        elif sys.argv[2] == '--warm-interruption':
            asyncio.run(warm_interruption(state_dir, identity))
        elif sys.argv[2] == '--observe-public-stream':
            asyncio.run(observe_public_stream(state_dir, identity))
        else:
            asyncio.run(recover_interrupted(state_dir, identity))
    elif len(sys.argv) == 2:
        asyncio.run(exercise(state_dir))
    else:
        raise ValueError('Select one Saved fixture mode and its state')
