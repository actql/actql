import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {runCapturedStrategy, runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {inspectAuthorizedRunState, installRunStateAuthority,
  installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {connect as connectClient} from '../../packages/sdk/index.mjs';

const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
const scratch = new URL('../../_build/client-program-bridge-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
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

// Test-only evidence isolates checked Program binding. Product admission must
// derive every other evidence CID from its real compiler and Host authority.
function publicationEvidence(program, parameters, semantics,
  checkEnvironmentCid) {
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
      aoa_logical_cid: cid('9'),
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
  const evidence = publicationEvidence(
    moon.clientRequestProgramCid(request),
    moon.clientRequestParametersCid(request),
    moon.clientProgramSemanticsCid(prepared),
    moon.clientProgramCheckEnvironmentCid(prepared));
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
  const semanticsCid = moon.clientProgramSemanticsCid(prepared);
  assert.match(semanticsCid, /^sha256:[a-f0-9]{64}$/u);
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
  assert.equal(moon.clientProgramPrepareEffectFree(document, 'auto', environment),
    undefined);
  assert.equal(moon.clientProgramPrepareEffectFree(
    document.replace('actql/0.1', 'actql/9.9'), 'json', environment),
  undefined);
  assert.equal(moon.clientProgramCheckEnvironment(
    '{}', evidenceCid, false, false, true, false, false, false, false),
  undefined);
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
    const retained = restarted.lookupDefinition({
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      requestId: 'saved-request',
    }, moon, control);
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
    } finally {
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
    }
  });

test('checked Values Program publishes and reads its real Local Result',
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
    const setup = moon.clientProgramOpenSourceFreeLocalHost(
      prepared, registry, values, 1n, 0n, 0n, 0n);
    assert.ok(setup);
    const control = runtimeCore(moon).publicationControl;
    const plan = checkedValuesPublicationPlan(prepared, control);
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
    const journal = openClientRequestJournal(journalDirectory);
    try {
      const accepted = journal.acceptDefinition(identity, {
        tenantId: 'tenant-a', runDefinition: plan.runDefinition,
        lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      }, moon, control);
      assert.equal(accepted.inserted, true);
      assert.equal(accepted.ref.runDefinitionCid,
        plan.runDefinition.identity);
    } finally {
      journal.close();
    }
    let store = await openLocalPublicationStore(configuration, control);
    let published;
    try {
      published = await runPublishedCapturedStrategy(setup, {store, plan});
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
        const retained = reopened.lookupDefinition({
          tenantId: 'tenant-a', authorityScopeCid: cid('a'),
          requestId: 'published-values-request',
        }, moon, control);
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
          durability: 'volatile', scopeRef: 'principal-after-restart',
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
          return {ref: requested, durability: 'volatile', revision: 0};
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
        assert.equal((await execution.status()).status, 'succeeded');
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
