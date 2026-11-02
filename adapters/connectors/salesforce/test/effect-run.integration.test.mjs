import {withFixtureConnector} from '../../../host-common/connector-manifest.fixture.mjs';

import assert from 'node:assert/strict';

import {spawn, spawnSync} from 'node:child_process';

import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';

import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';

import {createServer} from 'node:http';

import {join} from 'node:path';

import {DatabaseSync} from 'node:sqlite';

import test from 'node:test';

import {fileURLToPath} from 'node:url';

import * as moon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

import {installNodeClientEffectRun} from '../../../host-node/client-effect-run.mjs';

import {openClientRequestJournal} from '../../../host-node/client-request-journal.mjs';

import {installNodeClientSubmission} from '../../../host-node/client-submission.mjs';

import {installNodeClientRequestLookup} from '../../../host-node/client-request-lookup.mjs';

import {createClientHttpHandler} from '../../../host-node/client-http.mjs';

import {fundedClientPreparation} from '../../../host-node/funded-client-preparation.fixture.mjs';

import {completeCapturedEffectRun, runCapturedEffectComputation,
  runCapturedInternalStrategy,
  runCapturedStrategy,
  runPublishedCapturedStrategy} from '../../../host-node/entry.mjs';

import {checked} from '../../../host-common/runtime-result.mjs';

import {canonicalJson} from
  '../../../host-common/publication-contract-control.fixture.mjs';

import {runtimeCore} from '../../../host-common/runtime-core.mjs';

import {connect as connectClient, getSubmissionOutcome} from '../../../../packages/sdk/index.mjs';

const fixture = new URL('../../../../packages/sdk/fixtures/', import.meta.url);

const scratch = new URL('../../../../_build/client-program-bridge-tests/', import.meta.url);

const retireFixtureDirectory = (t, directory) => {
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
    t.diagnostic(`Retained Effect admission fixture: ${directory}`);
    return;
  }
  return rm(directory, {recursive: true, force: true});
};

const cid = digit => `sha256:${digit.repeat(64)}`;

const hashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(JSON.stringify(body))
    .digest('hex')}`;
};

const canonicalHashWithoutSelf = (value, selfKey) => {
  const body = {...value};
  delete body[selfKey];
  return `sha256:${createHash('sha256').update(canonicalJson(body))
    .digest('hex')}`;
};

const canonicalHash = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;

async function effectFixture({splitSource = false,
  splitEffectSource = 'consumer', writeKind = 'create',
  memberIds = ['save'], target = 'connector://crm/account',
  mappingRef = 'mapping:crm.account.v1', sourceIds,
  continueMembers = [], generated, labels} = {}) {
  const [documentBody, environmentBody] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
  ]);
  const targetSchema = {
    additional_properties: false,
    fields: {
      Id: {nullable: false, type: sourceIds || writeKind === 'create' ?
        'string' : 'number'},
      Name: {nullable: true, type: sourceIds ? 'string' : 'number'},
    },
    nullable: false,
    type: 'object',
  };
  if (writeKind === 'create' && sourceIds) {
    targetSchema.fields.External_Key__c = {nullable: false,
      type: 'string'};
  }
  const mapping = {
    connector_manifest_cid: cid('a'),
    conversions: [],
    mapping_contract_cid: '',
    mapping_ref: mappingRef,
    minimum_approval: 'none',
    permission_rules: [{
      effect_kind: writeKind, permissions: ['scope:' + writeKind],
      selector_class: writeKind === 'create' ? 'none' :
        writeKind === 'upsert' ? 'key' : 'id',
      write_fields: writeKind === 'create' && sourceIds ?
        ['Name', 'External_Key__c'] : ['Name'],
    }],
    primary_identity: 'Id',
    required_fields: writeKind === 'create' && sourceIds ?
      ['External_Key__c'] : [],
    required_permissions: [],
    resource_identity_cid: cid('b'),
    row_mapping: writeKind === 'create' && sourceIds ? {
      Name: {field: 'id', null_behavior: 'reject'},
      External_Key__c: {field: 'id', null_behavior: 'reject'},
    } : {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1',
    target_ref: target,
    target_schema: targetSchema,
    target_schema_identity: `sha256:${createHash('sha256')
      .update(canonicalJson(targetSchema)).digest('hex')}`,
    version: 'salesforce-v1',
    writable_fields: writeKind === 'create' && sourceIds ?
      ['Name', 'External_Key__c'] : ['Name'],
  };
  mapping.mapping_contract_cid = writeKind === 'create' && sourceIds
    ? canonicalHashWithoutSelf(mapping, 'mapping_contract_cid')
    : hashWithoutSelf(mapping, 'mapping_contract_cid');
  const environmentDocument = JSON.parse(environmentBody);
  if (generated === undefined) {
    mapping.connector_manifest_cid = withFixtureConnector(environmentDocument,
      mapping.target_ref);
    mapping.mapping_contract_cid = canonicalHashWithoutSelf(mapping,
      'mapping_contract_cid');
  } else {
    // A Site-generated execution Mapping with its declaration's Catalog and
    // manifest entry; no hand-written Mapping.
    Object.assign(mapping, JSON.parse(generated.body));
    for (const key of Object.keys(mapping)) {
      if (!(key in JSON.parse(generated.body))) delete mapping[key];
    }
    const byBody = texts => texts.map(text => JSON.parse(text)).sort(
      (a, b) => canonicalHash(a) < canonicalHash(b) ? -1 : 1);
    environmentDocument.connector_catalogs = [
      JSON.parse(generated.declared.catalog)];
    environmentDocument.source_views = byBody(
      generated.declared.source_views);
    environmentDocument.contract_registry = byBody(
      generated.declared.contracts);
    environmentDocument.connector_manifest = {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(generated.declared.manifest_entry)]};
  }
  environmentDocument.mapping_contracts = [mapping];
  environmentDocument.evidence_bundle_cid = canonicalHashWithoutSelf(
    environmentDocument, 'evidence_bundle_cid');
  const environment = moon.clientProgramCheckEnvironment(
    canonicalJson(environmentDocument),
    environmentDocument.evidence_bundle_cid,
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  const document = JSON.parse(documentBody);
  if (sourceIds) {
    document.stages[0].steps[0].values.schema.id.type = 'string';
    document.stages[0].steps[0].values.rows = sourceIds.map(id => ({id}));
  }
  if (labels) {
    // A nullable label beside each id: some rows carry null.
    document.stages[0].steps[0].values.schema.label = {type: 'string',
      nullable: true};
    document.stages[0].steps[0].values.rows = sourceIds.map((id, index) =>
      ({id, label: labels[index]}));
    document.stages[0].results.rows.fields = ['id', 'label'];
  }
  const write = writeKind === 'create'
    ? {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'}}
    : {target, mapping: mapping.mapping_ref,
      from: {result: 'rows'},
      [writeKind === 'upsert' ? 'key' : 'id']: 'id',
      set: {Name: {field: 'id'}}};
  const effects = Object.fromEntries(memberIds.map(id =>
    [id, {[writeKind]: continueMembers.includes(id)
      ? {...write, on_item_failure: 'continue'} : write}]));
  document.stages[0].effects = effects;
  if (splitSource) {
    delete document.stages[0].effects;
    document.stages.push({
      id: 'middle',
      inputs: {rows: {result: {stage: 'source', result: 'rows'}}},
      steps: [
        // An ordinary source-free producer/import chain feeding terminal Effects.
        {select: ['id'], as: 'projected'},
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
    environmentWire: canonicalJson(environmentDocument),
    mappingCid: mapping.mapping_contract_cid};
}

test('public Effect submit rejects an unsupported checked acquisition shape before Run acceptance',
  async t => {
    const terminal = await effectFixture({splitSource: true,
      writeKind: 'create', memberIds: ['save', 'save_again'],
      sourceIds: ['001000000000001', '001000000000002']});
    const terminalOutcome = moon.clientProgramPrepareEffectComputationWithParameters(
      terminal.document, 'json', terminal.environment, undefined, []);
    const supported = moon.clientProgramEffectPreparationReady(terminalOutcome);
    assert.ok(supported, moon.clientProgramEffectPreparationIssueCode(terminalOutcome));
    // The shared source-free DAG compiler now supports this terminal shape.
    // Compilation alone is not a claim that its public publication is closed.
    checked(moon.clientProgramCompileLocalEffects(supported));
    const acquired = await effectFixture({splitSource: true,
      writeKind: 'update', memberIds: ['save', 'save_again']});
    const program = JSON.parse(acquired.document);
    // The installed single-acquisition profile supports one terminal Local
    // Unit, not this checked acquisition followed by two Local Units. Keep
    // a genuinely unsupported Host shape instead of rejecting source-free DAGs.
    program.stages[0].inputs = {remote: {connector: 'crm/main', resource: 'r'}};
    program.stages[0].steps = [{select: ['id'], as: 'selected'}];
    const environmentDocument = JSON.parse(acquired.environmentWire);
    const sourceEnvironment = JSON.parse(await readFile(new URL(
      '../../../host-node/fixtures/query-amount-environment.json', import.meta.url), 'utf8'));
    for (const name of ['schema_snapshots', 'connector_capabilities',
      'connector_catalogs', 'source_views', 'contract_registry']) {
      environmentDocument[name] = [...environmentDocument[name], ...sourceEnvironment[name]]
        .sort((left, right) => canonicalHash(left) < canonicalHash(right) ? -1 : 1);
    }
    withFixtureConnector(environmentDocument, 'connector://crm/main/r#v');
    environmentDocument.evidence_bundle_cid = canonicalHashWithoutSelf(
      environmentDocument, 'evidence_bundle_cid');
    const environment = moon.clientProgramCheckEnvironment(canonicalJson(environmentDocument),
      environmentDocument.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const unsupported = {document: JSON.stringify(program), environment};
    const preparation = await fundedClientPreparation(t, {moon, environment, allowEffects: true, http: true});
    assert.equal(typeof preparation.prepareRequest, 'function');
    const prepare = preparation.prepare;
    const prepared = await prepare({kind: 'aql',
      input: {text: unsupported.document, format: 'json'},
      parameters: null});
    assert.equal(moon.clientProgramEffectCompilationIssueCode(
      moon.clientProgramCompileLocalEffects(prepared)),
    'unsupported_program');
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'unsupported-effect-submit-'));
    t.after(() => retireFixtureDirectory(t, directory));
    const journal = openClientRequestJournal(directory);
    const runs = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({
        executionContextCid: cid('a'), hostPolicyCid: cid('b'),
        createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z',
      }),
      authorizeRunStart: async () => true,
      execute: () => assert.fail('unsupported Program started execution'),
    });
    const services = {
      authenticate: header => header === 'Bearer scoped-token'
        ? 'principal-a' : undefined,
      authorizeConnection: () => true,
      negotiate: () => ({
        version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
        durability: 'durable', scopeRef: 'principal-a',
        capabilities: ['result-jsonl'],
        limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
          maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
          maxRows: 100, maxBatchRows: 10,
          maxBatchRetainedValueBytes: 2048},
      }),
      prepareRequest: preparation.prepareRequest,
      prepareSubmit: preparation.prepareSubmit,
      submit: async ({preparedProgram, requestId, principalId,
        connection, submission}) => {
        const accepted = await runs.accept({prepared: preparedProgram,
          authorityScopeCid: cid('e'), requestId, namespaceId: 'namespace-a',
          principalId, connection,
          lookupExpiresAt: '2027-01-01T00:00:00.000Z', submission});
        await runs.start(accepted);
        return {ref: accepted.ref, durability: accepted.durability,
          revision: accepted.revision};
      },
    };
    const authorizedScope = ({principalId, connection}) =>
      principalId === 'principal-a' && connection.mode === 'local' &&
      connection.owner === 'local'
        ? {authorityScopeCid: cid('e'), namespaceId: 'namespace-a'} : undefined;
    const lookupRequest = installNodeClientRequestLookup({journal,
      control: moon, authorizedScope});
    const submissions = installNodeClientSubmission({journal, moon,
      ...preparation.submission,
      authorizedScope, prepareSubmit: services.prepareSubmit,
      submit: services.submit, lookupRequest});
    const server = createServer(createClientHttpHandler({...services, lookupRequest,
      negotiate: async facts => ({...services.negotiate(facts),
        submissionEpoch: await submissions.issueEpoch(facts)}),
      // Public submit-intent carries the existing attempt envelope; the
      // lower-level submitIntent outcome is not an HTTP attempt response.
      submitIntent: submissions.submitAttempt,
      lookupSubmission: submissions.lookupSubmission}));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const client = await connectClient({mode: 'local', owner: 'local',
        endpoint: `http://127.0.0.1:${server.address().port}/`,
        token: 'scoped-token', durability: 'durable'});
      try {
        await assert.rejects(client.startSource(unsupported.document,
          {format: 'json', submissionRef: client.newSubmission({nonce: 'unsupported-effect-request'})}),
        error => {
          assert.equal(error.code, 'SubmissionPreparationFailed', JSON.stringify({
            outcome: getSubmissionOutcome(error), cause: error.cause?.message,
          }));
          assert.deepEqual(getSubmissionOutcome(error).problem,
            {code: 'ClientProgramUnsupported', classification: 'implementation_limit'});
          return true;
        });
      } finally { client.close(); }
    } finally {
      await new Promise(resolve => server.close(resolve));
      journal.close();
    }
    const database = new DatabaseSync(join(directory,
      'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(database.prepare('SELECT COUNT(*) AS n FROM client_requests')
        .get().n, 0);
    } finally { database.close(); }
  });

test('Effect publication preparation failure reserves no physical start',
  async t => {
    const fixture = await effectFixture();
    const prepare = await fundedClientPreparation(t, {moon,
      environment: fixture.environment, allowEffects: true});
    const prepared = await prepare({kind: 'aql', input: {text: fixture.document,
      format: 'json'}, parameters: null});
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-plan-failure-'));
    t.after(() => retireFixtureDirectory(t, directory));
    const journal = openClientRequestJournal(directory);
    t.after(() => journal.close());
    let physicalStarts = 0;
    const runs = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z'}),
      authorizeRunStart: async () => true,
      prepareExecution() { throw new Error('PlanIssuanceFailed'); },
      execute() { physicalStarts++; },
    });
    const accepted = await runs.accept({prepared,
      authorityScopeCid: cid('e'), requestId: 'effect-plan-failure',
      namespaceId: 'namespace-a', principalId: 'principal-a',
      connection: {mode: 'local', owner: 'local'},
      lookupExpiresAt: '2027-01-01T00:00:00.000Z'});
    await assert.rejects(runs.start(accepted), /PlanIssuanceFailed/);
    const retained = journal.lookupRunDefinition(accepted.ref, moon,
      runtimeCore(moon).publicationControl);
    assert.equal(retained.preDispatchFailureConfirmed, true);
    assert.equal(retained.physicalStartReserved, false);
    assert.equal(physicalStarts, 0);
    assert.equal((await runs.start(accepted)).kind, 'reconcile');
    assert.equal(physicalStarts, 0);
    const asyncRuns = installNodeClientEffectRun({moon, journal,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt: '2026-09-24T00:00:00.000Z',
        expiresAt: '2027-01-01T00:00:00.000Z'}),
      authorizeRunStart: async () => true,
      async prepareExecution() { throw new Error('LatePlanFailure'); },
      execute() { physicalStarts++; },
    });
    const asynchronous = await asyncRuns.accept({prepared,
      authorityScopeCid: cid('e'), requestId: 'effect-async-plan-failure',
      namespaceId: 'namespace-a', principalId: 'principal-a',
      connection: {mode: 'local', owner: 'local'},
      lookupExpiresAt: '2027-01-01T00:00:00.000Z'});
    await assert.rejects(asyncRuns.start(asynchronous),
      {name: 'TypeError', message: 'AsyncClientEffectPreparation'});
    assert.equal(journal.lookupRunDefinition(asynchronous.ref, moon,
      runtimeCore(moon).publicationControl).physicalStartReserved, false);
    assert.equal(physicalStarts, 0);
  });

test('shared Effect Client admission and physical claim survive races and restart', async t => {
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'effect-client-owner-'));
  t.after(() => retireFixtureDirectory(t, directory));
  const {document, environment, environmentWire} = await effectFixture({memberIds: ['save', 'save_again']});
  const prepare = text => {
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      text, 'json', environment, undefined, []);
    const value = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(value, moon.clientProgramEffectPreparationIssueCode(outcome));
    return value;
  };
  const prepared = prepare(document);
  const [registry, contract] = await Promise.all([
    readFile(new URL('../../../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
    readFile(new URL('../../../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'),
  ]);
  const values = JSON.stringify(JSON.parse(contract).execution_contracts['REL.values']);
  const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
    registry, values, undefined, undefined));
  const control = runtimeCore(moon).publicationControl;
  let starts = 0;
  let failAfterCapture = false;
  let currentAuthorization = true;
  let preflightCompiles = 0;
  const countedMoon = {...moon,
    clientProgramCompileLocalEffects(...args) {
      preflightCompiles++;
      return moon.clientProgramCompileLocalEffects(...args);
    }};
  const install = (journal, runtime = moon) => installNodeClientEffectRun({moon: runtime,
    publicationControl: control, journal,
    authorizeRequest: async () => currentAuthorization ? {
      executionContextCid: cid('a'), hostPolicyCid: cid('b'),
      createdAt: '2026-09-26T00:00:00.000Z',
      expiresAt: '2098-01-01T00:00:00.000Z',
    } : undefined,
    authorizeRunStart: async () => currentAuthorization,
    async execute({owner, prepared: actual, compilation}) {
      assert.equal(actual, prepared);
      assert.ok(JSON.parse(moon.clientProgramEffectCompilationPlanWire(
        compilation)).root_refs.some(root => root.role === 'effect_result'));
      starts++;
      const setup = moon.clientProgramOpenSourceFreeLocalEffectHost(
        owner, installedContracts, values, 1n, 0n, 0n, 0n, undefined, undefined);
      assert.ok(setup);
      const execution = await runCapturedEffectComputation(setup);
      await execution.close();
      assert.equal(execution.cleanupPending(), false);
      if (failAfterCapture) throw new Error('LostEffectExecutionReply');
      return 'captured';
    },
  });
  const request = id => ({prepared, authorityScopeCid: cid('a'), requestId: id,
    namespaceId: 'namespace-a', principalId: 'caller', connection: {owner: 'local'},
    lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
  let journal = openClientRequestJournal(directory);
  let other = openClientRequestJournal(directory);
  let host = install(journal, countedMoon);
  let competing = install(other);
  host.checkSupported(prepared);
  assert.equal(preflightCompiles, 1);
  const [first, second] = await Promise.all([
    host.accept(request('race')), competing.accept(request('race')),
  ]);
  assert.equal(preflightCompiles, 1,
    'accepted Run reuses the checked preflight compilation');
  assert.deepEqual(first.ref, second.ref);
  assert.equal(starts, 0, 'acceptance never starts capture');
  assert.deepEqual((await Promise.all([host.start(first), competing.start(second)]))
    .map(value => value.kind).sort(), ['reconcile', 'started']);
  assert.equal(starts, 1);
  assert.equal((await host.start(first)).kind, 'reconcile');
  const changed = JSON.parse(document);
  changed.id = 'changed-effect-intent';
  await assert.rejects(host.accept({...request('race'), prepared: prepare(JSON.stringify(changed))}),
    {code: 'ClientRequestIntentConflict'});
  const unstarted = await host.accept(request('unstarted'));
  // Reserve dispatch, crash before the separate physical-start claim.
  const identity = moon.clientProgramEffectRequestIdentity(prepared, cid('a'),
    'unstarted', moon.clientProgramSourceFreeInputIntentCid());
  journal.reserveDispatch(identity, {namespaceId: 'namespace-a', currentAuthorization: true}, moon, control);
  other.close(); journal.close();
  journal = openClientRequestJournal(directory);
  host = install(journal);
  const resumed = await host.accept(request('unstarted'));
  assert.deepEqual(resumed.ref, unstarted.ref);
  assert.equal((await host.start(resumed)).kind, 'started');
  assert.equal(starts, 2);
  const gated = await host.accept(request('gated-start'));
  const gateCalls = [];
  await assert.rejects(host.start(gated, {
    beforePhysicalStart() {
      gateCalls.push('before');
      throw new Error('ResumeClaimStale');
    },
    started() { gateCalls.push('started'); },
  }), /ResumeClaimStale/);
  assert.deepEqual(gateCalls, ['before']);
  assert.equal(starts, 2);
  const gatedIdentity = moon.clientProgramEffectRequestIdentity(prepared,
    cid('a'), 'gated-start', moon.clientProgramSourceFreeInputIntentCid());
  assert.equal(journal.resolveDefinition(gatedIdentity, {namespaceId: 'namespace-a'},
    moon, control).physicalStartReserved, false);
  assert.equal((await host.start(gated, {
    beforePhysicalStart() { gateCalls.push('before'); },
    started() { gateCalls.push('started'); },
  })).kind, 'started');
  assert.deepEqual(gateCalls, ['before', 'before', 'started']);
  assert.equal(starts, 3);
  failAfterCapture = true;
  const unknown = await host.accept(request('unknown'));
  await assert.rejects(host.start(unknown), /LostEffectExecutionReply/);
  assert.equal(starts, 4);
  journal.close();
  journal = openClientRequestJournal(directory);
  t.after(() => journal.close());
  host = install(journal);
  const recovered = await host.accept(request('unknown'));
  assert.deepEqual(recovered.ref, unknown.ref);
  assert.equal((await host.start(recovered)).kind, 'reconcile');
  assert.equal(starts, 4, 'unknown Effect outcome never retries capture/apply');
  const pendingProcess = await host.accept(request('process-unstarted'));
  journal.close();
  const child = spawnSync(process.execPath, [fileURLToPath(new URL(
    './fixtures/resume-client-effect-run.mjs', import.meta.url))], {
    input: JSON.stringify({directory, document, environmentWire, registry, values,
      requestId: 'process-unstarted'}), encoding: 'utf8', timeout: 20000,
  });
  assert.equal(child.status, 0, child.stderr);
  const childResult = JSON.parse(child.stdout);
  assert.equal(childResult.kind, 'started');
  assert.equal(childResult.captures, 1);
  assert.deepEqual(childResult.ref, pendingProcess.ref);
  const replayChild = spawnSync(process.execPath, [fileURLToPath(new URL(
    './fixtures/resume-client-effect-run.mjs', import.meta.url))], {
    input: JSON.stringify({directory, document, environmentWire, registry, values,
      requestId: 'unknown'}), encoding: 'utf8', timeout: 20000,
  });
  assert.equal(replayChild.status, 0, replayChild.stderr);
  assert.deepEqual(JSON.parse(replayChild.stdout), {
    kind: 'reconcile', captures: 0, ref: unknown.ref,
  });
  journal = openClientRequestJournal(directory);
  host = install(journal);
  const attached = await host.accept(request('unknown'));
  currentAuthorization = false;
  await assert.rejects(host.start(attached), {code: 'ClientRunStartDenied'});
  await assert.rejects(host.accept(request('unknown')), {code: 'ClientEffectRunDenied'});
});

test('shared Effect start rejects expired saved admission before capture',
  async t => {
    await mkdir(scratch, {recursive: true});
    const directory = await mkdtemp(join(scratch.pathname,
      'effect-client-deadline-'));
    t.after(() => retireFixtureDirectory(t, directory));
    const {document, environment} = await effectFixture({
      memberIds: ['save', 'save_again'],
    });
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      document, 'json', environment, undefined, []);
    const prepared = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome));
    const control = runtimeCore(moon).publicationControl;
    let clock = '2026-09-26T00:00:01.000Z';
    let createdAt = '2026-09-26T00:00:00.000Z';
    let expiresAt = '2026-09-26T00:00:02.000Z';
    let expireDuringAuthorization = false;
    let authorizationCalls = 0;
    let physicalStarts = 0;
    const install = journal => installNodeClientEffectRun({moon,
      publicationControl: control, journal, now: () => clock,
      authorizeRequest: async () => ({executionContextCid: cid('a'),
        hostPolicyCid: cid('b'), createdAt, expiresAt}),
      authorizeRunStart: async () => {
        authorizationCalls++;
        if (expireDuringAuthorization && authorizationCalls === 2) {
          clock = expiresAt;
        }
        return true;
      },
      execute: async () => { physicalStarts++; return 'captured'; },
    });
    const request = requestId => ({prepared, authorityScopeCid: cid('a'),
      requestId, namespaceId: 'namespace-a', principalId: 'caller',
      connection: {owner: 'local'},
      lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
    let journal = openClientRequestJournal(directory);
    let host = install(journal);
    createdAt = '2020-01-01T00:00:00.000Z';
    expiresAt = '2021-01-01T00:00:00.000Z';
    await assert.rejects(host.accept(request('expired-new')),
      {code: 'ClientEffectRunExpired'});
    createdAt = '2026-09-26T00:00:00.000Z';
    expiresAt = '2026-09-26T00:00:02.000Z';
    const delayed = await host.accept(request('expired-before-start'));
    clock = expiresAt;
    await assert.rejects(host.start(delayed),
      {code: 'ClientEffectRunExpired'});
    assert.equal(journal.resolveDefinition(
      moon.clientProgramEffectRequestIdentity(prepared, cid('a'),
        'expired-before-start', moon.clientProgramSourceFreeInputIntentCid()),
      {namespaceId: 'namespace-a'}, moon, control).physicalStartReserved, false);
    clock = '2026-09-26T00:00:01.000Z';
    authorizationCalls = 0;
    expireDuringAuthorization = true;
    const pending = await host.accept(request('expired-during-authority'));
    await assert.rejects(host.start(pending),
      {code: 'ClientEffectRunExpired'});
    expireDuringAuthorization = false;
    authorizationCalls = 0;
    clock = '2026-09-26T00:00:01.000Z';
    const restarting = await host.accept(request('expired-after-restart'));
    journal.close();
    journal = openClientRequestJournal(directory);
    t.after(() => journal.close());
    host = install(journal);
    clock = '2026-09-26T00:00:03.000Z';
    expiresAt = '2098-01-01T00:00:00.000Z';
    const reaccepted = await host.accept(request('expired-after-restart'));
    assert.deepEqual(reaccepted.ref, restarting.ref);
    await assert.rejects(host.start(reaccepted),
      {code: 'ClientEffectRunExpired'});
    assert.equal(physicalStarts, 0);
    clock = '2026-09-26T00:00:01.000Z';
    expiresAt = '2026-09-26T00:00:03.000Z';
    const valid = await host.accept(request('valid-control'));
    assert.equal((await host.start(valid)).kind, 'started');
    assert.equal(physicalStarts, 1);
    clock = '2026-09-26T00:00:04.000Z';
    assert.equal((await host.start(valid)).kind, 'reconcile');
    assert.equal(physicalStarts, 1);
  });
