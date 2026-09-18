import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {
  storeCompletedOutputPayload,
  storeCompletedResultPayload,
  storeCompletedResultPublicationPayload,
} from './durable-result-payload.mjs';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const cid = digit => `sha256:${digit.repeat(64)}`;
const defaultSchemaWire =
  '{"answer":{"nullable":false,"type":"integer"}}';
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
      const resultSchemaWire = hooks.schemaWire ?? defaultSchemaWire;
      return Object.freeze({
        orderedRowsCid: hooks.cid ?? digest(text),
        logicalRelationCid: hooks.logicalCid ??
          digest(`{"sort":"relation","value":${text}}`),
        resultSchemaCid: hooks.schemaCid ?? digest(resultSchemaWire),
        resultSchemaWire,
        resultFields: hooks.resultFields ?? ['answer'],
        codecContractCid: hooks.codecCid ?? cid('d'),
        bytes: Buffer.byteLength(text),
        nodes: 7,
        rows: 2,
        schemaBytes: Buffer.byteLength(resultSchemaWire),
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

test('Result evidence is issued before its durable payload becomes visible',
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
    const evidenceContext = Object.freeze({context: true});
    const publicationLimits = Object.freeze({
      maxWireBytes: 4096, maxNodes: 100, maxDepth: 10,
    });
    const events = [];
    const evidence = Object.freeze({derivation: {}, ordering: {}});
    const artifact = Object.freeze({name: 'result_artifact'});
    const snapshot = Object.freeze({kind: 'captured-result-snapshot'});
    const durableBinding = Object.freeze({name: 'durable_result_binding'});
    const publicationControl = Object.freeze({
      issueResultArtifact(handle, invocation, retention, supplied) {
        assert.deepEqual(handle, {});
        assert.equal(invocation, 'invocation');
        assert.equal(retention, 'retention');
        assert.equal(supplied, publicationLimits);
        events.push('artifact');
        return artifact;
      },
      admitCompletedResultSnapshot(handle, supplied) {
        assert.deepEqual(handle, {});
        assert.equal(supplied, publicationLimits);
        events.push('snapshot');
        return snapshot;
      },
      issueDurableResultBinding(chain, physical, supplied) {
        assert.equal(chain.runDefinition, 'run-definition');
        assert.equal(chain.definition, 'result-definition');
        assert.equal(chain.invocation, 'invocation');
        assert.equal(chain.artifact, artifact);
        assert.equal(chain.ordering, evidence.ordering);
        assert.equal(chain.retention, 'retention');
        assert.deepEqual(physical, {
          codecContractCid: cid('d'),
          resultFields: ['answer'],
          resultSchemaWire: defaultSchemaWire,
          materialGenerationCid: digest(text),
          storeAuthorityCid: cid('a'),
          rowCount: 2,
          byteCount: Buffer.byteLength(text),
          physicalSha256: digest(text).slice('sha256:'.length),
        });
        assert.equal(supplied, publicationLimits);
        events.push('binding');
        return durableBinding;
      },
    });
    const publication = Object.freeze({
      control: publicationControl,
      runDefinition: 'run-definition',
      definition: 'result-definition',
      evidenceContext,
      limits: publicationLimits,
      invocation: 'invocation',
      retention: 'retention',
    });
    const control = {
      ...exportFixture([text], text, {
        cancelled: () => events.push('cancel'),
      }),
      beginResult(actualHost, result, supplied) {
        assert.equal(actualHost, host);
        assert.equal(result, 0);
        assert.equal(supplied, resultLimits);
        return {};
      },
      issueResultEvidence(handle, context, supplied) {
        assert.deepEqual(handle, {});
        assert.equal(context, evidenceContext);
        assert.equal(supplied, publicationLimits);
        events.push('evidence');
        return evidence;
      },
    };
    const stored = await storeCompletedResultPublicationPayload(
      store,
      control,
      host,
      0,
      resultLimits,
      publication,
    );
    assert.equal(stored.publication.derivation, evidence.derivation);
    assert.equal(stored.publication.ordering, evidence.ordering);
    assert.equal(stored.publication.artifact, artifact);
    assert.equal(stored.publication.snapshot, snapshot);
    assert.equal(stored.publication.durableBinding, durableBinding);
    assert.equal(stored.schema.semanticCid, digest(defaultSchemaWire));
    assert.deepEqual(events,
      ['evidence', 'artifact', 'snapshot', 'binding', 'cancel']);
    assert.equal(stored.prepared.status().pending, true);

    const failing = {
      ...control,
      issueResultEvidence() { throw new Error('evidence rejected'); },
    };
    await assert.rejects(
      storeCompletedResultPublicationPayload(
        store,
        failing,
        host,
        0,
        resultLimits,
        publication,
      ),
      error => error.code === 'DurableResultPayloadFailed' &&
        error.primaryFailure?.message === 'evidence rejected',
    );
    assert.equal(store.status().objectCount, 2);
    assert.equal(store.status().reservedBytes, 0);
    assert.equal(store.status().reservedObjects, 0);
    assert.equal(await stored.prepared.release(), true);
    assert.equal(stored.prepared.status().pending, false);
    assert.equal(store.status().objectCount, 1);
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
        resultSchemaCid: digest(defaultSchemaWire),
        resultSchemaWire: defaultSchemaWire,
        resultFields: ['answer'],
        codecContractCid: cid('d'),
        bytes: Buffer.byteLength(text), nodes: 7, rows: 2,
        schemaBytes: Buffer.byteLength(defaultSchemaWire),
        schemaNodes: 8, schemaFields: 1},
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
          ? error => error.code === 'DurableResultPayloadFailed' &&
            error.primaryFailure?.code ===
              'PublicationObjectIdentityMismatch'
          : error => error.code === 'DurableResultPayloadFailed' &&
            error.primaryFailure?.name === 'AbortError',
      );
      assert.equal(cancelled, 1);
      assert.equal(store.status().storedBytes, 0);
      assert.equal(store.status().objectCount, 0);
      assert.equal(store.status().reservedBytes, 0);
      assert.equal(store.status().reservedObjects, 0);
    }
  });

test('immutable and primitive failures retain every cleanup owner', async () => {
  const primaries = [
    Object.freeze(new Error('frozen')),
    Object.seal(new Error('sealed')),
    null,
    false,
    'failure',
  ];
  for (const primary of primaries) {
    let reservationHeld = true;
    let writerCancels = 0;
    let exportCancels = 0;
    const writerFailure = new Error('writer cancel failed');
    const exportFailure = new Error('export cancel failed');
    const writer = Object.freeze({
      append() { throw new Error('unexpected append'); },
      seal() { throw new Error('unexpected seal'); },
      status: () => Object.freeze({reservationHeld}),
      async cancel() {
        writerCancels++;
        if (writerCancels === 1) throw writerFailure;
        reservationHeld = false;
        return true;
      },
    });
    const store = Object.freeze({
      createObjectWriter() { return writer; },
    });
    const control = Object.freeze({
      begin() { return {}; },
      next() { throw primary; },
      finish() { throw new Error('unexpected finish'); },
      identity() { throw new Error('unexpected identity'); },
      cancel() {
        exportCancels++;
        if (exportCancels === 1) throw exportFailure;
      },
    });
    let failure;
    try {
      await storeCompletedOutputPayload(store, control, {}, limits);
      assert.fail('payload export must fail');
    } catch (error) {
      failure = error;
    }
    assert.equal(failure.code, 'DurableResultPayloadFailed');
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cause, primary);
    assert.equal(failure.cleanupPending, true);
    assert.deepEqual(failure.cleanupErrors, [writerFailure, exportFailure]);
    assert.equal(failure.cleanupHandle.status().pending, true);
    const retried = await failure.cleanupHandle.retry();
    assert.equal(retried.pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal(reservationHeld, false);
    assert.equal(writerCancels, 2);
    assert.equal(exportCancels, 2);
    await failure.cleanupHandle.retry();
    assert.equal(writerCancels, 2);
    assert.equal(exportCancels, 2);
  }
});
