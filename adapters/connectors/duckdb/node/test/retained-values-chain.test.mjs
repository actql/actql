import {publicationOriginalFixture, adoptCapturedPublicationFixture} from '../../../../host-node/fixtures/local-publication-original.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import {createHash} from 'node:crypto';
import {DuckDBInstance} from '@duckdb/node-api';
import * as moon from '../../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as fixture from '../../../../../_build/js/release/build/connectors/duckdb/conformance/conformance.js';
import {canonicalText} from '../../../../../scripts/check-canonical-json.mjs';
import {runtimeCore} from '../../../../host-common/runtime-core.mjs';
import {openFundedClientPreparation} from '../../../../host-node/funded-client-preparation.fixture.mjs';
import {createNodeHostEntry} from '../../../../host-node/entry.mjs';
import {installStrategyContributions} from '../../../../connectors-builtin/strategy.generated.mjs';
import {checked} from '../../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../../host-common/compiler-binding.generated.mjs';
import {sourceFreeTaskPlan, acquiredTaskRunAdmission,
  acquiredTaskPublicationPlan} from '../../../../host-node/local-values-plan.mjs';
import {authorizeLocalDatabase} from '../session.mjs';
import {runNativeHostQuery, runRetainedNativeHostQuery, nativeSourceIdentityMatches,
  issueNativeSourceEvidence} from '../host.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {installLocalRetainedStore} from '../../../../local-node/retained-store.mjs';
import {createLocalRetainedStore} from '../../../../store-local/files.mjs';
import {identifyRetainedCapturedSource} from '../../../../local-node/captured-source-identity.mjs';
import {openLocalPublicationStore} from '../../../../store-local/publication-store.mjs';
import {pinnedEngineContracts} from './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../../../../', import.meta.url));
const cid = digit => `sha256:${digit.repeat(64)}`;
const resultNames = ['published', 'consumed_a', 'consumed_b'];

async function assertPublishedRows(publication, plan, execution, expected) {
  const inventory = execution.publicationInventory.occurrences;
  assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
  for (const name of resultNames) {
    const occurrence = inventory.find(value => value.name === name);
    const chunks = [];
    const result = await publication.consumeCommittedResult({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, occurrence.definitionContract.identity, () => true,
    chunk => chunks.push(Buffer.from(chunk)));
    assert.equal(result.rowCount, expected.length);
    assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
  }
}

function program(rows, filter = 'id >= 2') {
  const consumers = ['a', 'b'].map(name => ({
    id: `consumer_${name}`,
    inputs: {r: {result: {stage: 'source', result: 'out'}}},
    steps: [{from: 'r', select: ['id'], as: 'selected'}],
    results: {out: {from: 'selected', fields: ['id']}},
  }));
  return JSON.stringify({version: 'actql/0.1', id: 'retained-values-chain',
    stages: [{id: 'source', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false}}, rows},
        as: 'seed'},
      {filter, as: 'kept'},
      {select: ['id'], as: 'selected'},
    ], results: {out: {from: 'selected', fields: ['id']}}}, ...consumers],
    results: Object.fromEntries(resultNames.map((name, index) => [name,
      {from: {stage: index === 0 ? 'source' : `consumer_${index === 1 ? 'a' : 'b'}`,
        result: 'out'}}])),
  });
}

function capturedProgram(filter = 'id >= 2', sort = true) {
  const document = JSON.parse(program([]));
  document.id = 'retained-captured-chain';
  document.params = {minimum: {type: 'number', nullable: false}};
  document.stages.unshift({id: 'acquire',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{filter: 'id > $minimum', as: 'scanned'},
      {select: ['id'], as: 'captured'}],
    results: {out: {from: 'captured', fields: ['id']}},
  });
  document.stages[1].inputs = {r: {result: {stage: 'acquire', result: 'out'}}};
  document.stages[1].steps = [{from: 'r', filter, as: 'kept'},
    ...(sort ? [{from: 'kept', sort: [{id: 'asc'}], as: 'ordered'}] : []),
    {from: sort ? 'ordered' : 'kept', select: ['id'], as: 'selected'}];
  return JSON.stringify(document);
}

// This is the post-capture projection from the independent INFER KEEP
// fixture. Values supplies already captured outcomes; it is not evidence of
// model dispatch, acquisition capture, or replay.
function objectPropertyProgram(filtered) {
  const document = JSON.parse(program([]));
  document.id = 'retained-object-property';
  const field = name => ({field: name});
  const property = (value, name) => ({property: {value, name}});
  const assessment = field('assessment');
  const fields = filtered ? ['id', 'risk'] : ['id', 'note', 'assessment'];
  document.stages[0].steps = [
    {values: {schema: {
      id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true},
      outcome: {type: 'string', nullable: false},
      value: {type: 'object', nullable: true, fields: {
        risk: {type: 'string', nullable: false},
        reason: {type: 'string', nullable: true},
      }},
    }, rows: [
      {id: 'a', text: 'urgent', outcome: 'ok', value: {risk: 'high', reason: null}},
      {id: 'b', text: null, outcome: 'failed:refusal', value: null},
    ]}, as: 'captured'},
    {from: 'captured', derive: {assessment: {object: {
      input_key: {object: {id: field('id')}},
      outcome: field('outcome'), value: field('value'),
    }}, note: field('text')}, as: 'kept'},
    ...(filtered ? [
      {from: 'kept', filter: {and: [
        {eq: [property(assessment, 'outcome'), {literal: 'ok'}]},
        {eq: [property(property(assessment, 'value'), 'risk'), {literal: 'high'}]},
      ]}, as: 'accepted'},
      {from: 'accepted', derive: {risk:
        property(property(assessment, 'value'), 'risk')}, as: 'risk_rows'},
    ] : []),
    {from: filtered ? 'risk_rows' : 'kept', select: fields, as: 'selected'},
  ];
  document.stages[0].results.out.fields = fields;
  for (const consumer of document.stages.slice(1)) {
    consumer.steps[0].select = fields;
    consumer.results.out.fields = fields;
  }
  return JSON.stringify(document);
}

function familyProgram(family, filter = 'id >= 1') {
  const document = JSON.parse(program([]));
  document.id = `retained-installed-${family}`;
  const rows = [{id: 3}, {id: 1}, {id: 2}];
  const values = family === 'vectors'
    ? {schema: {id: {type: 'number', nullable: false},
      embedding: {type: 'vector', dimensions: 2, nullable: false}},
    rows: rows.map(({id}) => ({id, embedding: [0, 2]}))}
    : family === 'graph'
      ? {schema: {id: {type: 'number', nullable: false},
        src: {type: 'number', nullable: false}, dst: {type: 'number', nullable: false}},
      rows: rows.map(({id}) => ({id, src: id, dst: id}))}
      : {schema: {id: {type: 'number', nullable: false}}, rows};
  const bridge = family === 'events'
    ? {from: 'seed', to_events: {id: 'id', time: 'id'}, as: 'carrier'}
    : family === 'vectors'
      ? {from: 'seed', to_vectors: {id: 'id', vector: 'embedding'}, as: 'carrier'}
      : {graph: {version:'actql-graph-constructor/0.1',
        nodes:[{name:'N',from:'seed',key:['id'],labels:[{name:'Node',
          properties:{mode:'columns',columns:[{from:'id',to:'id'}]}}]}],
        edges:[{name:'E',from:'seed',key:['id'],
          source:{definition:'N',key:['src']},target:{definition:'N',key:['dst']},
          labels:[{name:'Link',properties:{mode:'no_properties'}}]}]},as:'carrier'};
  const compute = family === 'events'
    ? {watermark_events: {watermark_ms: 2, policy: 'mark'}}
    : {normalize_vectors: true};
  const projection = family === 'events' ? {events: true}
    : {vectors: true};
  const fields = family === 'events' ? ['id', 'late']
    : family === 'vectors' ? ['id', 'embedding'] : ['id'];
  document.stages[0].steps = [{values, as: 'seed'}, bridge,
    ...(family === 'graph' ? [{from:'carrier',match_nodes:{definition:'N',
      where:'true',fields:['id']},as:'rows'}] : [
      {from: 'carrier', ...compute, as: 'computed'},
      {from: 'computed', ...projection, as: 'rows'},
    ]),
    {from: 'rows', filter, as: 'kept'},
    {from: 'kept', sort: [{id: 'desc'}], as: 'ordered'},
    {from: 'ordered', select: fields, as: 'selected'}];
  document.stages[0].results.out.fields = fields;
  for (const consumer of document.stages.slice(1)) {
    consumer.steps[0].select = fields;
    consumer.results.out.fields = fields;
  }
  return JSON.stringify(document);
}

// Use the checked acquisition planner and real native capture. The
// test installs Compute configuration directly; public Client dispatch mode
// selection remains with its Host owner.
async function openCapturedRetained(prepared, contracts, installedContracts, directory, rows, budgets,
  fileInput = false, retainPublication) {
  const [registry, values, fragment, ordered] = contracts;
  const planned = moon.clientProgramPrepareLocalQueryRequirement(
    prepared, 0, 0, installedContracts, values, fragment, ordered);
  assert.equal(planned?.$tag, 1, `captured requirement: ${inspect(planned, {depth: 8})}`);
  const requirement = checked(planned);
  const facts = checked(moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
  const [sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid] = facts;
  const context = checked(moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
  const bodies = await Promise.all(['actql-query-acquisition.json',
    'actql-query-process-evidence.json', 'actql-query-two-receipt.json']
    .map(name => readFile(join(root, 'spec/contracts', name), 'utf8')));
  const acquisition = checked(moon.clientProgramPrepareDuckDBAcquisition(
    requirement, 'main', 'records', ...bodies));
  const limits = {
    maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
    maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
    memoryBytes: 128 * 1024 * 1024, threads: 1,
  };
  // Adopt the typed Plan on the original Request before any physical capture.
  retainPublication(acquisition, limits);
  const databasePath = join(directory, 'records.duckdb');
  const database = await DuckDBInstance.create(databasePath);
  const connection = await database.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    for (const row of rows) {
      await connection.run('INSERT INTO records VALUES ($1, NULL)', [row.id]);
    }
  } finally {
    connection.closeSync();
    database.closeSync();
  }
  const grant = await authorizeLocalDatabase(databasePath, {
    ...fixtureSourceAccess, sourceRef,
  });
  const captureStartedAt = new Date().toISOString();
  const capture = fileInput
    ? await runRetainedNativeHostQuery(grant, acquisition, limits, {
      parentDirectory: directory, maxFrameBytes: 4096,
      wire: {max_columns: 10, max_order_work: 10000, max_bytes: 100000,
        max_nodes: 10000, max_depth: 64},
    }) : await runNativeHostQuery(grant, acquisition, limits);
  try {
    const captureCompletedAt = new Date().toISOString();
    const source = capture.source();
    assert.equal(moon.clientProgramCapturedSourceMatches(prepared, source), true);
    const identity = fileInput
      ? await identifyRetainedCapturedSource(moon, source)
      : checked(moon.clientProgramIdentifyCapturedSourceRelation(source));
    if (fileInput && rows.length === 0) {
      // Independent SHA-256 of {"sort":"relation","value":[]}.
      assert.equal(moon.clientProgramCapturedSourceLogicalCid(identity),
        'sha256:d2889f6d3b43fe20f75149d13eb0585918c94cf3a5b0520f5f9e1525b0846f3d');
    }
    assert.equal(nativeSourceIdentityMatches(capture, identity), true);
    const logicalInput = checked(moon.clientProgramIssueCapturedSourceLogical(
      prepared, source, identity, requirement));
    const setup = budgets
      ? fixture.strategyFixtureCapturedRetainedSubset(prepared, source,
        registry, values, fragment, budgets.work, budgets.workspace)
      : moon.clientProgramOpenCapturedLocalRetainedHost(prepared,
        source, installedContracts, values, 1n, 0n, 0n, 0n, fragment, ordered);
    assert.ok(setup, 'the product captured factory must install retained output');
    return {setup, capture, identity, logicalInput, requirement,
      checkedSource: {sourceRef, sourceContractCid, carrierSchemaContractCid,
        sourceDataPolicyCid, dataClassification, sourceViewContractCid},
      captureStartedAt, captureCompletedAt,
      issueSourceEvidence: options => issueNativeSourceEvidence(capture,
        {...options, context, identity, logicalInput})};
  } catch (error) {
    capture.close();
    await capture.cleanupHandle?.retry();
    throw error;
  }
}

async function retainedRun(document, use, mode = 'success', budgets, captureRows,
  fileInput = false, route = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retained-values-chain-'));
  let retained, publication, owner, execution, captured, publicationFailure, preparation;
  let prepared, captureRun, capturePreparation, captureRequestIdentity;
  let permitCleanup = mode !== 'finalize-failure' && !route.publicationFault;
  let dispatches = 0, appendsFailed = 0, finalizationsFailed = 0;
  let producerWork = 0n, sawStop = false, scheduled = false;
  let receiptProgress;
  const receiptTrace = [];
  const exportTrace = [];
  let exportSteps = 0;
  let exportPreparationSteps = 0;
  const exportPreparationTrace = [];
  let completedDispatches = 0, resultPreparationSteps = 0;
  let resultOrderReached = false, resultPreparationCancels = 0;
  let resultSchemaReached = false;
  const observedDispatch = route.cancelDispatch ?? 1;
  const cancellation = new AbortController();
  try {
    const body = JSON.parse(await readFile(join(root, captureRows
      ? 'adapters/host-node/fixtures/query-amount-environment.json'
      : 'packages/sdk/fixtures/values.environment.json'), 'utf8'));
    if (route.family === 'graph' || route.observeSchemaPreparation) {
      if (route.family === 'graph') Object.assign(body.host_policy_profile.capacity, {
        max_graph_construction_input_rows: 1000,
        max_graph_construction_nodes: 1000, max_graph_construction_edges: 1000,
      });
      // Two independently authored 65-field object cells fit this explicit
      // fixture policy. This is not an exact nested-byte boundary test.
      if (route.observeSchemaPreparation) {
        body.host_policy_profile.capacity.max_nested_value_bytes = 4096;
      }
      delete body.evidence_bundle_cid;
      body.evidence_bundle_cid = 'sha256:' + createHash('sha256')
        .update(canonicalText(body)).digest('hex');
    }
    const checkArguments = [canonicalText(body), body.evidence_bundle_cid,
      false, route.family === 'vectors', true, route.family === 'graph',
      route.family === 'events', false, false];
    const environment = route.family === 'graph'
      ? moon.clientProgramCheckEnvironmentWithGraphProfile(
        ...checkArguments,
        'sha256:' + createHash('sha256').update(canonicalText(JSON.parse(
          await readFile(join(root,'spec/contracts/actql-numeric-reduction.json'),'utf8'),
        ))).digest('hex'),
        'sha256:' + createHash('sha256').update(canonicalText(JSON.parse(
          await readFile(join(root,
            'spec/dependencies/actql-graph-laws.json'),'utf8'),
        ))).digest('hex'),
      )
      : moon.clientProgramCheckEnvironment(...checkArguments);
    assert.ok(environment);
    preparation = await openFundedClientPreparation({moon, environment, retainedRelationOutput: true});
    const preparationRequest = {kind: 'aql', input: {text: document, format: 'json'},
      parameters: captureRows ? {minimum: 0} : null};
    try {
      prepared = await preparation.prepare(preparationRequest);
    } catch (error) {
      throw new Error(`${error.message}: ${inspect(error.cause, {depth: 4})}`,
        {cause: error});
    }
    const contracts = await pinnedEngineContracts(root, ['registered_body',
      'registered_values', 'registered_fragment', 'registered_ordered']);
    const [registry, values, fragment, ordered] = contracts;
    const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
      registry, values, fragment, ordered));
    if (captureRows) {
      captureRequestIdentity = moon.clientProgramRequestIdentity(prepared,
        cid('a'), 'retained-captured-chain', cid('b'));
      assert.ok(captureRequestIdentity);
      captured = await openCapturedRetained(prepared,
        contracts, installedContracts, directory, captureRows, budgets, fileInput,
        (acquisition, limits) => {
          captureRun = adoptCapturedPublicationFixture({moon, preparation,
            prepared, request: preparationRequest, identity: captureRequestIdentity,
            acquisition, limits, installedContracts, contracts});
          assert.ok(captureRun);
          // Retain the actual returned Run before any later projection can fail.
          const publicationPreparation = preparation.manager.publicationPreparation(prepared);
          assert.strictEqual(publicationPreparation, captureRun.value);
          capturePreparation = Object.freeze({publicationPreparation,
            publicationOriginal: Object.freeze({kind: 'installed_run', value: publicationPreparation}),
            compilationOriginal: preparation.manager.compilationOriginal(prepared)});
        });
    }
    // Boundary injection uses the same checked owner, installed provider and
    // retained driver. Ordinary success/fault cases use the product factory.
    const setup = captured?.setup ?? (budgets
      ? fixture.strategyFixtureSourceFreeRetainedSubset(prepared,
        registry, values, fragment, budgets.work, budgets.workspace)
      : moon.clientProgramOpenSourceFreeLocalRetainedHost(
        prepared, installedContracts, values, 1n, 0n, 0n, 0n, fragment, undefined));
    assert.ok(setup, 'the checked retained factory must admit this chain');
    const first = captured ? 1 : 0;
    // Existing Relation chains remain one task. Carrier fixtures explicitly
    // require the checked DAG's selected boundaries, not authored Stage splits.
    const expectedSteps = route.taskSteps ?? [
      JSON.parse(document).stages[first].steps.length, 1, 1,
    ];
    for (const [index, count] of expectedSteps.entries()) {
      assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup, first + index),
        count, `physical task ${index}`);
    }
    assert.equal(fixture.strategyFixtureConfiguredTaskStepCount(setup,
      first + expectedSteps.length), undefined);
    const observedMoon = new Proxy(moon, {
      get(target, property, receiver) {
        if (route.observePublicationValidation &&
            ['strategyEffectFreeRunEvidenceChainValid',
              'strategyEffectFreePublicationCommitValid'].includes(property)) {
          return () => assert.fail('blocking publication validation');
        }
        if (route.observePublicationValidation &&
            property === 'strategyBeginEffectFreeChainCheckRetained') {
          const original = Reflect.get(target, property, receiver);
          return (...args) => {
            const preparation = Reflect.apply(original, target, args);
            route.retainedChainStarts = (route.retainedChainStarts ?? 0) + 1;
            assert.equal(target.strategyEffectFreeChainCheckFixturePhase(preparation), 'done',
              'the same retained original must not repeat computation checking');
            if (route.cancelValidationPhase === 'before-retained-check') {
              scheduled = true;
              cancellation.abort();
            }
            return preparation;
          };
        }
        if (route.observePublicationValidation &&
            property === 'strategyEffectFreeChainCheckAdvance') {
          return preparation => {
            const result = target[property](preparation, 1);
            route.validationPolls = (route.validationPolls ?? 0) + 1;
            assert.equal(result, 1, 'the original computation proof is already complete');
            assert.equal(completedDispatches, 3);
            if (route.cancelValidationPhase === 'after-retained-check') {
              scheduled = true;
              cancellation.abort();
            }
            return result;
          };
        }
        if (route.observePublicationValidation &&
            property === 'strategyEffectFreeChainCheckCancel') {
          return preparation => {
            target[property](preparation);
            route.validationCancels = (route.validationCancels ?? 0) + 1;
            assert.equal(preparation.live, 0);
            assert.equal(preparation.inputs, undefined);
          };
        }
        if (route.observePublicationValidation &&
            property === 'clientStoreAdvanceOriginalValidation') {
          return validation => {
            const state = validation.state;
            assert.ok(state);
            const checker = runtimeField(state, 0);
            const result = target[property](validation, 1);
            const complete = runtimeField(checked(result), 0);
            assert.equal(typeof complete, 'boolean');
            route.commitPolls = (route.commitPolls ?? 0) + 1;
            const phase = target.strategyEffectFreeCommitCheckFixturePhase(checker);
            (route.commitPhases ??= new Set()).add(phase);
            for (const [name, label] of [['resultEvidencePolls', 'result-evidence'],
              ['bindingPolls', 'bindings'], ['namespacePolls', 'namespace-check']]) {
              if (phase === label) route[name] = (route[name] ?? 0) + 1;
            }
            if (!complete) {
              assert.strictEqual(validation.state, state);
              assert.strictEqual(runtimeField(validation.state, 0), checker);
            }
            return result;
          };
        }
        if (route.observePublicationValidation &&
            property === 'clientStoreCancelOriginalValidation') {
          return validation => {
            target[property](validation);
            route.storeValidationRetirements = (route.storeValidationRetirements ?? 0) + 1;
            assert.equal(validation.state, undefined);
          };
        }
        if (route.observeCapturePreparation &&
            ['strategyIssueEffectFreeCapturedRun',
              'strategyIssueEffectfulCapturedRun'].includes(property)) {
          return () => assert.fail('blocking Captured Run issuance');
        }
        if (route.observeCapturePreparation &&
            property === 'strategyCapturedRunAdvance') {
          return preparation => {
            const before = target.strategyCapturedRunFixturePhase(preparation);
            const result = target[property](preparation,
              ['snapshot-inventory', 'root-check', 'rows-check'].includes(route.cancelCapturePhase) &&
                before === route.cancelCapturePhase ? 1 : 32);
            const complete = checked(result);
            const phase = target.strategyCapturedRunFixturePhase(preparation);
            route.capturePolls = (route.capturePolls ?? 0) + 1;
            (route.capturePhases ??= new Set()).add(phase);
            route.capturePhases.add(before);
            if (before === 'root-check' || phase === 'root-check') {
              route.captureRootPolls = (route.captureRootPolls ?? 0) + 1;
              assert.equal(complete, false);
            }
            if (phase === 'snapshot-inventory') {
              route.captureSnapshotPolls = (route.captureSnapshotPolls ?? 0) + 1;
              assert.equal(complete, false);
            }
            assert.equal(completedDispatches, 3);
            if (mode === 'cancel-during-captured-run' && !scheduled &&
                (phase === route.cancelCapturePhase || before === route.cancelCapturePhase) &&
                route.capturePolls > 1 &&
                (phase !== 'snapshot-inventory' || route.captureSnapshotPolls >= 3)) {
              assert.equal(complete, false);
              assert.ok(route.capturePolls > 1);
              scheduled = true;
              if (route.cancelCapturePhase === 'root-check') cancellation.abort();
              else if (route.cancelCapturePhase === 'rows-check') {
                // Cancel while the original row checker is still pending;
                // a timer can otherwise arrive after retained completion.
                assert.equal(phase, 'rows-check');
                cancellation.abort();
              }
              else setTimeout(() => cancellation.abort(), 0);
            }
            return result;
          };
        }
        if (route.observeCapturePreparation &&
            property === 'strategyCapturedRunCancel') {
          return preparation => {
            const completed = target.strategyCapturedRunFixturePhase(preparation) === 'retained';
            target[property](preparation);
            // Completed managed-view retirement is separate from cancellation;
            // Store, Compute and physical acknowledgements remain with their Owners.
            const counter = completed ? 'captureRetirements' : 'captureCancels';
            route[counter] = (route[counter] ?? 0) + 1;
            assert.equal(target.strategyCapturedRunFixturePhase(preparation), 'closed');
            assert.equal(preparation.live, 0);
            assert.equal(preparation.inputs, undefined);
          };
        }
        if (route.observeSnapshotPreparation &&
            property === 'strategyHostOutputSnapshotAdvance') {
          return value => {
            const result = target[property](value, 1);
            const complete = checked(result);
            const admission = value.phase.$tag === 1 ? value.phase._0 : undefined;
            const canonical = admission?.phase.$tag === 2
              ? admission.phase._0 : undefined;
            if (canonical?.text?.offset >= 64) {
              route.snapshotTextReached = true;
              if (mode === 'cancel-during-result-snapshot' && !scheduled) {
                assert.equal(complete, false);
                assert.equal(completedDispatches, 3);
                assert.notEqual(value.parent.receipt, undefined);
                assert.notEqual(value.parent.retained, undefined);
                scheduled = true;
                setTimeout(() => cancellation.abort(), 0);
              }
            }
            return result;
          };
        }
        if (route.observeSnapshotPreparation &&
            property === 'strategyHostOutputSnapshotCancel') {
          return value => {
            const parent = value.parent;
            const admission = value.phase.$tag === 1 ? value.phase._0 : undefined;
            target[property](value);
            route.snapshotCancels = (route.snapshotCancels ?? 0) + 1;
            assert.equal(value.parent, undefined);
            assert.equal(admission.live, 0);
            assert.equal(admission.fields.length, 0);
            // The child has no release authority over the parent Result pin.
            assert.notEqual(parent.receipt, undefined);
            assert.notEqual(parent.retained, undefined);
          };
        }
        if (route.observeResultPreparation &&
            property === 'strategyHostResultTransformationAdvance') {
          return value => {
            const result = target[property](value, 1);
            const complete = checked(result);
            assert.equal(typeof complete, 'boolean');
            resultPreparationSteps++;
            // Read the real common cursor only to place cancellation. This
            // whitebox observation creates no replacement execution state.
            const rows = value.core.preparation.preparation.rows;
            const schema = value.core.preparation.preparation.metadata?.schema_cursor;
            if (route.observeSchemaPreparation && schema?.phase === 4 &&
                schema.contract?.pending.some(frame =>
                  typeof frame._1 === 'number' &&
                  Array.isArray(frame._0?.values) && frame._1 >= 4)) {
              resultSchemaReached = true;
              if (mode === 'cancel-during-result-schema' && !scheduled) {
                assert.equal(completedDispatches, 3);
                assert.equal(complete, false);
                assert.notEqual(value.core.borrow, undefined);
                scheduled = true;
                setTimeout(() => cancellation.abort(), 0);
              }
            }
            if (rows.comparison.phase === 3 && rows.comparison.offset > 20) {
              resultOrderReached = true;
              if (mode === 'cancel-during-result-order' && !scheduled) {
                assert.equal(completedDispatches, 3);
                assert.equal(complete, false);
                assert.equal(rows.closed, false);
                assert.notEqual(value.core.borrow, undefined);
                scheduled = true;
                setTimeout(() => cancellation.abort(), 0);
              }
            }
            return result;
          };
        }
        if (route.observeResultPreparation &&
            property === 'strategyHostResultTransformationCancel') {
          return value => {
            target[property](value);
            resultPreparationCancels++;
            assert.equal(value.core.borrow, undefined);
            assert.equal(value.core.preparation.preparation.rows.closed, true);
          };
        }
        if (property !== 'strategyModule_local_Dispatch' &&
            property !== 'strategyModule_local_ManagedStart') {
          return Reflect.get(target, property, receiver);
        }
        return (...args) => {
          const dispatch = ++dispatches;
          const operations = checked(target[property](...args));
          return {$tag: 1, _0: new Proxy(operations, {
            get(operation, name, receiver) {
              if (name === 'execute') return () => assert.fail('synchronous Compute');
              if ((route.observeResultPreparation || route.observeCapturePreparation ||
                  route.observePublicationValidation) &&
                  name === 'complete') {
                return (...args) => {
                  const result = operation.complete(...args);
                  if (result.$tag === 1) completedDispatches++;
                  return result;
                };
              }
              if (name === 'output' && (route.observeExport || route.observePreparation) &&
                  dispatch === observedDispatch) {
                const output = Reflect.get(operation, name, receiver);
                assert.ok(output, 'this Program must select the actual row-file output');
                return new Proxy(output, {
                  get(exporter, field, receiver) {
                    if (field === 'next') return () => assert.fail('blocking row export');
                    if (field === 'prepare') return () => {
                      const result = exporter.prepare(1);
                      if (result.$tag === 1) {
                        exportPreparationSteps += result._0._1;
                        if (exportPreparationTrace.length < 16) exportPreparationTrace.push({
                          complete: result._0._0, steps: result._0._1});
                        if (mode === 'cancel-during-export-preparation' && !scheduled &&
                            exportPreparationSteps === 10) {
                          assert.equal(result._0._0, false);
                          scheduled = true;
                          setTimeout(() => cancellation.abort(), 0);
                        }
                      }
                      return result;
                    };
                    if (field !== 'advance') return Reflect.get(exporter, field, receiver);
                    return () => {
                      const result = exporter.advance(1);
                      if (result.$tag === 1) {
                        exportSteps += result._0.steps;
                        if (exportTrace.length < 16) exportTrace.push({
                          complete: result._0.complete, batchReady: result._0.batch != null,
                          steps: result._0.steps});
                        if (mode === 'cancel-during-export' && !scheduled && exportSteps === 10) {
                          assert.equal(result._0.complete, false);
                          assert.equal(result._0.batch, undefined);
                          scheduled = true;
                          setTimeout(() => cancellation.abort(), 0);
                        }
                      }
                      return result;
                    };
                  },
                });
              }
              if (name === 'execution_stopped') return () => {
                const stopped = operation.execution_stopped();
                if (dispatch === observedDispatch && cancellation.signal.aborted && stopped) {
                  sawStop = true;
                }
                return stopped;
              };
              if (name === 'advance_finalization' && mode === 'cancel-during-receipt') {
                return quantum => {
                  const result = operation.advance_finalization(Math.min(quantum, 1));
                  if (dispatch === observedDispatch && result.$tag === 1 &&
                      receiptTrace.length < 32) {
                    receiptTrace.push({progress: result._0.progress,
                      complete: result._0.complete, material: operation.material() != null});
                  }
                  if (dispatch === observedDispatch && result.$tag === 1 &&
                      !scheduled && !result._0.complete &&
                      result._0.progress === 4n && operation.material() == null) {
                    // Two output rows, then row/column receipt-copy roots.
                    // The old atomic issuer cannot reach this observation.
                    receiptProgress = result._0.progress;
                    scheduled = true;
                    setTimeout(() => cancellation.abort(), 0);
                  }
                  return result;
                };
              }
              if (name !== 'advance') return Reflect.get(operation, name, receiver);
              return quantum => {
                const result = operation.advance(Math.min(quantum, 1));
                if (dispatch === observedDispatch && result.$tag === 1) {
                  producerWork += result._0.work;
                  // For Values, eleven polls and one handoff precede Filter.
                  // Captured mode proves positive Compute progress only.
                  if (['cancel-after-filter', 'cancel-after-progress'].includes(mode) && !scheduled &&
                      producerWork >= (route.cancelWork ?? 13n) && !result._0.complete) {
                    scheduled = true;
                    setTimeout(() => cancellation.abort(), 0);
                  }
                }
                return result;
              };
            },
          })};
        };
      },
    });
    const host = createNodeHostEntry(() => observedMoon, installStrategyContributions);
    const runtime = runtimeCore(observedMoon);
    const options = {moon, control: runtime.publicationControl,
      ...(captured ? {
        publicationOriginal: capturePreparation.publicationOriginal,
        publicationPreparation: capturePreparation.publicationPreparation,
        compilationOriginal: capturePreparation.compilationOriginal,
        requestIdentity: captureRequestIdentity,
      } : {publicationOriginal: publicationOriginalFixture(moon, prepared, true)}),
      preparedProgram: prepared, authorityScopeCid: cid('a'),
      namespaceId: route.publicationNamespace ?? 'local',
      storeAuthorityCid: cid('c'), now: () => captured
        ? new Date().toISOString() : '2026-09-30T00:00:00.000Z'};
    let plan = captured ? acquiredTaskPublicationPlan({...options,
      acquired: acquiredTaskRunAdmission(options), captured,
      sourceEvidence: options.control.admitRunEvidence('source_evidence',
        await captured.issueSourceEvidence({authorityScopeCid: options.authorityScopeCid,
          effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid}),
        {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
      effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(prepared),
      captureStartedAt: captured.captureStartedAt,
      captureCompletedAt: captured.captureCompletedAt}) : sourceFreeTaskPlan(options);
    if (route.withoutClientSelection) {
      // This optional selection is not the captured graph's ResultPort. The
      // ordinary publication API must still use that exact checked occurrence.
      plan = Object.freeze({...plan, results: Object.freeze(plan.results.map(
        ({transformation, ...result}) => Object.freeze(result)))});
    }
    retained = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 8 * 1024 * 1024, maxFrameBytes: 1024 * 1024});
    publication = await openLocalPublicationStore({
      directory: join(directory, 'publication'), storeAuthorityCid: cid('c'),
      capacityBytes: 512 * 1024 * 1024,
      // The same Store holds Result data, schemas and publication contracts.
      maxObjectBytes: Math.max(plan.outputLimits.maxWireBytes,
        plan.outputLimits.maxSchemaBytes, plan.contractLimits.maxWireBytes), maxObjects: 100,
      maxContractNodes: 10000, maxContractDepth: 64,
    }, runtime.publicationControl);
    // Carrier and Bridge outputs retain managed generations; this injects a
    // fault in the real Named Result payload Store, not a fictitious row lease.
    let publicationWriters = 0;
    const publicationStore = route.observePublicationValidation
      ? Object.freeze({...publication,
        async putPublicationContract(...args) {
          route.contractWrites = (route.contractWrites ?? 0) + 1;
          return publication.putPublicationContract(...args);
        },
        async createAttempt(...args) {
          route.attemptCreates = (route.attemptCreates ?? 0) + 1;
          return publication.createAttempt(...args);
        },
        async beginPublicationAttemptWithRecords(...args) {
          route.atomicAttemptCreates = (route.atomicAttemptCreates ?? 0) + 1;
          return publication.beginPublicationAttemptWithRecords(...args);
        },
      }) : !route.publicationFault ? publication
      : Object.freeze({...publication,
        createPreparedObjectWriter(...args) {
          assert.equal(dispatches, 9, 'publication follows all Compute tasks');
          const writer = publication.createPreparedObjectWriter(...args);
          if (++publicationWriters !== 1) return writer;
          return Object.freeze({...writer,
            async append(...parts) {
              if (route.publicationFault !== 'append') return writer.append(...parts);
              appendsFailed++;
              throw new Error('InjectedPublicationAppendFailure');
            },
            async seal(...identity) {
              if (route.publicationFault !== 'finalize') return writer.seal(...identity);
              finalizationsFailed++;
              throw new Error('InjectedPublicationFinalizeFailure');
            },
            async cancel() {
              if (!permitCleanup) throw new Error('InjectedPublicationCleanupPending');
              return writer.cancel();
            },
          });
        },
      });
    const leases = [];
    const configuration = installLocalRetainedStore((key, bytes) => {
      leases.push(key);
      const failWrite = leases.length === (route.failLease ?? 1) &&
        (mode === 'append-failure' || mode === 'finalize-failure');
      let writer, closed = false;
      return Object.freeze({
        status: () => ({reservedBytes: writer && (!closed ||
          (failWrite && !permitCleanup)) ? bytes : 0,
          cleanupPending: (failWrite && !permitCleanup) ||
            (writer?.cleanupHandle?.status().pending ?? false)}),
        reserve(value) {
          writer = retained.reserve(value);
          if (!failWrite) return writer;
          return Object.freeze({
            start: () => writer.start(),
            async append(part) {
              if (mode !== 'append-failure') return writer.append(part);
              appendsFailed++;
              throw new Error('InjectedRetainedAppendFailure');
            },
            async seal(identity) {
              finalizationsFailed++;
              await writer.seal(identity);
              throw new Error('InjectedRetainedFinalizeFailure');
            },
          });
        },
        close() {
          if (cancellation.signal.aborted) {
            if (route.observeResultPreparation || route.observeCapturePreparation ||
                route.observePublicationValidation) {
              assert.equal(completedDispatches, 3,
              'Result preparation follows physically completed Compute');
            } else assert.equal(sawStop, true);
          }
          closed = true;
          writer?.cancel();
        },
        async cleanup() {
          if (failWrite && !permitCleanup) throw new Error('InjectedCleanupPending');
          await writer?.cleanupHandle?.retry?.();
        },
      });
    });
    await use({setup, plan, retained, publication, leases, captured,
      observations: () => ({dispatches, producerWork, sawStop, scheduled, receiptProgress, receiptTrace,
        exportTrace, exportSteps, exportPreparationTrace, exportPreparationSteps,
        completedDispatches, resultPreparationSteps, resultOrderReached,
        resultPreparationCancels, resultSchemaReached,
        abortReason: cancellation.signal.reason,
        appendsFailed, finalizationsFailed}),
      permitCleanup() { permitCleanup = true; },
      async run() {
        try {
          owner = await host.runPublishedCapturedStrategy(setup,
            {store: publicationStore, plan}, {local: configuration},
            cancellation.signal);
          execution = owner.execution;
          return owner;
        } catch (error) {
          execution = error.execution;
          publicationFailure = error;
          if (mode !== 'success') throw error;
          throw new Error(`${error.message}: ${inspect(error.cause)}; ` +
            `failure=${inspect(execution?.failure, {depth: 8})}`, {cause: error});
        }
      },
    });
  } catch (cause) {
    if (cause?.code !== 'RunHostTaskInvocationRejected') throw cause;
    throw Object.assign(new Error(`${cause.message}: ${inspect(cause.cause, {depth: 6})}`,
      {cause}), {code: cause.code});
  } finally {
    const beforeCleanup = dispatches;
    permitCleanup = true;
    try {
      if (route.publicationFault && publicationFailure?.cleanupHandle) {
        assert.equal((await publicationFailure.cleanupHandle.retry()).pending, false);
      }
      if (owner) {
        await owner.close();
        assert.equal(await owner.cleanup(), true);
      } else if (execution) {
        await execution.close();
        assert.equal(await execution.cleanup(), true);
      }
      if (execution) {
        assert.equal(dispatches, beforeCleanup, 'cleanup must not redispatch Compute');
        assert.equal(execution.usage().heldBytes, 0n);
        assert.equal(execution.usage().reservedExecutionBytes, 0n);
      }
      if (retained) {
        assert.equal(retained.status().reservedBytes, 0);
        assert.equal(retained.status().holdings, 0);
        assert.equal(retained.status().reservedReadBufferBytes, 0);
      }
      if ((route.publicationFault || route.observeResultPreparation ||
          route.observeCapturePreparation || route.observePublicationValidation) && publication) {
        assert.equal(publication.status().reservedBytes, 0);
        assert.equal(publication.status().reservedObjects, 0);
      }
      if (captured) {
        assert.equal(nativeSourceIdentityMatches(captured.capture,
          captured.identity), true, 'Compute cleanup must not retire the acquisition');
      }
    } finally {
      try {
        await retained?.close();
        await retained?.cleanup();
        await publication?.close();
      } finally {
        try {
          captured?.capture.close();
          await captured?.capture.cleanupHandle?.retry();
        } finally {
          await rm(directory, {recursive: true, force: true});
        }
      }
    }
    // Return the original Request preparation only after its retained users
    // and captured input have completed their existing cleanup above.
    if (captureRun !== undefined) {
      const run = captureRun;
      try {checked(moon.clientProgramInstalledManagedRunRetire(run.value));}
      catch (cause) {
        if (moon.clientProgramInstalledPreparationPayloadSevered(
          run.value, captureRequestIdentity) !== true) throw cause;
      }
      preparation.retireOriginal(prepared);
      preparation.manager.severPreparation(prepared, run.original);
      checked(moon.clientProgramInstalledManagedRunRetire(run.value));
      preparation.manager.retireSeveredPreparation(run.original);
    }
    await preparation?.close();
  }
}

for (const filtered of [false, true]) {
  test(`retained object projection publishes nullable outcomes${filtered ? ' after property filtering' : ''}`,
    async () => retainedRun(objectPropertyProgram(filtered),
      async ({run, plan, publication, observations}) => {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().dispatches, 3);
        await assertPublishedRows(publication, plan, owner.execution,
          filtered ? [{id: 'a', risk: 'high'}] : [
            {id: 'a', note: 'urgent', assessment: {input_key: {id: 'a'},
              outcome: 'ok', value: {risk: 'high', reason: null}}},
            {id: 'b', note: null, assessment: {input_key: {id: 'b'},
              outcome: 'failed:refusal', value: null}},
          ]);
      }));
}

for (const mode of ['success', 'cancel-during-export', 'cancel-during-export-preparation']) {
  test(`retained row-file export yields within Unicode Text: ${mode}`, async () => {
    const text = 'a'.repeat(1024) + '😀';
    const document = JSON.parse(program([{id: 1, s: text}, {id: 2, s: null}], 'true'));
    document.id = 'retained-row-file-progress';
    document.stages[0].steps[0].values.schema.s = {type: 'string', nullable: true};
    document.stages[0].steps[2].select = ['id', 's'];
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 's'];
      if (stage.inputs.r) stage.steps[0].select = ['id', 's'];
    }
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations, leases}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().dispatches, 3);
        assert.ok(observations().exportPreparationSteps > 16);
        assert.ok(observations().exportPreparationTrace.every(poll =>
          poll.steps === 1 && !poll.complete));
        assert.ok(observations().exportSteps > 32);
        assert.ok(observations().exportTrace.every(poll =>
          poll.steps === 1 && !poll.complete && !poll.batchReady));
        await assertPublishedRows(publication, plan, owner.execution,
          [{id: 1, s: text}, {id: 2, s: null}]);
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunExecutionFailed');
          execution = error.execution;
          return true;
        });
        assert.equal(execution.status, 'host-tasks-failed');
        assert.deepEqual(execution.completed, []);
        if (mode === 'cancel-during-export') {
          assert.equal(execution.failure.code, 'ManagedExecutionFailed');
          assert.equal(execution.failure.cause.primaryFailure, observations().abortReason);
          assert.equal(execution.failure.cause.primaryFailure.name, 'AbortError');
          assert.equal(execution.failure.cleanupPending, true);
          assert.equal(observations().exportSteps, 10);
        } else {
          assert.equal(execution.failure, observations().abortReason);
          assert.equal(execution.failure.name, 'AbortError');
          assert.equal(observations().exportPreparationSteps, 10);
          assert.equal(observations().exportSteps, 0);
          assert.deepEqual(observations().exportPreparationTrace,
            Array.from({length: 10}, () => ({complete: false, steps: 1})));
          assert.deepEqual(leases, []);
          assert.equal(observations().exportTrace.length, 0);
        }
        assert.equal(observations().dispatches, 1);
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
    }, mode, undefined, undefined, false, {observeExport: true});
  });
}

for (const mode of ['success', 'cancel-during-result-order']) {
  test(`retained Named Result ordering yields inside a long Text comparison: ${mode}`, async () => {
    const prefix = 'x'.repeat(1024) + '😀';
    const document = JSON.parse(program([{id: 1, s: `${prefix}b`},
      {id: 2, s: `${prefix}a`}], 'true'));
    document.id = 'retained-result-order-progress';
    document.stages[0].steps[0].values.schema.s = {type: 'string', nullable: false};
    document.stages[0].steps[2].select = ['id', 's'];
    // Keep the producer's full checked contract across task input edges.
    // Ordering still selects the real publication transformation owner.
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 's'];
      stage.results.out.order_by = [{s: 'asc'}];
      if (stage.inputs.r) stage.steps[0].select = ['id', 's'];
    }
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.ok(observations().resultPreparationSteps > 3000);
        assert.equal(observations().resultOrderReached, true);
        assert.equal(observations().completedDispatches, 3);
        await assertPublishedRows(publication, plan, owner.execution,
          [{id: 2, s: `${prefix}a`}, {id: 1, s: `${prefix}b`}]);
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          assert.equal(error.cause.code, 'DurableResultPayloadFailed');
          assert.equal(error.cause.primaryFailure, observations().abortReason);
          assert.equal(error.cause.cause, observations().abortReason);
          execution = error.execution;
          return true;
        });
        assert.equal(observations().scheduled, true);
        assert.equal(observations().resultOrderReached, true);
        assert.equal(observations().completedDispatches, 3);
        assert.equal(observations().resultPreparationCancels, 1);
        assert.deepEqual(execution.completed.map(task => task.task), [0, 1, 2]);
        assert.ok(execution.completed.every(task => task.realization === 'local'));
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(observations().dispatches, 3);
    }, mode, undefined, undefined, false, {observeResultPreparation: true});
  });
}

for (const mode of ['success', 'cancel-during-result-snapshot']) {
  test(`retained Result snapshot admission yields inside long Text: ${mode}`, async () => {
    const text = `${'é'.repeat(257)}e\u0301\r\n😀`;
    const first = {id: 1, note: text};
    const second = {id: 2, note: null};
    const document = JSON.parse(program([first, second], 'true'));
    document.id = 'retained-result-snapshot-progress';
    document.stages[0].steps[0].values.schema.note = {type: 'string', nullable: true};
    document.stages[0].steps[2].select = ['id', 'note'];
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 'note'];
      stage.results.out.order_by = [{id: 'desc'}];
      if (stage.inputs.r) stage.steps[0].select = ['id', 'note'];
    }
    const route = {observeResultPreparation: true, observeSnapshotPreparation: true};
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(route.snapshotTextReached, true);
        await assertPublishedRows(publication, plan, owner.execution, [second, first]);
      } else {
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          assert.equal(error.cause.code, 'DurableResultPayloadFailed');
          assert.equal(error.cause.primaryFailure, observations().abortReason);
          assert.equal(error.cause.cause, observations().abortReason);
          assert.deepEqual(error.execution.completed.map(task => task.task), [0, 1, 2]);
          return true;
        });
        assert.equal(route.snapshotTextReached, true);
        assert.equal(route.snapshotCancels, 1);
        assert.equal(observations().scheduled, true);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(observations().dispatches, 3);
      assert.equal(observations().completedDispatches, 3);
    }, mode, undefined, undefined, false, route);
  });
}

for (const phase of ['success', 'root-check', 'snapshot-inventory', 'context-check', 'rows-check']) {
  test(`retained Captured Run issuance yields through final evidence checking: ${phase}`, async () => {
    const first = {id: 1, note: `${'é'.repeat(257)}e\u0301\r\n😀`};
    const second = {id: 2, note: null};
    const document = JSON.parse(program([first, second], 'true'));
    document.id = 'retained-captured-run-progress';
    document.stages[0].steps[0].values.schema.note = {type: 'string', nullable: true};
    document.stages[0].steps[2].select = ['id', 'note'];
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 'note'];
      stage.results.out.order_by = [{id: 'desc'}];
      if (stage.inputs.r) stage.steps[0].select = ['id', 'note'];
    }
    const route = {observeCapturePreparation: true, cancelCapturePhase: phase};
    const mode = phase === 'success' ? 'success' : 'cancel-during-captured-run';
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.ok(route.capturePhases.has('root-check'));
        assert.ok(route.capturePhases.has('context-check'));
        assert.ok(route.capturePhases.has('rows-check'));
        await assertPublishedRows(publication, plan, owner.execution, [second, first]);
        assert.equal(route.captureCancels ?? 0, 0);
        assert.equal(route.captureRetirements, 1);
      } else {
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          assert.equal(error.cause, observations().abortReason);
          assert.deepEqual(error.execution.completed.map(task => task.task), [0, 1, 2]);
          return true;
        });
        assert.ok(route.capturePhases.has(phase));
        if (phase === 'root-check') assert.ok(route.captureRootPolls > 1);
        if (phase === 'snapshot-inventory') assert.ok(route.captureSnapshotPolls >= 3);
        assert.equal(route.captureCancels, 1);
        assert.equal(observations().scheduled, true);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.ok(route.capturePolls > 1);
      assert.equal(observations().dispatches, 3);
      assert.equal(observations().completedDispatches, 3);
    }, mode, undefined, undefined, false, route);
  });
}

// Independent received/copy/tighter evidence still traverses every aggregate
// boundary in captured_run_issuance_test.mbt. This ordinary same-original path
// instead proves proof reuse and the before/after-completion cancellation fence.
for (const phase of ['success', 'before-retained-check', 'after-retained-check']) {
  test(`retained publication preserves original validation ownership: ${phase}`, async () => {
    const first = {id: 1, note: `${'é'.repeat(257)}e\u0301\r\n😀`};
    const second = {id: 2, note: null};
    const document = JSON.parse(program([first, second], 'true'));
    document.id = 'retained-publication-validation-progress';
    document.stages[0].steps[0].values.schema.note = {type: 'string', nullable: true};
    document.stages[0].steps[2].select = ['id', 'note'];
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 'note'];
      stage.results.out.order_by = [{id: 'desc'}];
      if (stage.inputs.r) stage.steps[0].select = ['id', 'note'];
    }
    const route = {observePublicationValidation: true, cancelValidationPhase: phase,
      publicationNamespace: `scope-${'é'.repeat(4097)}😀`};
    const mode = phase === 'success' ? 'success' : 'cancel-during-publication-validation';
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(route.retainedChainStarts, 1);
        assert.equal(route.validationPolls, 1);
        assert.equal(route.validationCancels, 1);
        assert.ok(route.commitPolls > 1, 'the original Store checker must actually yield');
        assert.ok(route.resultEvidencePolls > 1);
        assert.ok(route.bindingPolls > 1);
        assert.ok(route.namespacePolls > 1);
        assert.equal(route.storeValidationRetirements, 1);
        await assertPublishedRows(publication, plan, owner.execution, [second, first]);
        assert.equal(route.atomicAttemptCreates, 1);
        assert.equal(route.attemptCreates ?? 0, 0);
      } else {
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          assert.equal(error.cause, observations().abortReason);
          assert.deepEqual(error.execution.completed.map(task => task.task), [0, 1, 2]);
          return true;
        });
        assert.equal(route.retainedChainStarts, 1);
        assert.equal(route.validationPolls ?? 0, phase === 'before-retained-check' ? 0 : 1);
        assert.equal(route.validationCancels, 1);
        assert.equal(route.commitPolls ?? 0, 0);
        assert.equal(route.contractWrites ?? 0, 0);
        assert.equal(route.atomicAttemptCreates ?? 0, 0);
        assert.equal(route.attemptCreates ?? 0, 0);
        assert.equal(observations().scheduled, true);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(observations().dispatches, 3);
      assert.equal(observations().completedDispatches, 3);
    }, mode, undefined, undefined, false, route);
  });
}

for (const withoutClientSelection of [false, true]) {
 for (const mode of ['success', 'cancel-during-result-schema']) {
  test(`retained Named Result schema yields within recursive contracts: ${mode}${
    withoutClientSelection ? ' without Client selection' : ''}`, async () => {
    const fields = Object.fromEntries(Array.from({length: 65}, (_, index) =>
      [`k${1000 + index}`, {type: 'number', nullable: false}]));
    const payload = first => Object.fromEntries(Object.keys(fields).map((name, index) =>
      [name, first + index]));
    const first = {id: 1, payload: payload(100)};
    const second = {id: 2, payload: payload(200)};
    const document = JSON.parse(program([first, second], 'true'));
    document.id = 'retained-result-schema-progress';
    document.stages[0].steps[0].values.schema.payload = {
      type: 'object', nullable: false, fields,
    };
    document.stages[0].steps[2].select = ['id', 'payload'];
    for (const stage of document.stages) {
      stage.results.out.fields = ['id', 'payload'];
      stage.results.out.order_by = [{id: 'desc'}];
      if (stage.inputs.r) stage.steps[0].select = ['id', 'payload'];
    }
    await retainedRun(JSON.stringify(document), async ({run, plan, publication, observations}) => {
      if (mode === 'success') {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().resultSchemaReached, true);
        await assertPublishedRows(publication, plan, owner.execution, [second, first]);
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunPublicationFailed');
          assert.equal(error.cause.code, 'DurableResultPayloadFailed');
          assert.equal(error.cause.primaryFailure, observations().abortReason);
          assert.equal(error.cause.cause, observations().abortReason);
          execution = error.execution;
          return true;
        });
        assert.equal(observations().scheduled, true);
        assert.equal(observations().resultSchemaReached, true);
        assert.equal(observations().resultPreparationCancels, 1);
        assert.deepEqual(execution.completed.map(task => task.task), [0, 1, 2]);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(observations().dispatches, 3);
      assert.equal(observations().completedDispatches, 3);
    }, mode, undefined, undefined, false,
    {observeResultPreparation: true, observeSchemaPreparation: true,
      withoutClientSelection});
  });
 }
}

for (const {family, name} of [
  {family: 'graph', name: 'installed retained graph factory executes a normal mixed Stage'},
  {family: 'events', name: 'installed retained events factory executes a normal mixed Stage'},
  {family: 'vectors', name: 'installed retained vectors factory executes a normal mixed Stage'},
]) {
  test(name,
    async () => retainedRun(familyProgram(family),
      async ({run, plan, publication, observations}) => {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().dispatches, family === 'graph' ? 8 : 9);
        await assertPublishedRows(publication, plan, owner.execution,
          family === 'events' ? [{id: 3, late: false}, {id: 2, late: false},
            {id: 1, late: true}]
            : family === 'vectors' ? [{id: 3, embedding: [0, 1]},
              {id: 2, embedding: [0, 1]}, {id: 1, embedding: [0, 1]}]
              : [{id: 3}, {id: 2}, {id: 1}]);
      }, 'success', undefined, undefined, false,
      {family, taskSteps: Array(family === 'graph' ? 8 : 9).fill(1)}));
}

for (const {name, family, mode, cancelDispatch} of [
  {name: 'installed retained Events cancels during Carrier computation',
    family: 'events', mode: 'cancel-after-progress', cancelDispatch: 3},
  {name: 'installed retained Vectors cancels after the Relation Bridge',
    family: 'vectors', mode: 'cancel-after-progress', cancelDispatch: 5},
  {name: 'installed retained Events cancels during Relation receipt preparation',
    family: 'events', mode: 'cancel-during-receipt', cancelDispatch: 5},
  {name: 'installed retained Events rejects a later filter arithmetic failure',
    family: 'events', mode: 'arithmetic'},
]) {
  test(name, async () => retainedRun(familyProgram(family,
    mode === 'arithmetic' ? '1 / (id - id) > 0'
      : mode === 'cancel-during-receipt' ? 'id >= 2' : 'id >= 1'),
  async ({run, plan, publication, observations, permitCleanup}) => {
    let execution;
    await assert.rejects(async () => {
      await run();
      assert.fail(`Unexpected publication: ${inspect(observations().receiptTrace)}`);
    }, error => {
      assert.equal(error.code, 'CapturedRunExecutionFailed', error.message);
      execution = error.execution;
      return true;
    });
    assert.equal(execution.status, 'host-tasks-failed');
    assert.ok(execution.completed.length < 7, 'no terminal producer or consumer');
    await assert.rejects(publication.lookupCommittedIndex({
      namespaceId: plan.request.namespaceId,
      authorityScopeCid: plan.request.authorityScopeCid,
      runDefinitionCid: plan.runDefinition.identity,
    }, () => true), /PublicationLookupDenied/);
    if (cancelDispatch) {
      assert.equal(observations().dispatches, cancelDispatch);
      assert.equal(execution.completed.length, cancelDispatch - 1);
      assert.ok(observations().producerWork > 0n);
      assert.equal(observations().scheduled, true);
      assert.equal(observations().sawStop, true);
      assert.equal(execution.failure.name, 'AbortError');
      if (mode === 'cancel-during-receipt') {
        assert.equal(observations().receiptProgress, 4n);
      }
    } else if (mode === 'arithmetic') {
      assert.equal(observations().dispatches, 5);
      assert.equal(fixture.strategyFixtureManagedFilterArithmetic(
        execution.failure.cause, 4), true);
    }
  }, mode, undefined, undefined, false,
  {family, taskSteps: Array(9).fill(1), cancelDispatch, cancelWork: 1n}));
}

for (const {name, family, publicationFault} of [
  {name: 'installed retained Vectors retains custody after publication append failure',
    family: 'vectors', publicationFault: 'append'},
  {name: 'installed retained Events retries cleanup after publication finalize failure',
    family: 'events', publicationFault: 'finalize'},
]) {
  test(name, async () => retainedRun(familyProgram(family),
    async ({run, plan, publication, observations, permitCleanup}) => {
      let failure;
      await assert.rejects(run(), error => {
        failure = error;
        return error.code === 'CapturedRunPublicationFailed';
      });
      assert.equal(failure.execution.status, 'host-tasks-completed');
      assert.equal(failure.execution.completed.length, 9);
      assert.equal(observations().dispatches, 9);
      assert.equal(publicationFault === 'append' ? observations().appendsFailed
        : observations().finalizationsFailed, 1);
      assert.equal(failure.cleanupPending, true);
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.ok(publication.status().reservedBytes > 0);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      assert.equal((await failure.cleanupHandle.retry()).pending, true);
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.equal(observations().dispatches, 9);
      permitCleanup();
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(publication.status().reservedBytes, 0);
      assert.equal(publication.status().reservedObjects, 0);
      assert.equal(observations().dispatches, 9, 'cleanup never repeats Compute');
    }, 'publication-failure', undefined, undefined, false,
    {family, taskSteps: Array(9).fill(1), publicationFault}));
}

// Independent scalar phase model, also checked in the portable provider test:
// Values20 + filter true31 + select19 + Values port31 + handoffs2 =103.
// Values includes four-step row charging. Its values_0 cursor costs31;
// selected Filter/Select reuse their existing admitted metadata. Historical
// 162/161 and Filter-only-reuse134/133 allowances remain accepted controls.
// Filter's three metadata entries, three roots, snapshot and two predicate
// slots peak at nine workspace entries. These are not sampled from a run.
for (const {name, work, workspace, failure} of [
  {name: 'historical scalar scan allowance', work: 162, workspace: 9},
  {name: 'historical scalar scan one-short allowance', work: 161, workspace: 9},
  {name: 'Filter-reuse scalar allowance', work: 134, workspace: 9},
  {name: 'Filter-reuse scalar one-short allowance', work: 133, workspace: 9},
  {name: 'exact scalar chain budgets', work: 103, workspace: 9},
  {name: 'one-short scalar chain work', work: 102, workspace: 9,
    failure: 'work'},
  {name: 'one-short scalar chain workspace', work: 162, workspace: 8,
    failure: 'workspace'},
]) {
  test(`retained Values honors ${name}`, async () => retainedRun(
    program([{id: 3}, {id: 1}, {id: 2}], 'true'),
    async ({run, plan, publication, observations}) => {
      if (!failure) {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().producerWork, 103n);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(),
          [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')),
            [{id: 3}, {id: 1}, {id: 2}]);
        }
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunExecutionFailed');
          execution = error.execution;
          return true;
        });
        assert.deepEqual(execution.completed, []);
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(failure === 'work'
          ? fixture.strategyFixtureRetainedInputLimit(execution.failure.cause)
          : fixture.strategyFixtureRetainedRowLimit(execution.failure.cause), true);
        assert.equal(observations().dispatches, 1);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
    }, failure ?? 'success', {work, workspace}));
}

for (const {name: mode} of [
  {name: 'cancel-after-filter'}, {name: 'arithmetic'},
  {name: 'append-failure'}, {name: 'finalize-failure'},
]) {
  test(`retained source-free Values chain retains responsibility after ${mode}`,
    async () => retainedRun(program([{id: 3}, {id: 1}, {id: 2}],
      mode === 'arithmetic' ? '1 / (id - id) > 0' : 'id >= 2'),
    async ({run, plan, publication, observations, permitCleanup}) => {
      let execution;
      await assert.rejects(run(), error => {
        assert.equal(error.code, 'CapturedRunExecutionFailed');
        execution = error.execution;
        return true;
      });
      assert.equal(execution.status, 'host-tasks-failed');
      assert.deepEqual(execution.completed, []);
      assert.equal(observations().dispatches, 1);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      if (mode === 'cancel-after-filter') {
        assert.ok(observations().producerWork >= 13n);
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
        assert.equal(execution.failure.name, 'AbortError');
      } else if (mode === 'arithmetic') {
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureRetainedChainFilterArithmetic(
          execution.failure.cause), true);
      } else if (mode === 'append-failure') {
        assert.equal(observations().appendsFailed, 1);
      } else {
        assert.equal(observations().finalizationsFailed, 1);
        assert.equal(execution.cleanupPending(), true);
        assert.equal(await execution.cleanup(), false);
        assert.ok(execution.usage().reservedExecutionBytes > 0n ||
          execution.usage().heldBytes > 0n);
        assert.equal(observations().dispatches, 1);
        permitCleanup();
      }
    }, mode));
}

for (const {name, rows, expected} of [
  {name: 'ordered source-free chain',
    rows: [{id: 3}, {id: 1}, {id: 2}], expected: [{id: 3}, {id: 2}]},
  {name: 'empty source-free chain', rows: [], expected: []},
  {name: 'empty filtered output', rows: [{id: 1}], expected: []},
]) {
  test(`retained Values publishes ${name} and two independent consumers`,
    async () => retainedRun(program(rows), async ({run, plan, publication, leases}) => {
      const owner = await run();
      assert.equal(owner.status, 'published');
      assert.deepEqual(owner.execution.completed.map(value => value.task), [0, 1, 2]);
      assert.deepEqual(owner.execution.completed.map(value => value.realization),
        ['local', 'local', 'local']);
      assert.ok(owner.execution.completed.every(value =>
        value.outputRepresentation === 'retained-file'));
      assert.equal(leases.length, 3);
      const inventory = owner.execution.publicationInventory.occurrences;
      assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
      // Resolve each independently named committed Result. A missing consumer
      // cannot remove its own assertion by disappearing from the inventory.
      for (const name of resultNames) {
        const occurrence = inventory.find(value => value.name === name);
        const chunks = [];
        const result = await publication.consumeCommittedResult({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, occurrence.definitionContract.identity, () => true,
        chunk => chunks.push(Buffer.from(chunk)));
        assert.equal(result.rowCount, expected.length);
        assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
      }
    }));
}

for (const fileInput of [false, true]) {
for (const {name, rows, expected} of [
  {name: 'ordered acquired chain',
    rows: [{id: 3}, {id: 1}, {id: 2}], expected: [{id: 2}, {id: 3}]},
  {name: 'empty acquired chain', rows: [], expected: []},
  {name: 'empty acquired filtered output', rows: [{id: 1}], expected: []},
]) {
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host publishes ${name} and two consumers`,
    async () => retainedRun(capturedProgram(),
      async ({run, plan, publication, leases, captured}) => {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.deepEqual(owner.execution.completed.map(value => value.task), [1, 2, 3]);
        assert.ok(owner.execution.completed.every(value =>
          value.realization === 'local' && value.outputRepresentation === 'retained-file'));
        assert.equal(leases.length, 3);
        assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          const result = await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.equal(result.rowCount, expected.length);
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')), expected);
        }
      }, 'success', undefined, rows, fileInput));
}
}

test('file-captured identity observes delivered cancellation and preserves acquisition custody',
  async () => retainedRun(capturedProgram(),
    async ({run, publication, plan, captured}) => {
      const cancellation = new AbortController();
      let rows = 0, finishes = 0;
      const observed = new Proxy(moon, {get(target, name, receiver) {
        if (name === 'clientProgramAppendCapturedSourceIdentityScan') {
          return (...args) => {
            const result = target[name](...args);
            if (result.$tag === 1 && ++rows === 1) {
              setImmediate(() => cancellation.abort());
            }
            return result;
          };
        }
        if (name === 'clientProgramFinishCapturedSourceIdentityScan') {
          return (...args) => { finishes++; return target[name](...args); };
        }
        return Reflect.get(target, name, receiver);
      }});
      await assert.rejects(identifyRetainedCapturedSource(observed,
        captured.capture.source(), cancellation.signal), {name: 'AbortError'});
      assert.equal(rows, 1);
      assert.equal(finishes, 0);
      assert.equal(captured.capture.storageUsage().reservedReadBufferBytes, 0);
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
      const identity = await identifyRetainedCapturedSource(moon, captured.capture.source());
      assert.equal(moon.clientProgramCapturedSourceLogicalCid(identity),
        moon.clientProgramCapturedSourceLogicalCid(captured.identity));
      const owner = await run();
      assert.equal(owner.status, 'published');
      await assertPublishedRows(publication, plan, owner.execution, [{id: 2}, {id: 3}]);
    }, 'success', undefined, [{id: 3}, {id: 1}, {id: 2}], true));

test('file-captured retained Host preserves source custody after positive Compute cancellation',
  async () => retainedRun(capturedProgram(),
    async ({run, plan, publication, captured, observations}) => {
      await assert.rejects(run, error => {
        const execution = error.execution;
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
        assert.ok(observations().producerWork > 0n);
        assert.equal(execution.completed.length, 0);
        assert.equal(observations().dispatches, 1);
        assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
        return true;
      });
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
    }, 'cancel-after-progress', undefined, [{id: 3}, {id: 1}, {id: 2}], true));

// The same three-row Filter (31), Select (19), and one handoff (1) require
// 51 work units and nine peak workspace entries. No Values child runs here.
for (const fileInput of [false, true]) {
for (const {name, work, workspace, failure} of [
  {name: 'exact captured scalar budgets', work: 51, workspace: 9},
  {name: 'one-short captured scalar work', work: 50, workspace: 9, failure: 'work'},
  {name: 'one-short captured scalar workspace', work: 51, workspace: 8,
    failure: 'workspace'},
]) {
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host honors ${name}`, async () => retainedRun(
    capturedProgram('true', false),
    async ({run, plan, publication, captured, observations}) => {
      if (!failure) {
        const owner = await run();
        assert.equal(owner.status, 'published');
        assert.equal(observations().producerWork, 51n);
        const inventory = owner.execution.publicationInventory.occurrences;
        assert.deepEqual(inventory.map(value => value.name).sort(), [...resultNames].sort());
        for (const name of resultNames) {
          const occurrence = inventory.find(value => value.name === name);
          const chunks = [];
          await publication.consumeCommittedResult({
            namespaceId: plan.request.namespaceId,
            authorityScopeCid: plan.request.authorityScopeCid,
            runDefinitionCid: plan.runDefinition.identity,
          }, occurrence.definitionContract.identity, () => true,
          chunk => chunks.push(Buffer.from(chunk)));
          assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString('utf8')),
            [{id: 1}, {id: 2}, {id: 3}]);
        }
      } else {
        let execution;
        await assert.rejects(run(), error => {
          assert.equal(error.code, 'CapturedRunExecutionFailed');
          execution = error.execution;
          return true;
        });
        assert.deepEqual(execution.completed, []);
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(failure === 'work'
          ? fixture.strategyFixtureRetainedInputLimit(execution.failure.cause)
          : fixture.strategyFixtureRetainedRowLimit(execution.failure.cause), true);
        assert.equal(observations().dispatches, 1);
        await assert.rejects(publication.lookupCommittedIndex({
          namespaceId: plan.request.namespaceId,
          authorityScopeCid: plan.request.authorityScopeCid,
          runDefinitionCid: plan.runDefinition.identity,
        }, () => true), /PublicationLookupDenied/);
      }
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
    }, failure ?? 'success', {work, workspace}, [{id: 1}, {id: 2}, {id: 3}], fileInput));
}
}

for (const fileInput of [false, true]) {
for (const {name, mode} of [
  {name: 'captured progress cancellation', mode: 'cancel-after-progress'},
  {name: 'captured filter arithmetic', mode: 'arithmetic'},
  {name: 'captured append failure', mode: 'append-failure'},
  {name: 'captured finalize cleanup retry', mode: 'finalize-failure'},
]) {
  if (fileInput && !['append-failure', 'finalize-failure'].includes(mode)) continue;
  test(`product ${fileInput ? 'file-captured' : 'captured'} retained Host keeps source and cleanup after ${name}`,
    async () => retainedRun(capturedProgram(mode === 'arithmetic'
      ? '1 / (id - id) > 0' : 'id >= 2'),
    async ({run, plan, publication, captured, observations, permitCleanup}) => {
      let execution;
      await assert.rejects(run(), error => {
        assert.equal(error.code, 'CapturedRunExecutionFailed');
        execution = error.execution;
        return true;
      });
      assert.deepEqual(execution.completed, []);
      assert.equal(observations().dispatches, 1);
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
      await assert.rejects(publication.lookupCommittedIndex({
        namespaceId: plan.request.namespaceId,
        authorityScopeCid: plan.request.authorityScopeCid,
        runDefinitionCid: plan.runDefinition.identity,
      }, () => true), /PublicationLookupDenied/);
      if (mode === 'cancel-after-progress') {
        assert.equal(execution.failure.name, 'AbortError');
        assert.equal(observations().scheduled, true);
        assert.equal(observations().sawStop, true);
      } else if (mode === 'arithmetic') {
        assert.equal(execution.failure.code, 'MoonBitHostFailure');
        assert.equal(fixture.strategyFixtureRetainedCapturedFilterArithmetic(
          execution.failure.cause), true);
      } else if (mode === 'append-failure') {
        assert.equal(observations().appendsFailed, 1);
      } else {
        assert.equal(observations().finalizationsFailed, 1);
        assert.equal(execution.cleanupPending(), true);
        assert.equal(await execution.cleanup(), false);
        assert.ok(execution.usage().heldBytes > 0n ||
          execution.usage().reservedExecutionBytes > 0n);
        assert.equal(observations().dispatches, 1);
        permitCleanup();
      }
    }, mode, undefined, [{id: 3}, {id: 1}, {id: 2}], fileInput));
}
}
