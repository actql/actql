import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import * as hostPolicy from './installed-host-policy.mjs';
import {createResultFactory} from '../../packages/sdk/internal/result-read.mjs';

// Execute the actual Host negotiation expression and SDK reader. Common policy
// accessors and typed delivery are explicit ports, not a Task/Store substitute.
const source = await readFile(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const declarations = [];
function visit(value) {
  if (value === null || typeof value !== 'object') return;
  if (value.type === 'VariableDeclarator' && value.id.name === 'resultReadLimits') declarations.push(value.init);
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child !== null && typeof child === 'object') visit(child);
  }
}
visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
assert.equal(declarations.length, 1);
function negotiated({retained = 536870912n, rows = 2097152, transfer = 100000000000n, requestMemory} = {}) {
  const original = Object.freeze({});
  const moon = {
    clientLocalResourcePolicyOriginal: () => original,
    clientLocalPreparationResourceLimits(value, selectedRetained, selectedExecution) {
      assert.equal(value, original);
      assert.equal(selectedRetained, requestMemory === undefined ? undefined : BigInt(requestMemory.retainedBytes));
      assert.equal(selectedExecution, requestMemory === undefined ? undefined : BigInt(requestMemory.executionBytes));
      return [100000n, 100000n, 100000n, transfer, selectedRetained ?? retained, selectedExecution ?? retained];
    },
    clientLocalResourcePolicyRowCeiling(value) {assert.equal(value, original); return rows;},
  };
  const node = declarations[0];
  return Function('moon', 'localResourceResultReadLimits', 'requestMemory', `return (${source.slice(node.start, node.end)});`)(
    moon, hostPolicy.localResourceResultReadLimits, requestMemory);
}
const ref = Object.freeze({namespaceId: 'collection-fixture',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`, runDefinitionCid: `sha256:${'b'.repeat(64)}`});
function delivered(count, {limits = negotiated(), row = n => ({n})} = {}) {
  const stats = {opened: 0, pulled: 0, returned: 0, closed: 0};
  const activeReaders = new Set(), readerCleanups = new Set();
  const factory = createResultFactory({ref, limits, typedRows: true, lookupContext: {}}, {
    async runRequest(operation, _body, signal) {
      assert.equal(operation, 'read'); stats.opened++;
      return {kind: 'rows', frames: {
        async *[Symbol.asyncIterator]() {
          try {
            for (let n = 0; n < count; n++) {
              signal.throwIfAborted();
              const value = row(n); stats.pulled++;
              yield {value, byteLength: Buffer.byteLength(JSON.stringify(value))};
            }
          } finally {stats.returned++;}
        },
      }, async close() {stats.closed++;}};
    }, responseValue: value => value,
  }, {activeReaders, readerCleanups}, () => undefined);
  return {result: factory('answer'), stats, activeReaders, readerCleanups};
}
function closed(f) {
  assert.equal(f.stats.returned, 1); assert.equal(f.stats.closed, 1);
  assert.equal(f.activeReaders.size, 0); assert.equal(f.readerCleanups.size, 0);
}

test('collection negotiation borrows the same Task policy and narrows byte ceilings', () => {
  const standard = negotiated();
  assert.equal(standard.maxRows, 2097152);
  assert.equal(standard.maxRetainedValueBytes, 536870912);
  assert.equal(standard.maxReadWireBytes, 10 * 1024 * 1024);
  assert.equal(standard.maxRowWireBytes, 1024 * 1024);
  assert.equal(standard.maxBatchRows, 1000);
  const small = negotiated({retained: 8192n, rows: 32, transfer: 4096n});
  assert.equal(small.maxRows, 32); assert.equal(small.maxRetainedValueBytes, 8192);
  assert.equal(small.maxReadWireBytes, 4096);
  assert.equal(small.maxRowWireBytes, 4096);
  assert.equal(small.maxRowRetainedValueBytes, 8192);
  assert.equal(small.maxBatchRetainedValueBytes, 8192);
});

test('collection initializer forwards omitted small and large memory pairs to the same Core port', () => {
  for (const requestMemory of [undefined,
    {retainedBytes: 8192, executionBytes: 16384},
    {retainedBytes: 1073741824, executionBytes: 2147483648}]) {
    const actual = negotiated({requestMemory});
    assert.equal(actual.maxRetainedValueBytes, requestMemory?.retainedBytes ?? 536870912);
  }
});

for (const count of [9999, 10000, 10001, 100000]) {
  test(`collection reads all ${count} independent small rows within the actual selected budget`, async () => {
    const f = delivered(count);
    const rows = await (count === 10001 ? f.result.all({maxRows: count}) : f.result.all());
    assert.equal(rows.length, count);
    for (let n = 0; n < count; n++) assert.deepEqual(rows[n], {n});
    assert.equal(f.stats.pulled, count); closed(f);
  });
}

test('collection accepts a larger caller ceiling for one row without enlarging the Host budget', async () => {
  const f = delivered(1);
  assert.deepEqual(await f.result.all({maxRows: 10001}), [{n: 0}]); closed(f);
  const g = delivered(1), limits = negotiated();
  await assert.rejects(g.result.all({maxRows: limits.maxRows + 1}), {code: 'InvalidReadLimit'});
  await assert.rejects(g.result.all({maxRetainedValueBytes: limits.maxRetainedValueBytes + 1}), {code: 'InvalidReadLimit'});
  assert.equal(g.stats.opened, 0);
});

test('collection preserves a smaller caller row limit and its first cleanup', async () => {
  const f = delivered(10001);
  await assert.rejects(f.result.all({maxRows: 7}), {code: 'ResultRetainedLimit'});
  assert.equal(f.stats.pulled, 8); closed(f);
});

test('collection preserves wire, per-row decoded and raw-before-validator byte protection', async () => {
  const wire = delivered(3);
  await assert.rejects(wire.result.all({maxWireBytes: 20}), {code: 'ResultWireLimit'}); closed(wire);
  const huge = delivered(1, {row: () => ({cells: new Array(20000).fill(0)})});
  await assert.rejects(huge.result.all(), {code: 'ResultRowRetainedLimit'}); closed(huge);
  let validated = 0;
  const raw = delivered(2, {row: () => ({text: 'x'.repeat(300)})});
  const schema = {'~standard': {version: 1, vendor: 'test', validate(value) {
    validated++; delete value.text; return {value: null};
  }}};
  await assert.rejects(raw.result.all(schema, {maxRetainedValueBytes: 600}), {code: 'ResultRetainedLimit'});
  assert.equal(validated, 1); closed(raw);
});

test('collection byte ceiling does not become a total row or batch stream ceiling', async () => {
  const limits = negotiated({retained: 2048n, rows: 8});
  for (const kind of ['rows', 'batches']) {
    const f = delivered(100, {limits}); let n = 0;
    for await (const value of f.result[kind]()) {
      for (const row of kind === 'rows' ? [value] : value) assert.deepEqual(row, {n: n++});
    }
    assert.equal(n, 100); closed(f);
  }
});

test('collection policy keeps early break and cancel on the same original reader', async () => {
  const f = delivered(10001);
  for await (const row of f.result.rows()) {assert.deepEqual(row, {n: 0}); break;}
  assert.equal(f.stats.pulled, 1); closed(f);
  const g = delivered(10001), controller = new AbortController();
  const reason = new Error('caller cancellation');
  const schema = {'~standard': {version: 1, vendor: 'test', validate(row) {
    controller.abort(reason); return {value: row};
  }}};
  await assert.rejects(g.result.all(schema, {signal: controller.signal}));
  assert.equal(g.stats.pulled, 1); closed(g);
});
