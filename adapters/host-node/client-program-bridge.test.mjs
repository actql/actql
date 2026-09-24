import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {exportPinnedEffectInput} from './effect-input-export.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {runCapturedInternalStrategy, runCapturedStrategy,
  runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from
  '../host-common/publication-contract-control.fixture.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {storeCompletedRunResultSet} from
  '../host-common/completed-run-publication.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority,
  installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';

const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../_build/client-program-bridge-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
const hashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(JSON.stringify(body))
    .digest('hex')}`;
};
const evidenceCid =
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904';
const programCid =
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c';
const parametersCid =
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52';
const publicationLimits = Object.freeze({
  maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64,
});
const outputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 100, maxValueNodes: 10000, maxValueTextBytes: 100000,
  maxValueDepth: 64, maxValueWork: 100000, maxWireBytes: 100000,
  maxWireNodes: 10000, maxWireDepth: 64, maxColumns: 10,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000,
  maxLogicalWireNodes: 10003, maxLogicalWireDepth: 66,
  maxSchemaFields: 10, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 4096,
});
const effectInputExportArgs = limits => [
  limits.maxResultFields, limits.maxResultMappingWork,
  limits.maxResultOrderWork, limits.maxResultWorkspaceEntries,
  limits.maxRows, limits.maxValueNodes, limits.maxValueTextBytes,
  limits.maxValueDepth, limits.maxValueWork, limits.maxWireBytes,
  limits.maxWireNodes, limits.maxWireDepth, limits.maxColumns,
  limits.maxOrderWork, limits.maxLogicalWireBytes,
  limits.maxLogicalWireNodes, limits.maxLogicalWireDepth,
  limits.maxSchemaFields, limits.maxSchemaBytes, limits.maxSchemaNodes,
  limits.maxSchemaDepth, limits.maxBatchBytes,
];

async function checkedFixture() {
  const [document, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const environment = moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(), evidenceCid,
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  return {document, environment};
}

async function effectFixture({splitSource = false,
  splitEffectSource = 'consumer', writeKind = 'create',
  memberIds = ['save']} = {}) {
  const [documentBody, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const targetSchema = {
    additional_properties: false,
    fields: {
      Id: {nullable: false, type: writeKind === 'create' ?
        'string' : 'number'},
      Name: {nullable: true, type: 'number'},
    },
    nullable: false,
    type: 'object',
  };
  const mapping = {
    connector_manifest_cid: cid('a'),
    conversions: [],
    mapping_contract_cid: '',
    mapping_ref: 'mapping:crm.account.v1',
    minimum_approval: 'none',
    permission_rules: [{
      effect_kind: writeKind, permissions: ['scope:' + writeKind],
      selector_class: writeKind === 'create' ? 'none' : 'id',
      write_fields: ['Name'],
    }],
    primary_identity: 'Id',
    required_fields: [],
    required_permissions: [],
    resource_identity_cid: cid('b'),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1',
    target_ref: 'connector://crm/account',
    target_schema: targetSchema,
    target_schema_identity: `sha256:${createHash('sha256')
      .update(JSON.stringify(targetSchema)).digest('hex')}`,
    version: 'salesforce-v1',
    writable_fields: ['Name'],
  };
  mapping.mapping_contract_cid = hashWithoutSelf(mapping,
    'mapping_contract_cid');
  const environmentDocument = JSON.parse(environmentBody);
  environmentDocument.mapping_contracts = [mapping];
  if (splitSource) {
    environmentDocument.host_policy_profile.capacity = JSON.parse(
      canonicalJson({
        ...environmentDocument.host_policy_profile.capacity,
        max_graph_construction_edges: 1000,
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000,
      }));
  }
  environmentDocument.evidence_bundle_cid = hashWithoutSelf(
    environmentDocument, 'evidence_bundle_cid');
  const environment = moon.clientProgramCheckEnvironment(
    JSON.stringify(environmentDocument),
    environmentDocument.evidence_bundle_cid,
    false, false, true, splitSource, false, false, false,
  );
  assert.ok(environment);
  const document = JSON.parse(documentBody);
  const write = writeKind === 'create'
    ? {target: 'connector://crm/account', mapping: mapping.mapping_ref,
      from: {result: 'rows'}}
    : {target: 'connector://crm/account', mapping: mapping.mapping_ref,
      from: {result: 'rows'}, id: 'id',
      set: {Name: {field: 'id'}}};
  const effects = Object.fromEntries(memberIds.map(id =>
    [id, {[writeKind]: write}]));
  document.stages[0].effects = effects;
  if (splitSource) {
    delete document.stages[0].effects;
    document.stages.push({
      id: 'middle',
      inputs: {rows: {result: {stage: 'source', result: 'rows'}}},
      steps: [
        {graph: {
          nodes: {from: 'rows', id: 'id', fields: []},
          edges: {from: 'rows', source: 'id', target: 'id', fields: []},
        }, as: 'g'},
        {from: 'g', normalize_graph: true, as: 'normalized'},
        {from: 'normalized', node_rows: true, as: 'projected'},
        {from: 'projected', take: 2, as: 'selected'},
      ],
      results: {
        rows: {from: 'selected', fields: ['id']},
        early: {from: 'projected', fields: ['id']},
      },
    }, {
      id: 'consumer',
      inputs: {rows: {result: {stage: 'middle', result: 'rows'}}},
      steps: [{take: 2, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects,
    });
    document.results.answer.from.stage = 'consumer';
    if (splitEffectSource !== 'consumer') {
      document.stages.pop();
      document.results.answer.from.stage = 'middle';
      document.stages[1].effects = Object.fromEntries(memberIds.map(id =>
        [id, {[writeKind]: {
          ...write,
          from: {result: splitEffectSource === 'early' ? 'early' : 'rows'},
        }}]));
    }
  }
  return {document: JSON.stringify(document), environment,
    mappingCid: mapping.mapping_contract_cid};
}

function effectInputPreview(prepared, evidence, definition, invocation,
  mappingCid, artifactCid, writeKind = 'create',
  approvedValues = [], targetRows = approvedValues.map((_, index) =>
    index + 1), memberIds = ['save'],
  memberBoundaries = memberIds.map((_, index) => cid(String(index)))) {
  const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = {
    version: 'actql-authoring-context/0.1',
    program_definition_cid: definitionCid, annotations: [],
  };
  authoring.authoring_context_cid = `sha256:${createHash('sha256')
    .update(canonicalJson(authoring)).digest('hex')}`;
  const preview = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: definitionCid,
    invocation_cid: moon.strategyPublicationContractIdentity(invocation),
    run_identity_cid: moon.strategyPublicationContractIdentity(definition),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(evidence[3]),
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: authoring, barrier_provenance_cids: [],
    model_derived: false, model_task_contract_cids: [],
    model_invocation_evidence_cids: [], model_response_artifact_cids: [],
    effects: memberIds.map((effectId, memberIndex) => ({
      effect_id: effectId, effect_kind: writeKind,
      target: 'connector://crm/account', mapping: 'mapping:crm.account.v1',
      resolved_mapping_contract_cid: mappingCid,
      effect_identity_cid: cid('a'), source_result: 'rows',
      result_artifact_cid: artifactCid, preview_strength: 'full_diff',
      source_binding_cid: cid('c'), capability_evidence_cid: cid('d'),
      authority_scope_cid: cid('e'),
      write_footprint: {
        kind: 'collection', resource_identity_scheme_cid: cid('f'),
        provider_namespace: 'salesforce',
        provider_boundary_cid: memberBoundaries[memberIndex],
        resource_kind: 'Account', provider_object_identity_cids: [],
      },
      count: approvedValues.length, max_items: 2,
      required_permissions: ['write'],
      approval: 'none', on_item_failure: 'halt',
      changes: approvedValues.map((value, index) => ({
        target_row_identity: targetRows[index],
        target_guard: {state: 'version', version_cid: cid('6')},
        intended_changes: {state: 'present', value: {Name: value}},
        before: {state: 'present', value: {Name: 0}},
        after: {state: 'present', value: {Name: value}},
        row_preview_cid: cid('1'), row_idempotency_key: cid('8'),
      })),
      row_order: [],
      effect_member_preview_cid: cid('1'), executed: false,
    })),
    executed: false, effect_preview_cid: cid('2'),
  };
  if (writeKind !== 'create') {
    for (const [index, member] of preview.effects.entries()) {
      member.effect_plan_logical_cid = checked(
        moon.clientProgramEffectPlanCid(prepared, index, 10, 100,
          20000, 1000, 20));
    }
  }
  if (approvedValues.length > 0) {
    const rowsByMember = checked(moon.strategyEffectPreviewRowIdentities(
      canonicalJson(preview), 20000, 1000, 20));
    for (const [memberIndex, member] of preview.effects.entries()) {
      const rows = rowsByMember[memberIndex];
      member.changes.forEach((change, index) => {
        change.row_preview_cid = rows[index];
        change.row_idempotency_key = cid(String(index + 7));
      });
      member.row_order = rows;
    }
  }
  const identities = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20));
  preview.effects.forEach((member, index) => {
    member.effect_member_preview_cid = identities[index + 1];
  });
  preview.effect_preview_cid = checked(moon.strategyEffectPreviewIdentities(
    canonicalJson(preview), 20000, 1000, 20))[0];
  return {wire: canonicalJson(preview), authoringCid:
    authoring.authoring_context_cid};
}

test('internal Client bridge retains Effect closure without public apply',
  async () => {
    const {document, environment} = await effectFixture();
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    assert.equal(moon.clientProgramEffectPreparationIssue(outcome), undefined);
    assert.equal(moon.clientProgramPrepareEffectFree(
      document, 'json', environment), undefined);
    const foreign = moon.clientProgramPrepareEffectComputationWithParameters(
      document.replace('mapping:crm.account.v1', 'mapping:crm.foreign.v1'),
      'json', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationReady(foreign), undefined);
    assert.ok(moon.clientProgramEffectPreparationIssueCode(foreign));
    const invalidFormat = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'text', environment, undefined, []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidFormat),
      'invalid_format');
    const invalidParameters = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, '{', []);
    assert.equal(moon.clientProgramEffectPreparationIssueCode(invalidParameters),
      'supplied_syntax');
    assert.equal(checked(moon.clientProgramEffectPlanCid(
      prepared, 0, 10, 100, 10000, 1000, 20)), undefined);
    const update = await effectFixture({writeKind: 'update'});
    const updateOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        update.document, 'json', update.environment, undefined, []);
    const updatePrepared = moon.clientProgramEffectPreparationReady(
      updateOutcome);
    assert.ok(updatePrepared,
      moon.clientProgramEffectPreparationIssueCode(updateOutcome));
    assert.match(checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 0, 10, 100, 10000, 1000, 20)),
    /^sha256:[0-9a-f]{64}$/);
    assert.throws(() => checked(moon.clientProgramEffectPlanCid(
      updatePrepared, 1, 10, 100, 10000, 1000, 20)),
    {code: 'MoonBitHostFailure'});
  });

test('admitted source-free Effect Run computes through the installed Host',
  async t => {
    const {document, environment, mappingCid} = await effectFixture();
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared), cid('2'),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = checked(moon.strategyRunPublicationAdmit(...evidence));
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'tenant-a-scope', 'effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const foreignDocument = JSON.parse(document);
    foreignDocument.id = 'foreign-effect-compute';
    const foreignOutcome =
      moon.clientProgramPrepareEffectComputationWithParameters(
        JSON.stringify(foreignDocument), 'json', environment, undefined, []);
    const foreign = moon.clientProgramEffectPreparationReady(foreignOutcome);
    assert.ok(foreign);
    assert.equal(moon.clientProgramBindEffectRun(
      foreign, admission, definition), undefined);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
    const execution = await runCapturedInternalStrategy(
      moon.clientProgramLocalEffectHostRuntime(owned));
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'effect-result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const runDefinitionContract = control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), publicationLimits);
    const invocationContract = control.admit('run_invocation',
      moon.strategyPublicationContractJson(invocation), publicationLimits);
    const store = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    }, control);
    let storedResults;
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].outputRows, 2);
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control, runDefinition: runDefinitionContract,
        invocation: invocationContract,
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      assert.equal(storedResults.artifacts.length, 1);
      assert.equal(storedResults.results[0].orderedRows.rows, 2);
      assert.equal(storedResults.definitions[0].identity,
        execution.publicationInventory.occurrences[0]
          .definitionContract.identity);
      assert.equal(JSON.parse(storedResults.artifacts[0].wire)
        .actual_row_count, 2);
      const payload = [];
      await store.consumeObject(storedResults.results[0].physical.cid,
        chunk => payload.push(Buffer.from(chunk)));
      const bytes = Buffer.concat(payload);
      assert.equal(bytes.byteLength,
        storedResults.results[0].physical.bytes);
      assert.equal(`sha256:${createHash('sha256').update(bytes)
        .digest('hex')}`, storedResults.results[0].physical.cid);
      const binding = JSON.parse(storedResults.results[0].publication
        .durableBinding.wire);
      assert.equal(binding.logical_result_cid,
        storedResults.results[0].orderedRows.logicalRelationCid);
      assert.equal(binding.run_definition_cid,
        runDefinitionContract.identity);
      assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 1);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 0)), {code: 'MoonBitHostFailure'});
      const inputs = checked(moon.clientProgramPinEffectSources(owned, 1));
      let previewInputs;
      try {
        assert.equal(moon.clientProgramEffectInputCount(inputs), 1);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 1), false);
        assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        assert.throws(() => checked(moon.clientProgramPinEffectSources(
          owned, 1)), {code: 'MoonBitHostFailure'});
        const input = moon.clientProgramEffectInputAt(inputs, 0);
        assert.ok(input);
        const preview = effectInputPreview(
          prepared, evidence, definition, invocation, mappingCid,
          storedResults.artifacts[0].identity);
        const previewLimits = moon.clientProgramEffectPreviewInputLimits(
          20000, 1000, 20, 1000, 100, 20000, 1000, 20,
          1, 2, 100, 100);
        assert.ok(previewLimits);
        const foreignPreview = effectInputPreview(
          prepared, evidence, definition, invocation, cid('9'),
          storedResults.artifacts[0].identity);
        assert.throws(() => checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, foreignPreview.wire,
            foreignPreview.authoringCid, previewLimits)),
        {code: 'MoonBitHostFailure'});
        previewInputs = checked(
          moon.clientProgramBindEffectPreviewInputs(
            owned, inputs, invocation, 0, preview.wire,
            preview.authoringCid, previewLimits));
        assert.equal(moon.clientProgramEffectPreviewInputAt(
          previewInputs, 0), input);
        assert.equal(checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, 10, 100)), undefined);
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 0, -1, 100)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramEffectPreviewPlanTerminal(
            previewInputs, 1, 10, 100)),
        {code: 'MoonBitHostFailure'});
        assert.doesNotThrow(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [], [], 0, 1)));
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [], 1, 2)),
        {code: 'MoonBitHostFailure'});
        assert.throws(() => checked(
          moon.clientProgramCheckEffectPreviewTargetGuards(
            previewInputs, [cid('1')], [cid('2')], 1, 2)),
        {code: 'MoonBitHostFailure'});
        const other = moon.clientProgramOpenSourceFreeLocalEffectHost(
          bound, registry, values, 1n, 0n, 0n, 0n);
        assert.ok(other);
        const otherExecution = await runCapturedInternalStrategy(
          moon.clientProgramLocalEffectHostRuntime(other));
        try {
          assert.throws(() => checked(
            moon.clientProgramBindEffectPreviewInputs(
              other, inputs, invocation, 0, preview.wire,
              preview.authoringCid, previewLimits)),
          {code: 'MoonBitHostFailure'});
        } finally {
          await otherExecution.close();
        }
        const limits = moon.clientProgramEffectInputExportLimits(
          ...effectInputExportArgs(outputLimits));
        assert.ok(limits);
        assert.throws(() => checked(moon.clientProgramEffectInputExportStart(
          input, limits)), {code: 'MoonBitHostFailure'});
        const physical = execution.effectPhysicalSource(0);
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 1, limits,
          onChunk() { throw new Error('UnexpectedEffectChunk'); },
        }), {message: 'MissingEffectInput'});
        await assert.rejects(exportPinnedEffectInput({
          moon, execution, inputs, memberIndex: 0, limits,
          onChunk() { throw new Error('StoppedEffectConsumer'); },
        }), {message: 'StoppedEffectConsumer'});
        assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
        const observed = {
          effectPhysicalSource(task) {
            assert.equal(task, 0);
            return {
              ...physical,
              withRows(...args) {
                limits.max_rows = 0;
                limits.values.max_nodes = 0;
                return physical.withRows(...args);
              },
            };
          },
        };
        const chunks = [];
        const exported = await exportPinnedEffectInput({
          moon, execution: observed, inputs, memberIndex: 0,
          task: 999,
          limits,
          onChunk: async chunk => { chunks.push(chunk); },
        });
        assert.deepEqual(JSON.parse(chunks.join('')),
          [{id: 1}, {id: 2}]);
        assert.deepEqual(exported.fields, ['id']);
        assert.match(exported.logicalCid, /^sha256:[0-9a-f]{64}$/);
      } finally {
        assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
      }
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramEffectPreviewPlanTerminal(
          previewInputs, 0, 10, 100)),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), false);
      assert.throws(() => checked(
        moon.clientProgramCheckEffectPreviewTargetGuards(
          previewInputs, [], [], 0, 1)),
      {code: 'MoonBitHostFailure'});
    } finally {
      for (const result of storedResults?.results ?? []) {
        await result.prepared.release();
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('owned update Plan matches approved rows and rejects altered intent',
  async t => {
    const memberIds = ['save', 'save_again'];
    const {document, environment, mappingCid} = await effectFixture({
      writeKind: 'update', memberIds,
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared,
      moon.clientProgramEffectPreparationIssueCode(outcome));
    const evidence = publicationEvidence(
      moon.clientProgramEffectDefinitionCid(prepared), cid('2'),
      moon.clientProgramEffectSemanticsCid(prepared),
      moon.clientProgramEffectEnvironmentCid(prepared));
    const admission = checked(moon.strategyRunPublicationAdmit(...evidence));
    const definition = checked(moon.strategyIssueRunDefinition(
      admission, 'tenant-a-scope', 'update-effect-compute', cid('c'),
      '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
      100000, 10000, 64));
    const observation = checked(moon.strategyRunEvidenceSeal(
      'observation_set', JSON.stringify({
        version: 'actql-observation-set/0.1',
        invocation_template_cid: moon.strategyRunEvidenceIdentity(
          evidence[0]),
        source_evidence_cids: [], captured_input_artifact_cids: [],
        consistency: 'no_external_sources', capture_started_at: null,
        capture_completed_at: null,
        replayability: {materialized: false, availability_evidence_cids: []},
        data_policy_cid: cid('d'),
      }), 100000, 10000, 64));
    const invocation = checked(moon.strategyIssueRunInvocation(
      evidence[0], observation, 100000, 10000, 64));
    const bound = moon.clientProgramBindEffectRun(
      prepared, admission, definition);
    assert.ok(bound);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
      bound, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(owned);
    const execution = await runCapturedInternalStrategy(
      moon.clientProgramLocalEffectHostRuntime(owned));
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'update-plan-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const control = runtimeCore(moon).publicationControl;
    const store = await openLocalPublicationStore({
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    }, control);
    let storedResults, inputs;
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      const retention = control.seal('result_retention_policy',
        JSON.stringify({
          version: 'actql-result-retention-policy/0.1',
          retention_contract_cid: cid('e'),
          effective_data_policy_cid: cid('d'),
          available_until: '2026-09-24T01:00:00.000Z',
          delete_by: '2026-09-24T02:00:00.000Z',
          extension_ceiling_at: '2026-09-24T03:00:00.000Z',
          metadata_retention_policy_cid: cid('f'),
          metadata_delete_by: '2026-09-24T04:00:00.000Z',
          clock_contract_cid: cid('0'),
        }), publicationLimits);
      storedResults = await storeCompletedRunResultSet({
        execution, store, control,
        runDefinition: control.admit('run_definition',
          moon.strategyPublicationContractJson(definition),
          publicationLimits),
        invocation: control.admit('run_invocation',
          moon.strategyPublicationContractJson(invocation),
          publicationLimits),
        results: [{retention, evidenceContext: {
          computationContractCid: cid('2'), inputRelationCids: [],
          scopeCid: cid('3'), effectiveDataPolicyCid: cid('d'),
          authorityScopeCid: cid('a'),
        }}],
        outputLimits, contractLimits: publicationLimits,
      });
      inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
      const previewFor = (values, targets = values.map((_, index) =>
        index + 1)) => effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        storedResults.artifacts[0].identity, 'update', values,
        targets, memberIds);
      const preview = previewFor([1, 2]);
      const previewLimits = moon.clientProgramEffectPreviewInputLimits(
        20000, 1000, 20, 1000, 100, 20000, 1000, 20,
        2, 2, 100, 100);
      const conflicting = effectInputPreview(
        prepared, evidence, definition, invocation, mappingCid,
        storedResults.artifacts[0].identity, 'update', [1, 2],
        [1, 2], memberIds, [cid('0'), cid('0')]);
      assert.throws(() => checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, conflicting.wire,
          conflicting.authoringCid, previewLimits)),
      {code: 'MoonBitHostFailure'});
      const previewInputs = checked(
        moon.clientProgramBindEffectPreviewInputs(
          owned, inputs, invocation, 0, preview.wire,
          preview.authoringCid, previewLimits));
      const checkCurrent = ({sources = [cid('c'), cid('c')],
        contracts = [mappingCid, mappingCid],
        capabilities = [cid('d'), cid('d')],
        authorities = [cid('e'), cid('e')]} = {}) => checked(
        moon.clientProgramCheckEffectPreviewCurrentBindings(
          previewInputs, sources, contracts, capabilities, authorities,
          2, 8));
      assert.doesNotThrow(() => checkCurrent());
      assert.throws(() => checkCurrent({capabilities: [cid('d')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({sources: [cid('c'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({contracts: [mappingCid, cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({capabilities: [cid('d'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checkCurrent({authorities: [cid('e'), cid('f')]}),
      {code: 'MoonBitHostFailure'});
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const planLimits = {
        maxFields: 10, maxWork: 100, maxBytes: 20000,
        maxNodes: 1000, maxDepth: 20, maxUtf16Units: 20000,
      };
      const chunks = [];
      const verified = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0, limits,
        planLimits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.match(verified.logicalCid, /^sha256:[0-9a-f]{64}$/);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), true);
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 1), false);
      const secondChunks = [];
      const second = await verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 1, limits,
        planLimits,
        onChunk: async chunk => { secondChunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(secondChunks.join('')),
        [{id: 1}, {id: 2}]);
      assert.notEqual(second.proof, verified.proof);
      assert.doesNotThrow(() => checked(
        moon.clientProgramCheckEffectPlanProofs(
          previewInputs, [second.proof, verified.proof], 2, 4)));
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, verified.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const altered = previewFor([1, 99]);
      const alteredInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, altered.wire,
        altered.authoringCid, previewLimits));
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, alteredInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        alteredInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
      const partial = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: alteredInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { partial.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(partial.length, 1);
      const swapped = previewFor([1, 2], [2, 1]);
      const swappedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, swapped.wire,
        swapped.authoringCid, previewLimits));
      const swappedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: swappedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { swappedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(swappedChunks, []);
      const omitted = previewFor([]);
      const omittedInputs = checked(moon.clientProgramBindEffectPreviewInputs(
        owned, inputs, invocation, 0, omitted.wire,
        omitted.authoringCid, previewLimits));
      const omittedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs: omittedInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => { omittedChunks.push(chunk); },
      }), {code: 'MoonBitHostFailure'});
      assert.deepEqual(omittedChunks, []);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), true);
      const releasedChunks = [];
      await assert.rejects(verifyPinnedEffectPlan({
        moon, execution, previewInputs, previewIndex: 0,
        limits, planLimits,
        onChunk: async chunk => {
          releasedChunks.push(chunk);
          if (releasedChunks.length === 1) {
            assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
          }
        },
      }), {code: 'MoonBitHostFailure'});
      assert.equal(releasedChunks.length, 1);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.throws(() => checkCurrent(),
      {code: 'MoonBitHostFailure'});
      assert.equal(moon.clientProgramEffectPlanProofMatches(
        verified.proof, previewInputs, 0), false);
      assert.throws(() => checked(moon.clientProgramCheckEffectPlanProofs(
        previewInputs, [verified.proof, second.proof], 2, 4)),
      {code: 'MoonBitHostFailure'});
    } finally {
      if (inputs !== undefined) {
        moon.clientProgramReleaseEffectInputs(inputs);
      }
      for (const result of storedResults?.results ?? []) {
        await result.prepared.release();
      }
      await store.close();
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

async function verifySharedEffectSource({splitSource, expectedTask}) {
  const {document, environment} = await effectFixture({
    splitSource, splitEffectSource: 'middle',
  });
  const source = JSON.parse(document);
  const effectStage = source.stages[splitSource ? 1 : 0];
  effectStage.effects.save_again = structuredClone(effectStage.effects.save);
  const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(source), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(outcome);
  assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
  const evidence = publicationEvidence(
    moon.clientProgramEffectDefinitionCid(prepared), cid('2'),
    moon.clientProgramEffectSemanticsCid(prepared),
    moon.clientProgramEffectEnvironmentCid(prepared));
  const admission = checked(moon.strategyRunPublicationAdmit(...evidence));
  const definition = checked(moon.strategyIssueRunDefinition(
    admission, 'tenant-a-scope', 'two-effect-compute', cid('c'),
    '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
    100000, 10000, 64));
  const bound = moon.clientProgramBindEffectRun(
    prepared, admission, definition);
  assert.ok(bound);
  const [registry, contract] = await Promise.all([
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
      import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json',
      import.meta.url), 'utf8'),
  ]);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
    bound, registry, values, 1n, 0n, 0n, 0n);
  assert.ok(owned);
  assert.equal(moon.clientProgramLocalEffectSourceCount(owned), 2);
  const execution = await runCapturedInternalStrategy(
    moon.clientProgramLocalEffectHostRuntime(owned));
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.throws(() => checked(moon.clientProgramPinEffectSources(
      owned, 1)), {code: 'MoonBitHostFailure'});
    const inputs = checked(moon.clientProgramPinEffectSources(owned, 2));
    try {
      assert.equal(moon.clientProgramEffectInputCount(inputs), 2);
      const first = moon.clientProgramEffectInputAt(inputs, 0);
      const second = moon.clientProgramEffectInputAt(inputs, 1);
      assert.ok(first);
      assert.ok(second);
      assert.notEqual(first, second);
      assert.equal(moon.clientProgramEffectInputTask(first), expectedTask);
      assert.equal(moon.clientProgramEffectInputTask(second), expectedTask);
      assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
      assert.equal(moon.clientProgramReleaseEffectInput(first), true);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 0), false);
      assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), true);
      const chunks = [];
      const limits = moon.clientProgramEffectInputExportLimits(
        ...effectInputExportArgs(outputLimits));
      const exported = await exportPinnedEffectInput({
        moon, execution, inputs, memberIndex: 1, limits,
        onChunk: async chunk => { chunks.push(chunk); },
      });
      assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
      assert.deepEqual(exported.fields, ['id']);
      assert.equal(moon.clientProgramReleaseEffectInput(first), false);
      assert.throws(() => checked(moon.clientProgramPinEffectSources(
        owned, 2)), {code: 'MoonBitHostFailure'});
    } finally {
      assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
    }
    assert.equal(moon.clientProgramEffectInputAvailable(inputs, 1), false);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
}

test('two Effect members hold one completed Result independently', async () => {
  await verifySharedEffectSource({splitSource: false, expectedTask: 0});
  await verifySharedEffectSource({splitSource: true, expectedTask: 4});
});

test('Effect sources retain exact physical producers across split Stages',
  async () => {
    for (const [splitEffectSource, expectedTask] of [
      ['consumer', 5], ['middle', 4], ['early', 3],
    ]) {
      const {document, environment} = await effectFixture({
        splitSource: true, splitEffectSource,
      });
      const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
        document, 'json', environment, undefined, []);
      const prepared = moon.clientProgramEffectPreparationReady(outcome);
      assert.ok(prepared,
        `${splitEffectSource}: ${moon.clientProgramEffectPreparationIssueCode(outcome)}`);
      const evidence = publicationEvidence(
        moon.clientProgramEffectDefinitionCid(prepared), cid('2'),
        moon.clientProgramEffectSemanticsCid(prepared),
        moon.clientProgramEffectEnvironmentCid(prepared));
      const admission = checked(moon.strategyRunPublicationAdmit(...evidence));
      const definition = checked(moon.strategyIssueRunDefinition(
        admission, 'tenant-a-scope', 'split-effect-compute', cid('c'),
        '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z',
        100000, 10000, 64));
      const bound = moon.clientProgramBindEffectRun(
        prepared, admission, definition);
      assert.ok(bound);
      const [registry, contract] = await Promise.all([
        readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
          import.meta.url), 'utf8'),
        readFile(new URL('../../spec/contracts/actql-aoa.json',
          import.meta.url), 'utf8'),
      ]);
      const values = JSON.stringify(
        JSON.parse(contract).execution_contracts['REL.values']);
      const owned = moon.clientProgramOpenSourceFreeLocalEffectHost(
        bound, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(owned);
      const execution = await runCapturedInternalStrategy(
        moon.clientProgramLocalEffectHostRuntime(owned));
      try {
        assert.equal(execution.status, 'host-tasks-completed',
          execution.failure?.stack);
        const inputs = checked(moon.clientProgramPinEffectSources(owned, 1));
        try {
          const input = moon.clientProgramEffectInputAt(inputs, 0);
          assert.ok(input);
          assert.equal(moon.clientProgramEffectInputTask(input), expectedTask);
          assert.equal(moon.clientProgramCloseEffectSourcePort(inputs, 0), true);
          const chunks = [];
          const limits = moon.clientProgramEffectInputExportLimits(
            ...effectInputExportArgs(outputLimits));
          const exported = await exportPinnedEffectInput({
            moon, execution, inputs, memberIndex: 0, limits,
            onChunk: async chunk => { chunks.push(chunk); },
          });
          assert.deepEqual(JSON.parse(chunks.join('')), [{id: 1}, {id: 2}]);
          assert.deepEqual(exported.fields, ['id']);
          assert.throws(() => checked(moon.clientProgramPinEffectSources(
            owned, 1)), {code: 'MoonBitHostFailure'});
        } finally {
          assert.equal(moon.clientProgramReleaseEffectInputs(inputs), true);
        }
      } finally {
        await execution.close();
        assert.equal(execution.cleanupPending(), false);
      }
    }
  });

test('private Plan binding uses the escaped checked Unit Result name', async () => {
  const {document, environment} = await checkedFixture();
  const renamed = JSON.parse(document);
  renamed.stages[0].results['a~/b'] = renamed.stages[0].results.rows;
  delete renamed.stages[0].results.rows;
  renamed.results.answer.from.result = 'a~/b';
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(renamed), 'json', environment);
  assert.ok(prepared);
  const body = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const binding = JSON.parse(body);
  assert.deepEqual([
    binding.target.unit_definition_cid,
    binding.target.result_name,
    binding.subject_ref,
    binding.resolved_limit_cid,
    binding.binding_cid,
  ], [
    'sha256:20cfb6440b10bee12f7647df2286cb63eca491c608df0ecbf1c13c21089eeb43',
    'a~/b',
    'unit:sha256:20cfb6440b10bee12f7647df2286cb63eca491c608df0ecbf1c13c21089eeb43#/results/a~0~1b/rows',
    'sha256:ee1d282f8b184e1f2202d5a70bf411a1a097fafe06b99e2ba87520206be820fc',
    'sha256:8b311359a8abfa4ef16ac3237daef1bdcc26ba8d753107afa074cab36feac400',
  ]);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body)));
});

test('binding set covers every checked Unit Result port', async () => {
  const {document, environment} = await checkedFixture();
  const doubled = JSON.parse(document);
  doubled.stages[0].results.second =
    structuredClone(doubled.stages[0].results.rows);
  doubled.results.second = {from: {stage: 'source', result: 'second'}};
  const prepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(doubled), 'json', environment);
  assert.ok(prepared);
  const bindings = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsBindingJson(
      prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesBindingJson(
      prepared, 0, index)),
  ]);
  const limits = [0, 1].flatMap(index => [
    checked(moon.clientProgramPublicationRowsLimitJson(prepared, 0, index)),
    checked(moon.clientProgramPublicationBytesLimitJson(prepared, 0, index)),
  ]);
  const issued = checked(moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issued), limits);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issued),
    bindings);
  const entries = limits.map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issued),
    entries);
  const witnesses = checked(
    moon.clientProgramIssuePublicationWitnesses(prepared));
  const witnessBodies = moon.clientProgramPublicationWitnessBodies(witnesses);
  const witnessCids = moon.clientProgramPublicationWitnessCids(witnesses);
  assert.equal(witnessBodies.length, witnessCids.length);
  assert.ok(witnessBodies.length > 1);
  assert.equal(new Set(witnessCids).size, witnessCids.length);
  for (const body of witnessBodies) {
    const witness = JSON.parse(body);
    assert.ok(witnessCids.includes(witness.witness_cid));
  }
  for (const body of limits) {
    for (const candidate of JSON.parse(body).candidates) {
      assert.ok(witnessCids.includes(candidate.witness_cid));
    }
  }
  assert.deepEqual(moon.clientProgramPublicationWitnessBodies(checked(
    moon.clientProgramAdmitPublicationWitnesses(
      prepared, witnessBodies))), witnessBodies);
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.slice(1))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitPublicationWitnesses(
    prepared, witnessBodies.toReversed())), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      entries.toReversed())));
  const manifestBody = {
    plan_facts: entries.map(entry => JSON.parse(entry)),
    version: 'actql-plan-fact-manifest/0.1',
  };
  const manifestCid = hashWithoutSelf(manifestBody,
    'plan_fact_manifest_cid');
  const manifest = JSON.stringify({...manifestBody,
    plan_fact_manifest_cid: manifestCid});
  const encodedManifest = checked(
    moon.clientProgramEncodePlanFactManifestIdentity(
      JSON.stringify(manifestBody.plan_facts)));
  assert.equal(moon.clientProgramPlanFactManifestCid(encodedManifest),
    manifestCid);
  assert.deepEqual(JSON.parse(moon.clientProgramPlanFactManifestWire(
    encodedManifest)), JSON.parse(manifest));
  assert.equal(checked(moon.clientProgramCheckPlanFactManifestIdentity(
    manifest, JSON.stringify(manifestBody.plan_facts))), manifestCid);
  assert.throws(() => checked(
    moon.clientProgramCheckPlanFactManifestIdentity(manifest,
      JSON.stringify(manifestBody.plan_facts.slice(1)))),
  {code: 'MoonBitHostFailure'});
  assert.equal(new Set(bindings.map(body => JSON.parse(body).binding_cid))
    .size, 4);
  assert.equal(new Set(limits.map(body => JSON.parse(body).resolved_limit_cid))
    .size, 4);
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared,
      bindings.toReversed())));
  const admitFacts = (limitBodies, bindingBodies) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(
      prepared, limitBodies, bindingBodies));
  assert.doesNotThrow(() => admitFacts(
    limits.toReversed(), bindings.toReversed()));
  for (const omitted of [0, 1, 2, 3]) {
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationFactEntries(prepared,
        entries.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits.filter((_, index) => index !== omitted), bindings),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => admitFacts(
      limits, bindings.filter((_, index) => index !== omitted)),
    {code: 'MoonBitHostFailure'});
    assert.throws(() => checked(
      moon.clientProgramAdmitPublicationBindingSet(prepared,
        bindings.filter((_, index) => index !== omitted))),
    {code: 'MoonBitHostFailure'});
  }
});

// Test-only evidence isolates checked Program binding. Product admission must
// derive every other evidence CID from its real compiler and Host authority.
function publicationEvidence(program, parameters, semantics,
  checkEnvironmentCid, aoaLogicalCid = cid('9')) {
  const limits = [100000, 10000, 64];
  const evidence = (name, body) => checked(moon.strategyRunEvidenceSeal(
    name, JSON.stringify(body), ...limits));
  const template = evidence('bound_invocation_template', {
    version: 'actql-bound-invocation-template/0.1',
    program_definition_cid: program,
    parameter_values_cid: parameters,
    invocation_bindings_cid: cid('3'),
    check_environment_cid: checkEnvironmentCid,
    grammar_manifest_cid: cid('5'),
    required_profile_contracts: [],
    barrier_contract_manifest_cid: cid('6'),
    source_evidence: 'unbound',
  });
  const plan = checked(moon.strategyPublicationSeal('compiled_plan',
    JSON.stringify({
      version: 'actql-compiled-plan/0.1',
      compiler_version: 'compiler-test-0.1',
      aoa_ir_version: 'aoa-ir-test-0.1',
      executable_plan_cid: cid('7'),
      program_definition_cid: program,
      program_semantics_cid: semantics,
      aoa_contract_cid: cid('8'),
      aoa_logical_cid: aoaLogicalCid,
    }), ...limits));
  const prepared = evidence('prepared_invocation', {
    version: 'actql-prepared-invocation/0.1',
    invocation_template_cid: moon.strategyRunEvidenceIdentity(template),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(plan),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    policy_decision: 'allow',
    expires_at: '2099-01-01T00:00:00.000Z',
  });
  const authorization = evidence('run_authorization', {
    version: 'actql-run-authorization/0.1',
    prepared_invocation_cid: moon.strategyRunEvidenceIdentity(prepared),
    execution_context_cid: cid('a'),
    host_policy_cid: cid('b'),
    decision: 'allowed',
  });
  return [template, prepared, authorization, plan];
}

// This fixture provides missing compiler/Host policy evidence. Its checked
// Program identity and the physical Result bytes come from product owners.
function checkedValuesPublicationPlan(prepared, control) {
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'published-values-request', cid('b'));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  const evidence = publicationEvidence(
    moon.clientRequestProgramCid(request),
    moon.clientRequestParametersCid(request),
    moon.clientProgramSemanticsCid(prepared),
    moon.clientProgramCheckEnvironmentCid(prepared),
    moon.clientProgramLocalValuesAoACid(aoa));
  const [template, preparedEvidence, authorization] = evidence
    .slice(0, 3).map((value, index) => control.admitRunEvidence(
      ['bound_invocation_template', 'prepared_invocation',
        'run_authorization'][index],
      moon.strategyRunEvidenceJson(value), publicationLimits));
  const compiledPlan = control.admit('compiled_plan',
    moon.strategyPublicationContractJson(evidence[3]), publicationLimits);
  const admission = control.admitCheckedClientRunPublication(
    prepared, template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.issueRunDefinition(admission, {
    scopeId: 'tenant-a-scope', runId: 'checked-values-published',
    inputArtifactSetCid: cid('c'),
    createdAt: '2026-09-24T00:00:00.000Z',
    validUntil: '2027-01-01T00:00:00.000Z',
  }, publicationLimits);
  const effectiveDataPolicyCid = cid('d');
  const observation = control.sealRunEvidence('observation_set',
    JSON.stringify({
      version: 'actql-observation-set/0.1',
      invocation_template_cid: template.identity,
      source_evidence_cids: [], captured_input_artifact_cids: [],
      consistency: 'no_external_sources', capture_started_at: null,
      capture_completed_at: null,
      replayability: {materialized: false, availability_evidence_cids: []},
      data_policy_cid: effectiveDataPolicyCid,
    }), publicationLimits);
  const invocation = control.issueRunInvocation(
    template, observation, publicationLimits);
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: cid('e'),
    effective_data_policy_cid: effectiveDataPolicyCid,
    available_until: '2026-09-24T01:00:00.000Z',
    delete_by: '2026-09-24T02:00:00.000Z',
    extension_ceiling_at: '2026-09-24T03:00:00.000Z',
    metadata_retention_policy_cid: cid('f'),
    metadata_delete_by: '2026-09-24T04:00:00.000Z',
    clock_contract_cid: cid('0'),
  }), publicationLimits);
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: cid('1'), entries: [],
    }), publicationLimits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: moon.clientRequestProgramCid(request),
      annotations: [],
    }), publicationLimits);
  return Object.freeze({
    admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze([Object.freeze({
      retention,
      evidenceContext: Object.freeze({
        computationContractCid: cid('2'), inputRelationCids: [],
        scopeCid: cid('3'), effectiveDataPolicyCid,
        authorityScopeCid: cid('a'),
      }),
    })]),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence: [],
      modelEvidence: [], barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: []}),
    request: Object.freeze({
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      publicationPolicyCid: cid('4'), publicationTargetCid: cid('5'),
      requestedAt: '2026-09-24T00:00:00.000Z',
    }),
    attempt: Object.freeze({
      attemptId: 'published-values-attempt', fenceCid: cid('6'),
      externalIdempotencyKey: undefined,
      startedAt: '2026-09-24T00:00:01.000Z',
    }),
    outputLimits, contractLimits: publicationLimits,
    now: () => '2026-09-24T00:02:00.000Z',
  });
}

test('Node ABI derives the checked named Result and request identity', async () => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  assert.ok(prepared);
  assert.equal(moon.clientProgramResultCount(prepared), 1);
  assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
  assert.equal(moon.clientProgramResultName(prepared, 1), undefined);
  assert.equal(moon.clientProgramCheckEnvironmentCid(prepared), evidenceCid);
  const steps = checked(moon.clientProgramLocalAoASteps(prepared, 0));
  assert.deepEqual(JSON.parse(steps), [{
    id: 'values_0', in: [], op: 'REL.values',
    params: {rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}}},
  }]);
  const pipeline = checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 0));
  assert.equal(pipeline, JSON.stringify({
    output: 'values_0', sources: {}, steps: JSON.parse(steps),
    version: 'aoa-pipeline/0.1',
  }));
  const aoa = checked(
    moon.clientProgramIssueLocalValuesAoAIdentity(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesAoAWire(aoa), pipeline);
  assert.equal(moon.clientProgramLocalValuesAoACid(aoa),
    'sha256:5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723');
  const unitSource = checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 0));
  assert.deepEqual(JSON.parse(unitSource), {
    id: 'source', inputs: {},
    results: {rows: {fields: ['id'], from: 'selected'}},
    steps: [{as: 'selected', values: {
      rows: [{id: 1}, {id: 2}],
      schema: {id: {nullable: false, type: 'number'}},
    }}],
    version: 'actql/0.1',
  });
  const outputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 0));
  assert.equal(moon.clientProgramLocalValuesOutputSchemaWire(outputSchema),
    '{"id":{"nullable":false,"type":"number"}}');
  assert.equal(moon.clientProgramLocalValuesOutputSchemaCid(outputSchema),
    'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513');
  const fragment = checked(moon.clientProgramIssueLocalValuesFragment(
    prepared, 0));
  const fragmentWire = moon.clientProgramLocalValuesFragmentWire(fragment);
  assert.equal(moon.clientProgramLocalValuesFragmentOutputContractCid(fragment),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.deepEqual(JSON.parse(fragmentWire), {
    input_contracts: {}, kind: 'aoa_fragment',
    logical_cid: moon.clientProgramLocalValuesAoACid(aoa),
    node_id: 'values_0',
    output_contracts: {values_0:
      moon.clientProgramLocalValuesFragmentOutputContractCid(fragment)},
    pipeline: JSON.parse(pipeline),
  });
  assert.equal(moon.clientProgramLocalValuesFragmentWire(checked(
    moon.clientProgramAdmitLocalValuesFragment(prepared, 0, fragmentWire))),
  fragmentWire);
  const resultRow = checked(moon.clientProgramIssueResultRowContract(
    prepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractName(resultRow), 'rows');
  assert.equal(moon.clientProgramResultRowContractWire(resultRow),
    '{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"}');
  assert.equal(moon.clientProgramResultRowContractCid(resultRow),
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c');
  assert.match(moon.clientProgramResultRowContractUnitCid(resultRow),
    /^sha256:[0-9a-f]{64}$/u);
  const resultPlan = checked(moon.clientProgramIssueResultPlan(prepared, 0));
  const resultPlanWire = moon.clientProgramResultPlanWire(resultPlan);
  assert.equal(moon.clientProgramResultPlanName(resultPlan), 'answer');
  assert.equal(moon.clientProgramResultPlanCid(resultPlan),
    'sha256:59fdfedffa402d123f1a04dd962b7cc1c404399ef08e825bb98151bb2ab39b68');
  assert.equal(moon.clientProgramResultPlanRowContractCid(resultPlan),
    moon.clientProgramResultRowContractCid(resultRow));
  assert.deepEqual(JSON.parse(resultPlanWire), {
    version: 'actql-result-plan/0.1', result_name: 'answer',
    unit_definition_cid:
      'sha256:61072398472dcda269c10498c3af97a2853703344a33e6471d31aec3ea0a554d',
    unit_result_name: 'rows', unit_result_ordinal: 0,
    projection: [{input: 'id', output: 'id', value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    order: {strategy: 'inherited', terms: []},
    typed_output_port: {carrier: 'relation', name: 'rows',
      row_contract_cid: moon.clientProgramResultRowContractCid(resultRow)},
    result_plan_logical_cid: moon.clientProgramResultPlanCid(resultPlan),
  });
  assert.equal(moon.clientProgramResultPlanWire(checked(
    moon.clientProgramAdmitResultPlan(prepared, 0, resultPlanWire))),
  resultPlanWire);
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    prepared, 0, resultPlanWire.replace('"result_name":"answer"',
      '"result_name":"foreign"'))), {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueResultPlan(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const directRoot = checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 0));
  const directRootWire = moon.clientProgramDirectValuesResultRootWire(directRoot);
  assert.deepEqual(JSON.parse(directRootWire), {
    name: 'answer', ref: {node_id: 'values_0', port: 'values_0'},
    role: 'requested_result',
  });
  assert.equal(moon.clientProgramDirectValuesResultRootPlanCid(directRoot),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.equal(moon.clientProgramDirectValuesResultRootRowContractCid(directRoot),
    moon.clientProgramLocalValuesFragmentOutputContractCid(fragment));
  assert.equal(moon.clientProgramDirectValuesResultRootWire(checked(
    moon.clientProgramAdmitDirectValuesResultRoot(
      prepared, 0, directRootWire))), directRootWire);
  assert.throws(() => checked(moon.clientProgramAdmitDirectValuesResultRoot(
    prepared, 0, directRootWire.replace('"answer"', '"foreign"'))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    prepared, 1)), {code: 'MoonBitHostFailure'});
  const wider = JSON.parse(document);
  const wideValues = wider.stages[0].steps[0].values;
  wideValues.schema.hidden = {nullable: false, type: 'string'};
  wideValues.rows[0].hidden = 'a';
  wideValues.rows[1].hidden = 'b';
  const widePrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(wider), 'json', environment);
  assert.ok(widePrepared);
  const wideResultPlan = checked(
    moon.clientProgramIssueResultPlan(widePrepared, 0));
  assert.notEqual(moon.clientProgramResultPlanCid(wideResultPlan),
    moon.clientProgramResultPlanCid(resultPlan));
  assert.throws(() => checked(moon.clientProgramAdmitResultPlan(
    widePrepared, 0, resultPlanWire)), {code: 'MoonBitHostFailure'});
  const wideOutputSchema = checked(
    moon.clientProgramIssueLocalValuesOutputSchema(widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesOutputSchemaCid(
    wideOutputSchema), moon.clientProgramLocalValuesOutputSchemaCid(outputSchema));
  const projectedRow = checked(moon.clientProgramIssueResultRowContract(
    widePrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(projectedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const wideFragment = checked(moon.clientProgramIssueLocalValuesFragment(
    widePrepared, 0));
  assert.notEqual(moon.clientProgramLocalValuesFragmentOutputContractCid(
    wideFragment), moon.clientProgramResultRowContractCid(projectedRow));
  assert.throws(() => checked(moon.clientProgramIssueDirectValuesResultRoot(
    widePrepared, 0)), {code: 'MoonBitHostFailure'});
  assert.deepEqual(JSON.parse(
    moon.clientProgramLocalValuesFragmentOutputContractWire(wideFragment)), {
    additional_properties: false,
    fields: {hidden: {nullable: false, type: 'string'},
      id: {nullable: false, type: 'number'}},
    nullable: false, type: 'object',
  });
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    widePrepared, 0, fragmentWire)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramAdmitLocalValuesFragment(
    prepared, 0, JSON.stringify({...JSON.parse(fragmentWire),
    unrecognized: true}))), {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline, moon.clientProgramLocalValuesAoACid(aoa))));
  assert.throws(() => checked(
    moon.clientProgramAdmitLocalValuesAoAIdentity(prepared, 0,
      pipeline.replace('"id":2', '"id":3'),
      moon.clientProgramLocalValuesAoACid(aoa))),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesPipelineJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramLocalValuesUnitSourceJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesOutputSchema(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueLocalValuesFragment(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramIssueResultRowContract(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(moon.clientProgramLocalAoASteps(prepared, 1)),
    {code: 'MoonBitHostFailure'});
  const semanticDocument = checked(
    moon.clientProgramSemanticDocumentJson(prepared));
  assert.deepEqual(JSON.parse(semanticDocument), JSON.parse(document));
  const annotated = JSON.parse(document);
  annotated.meta = {note: 'root'};
  annotated.stages[0].meta = {note: 'stage'};
  annotated.stages[0].steps[0].meta = {note: 'step'};
  const annotatedPrepared = moon.clientProgramPrepareEffectFree(
    JSON.stringify(annotated), 'json', environment);
  assert.ok(annotatedPrepared);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(annotatedPrepared)),
  semanticDocument);
  assert.equal(checked(
    moon.clientProgramLocalValuesUnitSourceJson(annotatedPrepared, 0)),
  unitSource);
  const annotatedRow = checked(moon.clientProgramIssueResultRowContract(
    annotatedPrepared, 0, 0));
  assert.equal(moon.clientProgramResultRowContractCid(annotatedRow),
    moon.clientProgramResultRowContractCid(resultRow));
  const semanticsCid = moon.clientProgramSemanticsCid(prepared);
  assert.match(semanticsCid, /^sha256:[a-f0-9]{64}$/u);
  const definition = checked(moon.clientProgramDefinitionJson(prepared));
  assert.deepEqual(JSON.parse(definition), {
    id: 'client-values', program_semantics_cid: semanticsCid,
    version: 'actql-program-definition/0.1',
  });
  assert.equal(`sha256:${createHash('sha256').update(definition)
    .digest('hex')}`, programCid);
  const semantics = checked(moon.clientProgramSemanticsJson(prepared));
  assert.equal(`sha256:${createHash('sha256').update(semantics)
    .digest('hex')}`, semanticsCid);
  const stageSemantics = checked(
    moon.clientProgramStageSemanticsJson(prepared, 0));
  assert.equal(`sha256:${createHash('sha256').update(stageSemantics)
    .digest('hex')}`,
  JSON.parse(semantics).program_template.stages[0].stage_semantics_cid);
  assert.throws(() => checked(
    moon.clientProgramStageSemanticsJson(prepared, 1)),
  {code: 'MoonBitHostFailure'});
  const rowsLimitBody = checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 0));
  const bytesLimitBody = checked(
    moon.clientProgramPublicationBytesLimitJson(prepared, 0, 0));
  const rowsLimit = JSON.parse(rowsLimitBody);
  const bytesLimit = JSON.parse(bytesLimitBody);
  const unit =
    'unit:sha256:61072398472dcda269c10498c3af97a2853703344a33e6471d31aec3ea0a554d';
  assert.deepEqual([rowsLimit.subject_ref, bytesLimit.subject_ref],
    [`${unit}#/results/rows/rows`, `${unit}#/results/rows/bytes`]);
  assert.deepEqual([rowsLimit.unit, rowsLimit.effective_max,
    bytesLimit.unit, bytesLimit.effective_max],
  ['rows', 2, 'bytes', 1000]);
  assert.deepEqual(rowsLimit.candidates.map(candidate => candidate.role),
    ['host_ceiling', 'proven_upper_bound']);
  for (const limit of [rowsLimit, bytesLimit]) {
    assert.equal(limit.version, 'actql-resolved-limit/0.1');
    assert.equal(limit.resolved_limit_cid,
      hashWithoutSelf(limit, 'resolved_limit_cid'));
    for (const witness of limit.candidates) {
      assert.equal(witness.witness_cid,
        hashWithoutSelf(witness, 'witness_cid'));
    }
  }
  const rowsBindingBody = checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 0));
  const bytesBindingBody = checked(
    moon.clientProgramPublicationBytesBindingJson(prepared, 0, 0));
  const issuedFacts = checked(
    moon.clientProgramIssuePublicationPlanFacts(prepared));
  assert.deepEqual(moon.clientProgramPublicationPlanFactLimits(issuedFacts),
    [rowsLimitBody, bytesLimitBody]);
  assert.deepEqual(moon.clientProgramPublicationPlanFactBindings(issuedFacts),
    [rowsBindingBody, bytesBindingBody]);
  const factEntries = [rowsLimitBody, bytesLimitBody].map(body =>
    `{"kind":"resolved_limit","value":${body}}`);
  assert.deepEqual(moon.clientProgramPublicationPlanFactEntries(issuedFacts),
    factEntries);
  assert.throws(() => checked(
    moon.clientProgramAdmitPublicationFactEntries(prepared,
      [factEntries[0], factEntries[0]])),
  {code: 'MoonBitHostFailure'});
  const rowsBinding = JSON.parse(rowsBindingBody);
  const bytesBinding = JSON.parse(bytesBindingBody);
  assert.deepEqual([
    rowsLimit.resolved_limit_cid, bytesLimit.resolved_limit_cid,
    rowsBinding.binding_cid, bytesBinding.binding_cid,
  ], [
    'sha256:d1dce9ccb30a076ebe729616043a663dddb85ba29c8de3f8f964bd8c71fbf1c0',
    'sha256:4cdf56db345268d69b01d9b3216a5fbc8f8a7c648e8ae9176dde762f1d64e8b3',
    'sha256:bd732ffbc9c3a523e3dffbb6e1ffd28a9696e12779ca32f099de040cd0d2cee2',
    'sha256:33d623c5108cff887acbb28ef6b7fda20615a217b7d55e8bd898b2e10f65da3f',
  ]);
  for (const [binding, limit, measure] of [
    [rowsBinding, rowsLimit, 'rows'],
    [bytesBinding, bytesLimit, 'bytes'],
  ]) {
    assert.deepEqual(binding, {
      binding_cid: binding.binding_cid,
      effective_max: limit.effective_max,
      resolved_limit_cid: limit.resolved_limit_cid,
      subject_ref: `${unit}#/results/rows/${measure}`,
      target: {
        kind: 'result_publication', measure, result_name: 'rows',
        unit_definition_cid: unit.slice('unit:'.length),
      },
      unit: measure,
      version: 'actql-execution-limit-binding/0.1',
    });
    assert.equal(binding.binding_cid, hashWithoutSelf(binding, 'binding_cid'));
    assert.notEqual(binding.binding_cid, hashWithoutSelf({
      ...binding, target: {...binding.target, result_name: 'answer'},
    }, 'binding_cid'));
  }
  const admitRows = body => checked(
    moon.clientProgramAdmitPublicationRowsBinding(prepared, 0, 0, body));
  const admitBytes = body => checked(
    moon.clientProgramAdmitPublicationBytesBinding(prepared, 0, 0, body));
  const admitSet = bodies => checked(
    moon.clientProgramAdmitPublicationBindingSet(prepared, bodies));
  const admitFacts = (limits, bindings) => checked(
    moon.clientProgramAdmitPublicationPlanFacts(prepared, limits, bindings));
  assert.doesNotThrow(() => admitRows(rowsBindingBody));
  assert.doesNotThrow(() => admitBytes(bytesBindingBody));
  assert.doesNotThrow(() => admitSet([bytesBindingBody, rowsBindingBody]));
  assert.doesNotThrow(() => admitFacts(
    [bytesLimitBody, rowsLimitBody],
    [bytesBindingBody, rowsBindingBody]));
  for (const invalid of [
    [rowsLimitBody],
    [rowsLimitBody, rowsLimitBody],
    [rowsLimitBody, '{}'],
    [rowsLimitBody, JSON.stringify({...bytesLimit,
      effective_max: bytesLimit.effective_max + 1})],
  ]) assert.throws(() => admitFacts(invalid,
    [rowsBindingBody, bytesBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => admitFacts(
    [rowsLimitBody, bytesLimitBody], [rowsBindingBody]),
  {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitSet([JSON.stringify({
    version: rowsBinding.version, target: rowsBinding.target,
    unit: rowsBinding.unit, subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  }), bytesBindingBody]));
  for (const invalid of [
    [rowsBindingBody],
    [rowsBindingBody, rowsBindingBody],
    [rowsBindingBody, JSON.stringify({...bytesBinding,
      binding_cid: cid('f')})],
    [bytesBindingBody, '{}'],
  ]) assert.throws(() => admitSet(invalid),
    {code: 'MoonBitHostFailure'});
  assert.doesNotThrow(() => admitRows(JSON.stringify({
    version: rowsBinding.version,
    target: rowsBinding.target,
    unit: rowsBinding.unit,
    subject_ref: rowsBinding.subject_ref,
    resolved_limit_cid: rowsBinding.resolved_limit_cid,
    effective_max: rowsBinding.effective_max,
    binding_cid: rowsBinding.binding_cid,
  })));
  const wrongPort = {
    ...rowsBinding,
    target: {...rowsBinding.target, result_name: 'answer'},
  };
  wrongPort.binding_cid = hashWithoutSelf(wrongPort, 'binding_cid');
  for (const invalid of [
    JSON.stringify(wrongPort),
    JSON.stringify({...rowsBinding, target: {
      ...rowsBinding.target, unit_definition_cid: cid('f'),
    }}),
    JSON.stringify({...rowsBinding, resolved_limit_cid: cid('f')}),
    JSON.stringify({...rowsBinding, binding_cid: cid('f')}),
    JSON.stringify({...rowsBinding, unknown: true}),
    rowsBindingBody.replace('"unit":"rows","version"',
      '"unit":"rows","unit":"rows","version"'),
  ]) assert.throws(() => admitRows(invalid), {code: 'MoonBitHostFailure'});
  assert.throws(() => admitBytes(rowsBindingBody),
    {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsBindingJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  assert.throws(() => checked(
    moon.clientProgramPublicationRowsLimitJson(prepared, 0, 1)),
  {code: 'MoonBitHostFailure'});
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  assert.ok(request);
  assert.equal(moon.clientRequestProgramCid(request), programCid);
  assert.equal(moon.clientRequestParametersCid(request), parametersCid);
  assert.equal(moon.clientRequestScopeCid(request),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3');
  assert.equal(moon.clientRequestIntentCid(request),
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const yaml = await readFile(new URL('values.yaml', fixture), 'utf8');
  const yamlPrepared = moon.clientProgramPrepareEffectFree(
    yaml, 'yaml', environment);
  assert.ok(yamlPrepared);
  assert.equal(moon.clientRequestProgramCid(
    moon.clientProgramRequestIdentity(
      yamlPrepared, cid('a'), 'saved-request', cid('b'))),
  programCid);
  assert.equal(moon.clientProgramSemanticsCid(yamlPrepared), semanticsCid);
  assert.equal(checked(moon.clientProgramDefinitionJson(yamlPrepared)),
    definition);
  assert.equal(checked(
    moon.clientProgramSemanticDocumentJson(yamlPrepared)), semanticDocument);
  assert.equal(checked(moon.clientProgramSemanticsJson(yamlPrepared)),
    semantics);
  assert.equal(checked(moon.clientProgramStageSemanticsJson(yamlPrepared, 0)),
    stageSemantics);
  assert.equal(checked(
    moon.clientProgramPublicationRowsLimitJson(yamlPrepared, 0, 0)),
  rowsLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesLimitJson(yamlPrepared, 0, 0)),
  bytesLimitBody);
  assert.equal(checked(
    moon.clientProgramPublicationRowsBindingJson(yamlPrepared, 0, 0)),
  rowsBindingBody);
  assert.equal(checked(
    moon.clientProgramPublicationBytesBindingJson(yamlPrepared, 0, 0)),
  bytesBindingBody);
  assert.equal(checked(moon.clientProgramLocalAoASteps(yamlPrepared, 0)), steps);
  assert.equal(checked(
    moon.clientProgramLocalValuesPipelineJson(yamlPrepared, 0)), pipeline);
  assert.equal(moon.clientProgramPrepareEffectFree(document, 'auto', environment),
    undefined);
  assert.equal(moon.clientProgramPrepareEffectFree(
    document.replace('actql/0.1', 'actql/9.9'), 'json', environment),
  undefined);
  assert.equal(moon.clientProgramCheckEnvironment(
    '{}', evidenceCid, false, false, true, false, false, false, false),
  undefined);
});

test('Node ABI binds separately supplied Parameters through the shared checker',
  async t => {
    const {environment} = await checkedFixture();
    const [json, yaml] = await Promise.all([
      readFile(new URL('parameter-values.json', fixture), 'utf8'),
      readFile(new URL('parameter-values.yaml', fixture), 'utf8'),
    ]);
    const prepare = (document, format, parameters) =>
      moon.clientProgramPrepareEffectFreeWithParameters(
        document, format, environment, parameters);
    const issue = outcome => moon.clientProgramPreparationIssueCode(outcome);
    const ready = outcome => moon.clientProgramPreparationReady(outcome);
    assert.equal(issue(prepare(json, 'json', undefined)), 'needs_inputs');
    assert.equal(issue(prepare(json, 'json', '{"n":"bad"}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":null}')),
      'check_invalid_input');
    assert.equal(issue(prepare(json, 'json', '{"n":2')),
      'supplied_syntax');
    assert.equal(issue(prepare(json, 'json', `{"n":"${'x'.repeat(65536)}"}`)),
      'supplied_too_large');
    assert.equal(issue(prepare(json, 'auto', '{"n":2}')),
      'invalid_format');
    const supplied = ready(prepare(json, 'json', '{"n":2}'));
    const repeated = ready(prepare(json, 'json', '{"n":2}'));
    const yamlSupplied = ready(prepare(yaml, 'yaml', '{"n":2}'));
    const changed = ready(prepare(json, 'json', '{"n":3}'));
    for (const value of [supplied, repeated, yamlSupplied, changed]) {
      assert.ok(value);
      assert.equal(moon.clientProgramResultName(value, 0), 'answer');
    }
    const identity = value => moon.clientProgramRequestIdentity(
      value, cid('a'), 'parameter-request', cid('b'));
    const first = identity(supplied);
    const same = identity(repeated);
    const yamlIdentity = identity(yamlSupplied);
    const other = identity(changed);
    assert.equal(moon.clientRequestProgramCid(first),
      moon.clientRequestProgramCid(yamlIdentity));
    assert.equal(moon.clientProgramSemanticsCid(supplied),
      moon.clientProgramSemanticsCid(yamlSupplied));
    assert.equal(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(yamlIdentity));
    assert.equal(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(same));
    assert.notEqual(moon.clientRequestParametersCid(first),
      moon.clientRequestParametersCid(other));
    assert.notEqual(moon.clientRequestIntentCid(first),
      moon.clientRequestIntentCid(other));
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'parameters-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const admission = {tenantId: 'tenant-a', runDefinitionCid: cid('c'),
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
    assert.equal(journal.accept(first, admission, moon).inserted, true);
    assert.equal(journal.accept(same, admission, moon).inserted, false);
    assert.throws(() => journal.accept(other, admission, moon),
      {code: 'ClientRequestIntentConflict'});
    const withDefault = json.replace('"n": {"type": "number"}',
      '"n": {"type": "number", "default": 5}');
    assert.notEqual(withDefault, json);
    assert.ok(ready(prepare(withDefault, 'json', undefined)));
  });

test('public submit rejects checker failures before Run admission', async () => {
  const {environment} = await checkedFixture();
  const document = await readFile(new URL('parameter-values.json', fixture),
    'utf8');
  const prepareSubmit = installNodeClientProgramPreparation({
    moon, environment});
  let admissions = 0;
  let admittedIdentity;
  const server = createServer(createClientHttpHandler({
    authenticate: header => header === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: () => true,
    negotiate: () => ({
      version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'volatile', scopeRef: 'principal-a', capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
        maxRows: 100, maxBatchRows: 10,
        maxBatchRetainedValueBytes: 2048},
    }),
    prepareSubmit,
    maxRequestBytes: 100000,
    submit: ({preparedProgram, requestId}) => {
      admissions++;
      admittedIdentity = moon.clientProgramRequestIdentity(preparedProgram,
        cid('a'), requestId, cid('b'));
      return {ref: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
        runDefinitionCid: cid('c')}, durability: 'volatile', revision: 0};
    },
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const origin = `http://127.0.0.1:${server.address().port}/`;
    const submit = parameters => fetch(new URL('actql/client/0.1/submit',
      origin), {
      method: 'POST', headers: {authorization: 'Bearer scoped-token',
        'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'local', owner: 'local',
        runners: [], consentRefs: []}, requestId: 'saved-parameter-id',
      kind: 'aql', input: {text: document, format: 'json'}, parameters}),
    });
    for (const [parameters, status, code] of [
      [null, 422, 'ClientProgramNeedsInputs'],
      [{n: null}, 422, 'ClientProgramRejected'],
      [{n: 'bad'}, 422, 'ClientProgramRejected'],
      [{n: 2, extra: true}, 422, 'ClientProgramRejected'],
      [{n: 'x'.repeat(65536)}, 413, 'ClientParametersTooLarge'],
    ]) {
      const response = await submit(parameters);
      assert.equal(response.status, status);
      assert.deepEqual(await response.json(), {code});
    }
    assert.equal(admissions, 0);
    const client = await connectClient({mode: 'local', owner: 'local',
      endpoint: origin, token: 'scoped-token'});
    try {
      await assert.rejects(client.aql(document, {format: 'json',
        requestId: 'sdk-invalid-parameter', parameters: {n: null}}),
      {code: 'ClientProgramRejected'});
      assert.equal(admissions, 0);
    } finally {
      client.close();
    }
    const prepared = prepareSubmit({kind: 'aql',
      input: {text: document, format: 'json'}, parameters: {n: 2}});
    assert.equal(moon.clientProgramResultName(prepared, 0), 'answer');
    const objectPrepared = prepareSubmit({kind: 'program',
      input: JSON.parse(document), parameters: {n: 2}});
    assert.equal(moon.clientProgramSemanticsCid(objectPrepared),
      moon.clientProgramSemanticsCid(prepared));
    const accepted = await submit({n: 2});
    assert.equal(accepted.status, 200);
    assert.equal(admissions, 1);
    assert.equal(moon.clientRequestParametersCid(admittedIdentity),
      moon.clientRequestParametersCid(moon.clientProgramRequestIdentity(
        prepared, cid('a'), 'saved-parameter-id', cid('b'))));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('Node publication admission rejects evidence from another checked Program',
  async t => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'saved-request', cid('b'));
    const evidence = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared),
      moon.clientProgramCheckEnvironmentCid(prepared));
    assert.ok(moon.clientProgramAdmitPublication(prepared, ...evidence));
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64};
    const bound = evidence.slice(0, 3).map((value, index) =>
      control.admitRunEvidence(
        ['bound_invocation_template', 'prepared_invocation',
          'run_authorization'][index],
        moon.strategyRunEvidenceJson(value), limits));
    const plan = control.admit('compiled_plan',
      moon.strategyPublicationContractJson(evidence[3]), limits);
    const admitted = control.admitCheckedClientRunPublication(
      prepared, ...bound, plan);
    assert.equal(admitted.kind, 'run-publication-admission');
    const definition = control.issueRunDefinition(admitted, {
      scopeId: 'tenant-a-scope',
      runId: 'checked-values-run',
      inputArtifactSetCid: cid('c'),
      createdAt: '2026-09-24T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
    }, limits);
    await mkdir(scratch, {recursive: true});
    const path = await mkdtemp(join(scratch.pathname, 'admission-'));
    t.after(() => rm(path, {recursive: true, force: true}));
    const journal = openClientRequestJournal(path);
    const accepted = journal.acceptDefinition(identity, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    journal.close(); // Lose the acceptance reply before using the Run ref.
    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const retained = restarted.resolveDefinition(identity,
      {tenantId: 'tenant-a'}, moon, control);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const changed = moon.clientProgramPrepareEffectFree(
      document.replace('"id": 2', '"id": 3'), 'json', environment);
    assert.ok(changed);
    assert.equal(moon.clientProgramAdmitPublication(changed, ...evidence),
      undefined);
    assert.throws(() => control.admitCheckedClientRunPublication(
      changed, ...bound, plan),
    /Publication evidence differs from checked Program/u);
    const changedRequest = moon.clientProgramRequestIdentity(
      changed, cid('a'), 'saved-request', cid('b'));
    assert.throws(() => restarted.resolveDefinition(changedRequest,
      {tenantId: 'tenant-a'}, moon, control),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => restarted.acceptDefinition(changedRequest, {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    }, moon, control), {code: 'ClientRequestIntentConflict'});
    const foreignSemantics = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity), cid('f'), evidenceCid);
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignSemantics), undefined);
    const foreignEnvironment = publicationEvidence(
      moon.clientRequestProgramCid(identity),
      moon.clientRequestParametersCid(identity),
      moon.clientProgramSemanticsCid(prepared), cid('f'));
    assert.equal(moon.clientProgramAdmitPublication(
      prepared, ...foreignEnvironment), undefined);
  });

test('durable request deduplication uses checked Program identity', async t => {
  const {document, environment} = await checkedFixture();
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  const request = moon.clientProgramRequestIdentity(
    prepared, cid('a'), 'saved-request', cid('b'));
  await mkdir(scratch, {recursive: true});
  const path = await mkdtemp(join(scratch.pathname, 'case-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const admission = {
    tenantId: 'tenant-a',
    runDefinitionCid: cid('d'),
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
  };
  assert.equal(journal.accept(request, admission, moon).inserted, true);
  assert.equal(journal.accept(request, {...admission,
    runDefinitionCid: cid('e')}, moon).inserted, false);
  const changed = moon.clientProgramPrepareEffectFree(
    document.replace('"id": 2', '"id": 3'), 'json', environment);
  assert.ok(changed);
  const changedRequest = moon.clientProgramRequestIdentity(
    changed, cid('a'), 'saved-request', cid('b'));
  assert.equal(moon.clientRequestRelation(request, changedRequest), 2);
  assert.throws(() => journal.accept(changedRequest, {...admission,
    runDefinitionCid: cid('e')}, moon),
  {code: 'ClientRequestIntentConflict'});
  assert.equal(journal.lookup({tenantId: 'tenant-a',
    authorityScopeCid: cid('a'), requestId: 'saved-request'}, moon)
    .ref.runDefinitionCid, cid('d'));
});

test('checked source-free Program executes through the standard Local Host',
  async () => {
    const {document, environment} = await checkedFixture();
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry.replace('"REL.values"', '"REL.changed"'),
      values, 1n, 0n, 0n, 0n), undefined);
    assert.equal(moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, -1n, 0n, 0n, 0n), undefined);
    const setup = moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const execution = await runCapturedStrategy(setup);
    try {
      assert.equal(execution.status, 'host-tasks-completed');
      assert.deepEqual(execution.resultInventory.map(result => result.name),
        ['answer']);
      assert.equal(execution.completed.length, 1);
      assert.equal(execution.completed[0].task, 0);
      assert.equal(execution.completed[0].outputRows, 2);
      assert.throws(() => execution.effectPhysicalSource(0),
        {code: 'InvalidEffectPhysicalSource'});
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('public Values submit computes and reads its real Local Result',
  async t => {
    const {document, environment} = await checkedFixture();
    const expected = JSON.parse(await readFile(new URL('values.expected.json',
      fixture), 'utf8'));
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', environment);
    assert.ok(prepared);
    const [registry, contract] = await Promise.all([
      readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
        import.meta.url), 'utf8'),
      readFile(new URL('../../spec/contracts/actql-aoa.json',
        import.meta.url), 'utf8'),
    ]);
    const values = JSON.stringify(
      JSON.parse(contract).execution_contracts['REL.values']);
    const control = runtimeCore(moon).publicationControl;
    let plan;
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname, 'result-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    const configuration = {
      directory, storeAuthorityCid: cid('7'),
      capacityBytes: 4 * 1024 * 1024,
      maxObjectBytes: outputLimits.maxWireBytes,
      maxObjects: 100, maxContractNodes: 10000,
      maxContractDepth: 64,
    };
    const journalDirectory = join(directory, 'requests');
    await mkdir(journalDirectory);
    const identity = moon.clientProgramRequestIdentity(
      prepared, cid('a'), 'published-values-request', cid('b'));
    let store = await openLocalPublicationStore(configuration, control);
    let published;
    try {
      const journal = openClientRequestJournal(journalDirectory);
      let issues = 0;
      let computes = 0;
      const submitServer = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-before-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local',
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-before-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        prepareSubmit: installNodeClientProgramPreparation({
          moon, environment}),
        submit: async ({preparedProgram, requestId}) => {
          const requested = moon.clientProgramRequestIdentity(
            preparedProgram, cid('a'), requestId, cid('b'));
          const accepted = await journal.admitOrLookupDefinition(requested, {
            tenantId: 'tenant-a',
            lookupExpiresAt: '2099-01-01T00:00:00.000Z',
            issueDefinition: () => {
              issues++;
              plan = checkedValuesPublicationPlan(preparedProgram, control);
              return plan.runDefinition;
            },
          }, moon, control);
          if (accepted.inserted) {
            const setup = moon.clientProgramOpenSourceFreeLocalHost(
              preparedProgram, registry, values, 1n, 0n, 0n, 0n);
            assert.ok(setup);
            computes++;
            published = await runPublishedCapturedStrategy(setup,
              {store, plan});
          }
          return {ref: accepted.ref, durability: accepted.durability,
            revision: accepted.revision};
        },
      }));
      await new Promise(resolve => submitServer.listen(0, '127.0.0.1',
        resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${submitServer.address().port}/`,
          token: 'scoped-token', durability: 'durable',
        });
        try {
          const submitted = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.equal(submitted.profile.durability, 'durable');
          assert.equal(submitted.ref.runDefinitionCid,
            plan.runDefinition.identity);
          const repeated = await client.aql(document, {format: 'json',
            requestId: 'published-values-request'});
          assert.deepEqual(repeated.ref, submitted.ref);
        } finally { client.close(); }
      } finally {
        await new Promise(resolve => submitServer.close(resolve));
        journal.close();
      }
      assert.equal(issues, 1);
      assert.equal(computes, 1);
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.deepEqual(published.execution.resultInventory.map(
        result => result.name), ['answer']);
      assert.equal(published.execution.completed[0].outputRows,
        expected.length);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close();
      assert.equal(published.cleanupPending(), false);
      assert.equal(await published.cleanup(), true);
      published = undefined;
      await store.close();
      store = await openLocalPublicationStore(configuration, control);
      const reopened = openClientRequestJournal(journalDirectory);
      let ref;
      try {
        const retained = await reopened.admitOrLookupDefinition(identity, {
          tenantId: 'tenant-a',
          lookupExpiresAt: '2099-01-01T00:00:00.000Z',
          issueDefinition: () => {
            throw new Error('Duplicate request reissued Run authority');
          },
        }, moon, control);
        assert.equal(retained.inserted, false);
        assert.equal(retained.runDefinition.wire, plan.runDefinition.wire);
        ref = retained.ref;
      } finally {
        reopened.close();
      }
      const authority = installResultAccessAuthority({
        authorizeResultReadRequest: () => true,
        admitResultRead: facts => ({
          authorizationContextCid: `sha256:${createHash('sha256')
            .update(facts.attemptId).digest('hex')}`,
          dataCeilingCid: cid('9'),
          egressAdmissionCid: cid('a'),
          expiresAt: '2026-09-24T01:00:00.000Z',
          maxBytes: 100000, maxUses: 1,
        }),
        authorizeResultRead: () => true,
        authorizeDeliveryAttemptLookup: () => true,
      });
      const service = installNodeResultAccessService({
        store, control, authority,
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
        frameLimits: {maxRowBytes: 4096, maxDepth: 32,
          maxFrameBytes: 4096},
      });
      const stateService = installRunStateService({
        store, control,
        authority: installRunStateAuthority({
          authorizeRunState: () => true,
          resultPolicyAvailable: () => true,
        }),
        now: () => '2026-09-24T00:30:00.000Z',
        limits: publicationLimits,
      });
      const server = createServer(createClientHttpHandler({
        authenticate: header => header === 'Bearer scoped-token'
          ? 'principal-after-restart' : undefined,
        authorizeConnection: facts => facts.connection.mode === 'local' &&
          facts.connection.owner === 'local' &&
          (facts.ref === undefined || facts.ref.tenantId === 'tenant-a'),
        negotiate: () => ({
          version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
          durability: 'durable', scopeRef: 'principal-after-restart',
          capabilities: ['result-jsonl'],
          limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
            maxRowRetainedValueBytes: 1024,
            maxRetainedValueBytes: 4096, maxRows: 100,
            maxBatchRows: 10, maxBatchRetainedValueBytes: 2048},
        }),
        attach: async ({ref: requested, principalId}) => {
          await inspectAuthorizedRunState(stateService, {
            indexKey: requested, principalId, purpose: 'inspect',
          });
          return {ref: requested, durability: 'durable', revision: 0};
        },
        stateService, resultService: service,
      }));
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const client = await connectClient({
          mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${server.address().port}/`,
          token: 'scoped-token',
        });
        const execution = await client.attach(ref);
        assert.equal(execution.profile.durability, 'durable');
        const state = await execution.status();
        assert.equal(validRunState(state), true);
        assert.equal(state.status, 'succeeded');
        assert.deepEqual(await execution.result('answer').all(), expected);
        const reader = execution.result('answer').rows();
        assert.deepEqual(await Array.fromAsync(reader), expected);
        assert.equal(reader.state(), 'complete');
        let attempt = await execution.result('answer')
          .deliveryAttempt(reader.attemptId);
        assert.equal(attempt.kind, 'found');
        for (let tries = 0; tries < 100 &&
          attempt.record?.state !== 'succeeded'; tries++) {
          await new Promise(resolve => setTimeout(resolve, 10));
          attempt = await execution.result('answer')
            .deliveryAttempt(reader.attemptId);
        }
        assert.equal(attempt.record.state, 'succeeded');
        client.close();
      } finally {
        await new Promise(resolve => server.close(resolve));
      }
    } finally {
      await published?.close();
      await store.close();
    }
  });
