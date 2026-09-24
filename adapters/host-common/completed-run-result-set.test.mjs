import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {storeCompletedRunResultSet} from './completed-run-publication.mjs';
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
