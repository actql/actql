import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {consumeDelegatedFile} from '../store-local/delegated-reader.mjs';
import {createProcessCompletionCustody} from './completion-custody.mjs';
import {completionRecordLimits, snapshotCompletionDescriptor, snapshotCompletionTask} from './completion-record.mjs';

const cid = `sha256:${'1'.repeat(64)}`;
const descriptor = () => ({registry_cid: cid, values_contract_cid: cid, rows_cid: cid,
  output_step: 1, input_count: 1, columns: 1, rows: 1, bytes: 10, nodes: 4, depth: 3,
  values: {nodes: 2, text_bytes: 2, work: 4}});
const limits = {maxCompletions: 2, maxInputs: 2, maxColumns: 10};
const taskIdentity = (task = 1) => ({task, output_step: 1,
  program_definition_cid: cid, program_parameters_cid: cid,
  unit_definition_cid: cid, unit_parameters_cid: cid, unit_contracts_cid: cid,
  inputs: [{input: 0, producer: 0, producer_target_is_input: false, producer_target_index: 1}],
  controls: [0]});

// Trusted channel/Store SPI fixture, not a computation proof. The real standard
// Host test separately checks that only common-completed output is delivered.
function fixture(options = limits, expected = Array.from({length: options.maxCompletions}, (_, i) => taskIdentity(i + 1))) {
  let alive = true, pending = false, stop, closes = 0, readers = 0;
  const body = Object.freeze({cid, bytes: 10, available: () => alive,
    delegateRead(session) {
      assert.equal(readers, 0);
      readers++;
      let settled = false;
      const descriptor = Object.freeze({session, token: 'exact-read-token', bytes: 10, cid});
      const release = () => { if (!settled) { settled = true; readers--; } };
      return {descriptor, confirmStopped: release,
        verify(report) {
          assert.deepEqual(report, descriptor);
          assert.equal(settled, false);
          if (!alive) throw Error('RetainedUnavailable');
          return {bytes: 10, cid};
        }, finish(report) {
        assert.deepEqual(report, descriptor);
        assert.equal(settled, false);
        release();
        if (!alive) throw Error('RetainedUnavailable');
        return {bytes: 10, cid};
      }};
    }});
  const bodies = new Map([['first', body]]);
  const stopped = new Promise(resolve => { stop = resolve; });
  const identity = {session: 'exact-session', run: 'run'};
  const cleanupHandle = {status: () => ({pending}), retry: async () => { pending = false; }};
  const store = {service: {invoke: async () => 'storage-only'}, cleanupHandle,
    observe() {}, body: key => bodies.get(key),
    async close() { closes++; alive = false; if (pending) throw new Error('DeletionFailed'); }};
  const custody = createProcessCompletionCustody(store, options, expected);
  custody.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
  const owner = {...identity, sequence: 2, call: 1};
  const submit = (change = {}, source = owner) => custody.service.invoke(
    {command: 'retain-completion', task: 1, output: 'first', descriptor: descriptor(),
      taskIdentity: taskIdentity(change.task ?? 1), ...change},
    new AbortController().signal, source);
  return {custody, body, bodies, submit, owner, stop, revoke() { alive = false; },
    failClose() { pending = true; }, closes: () => closes, readers: () => readers};
}

function readerChannel(session = 'reader-session', run = 'run') {
  let exited = false, resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  const channel = {identity: () => ({session, run}), status: () => ({exited}),
    cleanupHandle: {whenStopped: () => promise}};
  return {channel, owner: {session, run, sequence: 1, call: 1},
    stop() { exited = true; resolve(); },
    failSettlement() { reject(Error('UnconfirmedStop')); },
    actualExit() { exited = true; }};
}

test('fresh read requires exact custody, same Run, new session and checked task identity', async () => {
  const {custody, submit, stop, readers} = fixture();
  await submit();
  stop(); await Promise.resolve();
  const handle = custody.completion(1);
  assert.throws(() => custody.prepareReader({...handle}), {code: 'ForeignCompletionRecord'});
  const reader = custody.prepareReader(handle);
  for (const channel of [readerChannel('exact-session'), readerChannel('fresh', 'foreign')]) {
    assert.throws(() => reader.observe(channel.channel), {code: 'ForeignCompletionReader'});
  }
  const {channel, owner} = readerChannel();
  reader.observe(channel);
  assert.throws(() => reader.observe(channel), {code: 'CompletionReaderAlreadyBound'});
  const invoke = (request, source = owner) => reader.service.invoke(request, new AbortController().signal, source);
  const request = {command: 'read-completion', taskIdentity: taskIdentity()};
  await assert.rejects(invoke(request, {...owner, run: 'other'}), {code: 'ForeignCompletionReader'});
  await assert.rejects(invoke({...request, taskIdentity: {...taskIdentity(), output_step: 0}}), {code: 'ForeignCompletionTask'});
  assert.equal(readers(), 0);
  const result = await invoke(request);
  assert.deepEqual(result.taskIdentity, taskIdentity());
  assert.equal(result.origin.session, 'exact-session');
  assert.equal(result.lease.session, 'reader-session');
  assert.equal(readers(), 1);
  await assert.rejects(invoke(request), {code: 'CompletionReaderConsumed'});
  const finish = {command: 'finish-completion-read', report: result.lease};
  assert.deepEqual(await invoke({...finish, command: 'verify-completion-read'}), {bytes: 10, cid});
  assert.equal(readers(), 1);
  assert.equal(reader.cleanupHandle.status().pending, true);
  await assert.rejects(invoke(finish, {...owner, sequence: 2}), {code: 'ForeignCompletionReadReport'});
  await assert.rejects(invoke({...finish, report: {...result.lease, token: 'foreign'}}));
  assert.equal(reader.cleanupHandle.status().pending, true);
  assert.deepEqual(await invoke(finish), {bytes: 10, cid});
  assert.equal(readers(), 0);
  assert.equal(reader.cleanupHandle.status().pending, false);
  await assert.rejects(invoke(request), {code: 'CompletionReaderConsumed'});
});

test('fresh read cancellation and rejected settlement retain borrow until confirmed exit', async () => {
  const {custody, submit, readers} = fixture();
  await submit();
  const reader = custody.prepareReader(custody.completion(1));
  const source = readerChannel();
  reader.observe(source.channel);
  const signal = new AbortController();
  const request = {command: 'read-completion', taskIdentity: taskIdentity()};
  signal.abort();
  await assert.rejects(reader.service.invoke(request, signal.signal, source.owner));
  assert.equal(readers(), 0);
  await reader.service.invoke(request, new AbortController().signal, source.owner);
  await custody.close();
  assert.equal(readers(), 1);
  assert.equal(reader.cleanupHandle.status().pending, true);
  assert.throws(() => custody.prepareReader(custody.completion(1)), {code: 'RetainedUnavailable'});
  source.failSettlement(); await Promise.resolve();
  assert.equal((await reader.cleanupHandle.retry()).pending, true);
  await assert.rejects(reader.service.invoke(request, new AbortController().signal, source.owner), {code: 'ForeignCompletionReader'});
  source.actualExit();
  assert.equal((await reader.cleanupHandle.retry()).pending, false);
  assert.equal(readers(), 0);
  assert.equal((await reader.cleanupHandle.retry()).pending, false);
});

test('revocation between preparation and first read does not start a borrow', async () => {
  const {custody, submit, revoke, readers} = fixture();
  await submit();
  const reader = custody.prepareReader(custody.completion(1));
  const source = readerChannel();
  reader.observe(source.channel);
  revoke();
  await assert.rejects(reader.service.invoke({command: 'read-completion', taskIdentity: taskIdentity()},
    new AbortController().signal, source.owner), {code: 'RetainedUnavailable'});
  assert.equal(readers(), 0);
});

test('custody reader keeps real file capacity charged through revocation until exact terminal report', async t => {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-custody-read-'));
  const storage = await createLocalRetainedStore({parentDirectory, capacityBytes: 20, maxFrameBytes: 4});
  t.after(async () => { storage.close(); await storage.cleanup(); await rmdir(parentDirectory); });
  const writer = storage.reserve(20);
  await writer.start();
  const bytes = '[0]';
  await writer.append(bytes);
  const rows_cid = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const body = await writer.seal({bytes: 3, cid: rows_cid});
  // Trusted reporting fixture: this test checks custody/physical cleanup,
  // not whether these example bytes constitute a semantic completion.
  const custody = createProcessCompletionCustody({
    service: {invoke() {}}, observe() {}, body: () => body,
    async close() { storage.close(); await storage.cleanup(); },
  }, limits, [taskIdentity()]);
  const writerChannel = readerChannel('writer-session');
  custody.observe(writerChannel.channel);
  await custody.service.invoke({command: 'retain-completion', task: 1, output: 'first',
    descriptor: {...descriptor(), rows_cid, bytes: 3}, taskIdentity: taskIdentity()},
  new AbortController().signal, writerChannel.owner);
  writerChannel.stop(); await Promise.resolve();
  const reader = custody.prepareReader(custody.completion(1));
  const source = readerChannel();
  reader.observe(source.channel);
  t.after(async () => { source.stop(); await Promise.resolve(); });
  const invoke = request => reader.service.invoke(request, new AbortController().signal, source.owner);
  const {lease} = await invoke({command: 'read-completion', taskIdentity: taskIdentity()});
  const report = await consumeDelegatedFile(lease, chunk => assert(chunk.length <= 4));
  assert.deepEqual(await invoke({command: 'verify-completion-read', report}), {bytes: 3, cid: rows_cid});
  assert.equal(reader.cleanupHandle.status().pending, true);
  await custody.close();
  assert.equal(storage.status().reservedBytes, 3);
  await assert.rejects(invoke({command: 'verify-completion-read', report}), {code: 'RetainedUnavailable'});
  assert.equal(storage.status().reservedBytes, 3);
  await assert.rejects(invoke({command: 'finish-completion-read', report: {...report, token: 'foreign'}}),
    {code: 'ForeignStoreReadReport'});
  assert.equal(storage.status().reservedBytes, 3);
  await assert.rejects(invoke({command: 'finish-completion-read', report}), {code: 'RetainedUnavailable'});
  await storage.cleanup();
  assert.equal(storage.status().reservedBytes, 0);
  // The service conservatively retains its terminal bookkeeping until actual
  // reader exit after a revoked finish throws; no second read can start.
  source.stop(); await Promise.resolve();
  assert.equal(reader.cleanupHandle.status().pending, false);
  assert.equal(storage.status().admittedWriteBytes, 3);
});

test('completion record metadata is exact bounded snapshot, not a payload or wire authority', () => {
  const configuration = {...limits};
  const frozen = completionRecordLimits(configuration);
  configuration.maxInputs = 100;
  assert.equal(frozen.maxInputs, 2);
  for (const change of [{maxInputs: -1}, {maxCompletions: 0}, {extra: true}]) {
    assert.throws(() => completionRecordLimits({...limits, ...change}), /InvalidCompletionRecordLimits/);
  }
  const value = descriptor();
  const snapshot = snapshotCompletionDescriptor(value, frozen);
  value.values.nodes = 100;
  assert.equal(snapshot.values.nodes, 2);
  assert(Object.isFrozen(snapshot.values));
  for (const change of [{rows: NaN}, {bytes: 2147483648}, {columns: 11}, {input_count: 3},
    {rows_cid: 'claimed'}, {rowsData: []}, {values: {nodes: 1, work: 1}}]) {
    assert.throws(() => snapshotCompletionDescriptor({...descriptor(), ...change}, frozen), /InvalidCompletionDescriptor/);
  }
});

test('checked task identity snapshot preserves ports and rejects malformed or unbounded references', () => {
  const value = taskIdentity();
  const snapshot = snapshotCompletionTask(value, limits);
  value.inputs[0].producer_target_index = 99;
  value.controls.push(10);
  assert.equal(snapshot.inputs[0].producer_target_index, 1);
  assert.deepEqual(snapshot.controls, [0]);
  for (const change of [{task: 0}, {inputs: [value.inputs[0], value.inputs[0]]},
    {controls: [1]}, {controls: [0, 0, 0]}, {unit_parameters_cid: 'unbound'}, {extra: true},
    {inputs: [{...value.inputs[0], input: 1}]}, {inputs: [{...value.inputs[0], producer: 1}]}]) {
    assert.throws(() => snapshotCompletionTask({...taskIdentity(), ...change}, limits), /InvalidCompletionTask/);
  }
});

test('custody fixes a complete same-Program task projection before any Store binding', async () => {
  for (const expected of [[], [taskIdentity(), taskIdentity()],
    [taskIdentity(), {...taskIdentity(2), program_parameters_cid: `sha256:${'2'.repeat(64)}`}],
    [{...taskIdentity(2), controls: [1]}]]) {
    assert.throws(() => fixture(limits, expected), /InvalidCompletionTaskSet/);
  }
  const expected = [taskIdentity(), taskIdentity(2)];
  const {submit, custody} = fixture(limits, expected);
  expected[0].unit_parameters_cid = `sha256:${'2'.repeat(64)}`;
  expected[0].inputs.length = 0;
  expected.length = 0;
  await submit();
  assert.equal(custody.count(), 1);
});

test('custody checks task target, parameter identity and completed dependency occurrences', async () => {
  const next = taskIdentity(2);
  next.inputs = [{input: 0, producer: 1, producer_target_is_input: false, producer_target_index: 1}];
  next.controls = [1];
  const third = {...taskIdentity(3), controls: [2]};
  const expected = [taskIdentity(), next, third];
  const {custody, submit, bodies, body} = fixture({...limits, maxCompletions: 3}, expected);
  await assert.rejects(submit({taskIdentity: {...taskIdentity(), output_step: 2}}), {code: 'ForeignCompletionTask'});
  await submit();
  bodies.set('second', Object.freeze({...body}));
  const send = value => submit({task: 2, output: 'second', taskIdentity: value});
  await assert.rejects(send({...next, program_parameters_cid: `sha256:${'2'.repeat(64)}`}), {code: 'ForeignCompletionTask'});
  await assert.rejects(send({...next, inputs: [{...next.inputs[0], producer_target_index: 0}]}), {code: 'ForeignCompletionTask'});
  await assert.rejects(submit({task: 3, output: 'second', taskIdentity: {...taskIdentity(3), controls: [2]}}),
    {code: 'ForeignCompletionDependency'});
  assert.equal(custody.count(), 1);
  await send(next);
  assert.equal(custody.count(), 2);
  assert.deepEqual(custody.inspect(custody.completion(2)).taskIdentity, next);
});

test('sealed physical body alone creates no completion; exact delivered fact survives writer exit', async () => {
  const {custody, submit, stop} = fixture();
  assert.equal(custody.count(), 0);
  assert.equal(custody.completion(1), undefined);
  assert.deepEqual(await submit(), {task: 1});
  const handle = custody.completion(1);
  const record = custody.inspect(handle);
  assert.equal(record.retained, true);
  assert.deepEqual(record.origin, {session: 'exact-session', run: 'run', request: 2, task: 1, output: 'first'});
  assert.throws(() => custody.inspect({...handle}), {code: 'ForeignCompletionRecord'});
  stop(); await Promise.resolve();
  assert.deepEqual(custody.inspect(handle), record);
  await assert.rejects(submit({task: 2}), {code: 'ForeignCompletionSession'});
  await custody.close();
  assert.equal(custody.inspect(handle).retained, false);
  assert.deepEqual(custody.inspect(handle).descriptor, record.descriptor);
});

test('foreign session, missing holding and mismatched content cannot install a completion record', async () => {
  const {custody, submit, owner, bodies, body} = fixture();
  for (const source of [{...owner, run: 'other'}, {...owner, session: 'old'}]) {
    await assert.rejects(submit({}, source), {code: 'ForeignCompletionSession'});
  }
  for (const change of [{output: 'missing'}, {descriptor: {...descriptor(), bytes: 9}},
    {descriptor: {...descriptor(), rows_cid: `sha256:${'2'.repeat(64)}`}}]) {
    await assert.rejects(submit(change), {code: 'ForeignCompletionHolding'});
  }
  for (const change of [{task: 0}, {task: 1.5}, {extra: true}]) {
    await assert.rejects(submit(change), {code: 'InvalidCompletionRecord'});
  }
  assert.equal(custody.count(), 0);
  await submit();
  await assert.rejects(submit(), {code: 'DuplicateCompletionRecord'});
  bodies.set('alias', body);
  await assert.rejects(submit({task: 2, output: 'alias'}), {code: 'ForeignCompletionHolding'});
  assert.equal(custody.count(), 1);
});

test('record quota is cumulative and custody handles cannot cross otherwise identical owners', async () => {
  const first = fixture({...limits, maxCompletions: 1});
  const second = fixture();
  await first.submit(); await second.submit();
  assert.deepEqual(first.custody.inspect(first.custody.completion(1)), second.custody.inspect(second.custody.completion(1)));
  assert.throws(() => second.custody.inspect(first.custody.completion(1)), {code: 'ForeignCompletionRecord'});
  await assert.rejects(first.submit({task: 2}), {code: 'CompletionRecordLimit'});
  await first.custody.close();
  assert.equal(first.custody.count(), 1);
  assert.equal(second.custody.inspect(second.custody.completion(1)).retained, true);
});

test('custody close revokes use immediately without dropping failed physical cleanup', async () => {
  const {custody, submit, failClose} = fixture();
  await submit();
  const handle = custody.completion(1);
  failClose();
  await assert.rejects(custody.close(), /DeletionFailed/);
  assert.equal(custody.inspect(handle).retained, false);
  assert.equal(custody.cleanupHandle.status().pending, true);
  await assert.rejects(submit({task: 2}), {code: 'ForeignCompletionSession'});
  await custody.cleanupHandle.retry();
  assert.equal(custody.cleanupHandle.status().pending, false);
  assert.equal(custody.inspect(handle).descriptor.rows_cid, cid);
});
