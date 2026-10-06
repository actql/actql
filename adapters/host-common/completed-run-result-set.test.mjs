import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {releaseCompletedRunPreparedPayloads, storeCompletedRunResultSet} from
  './completed-run-publication.mjs';
import {runtimeCore} from './runtime-core.mjs';

const contract = identity => ({name: 'result_definition', identity,
  wire: '{}'});
const cid = digit => `sha256:${digit.repeat(64)}`;
const result = (name, task, definition, prepared) => ({
  occurrence: {name, task, definition},
  publication: {
    artifact: contract(cid('a')),
    derivation: contract(cid('b')),
    ordering: contract(cid('c')),
    durableBinding: contract(cid('d')),
    snapshot: {},
  },
  prepared,
});

test('a later export failure releases every earlier prepared Result',
  async () => {
    let released = 0;
    let pending = true;
    const definition = contract(cid('1'));
    const prepared = {
      status: () => ({pending}),
      async release() { released++; pending = false; },
    };
    const execution = {
      status: 'host-tasks-completed',
      resultInventory: [{name: 'first'}, {name: 'second'}],
      publicationInventory: {occurrences: [
        {name: 'first', task: 0, definitionContract: definition},
        {name: 'second', task: 1, definitionContract: definition},
      ]},
      async storePublicationResult(index) {
        if (index === 0) return result('first', 0, definition, prepared);
        throw new Error('SecondExportFailed');
      },
    };
    await assert.rejects(storeCompletedRunResultSet({
      execution, store: {}, control: runtimeCore(moon).publicationControl,
      runDefinition: contract(cid('2')),
      invocation: contract(cid('3')),
      results: [
        {retention: contract(cid('4')), evidenceContext: {}},
        {retention: contract(cid('4')), evidenceContext: {}},
      ],
      outputLimits: {}, contractLimits: {},
    }), {message: 'SecondExportFailed'});
    assert.equal(released, 1);
    assert.equal(pending, false);
  });

test('a foreign export cannot strand its prepared payload', async () => {
  let pending = true;
  const definition = contract(cid('1'));
  const execution = {
    status: 'host-tasks-completed',
    resultInventory: [{name: 'expected'}],
    publicationInventory: {occurrences: [
      {name: 'expected', task: 0, definitionContract: definition},
    ]},
    async storePublicationResult() {
      return result('foreign', 0, definition, {
        status: () => ({pending}),
        async release() { pending = false; },
      });
    },
  };
  await assert.rejects(storeCompletedRunResultSet({
    execution, store: {}, control: runtimeCore(moon).publicationControl,
    runDefinition: contract(cid('2')),
    invocation: contract(cid('3')),
    results: [{retention: contract(cid('4')), evidenceContext: {}}],
    outputLimits: {}, contractLimits: {},
  }), {code: 'InvalidCompletedRunPublicationExport'});
  assert.equal(pending, false);
});

test('explicit prepared release is single-flight and retryable', async () => {
  const definition = contract(cid('1'));
  const control = runtimeCore(moon).publicationControl;
  const limits = {maxWireBytes: 4096, maxNodes: 128, maxDepth: 8};
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('b'), effective_data_policy_cid: cid('a'),
    available_until: '2026-09-27T01:00:00.000Z',
    delete_by: '2026-09-27T02:00:00.000Z',
    extension_ceiling_at: '2026-09-27T03:00:00.000Z',
    metadata_retention_policy_cid: cid('c'),
    metadata_delete_by: '2026-09-27T04:00:00.000Z',
    clock_contract_cid: cid('d'),
  }), limits);
  let pending = true;
  let releases = 0;
  let retries = 0;
  let failRelease = true;
  let custodyRetirements = 0;
  const prepared = {
    status: () => ({pending}),
    async release() {
      releases++;
      if (failRelease) throw new Error('EIO');
      pending = false;
    },
    async retry() {
      retries++;
      failRelease = false;
      pending = false;
    },
  };
  const execution = {
    status: 'host-tasks-completed',
    resultInventory: [{name: 'first'}],
    publicationInventory: {occurrences: [
      {name: 'first', task: 0, definitionContract: definition},
    ]},
    async storePublicationResult() {
      return result('first', 0, definition, prepared);
    },
  };
  const stored = await storeCompletedRunResultSet({
    execution, store: {async retireEffectCaptureCustody(run) {
      assert.equal(run.identity, cid('2'));
      assert.equal(pending, false, 'payload release precedes capture retirement');
      custodyRetirements++;
      return false;
    }}, control,
    runDefinition: contract(cid('2')), invocation: contract(cid('3')),
    results: [{retention, evidenceContext: {}}],
    outputLimits: {}, contractLimits: limits,
  });
  const first = releaseCompletedRunPreparedPayloads(stored, control);
  const joined = releaseCompletedRunPreparedPayloads(stored, control);
  assert.equal(first, joined);
  await assert.rejects(first, {cleanupPending: true});
  assert.equal(releases, 1);
  assert.equal(pending, true);
  assert.equal(custodyRetirements, 0);
  assert.equal(await releaseCompletedRunPreparedPayloads(stored, control), true);
  assert.equal(retries, 1);
  assert.equal(pending, false);
  assert.equal(custodyRetirements, 1);
  assert.equal(await releaseCompletedRunPreparedPayloads(stored, control), false);
  assert.equal(releases, 1);
  assert.equal(custodyRetirements, 1);
  assert.throws(() => releaseCompletedRunPreparedPayloads(stored, {}),
    {code: 'InvalidCompletedRunResultSetOwner'});
});
