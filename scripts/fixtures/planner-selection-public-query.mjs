// Independent public acceptance for one bounded acquisition choice. Source and
// packed tests use this helper unchanged; no planner or execution replacement
// is injected. Estimates belong to the installed Host profile, not the Program.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {canonical, observeTwoSourceProvider,
  readTwoSourceJournal} from './two-source-public-query.mjs';

const nativeEvidence = 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8';
const broadEvidence = 'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89';
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const cidPattern = /^sha256:[0-9a-f]{64}$/u;

// Authored independently of the source provider, selected owner and Result.
export const plannerSelectionRows = [
  {id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30},
];
const acquisitionRows = [{id: 3}, {id: 2}, {id: 3}];
const expectedRows = [{id: 2}, {id: 3}, {id: 3}];
const expectedColumns = [{name: 'id', contract: {type: 'number', nullable: false}}];
// Obtained once by offline common preparation of the authored Program against
// the pinned left.environment.json; never derived from an executed Result.
export const plannerSelectionRequirementCids = Object.freeze({
  normal: 'sha256:1eaca4154c1d97c24db2bbff2fd875ee9ebdcc929d7e103ad818129ebc050d48',
  unsupportedPredicate: 'sha256:84feddd46622948d1375d8f3f0ac80e511aa83fa6f29914ca1878f95740b3fa9',
});
const requirementCidFor = item => item.filter === undefined
  ? plannerSelectionRequirementCids.normal : plannerSelectionRequirementCids.unsupportedPredicate;
const quantitiesFor = name => name === 'nativeQuery'
  ? {transferBytes: 137, retainedBytes: 103, moneyUnits: null}
  : {transferBytes: 421, retainedBytes: 303, moneyUnits: null};
const workSlotsFor = name => Array.from({length: name === 'nativeQuery' ? 11 : 8}, (_, index) => index);
const durationFor = (item, name) => name === 'nativeQuery' ? item.nativeMilliseconds : item.broadMilliseconds;
const basisFor = name => `Independent finite ${name} fixture estimate, not a measurement`;


export function plannerSelectionProgram(filter = 'amount >= 20') {
  return canonical({version: 'actql/0.1', id: 'fixture.planner-selection', stages: [
    {id: 'acquire', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{filter, as: 'filtered'}, {select: ['id'], as: 'captured'}],
      results: {rows: {from: 'captured', fields: ['id']}}},
    {id: 'ordered_result', inputs: {rows: {result: {stage: 'acquire', result: 'rows'}}},
      steps: [{sort: [{id: 'asc'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['id']}}},
  ], results: {selected: {from: {stage: 'ordered_result', result: 'rows'}}}});
}

export const plannerSelectionCases = [
  {name: 'native-cheaper', nativeMilliseconds: 10, broadMilliseconds: 20,
    expectedCandidate: 'nativeQuery', expectedIndex: 0},
  {name: 'broad-cheaper', nativeMilliseconds: 30, broadMilliseconds: 20,
    expectedCandidate: 'broadQuery', expectedIndex: 1},
  {name: 'equal-cost', nativeMilliseconds: 20, broadMilliseconds: 20,
    expectedCandidate: 'nativeQuery', expectedIndex: 0},
  {name: 'unknown-native', nativeMilliseconds: null, broadMilliseconds: 20,
    deferred: true},
  {name: 'native-capability-missing', nativeMilliseconds: 1, broadMilliseconds: 20,
    withoutNativeCapability: true, expectedCandidate: 'broadQuery', expectedIndex: 0},
  {name: 'unsupported-native-predicate', nativeMilliseconds: 1, broadMilliseconds: 20,
    filter: 'id + 1 > 2', expectedCandidate: 'broadQuery', expectedIndex: 0},
  {name: 'explicit-native-priority', priority: true,
    expectedCandidate: 'nativeQuery', expectedIndex: 0, expectedReason: 'HostPreferred'},
  {name: 'only-eligible-no-estimates', withoutNativeCapability: true, noEstimates: true,
    expectedCandidate: 'broadQuery', expectedIndex: 0, expectedReason: 'HostPreferred'},
  {name: 'missing-estimates', noEstimates: true, deferred: true},
  {name: 'foreign-native-estimate', nativeMilliseconds: 1, broadMilliseconds: 20,
    foreignNativeEstimate: true, deferred: true},
  {name: 'authorization-denied', nativeMilliseconds: 10, broadMilliseconds: 20,
    denyRead: true},
];

// Only explicit, independently authored fixture evidence enters these profiles.
// This factory asserts no production default or measured latency claim.
export function plannerSelectionPlanningFor(item, {source, requirementCid}) {
  assert.equal(requirementCid, requirementCidFor(item));
  if (item.priority) return {policy: 'priority', priority: ['nativeQuery', 'broadQuery']};
  if (item.noEstimates) return {policy: 'estimatedLatency', candidates: {}};
  const candidates = {};
  for (const name of ['nativeQuery', 'broadQuery']) {
    candidates[name] = {
      inputConditions: {requirementCid, source: {...source}},
      unit: 'milliseconds', basis: basisFor(name),
      estimates: [{workSlots: workSlotsFor(name), milliseconds: durationFor(item, name)}],
      quantities: quantitiesFor(name),
    };
  }
  if (item.foreignNativeEstimate) {
    candidates.nativeQuery.inputConditions.requirementCid = plannerSelectionRequirementCids.unsupportedPredicate;
    candidates.nativeQuery.inputConditions.source.database = source.database + '.unrelated';
  }
  return {policy: 'estimatedLatency', candidates};
}

const accountConfiguration = (outcome, operation, accountId) => canonical({
  version: 'actql-execution-account-config/0.1', account_id: accountId,
  entries: [{entry_id: 'fixture-entry', outcome, principal: {all: true},
    connection: {all: true}, resource: {all: true},
    operation: {any_of: [operation]}, exclusions: []}],
});

function hostAuthorization(observe) {
  const keys = generateKeyPairSync('ed25519');
  return {
    accountConfiguration: accountConfiguration('allow', 'write', 'planner-selection-host'),
    reviewers: [{keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
      principalId: 'fixture-reviewer', publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'fixture-host-key', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe,
  };
}

// The caller supplies the agreed installed-profile estimate representation.
// This boundary avoids baking a production default into acceptance fixtures.
export async function installPlannerSelectionFixture({root, duckdb, environment,
  acquisitionPlanningFor}) {
  assert.equal(typeof acquisitionPlanningFor, 'function');
  await mkdir(root, {recursive: true});
  const database = resolve(root, 'records.duckdb');
  const instance = await duckdb.DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    for (const {id, amount} of plannerSelectionRows) {
      await connection.run('INSERT INTO records VALUES (?, ?)', [id, amount]);
    }
  } finally { connection.closeSync(); instance.closeSync(); }
  const profiles = {}, planning = {};
  const source = {database, schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v'};
  for (const item of plannerSelectionCases) {
    const sourceEnvironment = structuredClone(environment);
    assert.ok(sourceEnvironment.connector_capabilities[0].capability_contract_cids.includes(nativeEvidence));
    assert.ok(sourceEnvironment.connector_capabilities[0].capability_contract_cids.includes(broadEvidence));
    if (item.withoutNativeCapability) {
      sourceEnvironment.connector_capabilities[0].capability_contract_cids =
        sourceEnvironment.connector_capabilities[0].capability_contract_cids.filter(value => value !== nativeEvidence);
      delete sourceEnvironment.evidence_bundle_cid;
      sourceEnvironment.evidence_bundle_cid = cid(sourceEnvironment);
    }
    const path = profiles[item.name] = resolve(root, `${item.name}.profile.json`);
    planning[item.name] = acquisitionPlanningFor(item, {source, requirementCid: requirementCidFor(item)});
    await writeFile(path, canonical({version: 'actql-installed-duckdb-source/0.1',
      database, schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
      checkEnvironmentWire: canonical(sourceEnvironment),
      accountConfigurationWire: accountConfiguration(item.denyRead ? 'deny' : 'allow',
        'read', 'planner-selection-source'),
      acquisitionPlanning: planning[item.name],
    }));
  }
  const nativeCheaper = structuredClone(planning['native-cheaper']);
  nativeCheaper.candidates.nativeQuery.estimates[0].milliseconds = 30;
  assert.deepEqual(nativeCheaper, planning['broad-cheaper'],
    'changing only one Native estimate is sufficient to reverse the choice');
  return {database, profiles, source};
}

async function openSingleSourcePublicHost({connect, openInstalledRemoteHttpHost,
  mode, directory, sourceProfilePath, tls, authorization,
  retainedRelationOutput = false}) {
  let host, server;
  let options = {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory, sourceProfilePath, authorization,
      retainedRelationOutput}};
  if (mode === 'https') {
    host = await openInstalledRemoteHttpHost({directory, sourceProfilePath, authorization,
      retainedRelationOutput,
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
    server = createServer(tls, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    options = {mode: 'remote', durability: 'durable', token: 'fixture-token',
      endpoint: `https://127.0.0.1:${server.address().port}/`};
  }
  return {connect: () => connect(options), async close() {
    if (server) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
  }};
}

// One public retained-output route, with an independent result oracle. The
// selected output representation is observed before normal cleanup.
export async function exerciseRetainedPlannerPublicQuery({connect, root,
  installation}) {
  const item = plannerSelectionCases[0];
  const directory = resolve(root, 'retained-public-state');
  let outputRepresentations;
  const events = [];
  const authorization = hostAuthorization((name, detail) => {
    events.push({name, detail});
    if (name === 'computed') outputRepresentations = detail.outputRepresentations;
  });
  const running = await openSingleSourcePublicHost({connect,
    mode: 'local', directory, sourceProfilePath: installation.profiles[item.name],
    authorization, retainedRelationOutput: true});
  let client;
  try {
    client = await running.connect().catch(error => {
      assert.fail(`retained Host initialization: ${error.primaryFailure?.stack ?? error.stack}`);
    });
    const requestId = 'retained-public-planner';
    const program = plannerSelectionProgram();
    const execution = await client.aql(program, {format: 'json', requestId});
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify({state,
      events: events.map(event => ({name: event.name,
        ...(event.name === 'dispatch_failed' ? {code: event.detail.code} : {})}))}));
    const result = execution.result('selected');
    assert.deepEqual(await result.all(), expectedRows);
    assert.deepEqual((await result.describe()).columns, expectedColumns);
    assert.ok(outputRepresentations?.some(value =>
      value.representation === 'retained-file'),
    'the public Host must select a real retained-file output');
    const attached = await client.attach(execution.ref);
    assert.deepEqual(await attached.result('selected').all(), expectedRows);
    const resent = await client.aql(program, {format: 'json', requestId});
    assert.deepEqual(resent.ref, execution.ref);
  } finally { client?.close(); await running.close(); }
}

function assertSelection(selection, item, source) {
  assert.ok(selection, 'the acquisition owner reports its common planner decision');
  assert.equal(selection.requirementCid, requirementCidFor(item));
  assert.equal(selection.status, item.deferred ? 'deferred' : 'selected');
  assert.equal(selection.reason, item.deferred ? 'Deferred' : item.expectedReason ?? 'EstimatedFastest');
  assert.equal(selection.selectedCandidate, item.expectedCandidate ?? null);
  assert.equal(selection.selectedIndex, item.expectedIndex ?? null);
  const nativeEligible = !item.withoutNativeCapability && item.filter === undefined;
  const names = nativeEligible ? ['nativeQuery', 'broadQuery'] : ['broadQuery'];
  assert.equal(selection.nativeSupported, nativeEligible);
  assert.equal(selection.broadSupported, true);
  assert.equal(selection.policy, item.priority ? 'priority' : 'estimatedLatency');
  assert.equal(selection.selectionBasis, !nativeEligible ? 'onlyEligible'
    : item.priority ? 'explicitPriority' : 'estimatedLatency');
  if (item.priority) assert.deepEqual(selection.priority, ['nativeQuery', 'broadQuery']);
  else assert.equal(selection.priority, undefined);
  assert.deepEqual(selection.candidates.map(value => value.candidate), names);
  assert.deepEqual(selection.candidates.map(value => value.index), nativeEligible ? [0, 1] : [0]);
  const admitted = name => !item.priority && !item.noEstimates &&
    !(name === 'nativeQuery' && item.foreignNativeEstimate);
  const optionalString = value => value === null ? null : String(value);
  const unknownQuantities = {transferBytes: null, retainedBytes: null, moneyUnits: null};
  const expectedEvidence = {}, expectedEstimates = {}, missing = [];
  for (const name of ['nativeQuery', 'broadQuery']) {
    const present = admitted(name);
    const milliseconds = present ? durationFor(item, name) : null;
    const quantities = present ? Object.fromEntries(Object.entries(quantitiesFor(name))
      .map(([key, value]) => [key, optionalString(value)])) : unknownQuantities;
    expectedEstimates[name] = {estimates: present
      ? [{workSlots: workSlotsFor(name), milliseconds: optionalString(milliseconds)}] : [], quantities};
    if (present) expectedEvidence[name] = {
      inputConditions: {requirementCid: requirementCidFor(item), source},
      unit: 'milliseconds', basis: basisFor(name),
      estimates: [{workSlots: workSlotsFor(name), milliseconds}], quantities: quantitiesFor(name),
    };
    if (!names.includes(name)) continue;
    const candidate = selection.candidates.find(value => value.candidate === name);
    assert.ok(candidate.registration, 'the diagnostic retains an actual registered candidate');
    assert.equal(candidate.milliseconds, optionalString(milliseconds));
    for (const [key, value] of Object.entries(quantities)) assert.equal(candidate[key], value);
    if (milliseconds === null) {
      missing.push(...workSlotsFor(name).map(slot => `${name}.workSlots[${slot}].milliseconds`));
    }
  }
  if (item.noEstimates) missing.push(...names.map(name => `${name}.evidence`));
  if (item.foreignNativeEstimate) missing.push('nativeQuery.inputConditions.requirementCid',
    'nativeQuery.inputConditions.source.database');
  assert.deepEqual(selection.estimates, expectedEstimates,
    'the planner retains exact admitted work coverage and quantities');
  assert.deepEqual(selection.evidence, expectedEvidence,
    'estimates retain their candidate, input conditions, unit and stated basis');
  assert.deepEqual(selection.missing, missing,
    'unknown evidence and wrong conditions report the exact missing information');
}

function assertObservation(document, selection, item) {
  assert.ok(document && typeof document === 'object', 'retain the actual receipt-owner document');
  const native = item.expectedCandidate === 'nativeQuery';
  assert.equal(document.version, native ? 'actql-query-two-receipt-observation/0.1'
    : 'actql-query-observation/0.1');
  assert.equal(document.requirement_cid, selection.requirementCid);
  assert.equal(document.source_ref, 'connector://crm/main/r#v');
  assert.equal(document.owner.stage, 'acquire');
  assert.equal(document.owner.input, 'remote');
  assert.match(document.owner.program_source_cid, cidPattern);
  assert.equal(document.coverage.complete, true);
  assert.equal(document.output.row_count, 3);
  assert.equal(document.output.rows_cid, cid(acquisitionRows),
    'the acquired rows retain source order before the downstream sort');
  assert.match(document.output.contract_cid, cidPattern);
  assert.equal(document.retention, 'process');
  if (native) {
    assert.equal(document.evidence_contract_cid, nativeEvidence);
    assert.deepEqual(Object.keys(document.accesses).sort(), ['native_result_cid', 'validation_scan_cid']);
    for (const [role, rows, fields] of [
      ['validation_scan', plannerSelectionRows, ['amount', 'id']],
      ['native_result', acquisitionRows, ['id']],
    ]) {
      const receipt = {version: 'actql-query-receipt/0.1', ...document.execution,
        requirement_cid: document.requirement_cid, snapshot: null,
        scan_scope_cid: document.coverage.scope_cid, role,
        received_rows_cid: cid(rows), received_rows: rows.length,
        received_fields: fields, received_bytes: Buffer.byteLength(canonical(rows))};
      assert.equal(document.accesses[`${role}_cid`], cid(receipt),
        `${role} matches independently authored rows, schema and byte count`);
    }
  } else {
    assert.deepEqual(document.actual_access, {
      scope_cid: cid({version: 'actql-query-access-scope/0.1',
        requirement_cid: document.requirement_cid,
        received_fields: ['amount', 'id'], received_rows_cid: cid(plannerSelectionRows)}),
      provider_scope_cid: null, received_rows: 4, received_fields: ['amount', 'id'],
      received_bytes: Buffer.byteLength(canonical(plannerSelectionRows)),
    });
  }
}

function assertSourceCommands(before, after, database, item) {
  const commands = after.sourceReadCommands.slice(before.sourceReadCommands.length);
  assert.equal(after.sourceReadSessions - before.sourceReadSessions, 1);
  const native = item.expectedCandidate === 'nativeQuery';
  assert.equal(commands.length, native ? 2 : 1, 'Native has two source receipts; Broad has one');
  assert.ok(commands.every(command => command.database === database));
  assert.equal(new Set(commands.map(command => command.session)).size, 1);
  assert.match(commands[0].sql, /^SELECT\s+"amount",\s*"id"\s+FROM\s+"main"\."records"\s*$/iu);
  if (native) {
    assert.equal(commands[1].sql,
      'SELECT "id" AS "id" FROM "main"."records" WHERE CAST("amount" AS DOUBLE) >= ?');
    assert.doesNotMatch(commands[1].sql, /ORDER\s+BY/iu, 'ordering is the downstream Local task');
  }
  const opens = after.sourceProviderOpens.slice(before.sourceProviderOpens.length);
  assert.ok(opens.length > 0);
  assert.ok(opens.every(path => path === database));
  return commands;
}

function readSelection(events) {
  const decisions = events.filter(event => event.name === 'acquisition_selection' ||
    event.name === 'acquisition_started').map(event => event.detail.selection);
  assert.ok(decisions.length > 0, 'read the actual pre-I/O planner owner diagnostic');
  for (const decision of decisions) assert.deepEqual(decision, decisions[0]);
  return decisions[0];
}

function readAcquisition(events, selection) {
  const completed = events.filter(event => event.name === 'acquisition_completed');
  assert.equal(completed.length, 1);
  const acquisition = completed[0].detail.acquisition;
  assert.deepEqual(acquisition.selection, selection);
  return acquisition.observation;
}

export async function exercisePlannerSelectionPublicQuery({connect, openInstalledRemoteHttpHost,
  root, installation, duckdb, tls}) {
  const provider = observeTwoSourceProvider(duckdb, {source: installation.database});
  const observations = [];
  const program = plannerSelectionProgram();
  try {
    for (const mode of ['local', 'https']) for (const item of plannerSelectionCases) {
      const events = [];
      const directory = resolve(root, `${mode}-${item.name}-state`);
      const before = provider.snapshot();
      const running = await openSingleSourcePublicHost({connect, openInstalledRemoteHttpHost,
        mode, directory, sourceProfilePath: installation.profiles[item.name], tls,
        authorization: hostAuthorization((name, detail) => events.push({name, detail}))});
      let client;
      const requestId = `planner-${mode}-${item.name}`;
      const text = item.filter === undefined ? program : plannerSelectionProgram(item.filter);
      try {
        client = await running.connect();
        if (item.denyRead || item.deferred) {
          let refusalCode;
          await assert.rejects(client.aql(text, {format: 'json', requestId}), error => {
            refusalCode = error.code;
            if (item.denyRead) assert.equal(refusalCode, 'ACTQL_E_ACCOUNT_DENIED');
            else assert.equal(refusalCode, 'ClientProgramRejected',
              'cost ignorance is a rejected preparation, not an unsupported Program claim');
            return true;
          });
          await new Promise(resolve => setImmediate(resolve));
          assert.deepEqual(provider.snapshot(), before, 'refusal performs zero provider opens and zero SQL');
          assert.deepEqual(await client.lookupRequest(requestId), {kind: 'not_found'});
          assert.equal(readTwoSourceJournal(directory).length, 0, 'refusal accepts no Run');
          assert.equal(events.filter(event => event.name === 'acquisition_started').length, 0);
          assert.equal(events.filter(event => event.name === 'acquisition_completed').length, 0);
          const selection = item.deferred ? readSelection(events) : undefined;
          if (item.deferred) assertSelection(selection, item, installation.source);
          if (item.denyRead) assert.equal(events.filter(event => event.name === 'acquisition_selection').length, 0,
            'current read authorization is checked before cost selection');
          observations.push({mode, name: item.name, selection, refusalCode,
            provider: {sourceIo: 0, sourceReads: 0, sourceProviderOpens: []}});
          continue;
        }
        const execution = await client.aql(text, {format: 'json', requestId});
        const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
        assert.equal(state.status, 'succeeded', JSON.stringify({mode, name: item.name, state}));
        const result = execution.result('selected');
        const rows = await result.all();
        const columns = (await result.describe()).columns;
        assert.deepEqual(rows, expectedRows, 'exact order and duplicate multiplicity');
        assert.deepEqual(columns, expectedColumns, 'exact retained column order and contracts');
        const reader = result.rows();
        assert.deepEqual(await Array.fromAsync(reader), expectedRows);
        assert.equal(reader.state(), 'complete');
        assert.equal(events.filter(event => event.name === 'acquisition_started').length, 1);
        assert.equal(events.filter(event => event.name === 'acquisition_completed').length, 1);
        const selection = readSelection(events);
        assertSelection(selection, item, installation.source);
        const acquisition = readAcquisition(events, selection);
        assertObservation(acquisition, selection, item);
        const after = provider.snapshot();
        const commands = assertSourceCommands(before, after, installation.database, item);
        const attached = await client.attach(execution.ref);
        assert.deepEqual(await attached.result('selected').all(), expectedRows);
        const resent = await client.aql(text, {format: 'json', requestId});
        assert.deepEqual(resent.ref, execution.ref);
        assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
        assert.deepEqual(provider.snapshot(), after, 'retained reads and duplicate submission do not reacquire');
        assert.equal(readTwoSourceJournal(directory).length, 1);
        observations.push({mode, name: item.name, ref: execution.ref,
          selection, acquisition, sourceReadCommands: commands, rows, columns});
        console.log(`Public planner selection passed: ${mode}/${item.name}`);
      } finally { client?.close(); await running.close(); }
    }
    // Profile-only latency changes preserve the same checked requirement and
    // output contract, while the actual receipt-owner shape changes.
    for (const mode of ['local', 'https']) {
      const sameProgram = observations.filter(item => item.mode === mode &&
        ['native-cheaper', 'broad-cheaper', 'equal-cost', 'native-capability-missing'].includes(item.name));
      assert.equal(new Set(sameProgram.map(item => item.selection.requirementCid)).size, 1);
      assert.equal(new Set(sameProgram.map(item => item.acquisition.owner.program_source_cid)).size, 1);
      assert.equal(new Set(sameProgram.map(item => item.acquisition.output.contract_cid)).size, 1);
    }
    assert.equal(observations.length, 22);
    return observations;
  } finally { provider.restore(); }
}
