import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {installedEffectIdentity, loadInstalledEffect as loadEffect,
  publishInstalledEffectProfile} from './installed-effect.mjs';
import {sourceAliasPublication} from './source-alias-publication.mjs';
import {installedUpdateTargets} from './installed-effect-inventory.mjs';
import {installedInventoryComponent} from './fixtures/installed-inventory-component.fixture.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {composeInstalledCheckEnvironment} from './installed-check-environment.mjs';
import {createInstalledRowEffect, retainInstalledRowEffectAdapter,
  installedRowEffectOwnerBinding, validateInstalledUpdateOwnerSelections} from './installed-row-effect.mjs';
import {installNodePublicSourcePreparation} from './public-source-preparation.mjs';
import {fundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {installNodeClientEffectRun} from './client-effect-run.mjs';
import {readInstalledModelExecution} from './installed-model.mjs';
import {installUpdateTargetOriginals} from './installed-update-originals.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {assertUpdateTargetSelectionCurrent, assertUpdateTargetSelectionMembersCurrent,
  createUpdateTargetOriginalShapeControl, updateTargetSelectionsCid,
  originalUpdateTargetSelectionsCid} from './update-target-original-shape.mjs';

const runtimeUrl = process.env.ACTQL_TEST_COMMON_RUNTIME === undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)
  : new URL(process.env.ACTQL_TEST_COMMON_RUNTIME, 'file:');
const moon = await import(runtimeUrl.href);
const baseWire = (await readFile(new URL('../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trimEnd();
const version = 'actql-installed-update-target-fixture/0.1';
// Authored publication metadata and row-owner ports test alias composition;
// they do not qualify bound connector initialization or physical Provider IO.
const loadInstalledEffect = (path, options) => options.loadMember(path, options);
const loadInstalledEffects = (paths, options) => paths.length < 2
  ? loadInstalledEffect(paths[0], options) : options.inventory.load('effect', paths, options);
const cid = digit => `sha256:${digit.repeat(64)}`;
const alias = (name = 'crm.Account', targetRef = 'connector://crm/account') => ({name, targetRef});
const seal = body => {
  const {evidence_bundle_cid: ignored, ...rest} = body;
  void ignored;
  for (const key of ['mapping_contracts', 'connector_catalogs']) {
    rest[key].sort((left, right) => contentCid(left).localeCompare(contentCid(right)));
  }
  return canonicalJson({...rest, evidence_bundle_cid: contentCid(rest)});
};

function adapter({connectorId = 'crm', count = 1} = {}) {
  const body = JSON.parse(baseWire);
  const targetRef = `connector://${connectorId}/account`;
  const manifestCid = withFixtureConnector(body, targetRef);
  const schema = {type: 'object', nullable: false, additional_properties: false,
    fields: {Id: {type: 'string', nullable: false}, Name: {type: 'string', nullable: true}}};
  body.mapping_contracts = Array.from({length: count}, (_, index) => {
    const mapping = {schema: 'actql.mapping_contract/0.1', version: 'fixture',
      connector_manifest_cid: manifestCid,
      mapping_ref: `mapping:${connectorId}.account.${index}.v1`, target_ref: targetRef,
      target_schema: schema, target_schema_identity: contentCid(schema),
      resource_identity_cid: cid('b'), primary_identity: 'Id',
      minimum_approval: 'required', conversions: [], required_fields: [],
      writable_fields: ['Name'], required_permissions: [],
      row_mapping: {Name: {field: 'name', null_behavior: 'reject'}},
      permission_rules: [{effect_kind: 'update', selector_class: 'id',
        write_fields: ['Name'], permissions: ['scope:update']}]};
    return {...mapping, mapping_contract_cid: contentCid(mapping)};
  });
  const effectSelectors = Object.freeze(body.mapping_contracts.map(mapping => Object.freeze({
    kind: 'update', target: mapping.target_ref, mappingRef: mapping.mapping_ref,
    mappingCid: mapping.mapping_contract_cid})));
  return {environmentWire: seal(body), effectSelectors,
    connectorBindings: Object.freeze([Object.freeze({connectorId, bindingCid: cid('c')})]),
    connectorRegistration: 'update_target_fixture', connectorRevision: 'update_target_fixture/0.1'};
}

async function fixture(t, installations = {main: adapter()}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-update-target-'));
  let inventory;
  const originalRows = new Set();
  t.after(async () => {
    await inventory?.close();
    for (const row of originalRows) await row.close();
    await rm(root, {recursive: true, force: true});
  });
  const counts = {loads: 0, publishes: 0, closes: 0, prepares: 0, credentials: 0};
  const checkedProfiles = [];
  const check = profile => {
    assert.equal(Object.hasOwn(profile, 'queryUpdateTargets'), false,
      'Host-owned aliases must not enter the provider closed profile');
    assert.ok(Object.keys(profile).every(key => ['version', 'installation'].includes(key)));
    checkedProfiles.push(profile);
    return Object.freeze({...profile});
  };
  const connectorTable = createInstalledConnectorTable([{
    name: 'update_target_fixture', registration: 'update_target_fixture', revision: 'update_target_fixture/0.1',
    effect: {profileVersion: version, load: async () => ({check,
      identityParts(profile) { check(profile); return [profile]; },
      publish(profile) { counts.publishes++; return profile; },
      async load(profile) {
        counts.loads++;
        const selected = installations[profile.installation ?? 'main'];
        const body = JSON.parse(selected.environmentWire);
        const connectorId = body.mapping_contracts[0].target_ref.split('/')[2];
        const unavailable = () => { counts.prepares++; assert.fail('Publication cannot perform provider work'); };
        let siteClosed = false;
        const row = await createInstalledRowEffect({moon, environmentWire: selected.environmentWire,
          connectorId, connectorRegistration: 'update_target_fixture',
          connectorRevision: selected.ownerRevision ?? 'update_target_fixture/0.1',
          connection: 'fixture', runtimeBundleCid: selected.ownerRuntime ?? cid('d'),
          bindingCid: cid('c'), continuationBinding: selected.ownerGeneration ?? cid('e'),
          ledgerRoot: join(root, 'ledger'),
          mappings: body.mapping_contracts.map(mapping => ({resource: 'account',
            mappingRef: mapping.mapping_ref, mappingCid: mapping.mapping_contract_cid,
            body: canonicalJson(mapping)})),
          site: {issueReadGrant: unavailable, issueEffectGrant: unavailable,
            close() { if (!siteClosed) {siteClosed = true; counts.closes++;} return true; }},
          authorization: {authorize: unavailable},
          driver: {kinds: ['update'], prepareRequest: unavailable, requestFacts: unavailable,
            writeOperation: unavailable, send: unavailable, project: unavailable,
            footprint: unavailable, targetRead: {operation: 'read'},
            observeTargets: unavailable, recoveryEntry: unavailable, recoverRequests: unavailable, requestCid: unavailable},
        });
        originalRows.add(row);
        // Fault fixtures may deliberately present unowned metadata. Valid
        // fixtures retain the real row factory's private provenance.
        // The independent environment sealer sorts contracts by CID. Its
        // inventory order need not equal the fixture author's insertion order;
        // retain the real row Owner only for the same COMPLETE selector set.
        const selectorSet = values => values.map(canonicalJson).sort();
        if (Array.isArray(selected.effectSelectors) &&
            JSON.stringify(selectorSet(selected.effectSelectors)) ===
            JSON.stringify(selectorSet(row.effectSelectors))) {
          selected.effectSelectors = row.effectSelectors;
        }
        const projected = Object.freeze({...row, ...selected,
          prepareCaptured: row.prepareCaptured, prepareRecovered: row.prepareRecovered,
          close: row.close});
        return projected.effectSelectors === row.effectSelectors
          ? retainInstalledRowEffectAdapter(row, projected) : projected;
      },
    })},
  }]);
  let sequence = 0;
  const path = async (targets, installation) => {
    const destination = join(root, `profile-${sequence++}.json`);
    await writeFile(destination, JSON.stringify({version,
      ...(installation === undefined ? {} : {installation}),
      ...(targets === undefined ? {} : {queryUpdateTargets: targets})}));
    return destination;
  };
  const loadMember = async (path, captured, retain) => {
    const before = new Set(originalRows);
    try {
      const value = await loadEffect(path, {...captured, installationServices: undefined});
      retain?.(value);
      return value;
    } catch (cause) {
      // This explicit component member owns the actual row factory result,
      // including a malformed facade the production loader must not trust.
      const acquired = [...originalRows].filter(row => !before.has(row));
      assert.ok(acquired.length <= 1);
      if (acquired.length) throw await retainInstalledHostInitializationFailure(cause,
        {installedEffect: acquired[0]});
      throw cause;
    }
  };
  inventory = installedInventoryComponent({}, originalRows, loadMember);
  const options = {root, principalId: 'fixture', moon, runtimeUrl, connectorTable,
    baseEnvironmentWire: baseWire, loadMember, inventory,
    resolveSecret() { counts.credentials++; assert.fail('Installation cannot read credentials'); }};
  return {root, path, options, counts, checkedProfiles};
}

const ownerFacts = (changes = {}) => ({
  connector_registration: 'update_target_fixture', connector_revision: 'update_target_fixture/0.1',
  runtime_bundle_cid: cid('d'), binding_cid: cid('c'), connection: 'fixture',
  profile: {continuation: 'actql-installed-row-effect-continuation/0.1',
    continuationBinding: 'binding_cid', dispatch: 'actql-installed-row-effect-dispatch/0.1',
    recovery: 'actql-installed-row-effect-recovery/0.1', source: 'actql-installed-row-effect-source/0.1',
    targetCheck: 'actql-installed-row-effect-check/0.1', unit: 'actql-installed-row-effect-unit/0.1'},
  continuation_binding: cid('e'), ...changes,
});
// Independent Python SHA-256 fixture, shared with the fixed selection corpus.
const ownerCid = 'sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9';
const primary = expected => error => {
  assert.equal(error.primaryFailure?.code ?? error.code, expected);
  return true;
};
const admitted = wire => {
  const environment = moon.clientProgramCheckEnvironment(wire,
    JSON.parse(wire).evidence_bundle_cid, false, true, true, true, true, false, false);
  assert.notEqual(environment, undefined);
  return environment;
};

function originalOwnerFixture(installed) {
  const environment = admitted(installed.environmentWire);
  const publication = sourceAliasPublication(moon, environment, [], [],
    {updateTargets: installed.queryUpdateTargets});
  const preparation = installNodePublicSourcePreparation({moon, environment, publication, allowEffects: true});
  const outcome = preparation.prepare({format: 'aql-text', document:
    "SELECT 'id' AS id, 'Ada' AS name |> RESULT updates |> EFFECT UPDATE crm.Account FROM RESULT updates ID id SET (Name = name)"});
  assert.equal(outcome.kind, 'effectful');
  const prepared = moon.clientProgramEffectPreparationReady(outcome.outcome);
  assert.ok(prepared, moon.clientProgramEffectPreparationIssueCode(outcome.outcome));
  const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
  const control = runtimeCore(moon).publicationControl;
  const limits = {maxWireBytes: 1_000_000, maxNodes: 100_000, maxDepth: 100};
  const originals = installUpdateTargetOriginals({moon, control, installedEffect: installed, limits});
  return {prepared, compilation, originals, control, limits};
}

test('original submitted intent binds UPDATE evidence after one shape admission', async t => {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  let journal;
  try {
    const owner = originalOwnerFixture(installed);
    const originalShape = createUpdateTargetOriginalShapeControl(moon);
    let shapes = 0;
    journal = openClientRequestJournal(join(f.root, 'intent-evidence'), {
      updateOriginalControl: Object.freeze({run(...args) {
        shapes++;
        return originalShape.run(...args);
      }}),
    });
    const authorityScopeCid = cid('a'), fields = {authorityScopeCid, currentAuthorization: true};
    const submissionRef = {epoch: journal.issueSubmissionEpoch(fields, moon), nonce: 'one-original-shape'};
    const text = "SELECT 'id' AS id, 'Ada' AS name |> RESULT updates |> EFFECT UPDATE crm.Account FROM RESULT updates ID id SET (Name = name)";
    const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'aql',
      input: {text, format: 'aql-text'}, parameters: null}), 1048576, 65536, 64);
    assert.ok(intent);
    const recorded = journal.recordSubmittedIntent(submissionRef, intent, fields, moon);
    const identity = moon.clientProgramEffectRequestIdentity(owner.prepared,
      authorityScopeCid, recorded.requestId, moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(identity);
    const allowed = checked(moon.clientProgramIssueAllowedEffectRun(owner.compilation,
      cid('1'), cid('2'), '2099-01-01T00:00:00.000Z'));
    const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'intent-update', 'intent-update-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    const runDefinition = owner.control.admit('run_definition', moon.strategyPublicationContractJson(definition), owner.limits);
    const original = owner.originals.captureRun({...owner, allowed, definition, identity});
    const evidence = {
      prepared: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(allowed)),
      authorization: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(allowed)),
      updateTargetRunOriginal: original,
    };
    const accepted = journal.acceptDefinition(identity, {namespaceId: 'intent-update', runDefinition,
      runAdmissionEvidence: evidence, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      submission: {...submissionRef, currentAuthorization: true, intentCid: recorded.intentCid}}, moon, owner.control);
    assert.equal(shapes, 1, 'Adding the checked intent CID does not re-admit unchanged UPDATE materials');
    assert.deepEqual(accepted.runAdmissionEvidence, {...evidence, submittedIntentCid: recorded.intentCid});
    const retained = journal.lookupRunDefinition(accepted.ref, moon, owner.control);
    assert.equal(shapes, 2, 'A distinct stored observation still admits its actual evidence');
    assert.deepEqual(retained.runAdmissionEvidence, accepted.runAdmissionEvidence);
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally {journal?.close(); await installed.close();}
});

async function intentEvidenceCounter(t) {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  let journal;
  try {
    const owner = originalOwnerFixture(installed), originalShape = createUpdateTargetOriginalShapeControl(moon);
    let shapes = 0;
    const directory = join(f.root, 'capture-controls');
    const journalOptions = {updateOriginalControl: Object.freeze({run(...args) {
      shapes++;
      return originalShape.run(...args);
    }})};
    journal = openClientRequestJournal(directory, journalOptions);
    const fields = {authorityScopeCid: cid('a'), currentAuthorization: true};
    const submissionRef = {epoch: journal.issueSubmissionEpoch(fields, moon), nonce: 'captured-evidence'};
    const text = "SELECT 'id' AS id, 'Ada' AS name |> RESULT updates |> EFFECT UPDATE crm.Account FROM RESULT updates ID id SET (Name = name)";
    const intent = moon.clientSubmittedIntent(JSON.stringify({kind: 'aql',
      input: {text, format: 'aql-text'}, parameters: null}), 1048576, 65536, 64);
    const recorded = journal.recordSubmittedIntent(submissionRef, intent, fields, moon);
    const identity = moon.clientProgramEffectRequestIdentity(owner.prepared,
      fields.authorityScopeCid, recorded.requestId, moon.clientProgramSourceFreeInputIntentCid());
    const allowed = checked(moon.clientProgramIssueAllowedEffectRun(owner.compilation,
      cid('1'), cid('2'), '2099-01-01T00:00:00.000Z'));
    const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'capture-control', 'capture-control-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    const original = owner.originals.captureRun({...owner, allowed, definition, identity});
    const evidence = {
      prepared: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(allowed)),
      authorization: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(allowed)),
      updateTargetRunOriginal: original,
    };
    const options = {namespaceId: 'capture-control',
      runDefinition: owner.control.admit('run_definition', moon.strategyPublicationContractJson(definition), owner.limits),
      runAdmissionEvidence: evidence, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
      submission: {...submissionRef, currentAuthorization: true, intentCid: recorded.intentCid}};
    return {owner, evidence, options, directory, recorded,
      get journal() {return journal;}, get shapes() {return shapes;},
      accept(overrides = {}) {return journal.acceptDefinition(identity, {...options, ...overrides}, moon, owner.control);},
      reopenWithLimit(maxRunDefinitionWireBytes) {
        journal.close();
        journal = openClientRequestJournal(directory, {...journalOptions, maxRunDefinitionWireBytes});
      },
      async close() {journal.close(); await installed.close();},
    };
  } catch (error) {journal?.close(); await installed.close(); throw error;}
}

test('captured UPDATE evidence is local to one acceptance and changed saved bytes refuse', async t => {
  const f = await intentEvidenceCounter(t);
  try {
    const first = f.accept();
    assert.equal(f.shapes, 1);
    const second = f.accept();
    assert.equal(f.shapes, 2, 'A new operation admits its proposed evidence once');
    assert.deepEqual(second.ref, first.ref);
    assert.equal(second.inserted, false);
    const copied = f.accept({runAdmissionEvidence: structuredClone(f.evidence)});
    assert.equal(f.shapes, 3, 'A copied input also receives its own full admission');
    assert.deepEqual(copied.runAdmissionEvidence, first.runAdmissionEvidence);
    const writer = new DatabaseSync(join(f.directory, 'client-requests.sqlite3'));
    try {
      writer.prepare('UPDATE client_requests SET run_admission_evidence_json = ?')
        .run(JSON.stringify({...first.runAdmissionEvidence, prepared: 'changed'}));
      assert.throws(() => f.accept(), {code: 'ClientRequestJournalCorrupt'});
      assert.equal(f.shapes, 5, 'Changed selected evidence follows full admission and refuses');
    } finally {writer.close();}
  } finally {await f.close();}
});

test('captured UPDATE evidence uses each input getter once and checks serialized materials', async t => {
  const f = await intentEvidenceCounter(t);
  try {
    let preparedReads = 0;
    const captured = f.accept({runAdmissionEvidence: {get prepared() {
      preparedReads++;
      return f.evidence.prepared;
    }, authorization: f.evidence.authorization, updateTargetRunOriginal: f.evidence.updateTargetRunOriginal}});
    assert.equal(preparedReads, 1);
    assert.equal(captured.runAdmissionEvidence.prepared, f.evidence.prepared);
    let serializations = 0;
    const changed = Object.assign(Object.create({toJSON() {
      serializations++;
      return {...f.evidence, prepared: 'changed serialized material'};
    }}), f.evidence);
    assert.throws(() => f.accept({runAdmissionEvidence: changed}), {code: 'InvalidClientRunAdmissionEvidence'});
    assert.equal(serializations, 1);
    const beforeUnknown = f.shapes;
    assert.throws(() => f.accept({runAdmissionEvidence: {...f.evidence, unknown: true}}),
      {code: 'InvalidClientRunAdmissionEvidence'});
    assert.equal(f.shapes, beforeUnknown, 'Unknown fields refuse before material admission');
  } finally {await f.close();}
});

test('captured UPDATE intent binding retains its final wire limit and original CID check', async t => {
  const f = await intentEvidenceCounter(t);
  try {
    assert.throws(() => f.accept({runAdmissionEvidence: {...f.evidence, submittedIntentCid: cid('f')}}),
      {code: 'ClientRequestSubmittedIntentMismatch'});
    f.reopenWithLimit(Buffer.byteLength(JSON.stringify(f.evidence)));
    assert.throws(() => f.accept(), error => {
      assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
      assert.equal(error.cause?.code, 'InvalidClientRunAdmissionEvidence');
      return true;
    }, 'The existing transaction error remains the same; no known-refusal reclassification');
    const reader = new DatabaseSync(join(f.directory, 'client-requests.sqlite3'), {readOnly: true});
    try {assert.equal(reader.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);}
    finally {reader.close();}
  } finally {await f.close();}
});

test('actual JSON UPDATE preparation retains the installed selection in its original Run', async t => {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  try {
    const environment = admitted(installed.environmentWire);
    const publication = sourceAliasPublication(moon, environment, [], [],
      {updateTargets: installed.queryUpdateTargets});
    const prepare = await fundedClientPreparation(t, {moon, environment,
      allowEffects: true, sourcePublication: publication});
    const prepared = await prepare({kind: 'program', parameters: null, input: {
      version: 'actql/0.1', id: 'json-update-original', stages: [{id: 'apply', inputs: {},
        steps: [{values: {schema: {id: {type: 'string', nullable: false},
          name: {type: 'string', nullable: false}}, rows: [{id: 'original-id', name: 'Ada'}]},
        as: 'selected'}],
        results: {rows: {from: 'selected', fields: ['id', 'name']}},
        effects: {save: {update: {target: 'connector://crm/account',
          mapping: 'mapping:crm.account.0.v1', from: {result: 'rows'}, id: 'id',
          set: {Name: {field: 'name'}}}}}}],
      results: {updates: {from: {stage: 'apply', result: 'rows'}}},
    }});
    assert.equal(prepare.kindOf(prepared), 'effectful');
    const control = runtimeCore(moon).publicationControl;
    const originals = installUpdateTargetOriginals({moon, control, installedEffect: installed,
      limits: {maxWireBytes: 1_000_000, maxNodes: 100_000, maxDepth: 100}});
    const selection = originals.selectionsOf(prepared);
    assert.equal(selection?.length, 1);
    const compilation = checked(moon.clientProgramCompileLocalEffects(prepared));
    const allowed = checked(moon.clientProgramIssueAllowedEffectRun(compilation,
      cid('1'), cid('2'), '2099-01-01T00:00:00.000Z'));
    const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'json-update', 'json-update-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    const identity = moon.clientProgramEffectRequestIdentity(prepared,
      cid('a'), 'json-update-request', moon.clientProgramSourceFreeInputIntentCid());
    const original = originals.captureRun({prepared, compilation, allowed, definition, identity});
    assert.equal(typeof original?.materialsWire, 'string');
    assert.equal(JSON.parse(moon.strategyPublicationContractJson(definition)).effect_target_selections_cid,
      originalUpdateTargetSelectionsCid(selection));
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { await installed.close(); }
});

test('actual JSON Model UPDATE acceptance saves and restores both originals in the same SQLite Run', async t => {
  const {program, configuration} = await import('../../scripts/fixtures/installed-infer-fixture.mjs');
  const selected = adapter();
  const {installation} = configuration(JSON.parse(selected.environmentWire));
  selected.environmentWire = installation.environmentWire;
  const f = await fixture(t, {main: selected});
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  let journal;
  try {
    const environment = admitted(installed.environmentWire);
    const publication = sourceAliasPublication(moon, environment, [], [],
      {updateTargets: installed.queryUpdateTargets});
    const prepare = await fundedClientPreparation(t, {moon, environment,
      allowEffects: true, sourcePublication: publication});
    const document = structuredClone(program);
    document.stages[0].steps[0].values.schema.text.nullable = false;
    document.stages[0].steps.splice(4, 2, {join: {with: 'unique', kind: 'inner',
      cardinality: 'one_to_one', on: [{left: 'id', right: 'id'}],
      select: {id: 'right.id', name: 'right.text'}}, as: 'selected'});
    // The existing composed Model graph rejoins its immediate original
    // uniqueness-checked prefix, as does the Common retained-material fixture.
    document.stages[0].steps.splice(2, 1);
    document.stages[0].results = {rows: {from: 'selected', fields: ['id', 'name']}};
    document.stages[0].effects = {save: {update: {target: 'connector://crm/account',
      mapping: 'mapping:crm.account.0.v1', from: {result: 'rows'}, id: 'id',
      set: {Name: {field: 'name'}}}}};
    document.results = {updates: {from: {stage: 'main', result: 'rows'}}};
    // Match public startSource(..., {format: 'json'}), not the separate
    // object-Program convenience route. Both must reach the same Effect Owner.
    const prepared = await prepare({kind: 'aql', parameters: null,
      input: {text: JSON.stringify(document), format: 'json'}});
    assert.equal(prepare.kindOf(prepared), 'effectful');
    const occurrence = moon.clientProgramEffectInferOccurrence(prepared);
    assert.ok(occurrence);
    const {execution} = readInstalledModelExecution(moon, prepared, installation, occurrence);
    const graph = checked(moon.clientProgramInstalledComposedInferPlanGraph(occurrence, execution));
    const control = runtimeCore(moon).publicationControl;
    const limits = {maxWireBytes: 1_000_000, maxNodes: 100_000, maxDepth: 100};
    const originals = installUpdateTargetOriginals({moon, control, installedEffect: installed, limits});
    assert.equal(originals.selectionsOf(prepared)?.length, 1);
    const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
    const resultPolicy = control.admitSourceFreeResultPolicy({kind: 'data_policy',
      cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563',
      wire: policyWire}, limits);
    const directory = join(f.root, 'model-requests');
    const options = {updateOriginalControl: createUpdateTargetOriginalShapeControl(moon)};
    journal = openClientRequestJournal(directory, options);
    const owner = installNodeClientEffectRun({moon, journal, updateTargetOriginals: originals,
      authorizeRequest: async () => ({executionContextCid: cid('1'), hostPolicyCid: cid('2'),
        createdAt: '2026-10-16T00:00:00.000Z', expiresAt: '2099-01-01T00:00:00.000Z'}),
      authorizeRunStart: async () => false,
      inferPlanFor: original => { assert.equal(original, prepared); return graph; },
      resultPolicyOriginalFor: () => resultPolicy,
      execute: async () => assert.fail('Admission/readback must not execute Provider work'),
      now: () => '2026-10-16T00:00:00.000Z'});
    owner.checkSupported(prepared);
    const captured = owner.capturePreparedOriginal(prepared);
    assert.equal(typeof captured?.preparedWire, 'string');
    const handle = await owner.accept({prepared, authorityScopeCid: cid('a'),
      requestId: 'json-model-update', namespaceId: 'json-model-update', principalId: 'fixture',
      connection: {}, lookupExpiresAt: '2099-01-01T00:00:00.000Z'});
    const retained = journal.lookupRunDefinition(handle.ref, moon, control);
    assert.ok(retained);
    const evidence = retained.runAdmissionEvidence;
    assert.equal(typeof evidence.updateTargetRunOriginal?.materialsWire, 'string');
    assert.equal(typeof evidence.modelOriginalRunWire, 'string');
    const run = JSON.parse(retained.runDefinition.wire);
    assert.equal(run.effect_target_selections_cid,
      originalUpdateTargetSelectionsCid(originals.selectionsOf(prepared)));
    assert.equal(JSON.parse(evidence.modelOriginalRunWire).runDefinitionWire, retained.runDefinition.wire);
    const materials = JSON.parse(evidence.updateTargetRunOriginal.materialsWire);
    assert.equal(typeof materials.infer_execution_contract_json, 'string');
    assert.equal(materials.infer_execution_contract_cid,
      installation.executionContracts[0].cid);
    journal.close();
    journal = openClientRequestJournal(directory, options);
    const reopened = journal.lookupOwnedDefinition({namespaceId: 'json-model-update',
      authorityScopeCid: cid('a'), requestId: 'json-model-update',
      runDefinitionCid: handle.ref.runDefinitionCid}, moon, control);
    assert.ok(reopened?.requestIdentity);
    assert.deepEqual(reopened.runAdmissionEvidence, evidence);
    assert.equal(reopened.runDefinition.wire, retained.runDefinition.wire);
    const restored = originals.restoreRun(evidence.updateTargetRunOriginal,
      reopened.runDefinition, reopened.requestIdentity);
    restored.assertUpdateSelectionCurrent();
    assert.equal(originalUpdateTargetSelectionsCid(restored.updateTargetSelections),
      run.effect_target_selections_cid);
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { journal?.close(); await installed.close(); }
});

test('actual bound installation repeats complete current checks without generic DATA reconstruction', async t => {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  try {
    const owner = originalOwnerFixture(installed);
    let completedCurrentChecks = 0, completedEqualities = 0, genericConversions = 0;
    const observedMoon = {...moon,
      clientProgramEffectTargetSelectionCurrent(...args) {
        const result = moon.clientProgramEffectTargetSelectionCurrent(...args);
        if (result) completedCurrentChecks++;
        return result;
      },
      clientProgramEffectTargetInstallationsDataEqual(...args) {
        const result = moon.clientProgramEffectTargetInstallationsDataEqual(...args);
        if (result) completedEqualities++;
        return result;
      },
      clientProgramEffectTargetOriginalDataEqual(...args) {
        genericConversions++;
        return moon.clientProgramEffectTargetOriginalDataEqual(...args);
      },
    };
    const originals = installUpdateTargetOriginals({moon: observedMoon, control: owner.control,
      installedEffect: installed, limits: owner.limits});
    const original = originals.capturePrepared(owner.prepared, owner.compilation);
    // Complete cold DATA admission remains mandatory; object identity is absent.
    const restored = originals.restorePrepared(JSON.parse(JSON.stringify(original)));
    assert.ok(genericConversions > 0, 'Complete Prepared equality keeps its original full path');
    completedCurrentChecks = completedEqualities = genericConversions = 0;
    for (let index = 0; index < 3; index++) restored.assertUpdateSelectionCurrent();
    console.log('ACTQL_INSTALLATION_WORK ' + JSON.stringify({completedCurrentChecks,
      completedEqualities, genericConversions}));
    assert.equal(completedCurrentChecks, 3);
    assert.equal(completedEqualities, 3);
    assert.equal(genericConversions, 0);
    observedMoon.clientProgramEffectTargetSelectionCurrent = () => false;
    assert.throws(() => restored.assertUpdateSelectionCurrent(),
      {name: 'TypeError', message: 'InvalidEffectTargetSelections'});
    assert.equal(completedEqualities, 3);
    observedMoon.clientProgramEffectTargetSelectionCurrent = moon.clientProgramEffectTargetSelectionCurrent;
    for (const port of [undefined, () => false]) {
      observedMoon.clientProgramEffectTargetInstallationsDataEqual = port;
      assert.throws(() => restored.assertUpdateSelectionCurrent(), primary('InstalledEffectOriginalSelectionChanged'));
    }
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { await installed.close(); }
});

test('actual UPDATE Owner saves and restores the original prepared and Run data through the same SQLite journal', async t => {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  try {
    const owner = originalOwnerFixture(installed);
    const saved = owner.originals.capturePrepared(owner.prepared, owner.compilation);
    assert.equal(saved.installations[0].cid, ownerCid);
    const restored = owner.originals.restorePrepared(JSON.parse(JSON.stringify(saved)));
    restored.assertUpdateSelectionCurrent();
    assert.equal(updateTargetSelectionsCid(restored.updateTargetSelections),
      updateTargetSelectionsCid(owner.originals.selectionsOf(owner.prepared)));
    const allowed = checked(moon.clientProgramIssueAllowedEffectRun(owner.compilation,
      cid('1'), cid('2'), '2099-01-01T00:00:00.000Z'));
    const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'original-update', 'original-update-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    const runDefinition = owner.control.admit('run_definition', moon.strategyPublicationContractJson(definition), owner.limits);
    const identity = moon.clientProgramEffectRequestIdentity(owner.prepared,
      cid('a'), 'original-update-request', moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(identity);
    const original = owner.originals.captureRun({...owner, allowed, definition, identity});
    const evidence = {prepared: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(allowed)),
      authorization: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(allowed)),
      updateTargetRunOriginal: original};
    const directory = join(f.root, 'requests');
    const configuration = {updateOriginalControl: createUpdateTargetOriginalShapeControl(moon)};
    let journal = openClientRequestJournal(directory, configuration);
    try {
      journal.acceptDefinition(identity, {namespaceId: 'original-update', runDefinition,
        runAdmissionEvidence: evidence, lookupExpiresAt: '2099-01-01T00:00:00.000Z'}, moon, owner.control);
      journal.close();
      journal = openClientRequestJournal(directory, configuration);
      const retained = journal.lookupOwnedDefinition({namespaceId: 'original-update', authorityScopeCid: cid('a'),
        requestId: 'original-update-request', runDefinitionCid: runDefinition.identity}, moon, owner.control);
      assert.ok(retained);
      assert.deepEqual(retained.runAdmissionEvidence, evidence);
      const current = owner.originals.validateRun({...owner, evidence: retained.runAdmissionEvidence,
        runDefinition: retained.runDefinition, identity: retained.requestIdentity});
      current.assertUpdateSelectionCurrent();
      const foreign = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
        'original-update', 'foreign-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
      assert.throws(() => owner.originals.restoreRun(original,
        owner.control.admit('run_definition', moon.strategyPublicationContractJson(foreign), owner.limits), identity));
      const body = JSON.parse(original.materialsWire);
      body.effect_target_selections_json = body.effect_target_selections_json.replace('mapping:crm.account.0.v1', 'mapping:foreign');
      assert.throws(() => owner.originals.restoreRun({...original, materialsWire: canonicalJson(body)}, runDefinition, identity));
    } finally { journal.close(); }
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { await installed.close(); }
});

test('actual UPDATE original refuses copied selection foreign prepared installation and stale generation', async t => {
  const f = await fixture(t, {main: adapter(), stale: {...adapter(), ownerGeneration: cid('f')}});
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  const stale = await loadInstalledEffect(await f.path([alias()], 'stale'), f.options);
  try {
    const owner = originalOwnerFixture(installed), foreign = originalOwnerFixture(installed);
    const selections = owner.originals.selectionsOf(owner.prepared);
    const members = selections.map(({stage_index, effect_id, target_ref, mapping_ref, mapping_cid}) =>
      ({stage_index, effect_id, target_ref, mapping_ref, mapping_cid}));
    assertUpdateTargetSelectionMembersCurrent(selections, members, owner.prepared);
    assert.throws(() => assertUpdateTargetSelectionMembersCurrent(selections, members, foreign.prepared));
    assert.throws(() => assertUpdateTargetSelectionMembersCurrent(selections.map(value => ({...value})), members, owner.prepared));
    const copiedDescriptors = Object.defineProperties([], Object.getOwnPropertyDescriptors(selections));
    assert.throws(() => assertUpdateTargetSelectionMembersCurrent(copiedDescriptors, members, owner.prepared));
    assert.equal(originalUpdateTargetSelectionsCid(selections, moon), updateTargetSelectionsCid(selections));
    assert.throws(() => originalUpdateTargetSelectionsCid(copiedDescriptors, moon));
    assert.throws(() => assertUpdateTargetSelectionCurrent(selections, [], owner.prepared));
    const saved = owner.originals.capturePrepared(owner.prepared, owner.compilation);
    assert.throws(() => originalOwnerFixture(stale).originals.restorePrepared(saved));
    assert.throws(() => owner.originals.restorePrepared({...saved,
      installations: [installedRowEffectOwnerBinding(stale)]}));
    assert.throws(() => owner.originals.restorePrepared({...saved, compiledPlanCid: cid('f')}));
    assert.throws(() => owner.originals.restorePrepared({...saved,
      preparedWire: saved.preparedWire.replace('mapping:crm.account.0.v1', 'mapping:foreign')}));
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { await installed.close(); await stale.close(); }
});

test('actual validated Run selection stays with the original caller preparation through installation checks', async t => {
  const f = await fixture(t, {main: adapter(), stale: {...adapter(), ownerGeneration: cid('f')}});
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  const stale = await loadInstalledEffect(await f.path([alias()], 'stale'), f.options);
  try {
    const owner = originalOwnerFixture(installed);
    const allowed = checked(moon.clientProgramIssueAllowedEffectRun(owner.compilation,
      cid('1'), cid('2'), '2099-01-01T00:00:00.000Z'));
    const definition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'caller-pair', 'caller-pair-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    const identity = moon.clientProgramEffectRequestIdentity(owner.prepared,
      cid('a'), 'caller-pair-request', moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(identity);
    const original = owner.originals.captureRun({...owner, allowed, definition, identity});
    const evidence = {prepared: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunPrepared(allowed)),
      authorization: moon.strategyRunEvidenceJson(moon.clientProgramAllowedEffectRunAuthorization(allowed)),
      updateTargetRunOriginal: original};
    const runDefinition = owner.control.admit('run_definition',
      moon.strategyPublicationContractJson(definition), owner.limits);
    const validated = owner.originals.validateRun({...owner, evidence, runDefinition, identity});
    // Match client-effect-run's original {prepared, compilation, ...original}
    // facts at selectedInstalledEffect -> validateOwnerSelections. Whole saved
    // material equality cannot graft a restored selection onto this caller.
    assert.equal(validateInstalledUpdateOwnerSelections(installed,
      validated.updateTargetSelections, owner.prepared), validated.updateTargetSelections);
    validated.assertUpdateSelectionCurrent();
    const members = validated.updateTargetSelections.map(({stage_index, effect_id,
      target_ref, mapping_ref, mapping_cid}) =>
      ({stage_index, effect_id, target_ref, mapping_ref, mapping_cid}));
    assertUpdateTargetSelectionMembersCurrent(validated.updateTargetSelections, members, owner.prepared);
    const foreign = originalOwnerFixture(installed);
    const changed = {code: 'InstalledRowEffectInstallationChanged'};
    assert.throws(() => validateInstalledUpdateOwnerSelections(installed,
      validated.updateTargetSelections, foreign.prepared), changed);
    assert.throws(() => validateInstalledUpdateOwnerSelections(installed,
      [...validated.updateTargetSelections], owner.prepared), changed);
    const copied = Object.defineProperties([], Object.getOwnPropertyDescriptors(validated.updateTargetSelections));
    assert.throws(() => validateInstalledUpdateOwnerSelections(installed, copied, owner.prepared), changed);
    assert.throws(() => validateInstalledUpdateOwnerSelections(stale,
      validated.updateTargetSelections, owner.prepared), changed);
    const staleOwner = originalOwnerFixture(stale);
    assert.throws(() => staleOwner.originals.validateRun({...owner, evidence, runDefinition, identity}));
    const foreignDefinition = checked(moon.clientProgramIssueEffectRunDefinition(allowed,
      'caller-pair', 'foreign-run', '2026-10-16T00:00:00.000Z', '2099-01-01T00:00:00.000Z'));
    assert.throws(() => owner.originals.validateRun({...owner, evidence, identity,
      runDefinition: owner.control.admit('run_definition', moon.strategyPublicationContractJson(foreignDefinition), owner.limits)}));
    const foreignIdentity = moon.clientProgramEffectRequestIdentity(owner.prepared,
      cid('a'), 'foreign-request', moon.clientProgramSourceFreeInputIntentCid());
    assert.ok(foreignIdentity);
    assert.throws(() => owner.originals.validateRun({...owner, evidence, runDefinition, identity: foreignIdentity}));
    const before = evidence.updateTargetRunOriginal.materialsWire;
    const substituted = {...evidence, updateTargetRunOriginal: {...original,
      materialsWire: before.replace('caller-pair-run', 'foreign-run')}};
    assert.notEqual(substituted.updateTargetRunOriginal.materialsWire, before);
    assert.throws(() => owner.originals.validateRun({...owner, evidence: substituted, runDefinition, identity}));
    assert.equal(evidence.updateTargetRunOriginal.materialsWire, before);
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  } finally { await installed.close(); await stale.close(); }
});

test('installed update aliases preserve exact frozen names and physical bindings without provider work', async t => {
  const selected = adapter();
  const f = await fixture(t, {main: selected});
  const targets = [alias('crm.e\u0301'), alias('crm.é')];
  const installed = await loadInstalledEffect(await f.path(targets), f.options);
  t.after(() => installed.close());
  assert.deepEqual(installed.queryUpdateTargets, targets.map(value =>
    ({...value, installationBindingCid: cid('c'), installationOwnerCid: ownerCid})));
  assert.ok(Object.isFrozen(installed.queryUpdateTargets));
  assert.ok(installed.queryUpdateTargets.every(Object.isFrozen));
  assert.equal(installed.effectSelectors, selected.effectSelectors);
  assert.deepEqual(f.counts, {loads: 1, publishes: 0, closes: 0, prepares: 0, credentials: 0});
});

test('Effect publication strips Host aliases before the provider check and publish', async t => {
  const f = await fixture(t);
  const result = await publishInstalledEffectProfile(await f.path([alias()]), f.options);
  assert.deepEqual(result, {version});
  assert.deepEqual(f.counts, {loads: 0, publishes: 1, closes: 0, prepares: 0, credentials: 0});
});

// Independently computed using Python hashlib over length-prefixed UTF-8
// preimages. The provider identity part is exactly {version}; alias rows are
// the domain-separated exact tuple list, never configuration-normalized text.
const identities = [
  [undefined, 'sha256:4c086066165a17f5203ef7838814403e3b625b30a23a91db83ad828aa81884b4'],
  [[], 'sha256:4c086066165a17f5203ef7838814403e3b625b30a23a91db83ad828aa81884b4'],
  [[alias()], 'sha256:84ebbaee6dd3f820f12c91ba140d2b3f7ef3172ee26fa02be73ce8ef82381b0e'],
  [[alias('crm.é')], 'sha256:05f94b29aa216ae6fa1e26b44eb99f1efb2a20d5b3e2234587d1ecd4874e3a7f'],
  [[alias('crm.e\u0301')], 'sha256:382fb01603944fdf3303af9d06a100ca6b9c2b35563d6083c8721a28402474f5'],
];
test('Effect identity retains the historical absent and empty preimage and pins exact alias metadata', async t => {
  const f = await fixture(t);
  for (const [targets, expected] of identities) {
    assert.equal(await installedEffectIdentity(await f.path(targets), f.options), expected);
  }
  assert.equal(f.counts.loads, 0);
  assert.equal(f.counts.credentials, 0);
});

test('identity changes on target registration changes without changing provider identity', async t => {
  const f = await fixture(t);
  const left = await installedEffectIdentity(await f.path([alias()]), f.options);
  const right = await installedEffectIdentity(await f.path([alias('crm.Account', 'connector://crm/contact')]), f.options);
  assert.notEqual(left, right);
  assert.ok(f.checkedProfiles.every(profile => JSON.stringify(profile) === JSON.stringify({version})));
});

test('malformed Host alias metadata refuses before loading or publishing a provider', async t => {
  const f = await fixture(t);
  const malformed = [null, {}, [null], [alias('')], [alias('crm.Account', '')],
    [{...alias(), mappingRef: 'mapping:crm.account.0.v1'}], [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}],
    [alias('x'.repeat(1025))], [alias('crm.Account', 'x'.repeat(4097))],
    [alias('crm.\ud800')], Array(1025).fill(alias())];
  for (const targets of malformed) {
    const path = await f.path(targets);
    await assert.rejects(loadInstalledEffect(path, f.options), {code: 'InvalidInstalledUpdateTargets'});
    await assert.rejects(installedEffectIdentity(path, f.options), {code: 'InvalidInstalledUpdateTargets'});
    await assert.rejects(publishInstalledEffectProfile(path, f.options), {code: 'InvalidInstalledUpdateTargets'});
  }
  assert.equal(f.counts.loads, 0);
  assert.equal(f.counts.publishes, 0);
});

for (const fault of ['unknown-target', 'missing-binding', 'foreign-binding',
  'missing-registration', 'unregistered-candidate', 'foreign-manifest']) {
  test(`update alias ownership rejects ${fault} and releases the loaded installation`, async t => {
    const selected = adapter({count: fault === 'unregistered-candidate' ? 2 : 1});
    let target = alias();
    if (fault === 'unknown-target') target = alias('crm.Account', 'connector://crm/contact');
    if (fault === 'missing-binding') selected.connectorBindings = [];
    if (fault === 'foreign-binding') selected.connectorBindings = [{connectorId: 'other', bindingCid: cid('c')}];
    if (fault === 'missing-registration') selected.effectSelectors = Object.freeze([]);
    if (fault === 'unregistered-candidate') selected.effectSelectors = Object.freeze([selected.effectSelectors[0]]);
    if (fault === 'foreign-manifest') {
      const body = JSON.parse(selected.environmentWire);
      withFixtureConnector(body, 'connector://other/account');
      const mapping = body.mapping_contracts[0];
      mapping.connector_manifest_cid = contentCid(body.connector_manifest.connectors.find(value => value.connector_id === 'other'));
      const {mapping_contract_cid: ignored, ...preimage} = mapping;
      void ignored;
      mapping.mapping_contract_cid = contentCid(preimage);
      selected.environmentWire = seal(body);
      selected.effectSelectors = Object.freeze([Object.freeze({...selected.effectSelectors[0],
        mappingCid: mapping.mapping_contract_cid})]);
    }
    const f = await fixture(t, {main: selected});
    await assert.rejects(loadInstalledEffect(await f.path([target]), f.options), primary(
      fault === 'missing-registration' ? 'InvalidInstalledEffectSelectors' :
        fault === 'foreign-binding' ? 'InstalledCheckEnvironmentConflict' : 'InvalidInstalledUpdateTargets'));
    assert.deepEqual(f.counts, {loads: 1, publishes: 0, closes: 1, prepares: 0, credentials: 0});
  });
}

test('all registered candidate Mappings remain in the published environment', async t => {
  const selected = adapter({count: 2});
  const f = await fixture(t, {main: selected});
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  t.after(() => installed.close());
  assert.equal(installed.environmentWire, selected.environmentWire);
  assert.equal(installed.effectSelectors.length, 2);
  assert.deepEqual(installed.queryUpdateTargets, [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}]);
  const publication = sourceAliasPublication(moon, admitted(installed.environmentWire), [], [],
    {updateTargets: installed.queryUpdateTargets});
  assert.deepEqual(publication.updateTargets, installed.queryUpdateTargets);
});

test('plural installation keeps conflicting logical aliases instead of first-match selection', async t => {
  const f = await fixture(t, {left: adapter({connectorId: 'left'}), right: adapter({connectorId: 'right'})});
  const paths = await Promise.all(['left', 'right'].map(name =>
    f.path([alias('logical.Account', `connector://${name}/account`)], name)));
  const installed = await loadInstalledEffects(paths, f.options);
  t.after(() => installed.close());
  assert.deepEqual(installed.queryUpdateTargets, ['left', 'right'].map(name =>
    ({...alias('logical.Account', `connector://${name}/account`), installationBindingCid: cid('c'), installationOwnerCid: ownerCid})));
  assert.ok(Object.isFrozen(installed.queryUpdateTargets));
  const environment = admitted(installed.environmentWire);
  const publication = sourceAliasPublication(moon, environment, [], [], {updateTargets: installed.queryUpdateTargets});
  assert.equal(publication.updateTargets.length, 2, 'Ambiguity belongs to the common resolver');
  assert.equal(f.counts.prepares, 0);
});

test('composed publication rejects an unregistered candidate hidden in a sibling installation', async t => {
  const left = adapter({connectorId: 'left'}), right = adapter({connectorId: 'right'});
  const body = JSON.parse(right.environmentWire);
  withFixtureConnector(body, 'connector://left/account');
  const additional = JSON.parse(adapter({connectorId: 'left', count: 2}).environmentWire)
    .mapping_contracts.find(mapping => mapping.mapping_ref === 'mapping:left.account.1.v1');
  body.mapping_contracts.push(additional);
  right.environmentWire = seal(body);
  right.connectorBindings = Object.freeze([...right.connectorBindings,
    Object.freeze({connectorId: 'left', bindingCid: cid('c')})]);
  const f = await fixture(t, {left, right});
  const paths = [await f.path([alias('logical.Account', 'connector://left/account')], 'left'),
    await f.path(undefined, 'right')];
  await assert.rejects(loadInstalledEffects(paths, f.options), primary('InvalidInstalledUpdateTargets'));
  assert.deepEqual(f.counts, {loads: 2, publishes: 0, closes: 2, prepares: 0, credentials: 0});
});

for (const plural of [false, true]) {
  test(`final Source-composed environment revalidates ${plural ? 'plural' : 'singular'} Effect registration coverage`, async t => {
    const f = await fixture(t, {main: adapter(), other: adapter({connectorId: 'other'})});
    const paths = [await f.path([alias()])];
    if (plural) paths.push(await f.path(undefined, 'other'));
    const installed = await loadInstalledEffects(paths, f.options);
    t.after(() => installed.close());
    const revalidate = sourceWire => {
      const finalWire = composeInstalledCheckEnvironment(moon, baseWire,
        sourceWire, installed.environmentWire);
      // Real common admission precedes the Host's final ownership check.
      admitted(finalWire);
      return installedUpdateTargets(installed, installed.queryUpdateTargets, finalWire);
    };
    assert.deepEqual(revalidate(baseWire), installed.queryUpdateTargets);
    assert.deepEqual(revalidate(adapter({connectorId: 'unrelated'}).environmentWire),
      installed.queryUpdateTargets, 'Unrelated Source Mapping facts remain available');
    assert.throws(() => revalidate(adapter({count: 2}).environmentWire),
      {code: 'InvalidInstalledUpdateTargets'},
      'A Source-only same-target Mapping must not enter the complete candidate inventory');
    assert.equal(f.counts.prepares, 0);
    assert.equal(f.counts.credentials, 0);
  });
}

test('absent and empty update aliases do not require new metadata from legacy singular owners', async t => {
  const selected = adapter();
  delete selected.effectSelectors;
  delete selected.connectorBindings;
  const f = await fixture(t, {main: selected});
  for (const targets of [undefined, []]) {
    const installed = await loadInstalledEffect(await f.path(targets), f.options);
    assert.deepEqual(installed.queryUpdateTargets, []);
    assert.ok(Object.isFrozen(installed.queryUpdateTargets));
    await installed.close();
  }
});

test('publication owns update metadata and omits the empty root section', () => {
  const environment = admitted(adapter().environmentWire);
  const empty = sourceAliasPublication(moon, environment);
  assert.equal(Object.hasOwn(empty, 'updateTargets'), false);
  assert.deepEqual(sourceAliasPublication(moon, environment, [], [], {updateTargets: []}), empty);
  const targets = [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}];
  const selected = sourceAliasPublication(moon, environment, [], [], {updateTargets: targets});
  targets[0].name = 'other.Name'; targets.push({...targets[0]});
  assert.deepEqual(selected.updateTargets, [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}]);
  assert.ok(Object.isFrozen(selected.updateTargets));
  assert.ok(Object.isFrozen(selected.updateTargets[0]));
});

test('closed preparation decoder validates update metadata through the real common owner', () => {
  const environment = admitted(adapter().environmentWire);
  const publication = sourceAliasPublication(moon, environment, [], [],
    {updateTargets: [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}]});
  const preparation = installNodePublicSourcePreparation({moon, environment, publication});
  const prepared = preparation.prepare({document: 'SELECT 1 AS value', format: 'sql'});
  assert.equal(prepared.kind, 'effect_free');
  assert.notEqual(moon.clientProgramPreparationReady(prepared.outcome), undefined);
  for (const updateTargets of [null, {}, [{...alias()}],
    [{...publication.updateTargets[0], mappingRef: 'mapping:crm.account.0.v1'}],
    [{...publication.updateTargets[0], installationBindingCid: 'not-a-cid'}],
    [{...publication.updateTargets[0], installationOwnerCid: 'not-a-cid'}],
    [{...publication.updateTargets[0], name: 'bad..path'}]]) {
    assert.throws(() => installNodePublicSourcePreparation({moon, environment,
      publication: {...publication, updateTargets}}), {message: 'InvalidPublicSourcePublication'});
  }
  assert.throws(() => installNodePublicSourcePreparation({moon, environment,
    publication: {...publication, extra: true}}), {message: 'InvalidPublicSourcePublication'});
});

test('update metadata cannot bypass a missing or refusing common validator', () => {
  const environment = admitted(adapter().environmentWire);
  const publication = sourceAliasPublication(moon, environment, [], [],
    {updateTargets: [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}]});
  for (const validator of [undefined, () => false]) {
    assert.throws(() => installNodePublicSourcePreparation({
      moon: {...moon, clientProgramPublicSourceEnvironmentMatches: validator}, environment, publication}),
    {message: 'InvalidPublicSourcePublication'});
  }
});

test('public full and logical UPDATE preparation retain the same concrete selection', () => {
  const environment = admitted(adapter().environmentWire);
  const publication = sourceAliasPublication(moon, environment, [], [],
    {updateTargets: [{...alias(), installationBindingCid: cid('c'), installationOwnerCid: ownerCid}]});
  const preparation = installNodePublicSourcePreparation({moon, environment, publication, allowEffects: true});
  const prefix = "SELECT 'id' AS id, 'Ada' AS name |> RESULT updates |> EFFECT UPDATE ";
  const suffix = ' FROM RESULT updates ID id SET (Name = name)';
  const prepare = target => {
    const outcome = preparation.prepare({document: prefix + target + suffix, format: 'aql-text'});
    assert.equal(outcome.kind, 'effectful');
    const prepared = moon.clientProgramEffectPreparationReady(outcome.outcome);
    assert.notEqual(prepared, undefined);
    const selection = moon.clientProgramEffectTargetSelections(prepared);
    assert.equal(typeof selection, 'string');
    assert.equal(JSON.parse(selection)[0].installation_owner_cid, ownerCid);
    return selection;
  };
  const explicit = prepare("TARGET 'connector://crm/account' MAPPING `mapping:crm.account.0.v1`");
  for (const target of ['crm.Account', 'crm.Account MAPPING `mapping:crm.account.0.v1`']) {
    assert.equal(prepare(target), explicit);
  }
  const withoutPublication = installNodePublicSourcePreparation({moon, environment, allowEffects: true});
  const unbound = withoutPublication.prepare({document: prefix + 'crm.Account' + suffix, format: 'aql-text'});
  assert.equal(unbound.kind, 'effect_free');
  assert.equal(moon.clientProgramPreparationReady(unbound.outcome), undefined);
  assert.equal(moon.clientProgramPreparationIssueCode(unbound.outcome), 'source_rejected');
});

test('owner identity is independent of alias names and changes with runtime, revision and generation', async t => {
  const f = await fixture(t, {main: adapter(), runtime: {...adapter(), ownerRuntime: cid('f')},
    revision: {...adapter(), ownerRevision: 'update_target_fixture/changed'},
    generation: {...adapter(), ownerGeneration: cid('f')}});
  const first = await loadInstalledEffect(await f.path([alias()]), f.options);
  t.after(() => first.close());
  assert.deepEqual(installedRowEffectOwnerBinding(first),
    {cid: ownerCid, wire: canonicalJson(ownerFacts())});
  const renamed = await loadInstalledEffect(await f.path([alias('renamed.Account')]), f.options);
  t.after(() => renamed.close());
  assert.equal(renamed.queryUpdateTargets[0].installationOwnerCid, ownerCid);
  for (const name of ['runtime', 'revision', 'generation']) {
    const replacement = await loadInstalledEffect(await f.path([alias()], name), f.options);
    t.after(() => replacement.close());
    assert.notEqual(replacement.queryUpdateTargets[0].installationOwnerCid, ownerCid);
    assert.equal(replacement.queryUpdateTargets[0].installationBindingCid, cid('c'));
  }
});

test('a copied installation cannot establish a new logical update owner', async t => {
  const f = await fixture(t);
  const installed = await loadInstalledEffect(await f.path([alias()]), f.options);
  t.after(() => installed.close());
  assert.equal(installedRowEffectOwnerBinding({...installed}), undefined);
  assert.throws(() => installedUpdateTargets({...installed}, [alias()]),
    {code: 'InvalidInstalledUpdateTargets'});
});

test('same-target candidate inventory cannot silently choose between original installed owners', async t => {
  const left = adapter();
  const right = {...adapter({count: 2}), ownerGeneration: cid('f')};
  const body = JSON.parse(right.environmentWire);
  body.mapping_contracts = body.mapping_contracts.filter(mapping =>
    mapping.mapping_ref === 'mapping:crm.account.1.v1');
  right.environmentWire = seal(body);
  right.effectSelectors = Object.freeze([right.effectSelectors[1]]);
  const f = await fixture(t, {left, right});
  const paths = [await f.path([alias()], 'left'), await f.path(undefined, 'right')];
  await assert.rejects(loadInstalledEffects(paths, f.options), primary('InvalidInstalledUpdateTargets'));
  assert.equal(f.counts.prepares, 0);
  assert.equal(f.counts.credentials, 0);
  assert.equal(f.counts.closes, 2);
});
