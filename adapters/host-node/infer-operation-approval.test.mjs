import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';

for (const [name, text] of [['decomposed', 'e\u0301'], ['composed', '\u00e9'],
  ['carriage return', '\r'], ['line feed', '\n']]) {
  test(`Model original Run packaging preserves ${name} data bytes`, () => {
    const wire = JSON.stringify({text});
    const compiled = {template: {wire}, preparedEvidence: {wire},
      authorization: {wire}, compiledPlan: {wire}};
    const actual = JSON.parse(originalModelRunWire(compiled, {wire}));
    assert.deepEqual(actual, {boundInvocationTemplateWire: wire,
      preparedInvocationWire: wire, runAuthorizationWire: wire,
      compiledPlanWire: wire, runDefinitionWire: wire});
    for (const original of Object.values(actual)) {
      assert.equal(JSON.parse(original).text, text);
    }
  });
}

// Adapter lifetime tests. The Core ports are explicit doubles; public Store
// authentication and process restart are covered by the installed acceptance.
function fixture({count = 1, missingSlot = false, missingOwner = false} = {}) {
  const active = {}, inventory = {}, input = {}, artifact = {};
  let stopped = false;
  let advances = 0;
  const moon = {
    clientProgramStartScopedInferExecution: () => ({$tag: 1, _0: active}),
    clientProgramRequireInferCallEntry: owner => {
      assert.equal(owner, active);
      return {$tag: 1, _0: undefined};
    },
    clientProgramAdvanceInferExecution: () => {
      advances++;
      return {$tag: 1, _0: stopped ? 'stopped' : 'waiting'};
    },
    clientProgramInferExecutionPollKind: poll => poll,
    clientProgramInferPreparedCallSet: () => missingOwner ? undefined : inventory,
    clientProgramInferPreparedCallCount: () => count,
    clientProgramInferPreparedInput: () => input,
    clientProgramInferPreparedInputArtifact: () => artifact,
    clientProgramInferPreparedIdentities: () => ({_0: 'models/fixture', _1: 'task', _2: 'request'}),
    clientProgramInferPreparedCallAt: () => missingSlot ? undefined : 'slot',
    strategyRunEvidenceJson: value => value === artifact ? 'artifact' : 'slot',
    clientProgramInferCallScopeUnitId: () => 'input',
    clientProgramInferCallScopeSnapshot: () => ({$tag: 1, _0: 'original-scope'}),
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
  };
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 0,
    graph: {}, registry: '', values: '', fragment: '', ordered: '', provider: {},
    durableCalls: true});
  return {operation, inventory, input, advances: () => advances};
}

test('prepared Waiting leaves the physical driver after one advance', async () => {
  const f = fixture();
  const waiting = await f.operation.run();
  assert.equal(waiting.status, 'waiting');
  assert.equal(waiting.preparedCallSet, f.inventory);
  assert.equal(f.advances(), 1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.advances(), 1);
  const facts = f.operation.preparedFacts(f.inventory);
  assert.equal(facts.input, f.input);
  assert.deepEqual(facts.slotWires, ['slot']);
  assert.equal(Object.isFrozen(facts.slotWires), true);
  await f.operation.close();
});

test('Waiting without the actual prepared owner is refused', async () => {
  const f = fixture({missingOwner: true});
  await assert.rejects(f.operation.run(), /InferPreparedOwnerUnavailable/);
  await f.operation.close();
});

for (const count of [-1, 129, NaN]) {
  test(`a non-finite or excessive prepared inventory (${count}) is refused`, async () => {
    const f = fixture({count});
    await f.operation.run();
    assert.throws(() => f.operation.preparedFacts(f.inventory), /InferPreparedOwnerUnavailable/);
    await f.operation.close();
  });
}

test('a missing ordered call cannot become a partial approved inventory', async () => {
  const f = fixture({missingSlot: true});
  await f.operation.run();
  assert.throws(() => f.operation.preparedFacts(f.inventory), /InferPreparedCallUnavailable/);
  await f.operation.close();
});
