import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedReaderPolicy} from '../examples/reader-policy.mjs';
import {readFileSync} from 'node:fs';

import type {snapshotCompletionTask} from '../../../../host-node/completion-record.mjs';

type Policy = ReturnType<typeof retainedReaderPolicy>;
type FixtureTask = Pick<ReturnType<typeof snapshotCompletionTask>, 'task' | 'output_step' | 'inputs'>;
type QuoteRuntime = Readonly<{retainedReadmissionFactsControlBytes?: () => unknown}>;
type ReaderPorts = Readonly<{
  checked<Value>(value: Value): Value;
  budget: Readonly<{
    processLedgerCreate(limits: Policy): object;
    processReadReserve(ledger: object, bytes: bigint, scratch: bigint): object;
    processStopped(ledger: object, reservation: object): void;
  }>;
  retainedReaderPolicy(): Policy;
  prepareExampleText(): Promise<Readonly<{taskIdentities(): readonly FixtureTask[]; contentRead(): never}>>;
  snapshotCompletionTask(task: FixtureTask): FixtureTask;
  processReadmissionControlBytes(): bigint;
}>;
type FixtureReader = (input: Readonly<{application: object; task: number}>, signal: AbortSignal,
  context: Readonly<{resourceLimits: Policy; callHost(): Promise<{descriptor: {bytes: number}}>}>,
  progress: {stage?: string}) => Promise<unknown>;

const profile = () => ({source_rows: 100, task_rows: 100, columns: 64, value_bytes: 2048,
  wire_bytes: 1000000, value_nodes: 100000, text_bytes: 1000000, work: 1000000,
  entries: 100000, batch_bytes: 1000});

test('reader bounds use the configured schema and simultaneous frame, not cumulative counts', () => {
  const supplied = profile();
  const policy = retainedReaderPolicy(supplied);
  assert.equal(policy.recordLimits.maxColumns, 64);
  assert.equal(policy.decodeLimits.max_nodes, 1000);
  assert.equal(policy.scratchBytes, 3056000n);
  supplied.columns = 1;
  supplied.batch_bytes = 1;
  assert.equal(policy.recordLimits.maxColumns, 64);
  assert.equal(policy.decodeLimits.max_bytes, 1000);
  const larger = retainedReaderPolicy({...profile(), source_rows: 10000, task_rows: 10000,
    value_nodes: 1000000, text_bytes: 10000000, work: 10000000});
  assert.equal(larger.scratchBytes, policy.scratchBytes);
  assert.equal(larger.frameLimits.maxRows, 10000);
  assert.equal(retainedReaderPolicy({...profile(), batch_bytes: 1001}).scratchBytes,
    policy.scratchBytes + 1056n);
});

test('reader rejects invalid profiles before reserving and keeps bounded defaults', () => {
  assert.throws(() => retainedReaderPolicy({...profile(), batch_bytes: 1000001}), /InvalidApplicationDataProfile/);
  assert.throws(() => retainedReaderPolicy({...profile(), columns: 257}), /InvalidApplicationDataProfile/);
  const policy = retainedReaderPolicy();
  assert.equal(policy.recordLimits.maxColumns, 10);
  assert.equal(policy.decodeLimits.max_nodes, 10000);
  assert(policy.scratchBytes < 268435456n);
  assert(Object.isFrozen(policy.decodeLimits));
});

// Execute the actual installed quote port, without importing another compiled
// runtime or constructing a fake completion. Runtime omission must fail before
// any receiving constructor, rather than silently selecting another quota.
function readmissionQuote(runtime: QuoteRuntime): () => bigint {
  const source = readFileSync(new URL('../../../../host-node/process-readmission.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('const defaultLimits = ');
  const end = source.indexOf('export function prepareProcessReadmission(');
  assert(start >= 0 && end > start);
  return new Function('runtime', `${source.slice(start, end).replace(/^export /gmu, '')}\nreturn processReadmissionControlBytes;`)(runtime);
}

test('installed readmission requires its authoritative fixed quote port exactly once', () => {
  assert.throws(() => readmissionQuote({}), {code: 'CompletionReadmissionRuntimeUnavailable'});
  for (const value of [undefined, 1, -1n, 9223372036854775808n]) {
    assert.throws(() => readmissionQuote({retainedReadmissionFactsControlBytes: () => value}),
      {code: 'InvalidCompletionReadmissionConstructionQuote'});
  }
  let calls = 0;
  const quote = readmissionQuote({retainedReadmissionFactsControlBytes() {calls++; return 731n;}});
  assert.equal(quote(), 731n);
  assert.equal(quote(), 731n);
  assert.equal(calls, 1);
});

function installedReader(ports: ReaderPorts): FixtureReader {
  const source = readFileSync(new URL('../examples/managed-reader.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('let ledger, used = false;');
  const end = source.indexOf('\nserveManagedExecution(');
  assert(start >= 0 && end > start);
  return new Function(...Object.keys(ports), `${source.slice(start, end)}\nreturn readContent;`)(...Object.values(ports));
}

test('original process Read reserves the common metadata quote before constructing content', async () => {
  for (const refused of [false, true]) {
    const originalLedger = {}, originalReservation = {}, marker = Error('bounded-constructor-stop');
    const events: string[] = [];
    const policy = retainedReaderPolicy(profile());
    const task = {task: 1, output_step: 0, inputs: []};
    const reader = installedReader({
      checked: value => value,
      budget: {
        processLedgerCreate(limits) {assert.equal(limits, policy); return originalLedger;},
        processReadReserve(ledger, bytes, scratch) {
          assert.equal(ledger, originalLedger); assert.equal(bytes, 17n);
          assert.equal(scratch, policy.scratchBytes + 731n); events.push('reserve');
          if (refused) throw marker;
          return originalReservation;
        },
        processStopped(ledger, reservation) {
          assert.equal(ledger, originalLedger); assert.equal(reservation, originalReservation);
          events.push('stopped');
        },
      },
      retainedReaderPolicy: () => policy,
      prepareExampleText: async () => ({taskIdentities: () => [task], contentRead() {
        events.push('content'); throw marker;
      }}),
      snapshotCompletionTask: value => value,
      processReadmissionControlBytes: readmissionQuote({retainedReadmissionFactsControlBytes: () => 731n}),
    });
    await assert.rejects(reader({application: {}, task: 1}, new AbortController().signal,
      {resourceLimits: policy, callHost: async () => ({descriptor: {bytes: 17}})}, {}), error => error === marker);
    assert.deepEqual(events, refused ? ['reserve'] : ['reserve', 'content', 'stopped']);
  }
});
