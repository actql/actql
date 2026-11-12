import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {createLocalResultReadWorkspace} from './local-result-read-workspace.mjs';
import {createLocalResultAuthorization} from './local-result-authorization.mjs';
import {sourceReadAccountConfiguration} from './local-account-config.mjs';
import * as access from '../host-common/result-access.mjs';
import {createResultDeliveryFixture} from '../../scripts/fixtures/result-delivery-acceptance.mjs';

// One actual freshly linked Common namespace. No mock semantics, shim,
// installed package overlay or new normal producer is selected by this case.
const raw = await import(process.env.ACTQL_RESULT_READ_COMMON_MODULE ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
const control = runtimeCore(raw).publicationControl;
const memory = Object.freeze({retainedBytes: 4 * 1024 * 1024, executionBytes: 4 * 1024 * 1024});
function owner(requestMemory = memory) {
  const parents = [], calls = {begin: 0, prepare: 0, grow: 0, close: 0};
  const runtime = Object.freeze({...raw,
    clientProgramBeginRequestPreparation(...args) {
      calls.begin++;
      const result = Reflect.apply(raw.clientProgramBeginRequestPreparation, raw, args);
      if (runtimeIsOk(result)) parents.push(runtimeField(result, 0));
      return result;
    },
    clientProgramReserveRequestResultRead(...args) {
      calls.prepare++;
      return Reflect.apply(raw.clientProgramReserveRequestResultRead, raw, args);
    },
    clientProgramGrowRequestResultReadRow(...args) {
      calls.grow++;
      return Reflect.apply(raw.clientProgramGrowRequestResultReadRow, raw, args);
    },
    clientProgramAbortRequestPreparation(...args) {
      calls.close++;
      return Reflect.apply(raw.clientProgramAbortRequestPreparation, raw, args);
    },
  });
  const workspace = createLocalResultReadWorkspace({runtime, requestMemory, assertCurrent() {}});
  const reserved = parent => {
    const actual = raw.clientProgramRequestPreparationAccounting(parent);
    return [runtimeField(actual, 0), runtimeField(actual, 1)];
  };
  return {workspace, parents, calls, reserved};
}
const hash = text => createHash('sha256').update(text).digest('hex');
const rows = Array(1000).fill('{"value":7}');
const expected = '[' + Array(1000).fill('{"value":7}').join(',') + ']';

for (const [format, wire] of [
  ['json', expected], ['jsonl', '{"value":7}\n'.repeat(1000)], ['csv', '"value"\n' + '7\n'.repeat(1000)],
]) test(`actual READ parent batches ${format} with independent bytes/hash and stable outgoing aliases`, async () => {
  const o = owner(), f = createResultDeliveryFixture(access, control, {rows, maxBytes: 16384, format, readWorkspace: o.workspace});
  const retained = [], originals = [];
  const result = await f.deliver({async write(bytes) {
    retained.push(bytes); originals.push(Buffer.from(bytes));
    return {confirmedBytes: bytes.byteLength};
  }, async finish() {return {confirmed: true};}});
  assert.equal(Buffer.concat(retained).toString(), wire);
  assert.equal(result.sha256, hash(wire));
  assert.equal(result.byteCount, Buffer.byteLength(wire));
  retained.forEach((bytes, n) => assert.deepEqual(Buffer.from(bytes), originals[n]));
  // Independent authored geometry: JSON is header + three <=4096 row batches + tail;
  // JSONL is three row batches; CSV header + one row batch.
  assert.equal(retained.length, format === 'json' ? 5 : format === 'jsonl' ? 3 : 2);
  assert.equal(o.calls.begin, 1); assert.equal(o.calls.prepare, 1);
  assert.equal(o.calls.grow, 1, 'one row high-water, no per-row Resource/Graph check');
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
  assert.deepEqual(await o.workspace.closeAll(), {pending: false});
});

test('actual bounded writes reobserve changed Account at callbacks rather than every staged row', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'actql-read-batches-'));t.after(() => rm(dir, {recursive: true, force: true}));
  const accountConfig = join(dir, 'account.json');
  const configuration = outcome => sourceReadAccountConfiguration({connection: 'local-mock', resource: 'result/answer', outcome});
  await writeFile(accountConfig, configuration('allow'));
  const authorize = createLocalResultAuthorization({moon: raw, authorization: {accountConfig, siteKey: 'local-mock'},
    principalId: 'principal', namespaceId: 'namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`});
  const original = fs.openSync;let opens = 0;
  fs.openSync = function(path, ...args) {if (path === accountConfig) opens++;return Reflect.apply(original, this, [path, ...args]);};
  syncBuiltinESMExports();
  try {
    const o = owner(), f = createResultDeliveryFixture(access, control, {rows, maxBytes: 16384, authorize, readWorkspace: o.workspace});
    await f.deliver();
    assert.equal(f.state.chunks.length, 5);
    assert.equal(opens, 7, 'request plus five actual writes and one finish boundary');
    assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
    const denied = owner();let callbacks = 0;
    const d = createResultDeliveryFixture(access, control, {rows, maxBytes: 16384, authorize, readWorkspace: denied.workspace,
      async afterWrite() {if (++callbacks === 2) await writeFile(accountConfig, configuration('deny'));}});
    await assert.rejects(d.deliver(), {code: 'ResultDeliveryDenied'});
    assert.equal(callbacks, 2);assert.equal(d.state.chunks.length, 2);
    assert.equal(d.state.finishes, 0);
    assert.equal(JSON.parse(d.state.record.wire).state, 'failed');
    assert.deepEqual(denied.reserved(denied.parents[0]), [0n, 0n]);
  } finally {fs.openSync = original;syncBuiltinESMExports();}
});

test('equal Result DATA has distinct concurrent READ parents and failed physical cleanup retains its original', async () => {
  const o = owner(), first = Object.freeze({result: 'same', attempt: 'one'}), second = Object.freeze({result: 'same', attempt: 'two'});
  const metadata = Object.freeze({payloadBytes: 1000, resultSchemaWire: '{"value":{"type":"integer","nullable":false}}', resultFields: ['value']});
  const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64}, frames = {maxRowBytes: 4096, maxFrameBytes: 4096, maxDepth: 32};
  o.workspace.begin(first);o.workspace.begin(second);
  o.workspace.prepare(first, metadata, limits, frames);o.workspace.prepare(second, metadata, limits, frames);
  assert.notEqual(o.parents[0], o.parents[1]);
  const a = o.reserved(o.parents[0]), b = o.reserved(o.parents[1]);
  assert(a[0] > 0n && b[0] > 0n && a[0] + b[0] > a[0]);
  o.workspace.close(first);
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);assert.deepEqual(o.reserved(o.parents[1]), b);
  let pending = true, retries = 0;
  const failure = Object.assign(new Error('original failed FD'), {cleanupPending: true,
    cleanupHandle: Object.freeze({status: () => ({pending}), async retry() {retries++;return {pending};}})});
  o.workspace.close(second, failure);
  assert.deepEqual(o.reserved(o.parents[1]), b);
  assert.deepEqual(await o.workspace.closeAll(), {pending: true});assert.equal(retries, 1);
  pending = false;
  assert.deepEqual(await o.workspace.closeAll(), {pending: false});
  assert.deepEqual(o.reserved(o.parents[1]), [0n, 0n]);
  assert.equal(retries, 1, 'already acknowledged original cleanup is not repeated');
});

test('actual READ capacity refusal precedes output without an unfunded fallback', async () => {
  const o = owner(Object.freeze({retainedBytes: 50000, executionBytes: 1024}));
  const f = createResultDeliveryFixture(access, control, {rows, maxBytes: 16384, readWorkspace: o.workspace});
  await assert.rejects(f.deliver());
  assert.deepEqual(f.state.chunks, []);assert.equal(f.state.finishes, 0);
  assert.equal(o.calls.prepare, 1);
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
});

for (const kind of ['partial', 'cancel', 'expiry']) test(`funded batch ${kind} keeps actual prefix and never issues success`, async () => {
  const o = owner(), f = createResultDeliveryFixture(access, control, {rows, maxBytes: 16384, readWorkspace: o.workspace});
  let writes = 0;const controller = new AbortController();
  await assert.rejects(f.deliver({async write(bytes) {
    writes++;
    if (writes === 2) {
      assert.equal(bytes.byteLength, 4091);
      if (kind === 'partial') throw Object.assign(new Error('original short sink write'), {
        deliveryProgress: {confirmedBytes: 3, exposure: 'unknown_additional', possibleUnconfirmedMaxBytes: 4088}});
      if (kind === 'cancel') controller.abort(new Error('original cancellation'));
      if (kind === 'expiry') f.state.now = '2026-10-03T00:00:00.000Z';
    }
    return {confirmedBytes: bytes.byteLength};
  }, async finish() {assert.fail('failed/cancelled batch cannot finish');}}, controller.signal));
  assert.equal(writes, 2);
  const terminal = JSON.parse(f.state.record.wire);
  assert.equal(terminal.state, kind === 'cancel' ? 'cancelled' : 'failed');
  assert.equal(Object.hasOwn(terminal, 'result_delivery_receipt_cid'), false);
  if (kind === 'partial') {
    assert.equal(terminal.confirmed_byte_count, 4);
    assert.equal(terminal.exposure, 'unknown_additional');
    assert.equal(terminal.possible_unconfirmed_max_bytes, 4088);
  }
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
});

test('funded empty and oversized single-row output preserve original canonical bytes', async () => {
  for (const selected of [[], ['{"value":9007199254740991}', '{"value":7}']]) {
    const o = owner(), f = createResultDeliveryFixture(access, control, {rows: selected, readWorkspace: o.workspace,
      frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 16}});
    const result = await f.deliver();
    const wire = '[' + selected.join(',') + ']';
    assert.equal(f.state.chunks.join(''), wire);assert.equal(result.sha256, hash(wire));
    assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
  }
});

test('record durability and original physical read cleanup both retain the SAME actual READ capacity', async () => {
  const {ResultDeliveryError} = await import('../host-common/result-delivery.mjs');
  const o = owner(), request = Object.freeze({result: 'same', attempt: 'original'});
  o.workspace.begin(request);
  o.workspace.prepare(request, {payloadBytes: 1000, resultSchemaWire: '{"value":{"type":"integer","nullable":false}}', resultFields: ['value']},
    {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64}, {maxRowBytes: 4096, maxFrameBytes: 4096, maxDepth: 32});
  const before = o.reserved(o.parents[0]);
  let recordPending = true, readerPending = true, records = 0, readers = 0;
  const physical = Object.assign(new Error('original FD close'), {cleanupPending: true,
    cleanupHandle: Object.freeze({status: () => ({pending: readerPending}), async retry() {readers++;return {pending: readerPending};}})});
  const failure = Object.assign(new ResultDeliveryError('ResultDeliveryFailed', physical), {cleanupPending: true,
    cleanupHandle: Object.freeze({status: () => ({pending: recordPending}), async retry() {records++;recordPending = false;return {pending: false};}})});
  o.workspace.close(request, failure);
  assert.deepEqual(await o.workspace.closeAll(), {pending: true});
  assert.equal(records, 1);assert.equal(readers, 1);
  assert.deepEqual(o.reserved(o.parents[0]), before, 'record ACK is not the original FD close ACK');
  assert.equal(failure.primaryFailure, physical);
  readerPending = false;
  assert.deepEqual(await o.workspace.closeAll(), {pending: false});
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
  assert.equal(records, 1);assert.equal(readers, 1);
});

test('failed original cleanup status observation never returns READ backing early', async () => {
  const o = owner(), request = Object.freeze({result: 'same', attempt: 'status-failure'});
  o.workspace.begin(request);
  let failed = true;
  const cause = Object.assign(new Error('original physical cleanup'), {cleanupPending: true,
    cleanupHandle: Object.freeze({status() {if (failed) throw new Error('original getter');return {pending: false};},
      async retry() {return {pending: true};}})});
  o.workspace.close(request, cause);
  const before = o.reserved(o.parents[0]);assert(before[0] > 0n);
  assert.deepEqual(await o.workspace.closeAll(), {pending: true});
  assert.deepEqual(o.reserved(o.parents[0]), before);
  failed = false;
  assert.deepEqual(await o.workspace.closeAll(), {pending: false});
  assert.deepEqual(o.reserved(o.parents[0]), [0n, 0n]);
});

test('normal installed Result caller captures SAME policy and uses its actual READ Request adapter', async () => {
  const {parse} = await import('acorn');
  const source = fs.readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const methods = [], calls = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.method && node.key.name === 'resultReadWorkspace') methods.push(node);
    if (node.type === 'CallExpression' && node.callee.name === 'installNodeResultAccessService') calls.push(node);
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child !== null && typeof child === 'object') visit(child);
  }
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(methods.length, 1);assert.equal(calls.length, 1);
  const forwarded = calls[0].arguments[0].properties.find(p => p.type === 'SpreadElement' &&
    source.slice(p.start, p.end).includes('readWorkspace: preparation.resultReadWorkspace(moon)'));
  assert(forwarded, 'the standard installed constructor forwards its original fixed preparation');
  const originals = {}, installation = {requestMemory: memory};let captured, initial = 0, current = 0;
  const factory = new Function('createLocalResultReadWorkspace', 'assertInitialControlHostPreparation',
    'clientOperationError', 'assertRetainedSourceManagedHost', 'originals', 'originalInstallation', 'moon',
    `let resultReadWorkspace; return ({${source.slice(methods[0].start, methods[0].end)}}).resultReadWorkspace;`);
  const actual = factory(options => {captured = options;return createLocalResultReadWorkspace(options);},
    value => {assert.equal(value, originals);initial++;}, code => Object.assign(new Error(code), {code}),
    value => {assert.equal(value, originals);current++;}, originals, installation, raw);
  const workspace = actual(raw);assert.equal(actual(raw), workspace);
  assert.equal(captured.runtime, raw);assert.equal(captured.requestMemory, memory);
  assert.throws(() => actual({}), {code: 'ForeignInstalledHostPreparation'});
  const request = Object.freeze({result: 'same', attempt: 'actual-caller'});
  workspace.begin(request);
  workspace.prepare(request, {payloadBytes: 20, resultSchemaWire: '{"value":{"type":"integer","nullable":false}}', resultFields: ['value']},
    {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64}, {maxRowBytes: 4096, maxFrameBytes: 4096, maxDepth: 32});
  workspace.row(request, 11);workspace.close(request);
  assert.deepEqual(await workspace.closeAll(), {pending: false});assert(initial >= 2 && current > 0);
});
