import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {
  storeCompletedOutputPayload,
  storeCompletedResultPayload,
} from './durable-result-payload.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = Object.freeze({
  maxRows: 10,
  maxValueNodes: 100,
  maxValueTextBytes: 4096,
  maxValueDepth: 10,
  maxValueWork: 8192,
  maxWireBytes: 4096,
  maxWireNodes: 100,
  maxWireDepth: 10,
  maxColumns: 10,
  maxOrderWork: 100,
  maxLogicalWireBytes: 8192,
  maxLogicalWireNodes: 103,
  maxLogicalWireDepth: 12,
  maxSchemaFields: 10,
  maxSchemaBytes: 4096,
  maxSchemaNodes: 100,
  maxSchemaDepth: 10,
  maxBatchBytes: 32,
});
const unusedContractControl = Object.freeze({
  admit() { throw new Error('unexpected semantic admission'); },
  recordTransition() { throw new Error('unexpected record transition'); },
  recordAllowsCommit() { throw new Error('unexpected commit check'); },
  effectFreeCommitValid() { throw new Error('unexpected chain check'); },
});

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-payload-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const store = await openLocalPublicationStore({
    directory,
    storeAuthorityCid: cid('a'),
    capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024,
    maxObjects: 100,
    maxContractNodes: 1000,
    maxContractDepth: 64,
  }, unusedContractControl);
  t.after(async () => { await store.close(); });
  return store;
}

function exportFixture(parts, text, hooks = {}) {
  let index = 0;
  return Object.freeze({
    begin(output, supplied) {
      assert.equal(output, hooks.output);
      assert.equal(supplied, limits);
      return {};
    },
    next() {
      hooks.next?.(index);
      return index < parts.length ? parts[index++] : undefined;
    },
    finish() { return hooks.tail ?? ''; },
    identity() {
      return Object.freeze({
        orderedRowsCid: hooks.cid ?? digest(text),
        logicalRelationCid: hooks.logicalCid ??
          digest(`{"sort":"relation","value":${text}}`),
        resultSchemaCid: hooks.schemaCid ?? cid('c'),
        bytes: Buffer.byteLength(text),
        nodes: 7,
        rows: 2,
        schemaBytes: 64,
        schemaNodes: 8,
        schemaFields: 1,
      });
    },
    cancel() { hooks.cancelled?.(); },
  });
}

test('exact Result occurrence streams through the same bounded Store path',
  async t => {
    const store = await fixture(t);
    const host = {};
    const text = '[{"answer":1}]';
    const resultLimits = Object.freeze({
      maxResultFields: 10,
      maxResultMappingWork: 100,
      maxResultOrderWork: 100,
      maxResultWorkspaceEntries: 10,
      ...limits,
    });
    const control = {
      ...exportFixture([text], text, {}),
      beginResult(actualHost, result, supplied) {
        assert.equal(actualHost, host);
        assert.equal(result, 2);
        assert.equal(supplied, resultLimits);
        return {};
      },
    };
    const stored = await storeCompletedResultPayload(
      store, control, host, 2, resultLimits,
    );
    assert.equal(stored.physical.cid, digest(text));
    assert.equal(stored.orderedRows.orderedRowsCid, digest(text));
  });

test('canonical batches stream to one durable object without whole-array input',
  async t => {
    const store = await fixture(t);
    const output = {};
    const text = '[{"a":1},{"a":"é😀"}]';
    const parts = ['[{"a":1}', ',{"a":"é', '😀"}'];
    let cancelled = 0;
    const result = await storeCompletedOutputPayload(
      store,
      exportFixture(parts, text, {
        output,
        tail: ']',
        cancelled: () => { cancelled++; },
      }),
      output,
      limits,
    );
    assert.deepEqual(result, {
      physical: {cid: digest(text), bytes: Buffer.byteLength(text),
        created: true},
      orderedRows: {orderedRowsCid: digest(text),
        logicalRelationCid:
          'sha256:5b3aeccd9ebf1cf22f64ef2357114e647d1daac6fbb7957e30a3e3043d7254d1',
        resultSchemaCid: cid('c'),
        bytes: Buffer.byteLength(text), nodes: 7, rows: 2,
        schemaBytes: 64, schemaNodes: 8, schemaFields: 1},
    });
    assert.equal(cancelled, 1, 'the export receipt releases its source');
    const bytes = [];
    await store.consumeObject(result.physical.cid,
      chunk => bytes.push(Buffer.from(chunk)));
    assert.equal(Buffer.concat(bytes).toString('utf8'), text);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
  });

test('identity mismatch and cancellation cannot leave a sealed object',
  async t => {
    for (const mode of ['identity', 'cancel']) {
      const store = await fixture(t);
      const output = {};
      const text = '[{"a":1},{"a":2}]';
      const controller = new AbortController();
      let cancelled = 0;
      const control = exportFixture(['[{"a":1}', ',{"a":2}'], text, {
        output,
        tail: ']',
        cid: mode === 'identity' ? cid('f') : undefined,
        next: index => {
          if (mode === 'cancel' && index === 1) controller.abort();
        },
        cancelled: () => { cancelled++; },
      });
      await assert.rejects(
        storeCompletedOutputPayload(
          store, control, output, limits, controller.signal,
        ),
        mode === 'identity'
          ? error => error.code === 'PublicationObjectIdentityMismatch'
          : error => error.name === 'AbortError',
      );
      assert.equal(cancelled, 1);
      assert.equal(store.status().storedBytes, 0);
      assert.equal(store.status().objectCount, 0);
      assert.equal(store.status().reservedBytes, 0);
      assert.equal(store.status().reservedObjects, 0);
    }
  });
