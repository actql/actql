import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientEffectRun} from '../adapters/host-node/client-effect-run.mjs';
import {modelConfiguration} from './fixtures/composed-infer-effect-input.mjs';
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
  let originalIntentReads = 0;
  const journal = {
    originalSubmittedIntent(value, scope, runtime) {
      assert.equal(this, journal); assert.equal(value, identity);
      assert.deepEqual(scope, {namespaceId: 'local'}); assert.equal(runtime, moon);
      originalIntentReads++;
      // This historical component record has no submitted-intent entry.
      // Lookup observes absence; it issues no replacement intent or start.
      return undefined;
    },
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
  try {return await effectRun.restoreComputation(handle);}
  finally {assert.equal(originalIntentReads, 1);}
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
  test(`${family} successful Model projection preserves non-null risk and nullable Graph note`, async () => {
    const {installation} = await modelConfiguration({});
    const task = JSON.parse(installation.environmentWire).model_task_contracts[0];
    assert.equal(task.task_id, 'model-task:composition-risk.v1');
    assert.deepEqual(task.output_contract, {type: 'object', nullable: false,
      additional_properties: false, fields: {risk: {type: 'string', nullable: false}}});
    const program = graphCompositionTemplates[family];
    const classify = program.stages[1];
    assert.deepEqual(classify.steps[1].infer, {contract: task.task_id, key: 'id',
      input: {score: {field: 'right_amount'}}});
    const join = classify.steps[2].join;
    assert.equal(join.kind, 'inner');
    assert.equal(join.select.outcome, 'left.outcome');
    assert.equal(join.select.value, 'left.value');
    assert.deepEqual(classify.steps[3], {filter: {eq: [{field: 'outcome'}, {literal: 'ok'}]}});
    assert.deepEqual(classify.steps[4], {derive: {risk: {property: {
      value: {field: 'value'}, name: 'risk'}}}});
    // language.md INFER restores the same non-null success contract after
    // this literal success filter. Typed property access preserves risk's
    // non-null field contract; it does not refine unrelated Graph properties.
    const columns = [
      {name: 'id', contract: {type: 'number', nullable: false}},
      {name: 'graph_identity', contract: {type: 'json', nullable: false}},
      {name: 'tenant_key', contract: {type: 'string', nullable: false}},
      {name: 'note', contract: {type: 'number', nullable: true}},
      {name: 'left_amount', contract: {type: 'number', nullable: false}},
      {name: 'right_amount', contract: {type: 'number', nullable: false}},
      {name: 'risk', contract: {type: 'string', nullable: false}},
    ];
    const expected = graphCompositionExpectations(family);
    assert.deepEqual(expected.classifiedColumns, columns);
    assert.deepEqual(expected.updateColumns, [...columns,
      {name: 'target_id', contract: {type: 'string', nullable: false, max_utf8_bytes: 15}},
      {name: 'next_name', contract: {type: 'string', nullable: false, max_utf8_bytes: 15}}]);
    assert.deepEqual(expected.classified.map(row => row.note), [7, null]);
  });

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
      'sha256:c9367bcbcf2cc701a7eaca6ba3ee2d9e82bce5ce3f3d71b461a6d9659b8760e1');
    assert.deepEqual(expected.classified.map(row => [row.id, row.note, row.risk]),
      [[1, 7, 'low'], [2, null, 'high']]);
    for (const row of expected.classified) {
      assert.deepEqual(row.graph_identity, {$json: {definition: family === 'node' ? 'N' : 'E',
        domain: graphDefinitionCid, key: ['a', row.id],
        key_types: [{kind: 'string'}, {kind: 'number'}]}});
    }
    assert.deepEqual(expected.updates, [{...expected.classified[1],
      target_id: 'a00000000000002', next_name: 'review-required'}]);
    assert.deepEqual(expected.classifiedColumns.find(column => column.name === 'graph_identity'),
      {name: 'graph_identity', contract: {type: 'json', nullable: false}});
    assert.deepEqual(expected.writes, [{id: 'a00000000000002', body: {Name: 'review-required'}}]);
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
  assert.deepEqual(constructor.graph.nodes[0].key, ['tenant_key','person_key']);
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
