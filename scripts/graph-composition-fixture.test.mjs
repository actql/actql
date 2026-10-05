import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientEffectRun} from '../adapters/host-node/client-effect-run.mjs';
import {graphCompositionProgram, graphCompositionTemplates,
  graphCompositionExpectations, graphDefinitionCid,
  graphCompositionRefusalProgram, graphCompositionRefusalTemplates,
  computationCustodySince} from
  './fixtures/graph-infer-effect-input.mjs';

const savedResultPolicy = Object.freeze({kind: 'data_policy',
  cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
  wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'});

async function restoreStartedEffect(resultPolicyOriginal, prepareExecution) {
  // Stub only the opaque checked Program/Run tokens. The actual Host adapter
  // must retrieve saved admission, recheck current authority and prepare it
  // without selecting today's Policy or issuing another physical-start claim.
  const prepared = {}, compilation = {}, allowed = {}, definition = {}, owner = {};
  const identity = {requestId: 'graph-policy-restoration'};
  const ref = {namespaceId: 'local', authorityScopeCid: 'sha256:' + '1'.repeat(64),
    runDefinitionCid: 'sha256:' + '2'.repeat(64)};
  const retained = JSON.parse(JSON.stringify({ref,
    runDefinition: {wire: '{"run_id":"retained-graph-run"}'},
    physicalStartReserved: true, preDispatchFailureConfirmed: false,
    cancellationRequested: false, observedTerminalOutcome: null,
    runAdmissionEvidence: {prepared: 'saved-prepared', authorization: 'saved-authorization',
      ...(resultPolicyOriginal === undefined ? {} : {resultPolicyOriginal})}}));
  const ok = value => ({$tag: 1, _0: value});
  const forbidden = () => assert.fail('restoration must not start or redispatch physical work');
  const moon = {
    clientProgramEffectCompilationIssueCode: () => undefined,
    clientProgramCompileLocalEffectsWithInfer: value => {
      assert.equal(value, prepared); return ok(compilation);
    },
    clientProgramEffectRequestIdentity: value => {
      assert.equal(value, prepared); return identity;
    },
    clientProgramSourceFreeInputIntentCid: () => 'source-free-intent',
    strategyRunEvidenceAdmit: (kind, wire) => ok({kind, wire}),
    strategyPublicationAdmit: (kind, wire) => {
      assert.equal(kind, 'run_definition'); assert.equal(wire, retained.runDefinition.wire);
      return ok(definition);
    },
    clientProgramAdmitAllowedEffectRun: (value, admission, authorization) => {
      assert.equal(value, compilation); assert.equal(admission.wire, 'saved-prepared');
      assert.equal(authorization.wire, 'saved-authorization'); return ok(allowed);
    },
    clientProgramBindCompiledEffectRun: (value, permission, run) => {
      assert.equal(value, prepared); assert.equal(permission, allowed);
      assert.equal(run, definition); return ok(owner);
    },
    clientProgramEffectRunStartCurrent: (permission, run) =>
      permission === allowed && run === definition,
    clientRunStartAction: forbidden,
    clientRequestAuthorityScopeCid: () => ref.authorityScopeCid,
    clientRequestCallerId: () => identity.requestId,
  };
  const journal = {
    lookupDefinition: () => retained, reserveDispatch: forbidden,
    reservePhysicalStart: forbidden,
    async admitOrLookupDefinition(value, options) {
      assert.equal(value, identity); assert.equal(options.namespaceId, 'local');
      return retained;
    },
    resolveDefinition(value) { assert.equal(value, identity); return retained; },
  };
  const effectRun = installNodeClientEffectRun({moon, journal,
    publicationControl: {admit: forbidden}, inferPlanFor: () => ({}),
    resultPolicyOriginalFor: () => assert.fail('restoration must not select a current Host Policy'),
    authorizeRequest: async () => ({}), authorizeRunStart: async () => true,
    prepareExecution, execute: forbidden, now: () => '2026-10-04T00:00:00.000Z'});
  const handle = await effectRun.accept({prepared, ...ref, requestId: identity.requestId,
    principalId: 'owner', connection: {mode: 'local'}, lookupExpiresAt: '2026-10-05T00:00:00.000Z'});
  return effectRun.restoreComputation(handle);
}

test('started Graph Effect restoration revalidates the saved Result Policy original without a new start', async () => {
  const restored = await restoreStartedEffect(savedResultPolicy, facts => {
    assert.deepEqual(facts.resultPolicyOriginal, savedResultPolicy);
    return {retainedOriginal: facts.resultPolicyOriginal};
  });
  assert.deepEqual(restored.preparedExecution.retainedOriginal, savedResultPolicy);
});

test('started Graph Effect restoration cannot replace a missing saved Policy with current configuration', async () => {
  await assert.rejects(restoreStartedEffect(undefined, facts => {
    assert.equal(facts.resultPolicyOriginal, undefined);
    throw new TypeError('InvalidHostResultDataPolicy');
  }), {name: 'TypeError', message: 'InvalidHostResultDataPolicy'});
});

test('cleanup accounting compares the current execution window without borrowing prior Run counters', () => {
  const observation = (name, transferredBytes) => ({name, pendingScratch: true,
    resourceUsage: {transferredBytes}});
  const previous = [observation('effect_computation_completed', '11'),
    observation('effect_computation_cleanup_completed', '11')];
  const current = [observation('effect_computation_completed', '29'),
    observation('effect_computation_cleanup_pending', '29'),
    observation('effect_computation_cleanup_completed', '29')];
  const unrelated = {name: 'effect_computation_completed', pendingScratch: false,
    resourceUsage: {transferredBytes: '43'}};
  const contents = [...previous, unrelated, ...current].map(record => JSON.stringify(record)).join('\n') + '\n';
  assert.deepEqual(computationCustodySince(contents, previous.length + 1), current);
  assert.deepEqual(computationCustodySince(contents, previous.length + 1 + current.length), []);
});

for (const family of ['node', 'edge']) {
  test(`${family} composition is a complete authored Program with only a MappingRef binding`, () => {
    const original = structuredClone(graphCompositionTemplates[family]);
    const bound = graphCompositionProgram('mapping:fixture', family);
    assert.equal(bound.stages[2].effects.save.update.mapping, 'mapping:fixture');
    bound.stages[2].effects.save.update.mapping = '__PUBLICATION_MAPPING_REF__';
    assert.deepEqual(bound, original);
    assert.deepEqual(graphCompositionTemplates[family], original);
    assert.throws(() => graphCompositionProgram('', family));
  });

  test(`${family} expectations preserve typed Graph keys, nullable guaranteed property and replay counts`, () => {
    const expected = graphCompositionExpectations(family);
    assert.equal(graphDefinitionCid,
      'sha256:e10869cfed10b18fbe00f13ddd456f4a4b5241199d16a3f31a08b4a53c026437');
    assert.deepEqual(expected.classified.map(row => [row.id, row.note, row.risk]),
      [[1, 7, 'low'], [2, null, 'high']]);
    for (const row of expected.classified) {
      assert.deepEqual(row.graph_identity, {definition: family === 'node' ? 'N' : 'E',
        domain: graphDefinitionCid, key: ['a', row.id],
        key_types: [{kind: 'string'}, {kind: 'number'}]});
    }
    assert.deepEqual(expected.sourceReadSessions, [0, 0, 0, 0]);
    assert.deepEqual(expected.modelInputs, [100, 200]);
    assert.deepEqual(expected.effectWriteCounts, [0, 0, 1, 1]);
    assert.deepEqual(expected.restartBoundaries, ['capture-waiting', 'approval-committed']);
  });
}

for (const variant of ['duplicate-key', 'null-property']) {
  test(`${variant} refusal submits an authored complete Graph Program without repair`, () => {
    const original = structuredClone(graphCompositionRefusalTemplates[variant]);
    const bound = graphCompositionRefusalProgram('mapping:fixture', variant);
    assert.equal(bound.stages[2].effects.save.update.mapping, 'mapping:fixture');
    bound.stages[2].effects.save.update.mapping = '__PUBLICATION_MAPPING_REF__';
    assert.deepEqual(bound, original);
    assert.deepEqual(graphCompositionRefusalTemplates[variant], original);
    assert.throws(() => graphCompositionRefusalProgram('', variant));
    assert.deepEqual(bound.stages[0].inputs, {});
    assert.deepEqual(bound.stages[1].steps.find(step => step.infer).infer,
      graphCompositionTemplates.node.stages[1].steps.find(step => step.infer).infer);
  });
}

test('duplicate Model keys remain distinct Graph identities until the explicit assertion', () => {
  const program = graphCompositionRefusalTemplates['duplicate-key'];
  const [persons, edges, constructor, rows, projection] = program.stages[0].steps;
  assert.deepEqual(persons.values.rows, [
    {person_key:1,tenant_key:'a',note:7}, {person_key:1,tenant_key:'b',note:9}]);
  assert.deepEqual(edges.values.rows, []);
  assert.deepEqual(constructor.property_graph.nodes[0].key, ['tenant_key','person_key']);
  assert.equal(rows.node_rows, true);
  assert.deepEqual(projection.select.slice(0,2), [{graph_identity:'id'}, {id:'person_key'}]);
  assert.deepEqual(program.stages[1].steps[0].assert_rows, {unique_by:['id']});
});

test('NULL refusal asserts a guaranteed nullable property without changing Graph or Model keys', () => {
  const program = graphCompositionRefusalTemplates['null-property'];
  assert.deepEqual(program.stages[0], graphCompositionTemplates.node.stages[0]);
  assert.deepEqual(program.stages[1].steps[0], {assert_rows:{unique_by:['note']}});
  assert.deepEqual(program.stages[1].steps.slice(1), graphCompositionTemplates.node.stages[1].steps);
  assert.deepEqual(program.stages[0].steps[0].values.schema.note, {type:'number',nullable:true});
  assert.equal(program.stages[0].steps[0].values.rows[0].note, null);
});
