import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createAuthorizationGate, requireAuthorizedDispatch, assertAuthorizationAccountCurrent, authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {localFileStoreDeclaration} from '../connectors/local/host/local-file-store-declaration.mjs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createInstalledRowEffect, composeInstalledRowEffectOwners,
  retainInstalledRowEffectAdapter} from './installed-row-effect.mjs';
import {installedEffectFor} from './installed-effect-inventory.mjs';

// Admission/provenance tests only. Core issuance and physical dispatch are not
// replaced with successful doubles; accepted recovery stops before the Ledger.
const cid = digit => `sha256:${digit.repeat(64)}`;
const profile = Object.freeze({
  continuation: 'actql-installed-row-effect-continuation/0.1',
  continuationBinding: 'binding_cid',
  dispatch: 'actql-installed-row-effect-dispatch/0.1',
  recovery: 'actql-installed-row-effect-recovery/0.1',
  source: 'actql-installed-row-effect-source/0.1',
  targetCheck: 'actql-installed-row-effect-check/0.1',
  unit: 'actql-installed-row-effect-unit/0.1',
});
const program = {stages: [{inputs: {}, steps: [{values: {}, as: 'rows'}]}]};
async function fixture(t, variants = [{}, {}]) {
  const root = await mkdtemp(join(tmpdir(), 'actql-row-routing-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const calls = [];
  const unused = action => () => { calls.push(action); assert.fail(action); };
  const moon = {strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind',
    clientProgramEffectCompilationPlanWire: compilation =>
    JSON.stringify({execution_material: {program: compilation}})};
  const effects = [], descriptors = [], installations = [];
  for (const [index, variant] of variants.entries()) {
    const name = `owner-${index}`;
    const identity = cid(String(index + 1));
    const mappingRef = `mapping:${name}/create.v1`;
    const target = `connector://${name}/records`;
    const descriptor = {effectId: `effect-${index}`, kind: 'create', target,
      mappingRef, mappingCid: identity};
    const options = {moon, mappings: [{resource: 'records', mappingRef,
      mappingCid: identity, body: JSON.stringify({mapping_contract_cid: identity,
        target_ref: target, minimum_approval: 'required', permission_rules: [
          {effect_kind: 'create', permissions: ['write']}], primary_identity: ['id']})}],
    environmentWire: '{}', connectorId: name, connectorRegistration: name,
    connectorRevision: `${name}/0.1`, connection: name,
    site: {issueEffectGrant: unused('grant'), issueReadGrant: unused('read grant'),
      close() { calls.push(`close:${name}`); }},
    authorization: {authorize: unused('authorize')}, runtimeBundleCid: cid('a'),
    bindingCid: identity, ledgerRoot: root,
    driver: {kinds: ['create'], prepareRequest: unused('request'),
      requestFacts: unused('facts'), writeOperation: unused('operation'),
      send: unused('send'), project: unused('project'), footprint: unused('footprint'),
      ...variant.driverExtra},
    ...variant};
    effects.push(await createInstalledRowEffect(options));
    descriptors.push(descriptor);
    installations.push({connector_registration: options.connectorRegistration,
      connector_revision: options.connectorRevision, runtime_bundle_cid: options.runtimeBundleCid,
      binding_cid: options.bindingCid, connection: options.connection,
      profile, continuation_binding: options.bindingCid});
  }
  return {moon, effects, descriptors, installations, calls, root};
}

test('composed route retains real owner ports without acquiring a provider', async t => {
  const f = await fixture(t);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  const inventory = {effects: f.effects, environmentWire: '{}'};
  installedEffectFor(inventory, f.descriptors).assertPrepared({moon: f.moon, compilation: program});
  for (const fault of [{mappingCid: cid('f')}, {target: 'foreign'},
    {capabilityCid: cid('f')}, {kind: 'update'}]) {
    assert.throws(() => installedEffectFor(inventory,
      [f.descriptors[0], {...f.descriptors[1], ...fault}]),
    {code: 'InstalledEffectProgramMismatch'});
  }
  assert.throws(() => installedEffectFor({effects: [...f.effects, f.effects[0]]}, f.descriptors),
    {code: 'InstalledEffectProgramMismatch'});
  assert.ok(Object.isFrozen(routed));
  assert.equal(routed.close, undefined, 'installation cleanup stays with original inventory');
  routed.assertPrepared({moon: f.moon, compilation: program});
  assert.deepEqual(f.calls, []);
  await f.effects[0].close();
  assert.deepEqual(f.calls, ['close:owner-0']);
  await f.effects[1].close();
  assert.deepEqual(f.calls, ['close:owner-0', 'close:owner-1']);
});

test('copied adapters cannot supply a routing port; exact loader projection retains it', async t => {
  const f = await fixture(t);
  const copy = Object.freeze({...f.effects[0]});
  assert.throws(() => composeInstalledRowEffectOwners([copy, f.effects[1]], f.descriptors, '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.throws(() => retainInstalledRowEffectAdapter(f.effects[0],
    {...copy, prepareRecovered() {}}), {code: 'ForeignInstalledEffectOccurrence'});
  assert.equal(retainInstalledRowEffectAdapter(f.effects[0], copy), copy);
  composeInstalledRowEffectOwners([copy, f.effects[1]], f.descriptors, '{}')
    .assertPrepared({moon: f.moon, compilation: program});
  assert.deepEqual(f.calls, []);
});

test('unsupported mixed kinds and foreign ports refuse before provider work', async t => {
  const f = await fixture(t);
  for (const kind of ['store', 'update', 'upsert', 'command']) {
    assert.throws(() => composeInstalledRowEffectOwners(f.effects,
      [{...f.descriptors[0], kind}, f.descriptors[1]], '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  }
  assert.throws(() => composeInstalledRowEffectOwners([{}, f.effects[1]], f.descriptors, '{}'),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(f.calls, []);
});

test('composed profile refuses imported, multi-stage and non-VALUES computation before dispatch', async t => {
  const f = await fixture(t);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  for (const compilation of [undefined, {stages: []}, {stages: [program.stages[0], program.stages[0]]},
    {stages: [{inputs: {source: {}}, steps: program.stages[0].steps}]},
    {stages: [{inputs: {}, steps: [{infer: {}}]}]},
    {stages: [{inputs: {}, steps: [{filter: {}}]}]}]) {
    assert.throws(() => routed.assertPrepared({moon: f.moon, compilation}),
      {code: 'InstalledEffectSetOwnerMismatch'});
  }
  assert.throws(() => routed.assertPrepared({moon: {}, compilation: program}),
    {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(f.calls, []);
});

test('composed stage refuses unequal original runtime, Ledger location and limits', async t => {
  for (const variant of [{moon: {strategyRemoteManagedOutputEvidenceKind: () => 'test-unused-kind'}},
    {ledgerRoot: join(tmpdir(), 'foreign-ledger')},
    {limits: {maxRows: 201}}]) {
    const f = await fixture(t, [{}, variant]);
    assert.throws(() => composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}'),
      {code: 'InstalledEffectSetOwnerMismatch'});
    assert.deepEqual(f.calls, []);
  }
});

test('recovery validates each original occurrence and installation before opening the Ledger', async t => {
  const limits = {key: {maxBytes: 4096, maxNodes: 64, maxDepth: 8}};
  const f = await fixture(t, [{limits}, {limits}]);
  const routed = composeInstalledRowEffectOwners(f.effects, f.descriptors, '{}');
  limits.key.maxBytes = 1;
  const invocation = cid('c');
  const body = {invocation_cid: invocation, effects: f.descriptors.map(d => ({
    effect_id: d.effectId, effect_kind: d.kind, target: d.target,
    mapping: d.mappingRef, resolved_mapping_contract_cid: d.mappingCid}))};
  const provider = {version: 'actql-installed-row-effect-routing/0.1',
    program_id: 'program', stage_id: 'stage', members: f.descriptors.map((d, i) => ({
      effect_id: d.effectId, mapping_cid: d.mappingCid,
      dispatch_request_cid: `sha256:${createHash('sha256').update(JSON.stringify({
        effect_id: d.effectId, run_invocation_cid: invocation,
        version: 'actql-installed-row-effect-dispatch/0.1'})).digest('hex')}`,
      installation: f.installations[i]}))};
  const stopped = new Error('StopBeforeLedger');
  const keyCalls = [];
  f.moon.strategyEffectRecoveredPreviewKeys = (...args) => { keyCalls.push(args); throw stopped; };
  const facts = {moon: f.moon, recovered: {computation: {preview: {}}},
    continuation: provider, control: {effectComputationPreviewWire: () => JSON.stringify(body),
      effectComputationPreviewLedgerIdentity: () => ({})}};
  assert.throws(() => routed.prepareRecovered(facts), error => error === stopped);
  assert.equal(keyCalls[0][5], 4096, 'original composed limits cannot change with bootstrap objects');
  for (const field of ['connector_registration', 'connector_revision', 'runtime_bundle_cid',
    'binding_cid', 'connection', 'continuation_binding']) {
    const changed = structuredClone(provider);
    changed.members[1].installation[field] = 'foreign';
    assert.throws(() => routed.prepareRecovered({...facts, continuation: changed}),
      {code: 'InstalledRowEffectInstallationChanged'});
  }
  const swapped = structuredClone(provider);
  swapped.members.reverse();
  assert.throws(() => routed.prepareRecovered({...facts, continuation: swapped}),
    {code: 'InstalledRowEffectInstallationChanged'});
  const changedTarget = structuredClone(body);
  changedTarget.effects[1].target = body.effects[0].target;
  assert.throws(() => routed.prepareRecovered({...facts, control: {
    ...facts.control, effectComputationPreviewWire: () => JSON.stringify(changedTarget)}}),
  {code: 'InstalledEffectProgramMismatch'});
  assert.deepEqual(f.calls, []);
});


test('retained-request composition requires an explicit member-scoped recovery port', async t => {
  const retained = {recoverRequests() { assert.fail('recovery before admission'); },
    recoveryEntry() { assert.fail('capture before admission'); },
    requestCid() { assert.fail('request before admission'); }};
  const unsupported = await fixture(t, [{driverExtra: retained}, {}]);
  assert.throws(() => composeInstalledRowEffectOwners(unsupported.effects,
    unsupported.descriptors, '{}'), {code: 'InstalledEffectSetOwnerMismatch'});
  assert.deepEqual(unsupported.calls, []);
  const scoped = await fixture(t, [{driverExtra: {...retained,
    recoverMemberRequests() { assert.fail('recovery before capture'); }}}, {}]);
  const stage = composeInstalledRowEffectOwners(scoped.effects, scoped.descriptors, '{}');
  stage.assertPrepared({moon: scoped.moon, compilation: program});
  assert.deepEqual(scoped.calls, []);
});

test('member-scoped recovery cannot be installed without the existing retained recovery protocol', async t => {
  await assert.rejects(fixture(t, [{driverExtra: {
    recoverMemberRequests() { assert.fail('uninstalled recovery'); }}}, {}]),
  {code: 'InvalidInstalledRowEffectDriver'});
});

test('schema-valid Command without approval minimum reaches the actual installed constructor', async t => {
  // Independent closed Command DATA; Account/Site and Core are explicit ports.
  // No grant, Ledger, request, Preview or physical operation runs in this case.
  const body = {schema: 'actql.command_contract/0.1', command_id: 'command:owner-0.send.v1',
    connector_id: 'owner-0', version: 'test/0.1',
    target: {resource_kind: 'mailbox', cardinality: 'single', binding: {kind: 'installation'}},
    input_schema: {id: 'owner-0.send.input', version: 'test/0.1', cid: cid('b')},
    input_contract: {additional_properties: false, fields: {
      body: {type: 'string', nullable: false}, subject: {type: 'string', nullable: false},
      to: {type: 'array', nullable: false, items: {type: 'string', nullable: false}}},
    required_fields: ['body', 'subject', 'to']},
    output_schema: {id: 'owner-0.send.output', version: 'test/0.1', cid: cid('c')},
    permissions: ['https://www.googleapis.com/auth/gmail.send'], preview: {strength: 'exact'},
    outcome: 'synchronous', idempotency: {support: 'unsupported'},
    reversibility: 'irreversible', atomicity: 'single_target'};
  assert.equal(Object.hasOwn(body, 'minimum_approval'), false);
  const commandCid = `sha256:${createHash('sha256').update(canonicalJson(body)).digest('hex')}`;
  const unused = () => assert.fail('No provider preparation or recovery in constructor admission');
  const f = await fixture(t, [{mappings: [], commands: [{resource: 'messages',
    commandRef: body.command_id, commandCid, body: JSON.stringify({...body, contract_cid: commandCid})}],
  driverExtra: {kinds: ['command'], recheckRequests: unused, recoveryEntry: unused,
    recoverRequests: unused, requestCid: unused}}]);
  assert.equal(f.effects.length, 1);
  assert.ok(Object.isFrozen(f.effects[0]));
  assert.deepEqual(f.calls, []);
  await f.effects[0].close();
  assert.deepEqual(f.calls, ['close:owner-0']);
});

async function commandApprovalProductionPorts() {
  const source = await readFile(new URL('./installed-row-effect.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const stage = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'createRowEffectStage');
  const variable = (body, name) => body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations).find(node => node.id.name === name).init;
  const expression = name => {const node = variable(stage.body.body, name); return source.slice(node.start, node.end);};
  const approval = variable(ast.body, 'approvalOf');
  const approvalOf = new Function(`return (${source.slice(approval.start, approval.end)});`)();
  return {source, stage, expression, approvalOf};
}

test('Command dispatch adds no contract floor to the original Account allow or immediate permit', async () => {
  // Exact production extra-floor function. Decisions are explicit DATA here;
  // the separate original authorization gate owns interpretation and custody.
  const f = await commandApprovalProductionPorts();
  const floor = new Function('approvalOf', 'text', 'refusedEffectPreparation',
    `return (${f.expression('requireApproval')});`)(f.approvalOf,
    value => typeof value === 'string' && value.length > 0, error => error);
  const command = {kind: 'command', command: {approval: 'required'}};
  for (const basis of ['account_allow', 'permitted_by_host']) {
    assert.doesNotThrow(() => floor(command, {action: 'dispatch', basis}));
  }
  const mapping = {kind: 'update', mapping: {approval: 'required'}};
  assert.throws(() => floor(mapping, {action: 'dispatch', basis: 'account_allow'}),
    {code: 'InstalledRowEffectApprovalRequired'});
  assert.doesNotThrow(() => floor(mapping, {action: 'dispatch', basis: 'resumed',
    checkpointCid: cid('a'), resolutionCid: cid('b')}));
});

test('Command Preview omits contract approval DATA while Mapping carriage stays exact', async () => {
  // Execute the complete original builder with explicit descriptor, identity,
  // source-binding and canonicalization ports. This does not issue Core facts.
  const f = await commandApprovalProductionPorts();
  const node = f.stage.body.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'authorPreview');
  const moon = {
    clientProgramEffectRequestAuthority: () => cid('a'), clientProgramEffectDefinitionCid: () => cid('b'),
    strategyRunEvidenceSeal: (_kind, wire) => JSON.parse(wire), strategyRunEvidenceJson: value => JSON.stringify(value),
    clientProgramEffectMemberDescriptor: (_prepared, _stage, effect) =>
      [0, effect, effect === 'command' ? 'command' : 'update', 'target', 'contract:fixture', cid('c'), 'rows', 'halt'],
    strategyPublicationContractIdentity: () => cid('d'), clientProgramEffectPlanCid: () => undefined,
    clientProgramEffectSemanticsCid: () => cid('e'), clientProgramEffectEnvironmentCid: () => cid('f'),
    clientProgramCanonicalEffectPreviewDraft: wire => wire,
    clientProgramAuthorEffectPreview: wire => [wire, []],
  };
  const control = {effectSourceArtifactPreviewBinding: () => [null, cid('1')],
    issueSourceFreeLocalEffectIdentity: () => ({identity: cid('2')}),
    checkSourceFreeLocalEffectPreviewIdentities() {}};
  const build = new Function('limits', 'moon', 'checked', 'runtimeField', 'approvalOf',
    'permissionsOf', 'pendingCid', 'fail', `return (${f.source.slice(node.start, node.end)});`)(
    {preview: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32}, maxRows: 10, planWork: 100,
      maxFields: 10, key: {maxBytes: 4096, maxNodes: 64, maxDepth: 8}}, moon, value => value,
    (value, index) => value[index], f.approvalOf, () => ['scope'], cid('0'), () => assert.fail('Unexpected builder refusal'));
  const members = [{kind: 'command', effectId: 'command', stageIndex: 0, command: {approval: 'required'}},
    {kind: 'update', effectId: 'mapping', stageIndex: 0, mapping: {approval: 'required'}}];
  const result = build({control, prepared: {}, inputs: {}, context: {}, requestScope: {}, members,
    rowsOf: [[], []], capabilities: [{identity: cid('3')}, {identity: cid('4')}], footprints: [{}, {}],
    payloads: members.map(() => ({summary: {artifact: {}}, localResultArtifact: {identity: cid('5')}}))});
  const effects = JSON.parse(result.wire).effects;
  assert.equal(Object.hasOwn(effects[0], 'approval'), false);
  assert.equal(effects[1].approval, 'required');
});

function commandAccountGate(outcome, answer = 'permit') {
  // Real gate and resumed-dispatch machinery; Core interpretation, Host answer
  // authentication and committed Journal rows are explicit finite ports. No
  // fixture imports a release Common, creates a key, DB, claim or physical IO.
  const configuration = {state: 'admitted', account_id: 'account', configuration_cid: cid('a'),
    entry_id: 'effect', outcome};
  let wire = JSON.stringify(configuration), persisted, resolved = false, entered = 0, hostCalls = 0;
  const claim = Object.freeze({intentId: 'intent', claimant: 'owner', generation: 1});
  const refuse = code => {throw Object.assign(new Error(code), {code});};
  const admission = () => ({configurationCid: configuration.configuration_cid,
    requestedClaims: persisted.requestedClaims, observedClaims: ['effect_scope_approved'],
    kind: 'effect_set', requiredArtifactCid: persisted.body.required_artifact.artifact_cid,
    decisionSubjectCid: persisted.decisionSubjectCid, authority: 'host',
    checkpointCid: cid('b'), resolutionCid: cid('c'), ...claim});
  const journal = {
    persistCheckpoint(value) {persisted = value;return {checkpointCid: cid('b'), checkpointId: 'checkpoint', runId: 'run'};},
    submitResolution() {assert.fail('Only the explicit committed-row port resolves this DATA fixture');},
    admitResume(held, {checkpointCid} = {}) {
      if (!resolved) refuse('ResolutionNotCommitted');
      if (held.intentId !== claim.intentId || held.claimant !== claim.claimant || held.generation !== claim.generation ||
          checkpointCid !== undefined && checkpointCid !== cid('b')) refuse('ForeignResumeClaim');
      return admission();
    },
    enterResumedDispatch(held) {journal.admitResume(held);entered++;return admission();},
  };
  const runtime = {
    executionAuthorizationAdmit: JSON.parse, executionAuthorizationMissing: () => ({state: 'missing'}),
    executionAuthorizationAccountJson: JSON.stringify,
    executionAuthorizationEvaluate: (account, principal, connection, resource, operation) =>
      ({...account, principal, connection, resource, operation}),
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction: evaluation => evaluation.outcome === 'allow'
      ? {action: 'dispatch', basis: 'account_allow'}
      : {action: 'deny', basis: 'account', reason: evaluation.outcome === 'no_match' ? 'no_match' : 'explicit'},
    executionAuthorizationPrepare: (evaluation, configurationCid, boundary, subjectCid, contextCid, authorities, claims) =>
      ({ok: true, subject: {account_id: evaluation.account_id, configuration_cid: configurationCid,
        entry_id: evaluation.entry_id, principal: evaluation.principal, connection: evaluation.connection,
        resource: evaluation.resource, operation: evaluation.operation, boundary, subject_cid: subjectCid, context_cid: contextCid},
      answering_authorities: authorities, required_claims: claims}),
    executionAuthorizationRequestJson: JSON.stringify,
    executionAuthorizationAnswer: (_request, kind, _subject, authority, claims) => kind === 'permit'
      ? {action: 'dispatch', authority, claims} : kind === 'defer'
        ? {action: 'checkpoint'} : {action: 'deny', reason: 'rejected'},
    executionAuthorizationDecisionJson: JSON.stringify,
  };
  const gate = createAuthorizationGate({runtime, configuration: wire,
    readConfiguration: () => wire, context: {principal: 'owner', contextCid: cid('d')},
    answeringAuthorities: ['host'], requiredClaims: ['effect_scope_approved'],
    decide(view) {hostCalls++;return {decision: answer, subject: view.subject, authority: 'host', claims: view.requiredClaims};},
    deferral: {journal, authorities: ['host'], binding: {fixture: true}, describe: () => ({body: {}})}});
  return {gate, scope: {connection: 'connection', resource: 'messages', operation: 'effect'},
    subjectCid: cid('e'), resumption: {claim: {...claim, checkpointCid: cid('b')}},
    resolve() {resolved = true;}, change() {wire = JSON.stringify({...configuration, configuration_cid: cid('f')});},
    counts: () => ({hostCalls, entered, persisted: persisted === undefined ? 0 : 1})};
}

test('Command uses the same original Account gate for allow deny no-match immediate permit reject and defer', async () => {
  const f = await commandApprovalProductionPorts();
  const floor = new Function('approvalOf', 'text', 'refusedEffectPreparation',
    `return (${f.expression('requireApproval')});`)(f.approvalOf,
    value => typeof value === 'string' && value.length > 0, error => error);
  const member = {kind: 'command', command: {}};
  for (const [outcome, answer, allowed] of [['allow', 'permit', true], ['deny', 'permit', false],
    ['no_match', 'permit', false], ['delegate', 'permit', true], ['delegate', 'reject', false], ['delegate', 'defer', false]]) {
    const x = commandAccountGate(outcome, answer);
    try {
      const enter = async () => {
        const decision = await requireAuthorizedDispatch(x.gate, 'effect_commit', x.scope, {subjectCid: x.subjectCid});
        floor(member, decision);
        assertAuthorizationAccountCurrent(decision);
        assert.ok(authorizationDispatchFacts(decision));
        assert.equal(decision.checkpointCid, undefined);
        assert.equal(decision.resolutionCid, undefined);
        return decision;
      };
      if (allowed) await enter();
      else await assert.rejects(enter(), error => ['ExecutionAuthorizationDenied', 'ExecutionAuthorizationWaiting'].includes(error.code));
      assert.equal(x.counts().hostCalls, outcome === 'delegate' ? 1 : 0);
      assert.equal(x.counts().persisted, answer === 'defer' ? 1 : 0);
      assert.equal(x.counts().entered, 0);
    } finally {assert.equal(x.gate.close(), true);}
  }
});

test('Command defer still requires the same committed Set Resolution original claim and current Account', async () => {
  const f = await commandApprovalProductionPorts();
  const floor = new Function('approvalOf', 'text', 'refusedEffectPreparation',
    `return (${f.expression('requireApproval')});`)(f.approvalOf,
    value => typeof value === 'string' && value.length > 0, error => error);
  const x = commandAccountGate('delegate', 'defer');
  try {
    const waiting = await x.gate.authorize('effect_commit', x.scope, {subjectCid: x.subjectCid});
    assert.equal(waiting.action, 'waiting');
    const resume = changes => x.gate.resume('effect_commit', x.scope,
      {subjectCid: x.subjectCid, resumption: x.resumption, ...changes});
    assert.equal((await resume()).detail, 'ResolutionNotCommitted');
    x.resolve();
    assert.equal((await resume({subjectCid: cid('1')})).detail, 'ResolutionSubjectMismatch');
    assert.equal((await resume({resumption: {claim: {...x.resumption.claim, generation: 2}}})).detail, 'ForeignResumeClaim');
    const original = await resume();
    assert.equal(original.action, 'dispatch');assert.equal(original.basis, 'resumed');
    assert.equal(original.checkpointCid, cid('b'));assert.equal(original.resolutionCid, cid('c'));
    floor({kind: 'command', command: {}}, original);
    assertAuthorizationAccountCurrent(original);
    assert.throws(() => assertAuthorizationAccountCurrent({...original}), {code: 'ForeignAuthorizationDecision'});
    original.admission.enter();
    assert.equal(x.counts().entered, 1);
    assert.throws(() => original.admission.enter(), {code: 'ResumeAdmissionConsumed'});
    x.change();
    assert.throws(() => assertAuthorizationAccountCurrent(original), {code: 'AuthorizationCurrentAccountChanged'});
    assert.equal(x.counts().entered, 1);
  } finally {assert.equal(x.gate.close(), true);}
});

test('Command constructor refuses an illegal minimum or foreign whole-body identity before any grant', async t => {
  const vector = JSON.parse(await readFile(new URL('../../spec/fixtures/gcs-command-approval-carriage.json', import.meta.url)));
  const base = JSON.parse(vector.current.environmentWire).command_contracts[0];
  const unused = () => assert.fail('No request or grant during constructor refusal');
  for (const mutate of [body => {body.minimum_approval = 'none';}, body => {body.minimum_approval = 'required';},
    body => {body.connector_id = 'foreign';}]) {
    const body = structuredClone(base);delete body.contract_cid;mutate(body);
    const commandCid = `sha256:${createHash('sha256').update(canonicalJson(body)).digest('hex')}`;
    await assert.rejects(fixture(t, [{connectorId: 'exports', mappings: [], commands: [{resource: 'messages',
      commandRef: body.command_id, commandCid, body: JSON.stringify({...body, contract_cid: commandCid})}],
    driverExtra: {kinds: ['command'], recheckRequests: unused, recoveryEntry: unused,
      recoverRequests: unused, requestCid: unused}}]), {code: 'InvalidInstalledRowEffectCommand'});
  }
});

test('Local STORE declaration keeps its separate Mapping floor while its Command carries none', () => {
  // Actual pure declaration assembler, explicit original declaration DATA.
  // rootPath is identity DATA only: no filesystem, Account or grant is opened.
  const hash = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
  const catalog = {schema: 'actql.connector_catalog/0.1', connector_id: 'local', connector_version: 'local/0.1',
    source_views: [], commands: [], contracts: []};
  const manifest = {connector: 'local', connector_id: 'local', connector_version: 'local/0.1'};
  const declared = {connector_id: 'local', connector_registration: 'local', connector_version: 'local/0.1',
    catalog: canonicalJson({...catalog, catalog_cid: hash(catalog)}), catalog_cid: hash(catalog),
    manifest_entry: canonicalJson(manifest), manifest_entry_cid: hash(manifest), contracts: []};
  const selected = localFileStoreDeclaration(canonicalJson(declared), {connectorId: 'local',
    rootPath: '/fixture/local-root', maxBytes: 65536});
  const command = JSON.parse(selected.commandWire), mapping = JSON.parse(selected.mappingWire);
  assert.equal(Object.hasOwn(command, 'minimum_approval'), false);
  assert.equal(mapping.minimum_approval, 'required');
  assert.equal(mapping.store_command.command_contract_cid, command.contract_cid);
  assert.equal(mapping.store_command.catalog_cid, JSON.parse(selected.declarationWire).catalog_cid);
});

test('current GCS receiver admits its exact Command while the frozen predecessor is refused before any grant', async t => {
  const current = JSON.parse(await readFile(new URL('../../spec/fixtures/gcs-command-approval-carriage.json', import.meta.url)));
  const historicalBytes = await readFile(new URL('../../' + current.predecessor.path, import.meta.url));
  assert.equal(createHash('sha256').update(historicalBytes).digest('hex'), current.predecessor.sha256);
  const historical = JSON.parse(historicalBytes);
  const oldCommand = JSON.parse(historical.wire).command_contracts[0];
  assert.equal(oldCommand.contract_cid, current.predecessor.commandCid);
  assert.equal(oldCommand.minimum_approval, 'required');
  const body = JSON.parse(current.current.environmentWire).command_contracts[0];
  assert.equal(body.contract_cid, current.current.commandCid);
  assert.equal(Object.hasOwn(body, 'minimum_approval'), false);
  const unchanged = structuredClone(oldCommand);delete unchanged.minimum_approval;delete unchanged.contract_cid;
  const {contract_cid, ...preimage} = body;
  assert.deepEqual(preimage, unchanged);
  assert.equal(`sha256:${createHash('sha256').update(canonicalJson(preimage)).digest('hex')}`, contract_cid);
  const source = await readFile(new URL('../../src/connectors/gcs/contract_acceptance/upload_test.mbt', import.meta.url), 'utf8');
  assert.ok(source.includes('#|' + current.current.environmentWire), 'actual receiver compares the same complete independent wire');
  const unused = () => assert.fail('No provider request, permission or grant at constructor admission');
  const options = selected => ({connectorId: 'exports', mappings: [], commands: [{resource: 'objects',
    commandRef: selected.command_id, commandCid: selected.contract_cid, body: JSON.stringify(selected)}],
  driverExtra: {kinds: ['command'], recheckRequests: unused, recoveryEntry: unused,
    recoverRequests: unused, requestCid: unused}});
  await assert.rejects(fixture(t, [options(oldCommand)]), {code: 'InvalidInstalledRowEffectCommand'});
  const admitted = await fixture(t, [options(body)]);
  assert.deepEqual(admitted.calls, []);
  await admitted.effects[0].close();
  assert.deepEqual(admitted.calls, ['close:owner-0']);
});

test('actual Salesforce loader projection retains the original registered Plan port without provider work', async t => {
  const f=await fixture(t),source=await readFile(new URL('../connectors/salesforce/host/installed-salesforce-effect.mjs',import.meta.url),'utf8');
  const fn=parse(source,{ecmaVersion:'latest',sourceType:'module'}).body.find(node=>
    node.type==='FunctionDeclaration'&&node.id.name==='installedSalesforceEffect');
  assert(fn);
  const statement=fn.body.body.find(node=>node.type==='ReturnStatement');assert(statement);
  const project=Function('rowEffect','installed','site','connectorId','accountConfiguration',
    'installedSalesforceSiteBinding','targetReadInventory','retainInstalledRowEffectAdapter',source.slice(statement.start,statement.end));
  const original=f.effects[0],selected=f.descriptors[0],site={context:{},connectorRegistration:'owner-0',
    connectorRevision:'owner-0/0.1',connection:'owner-0',close(){assert.fail('No provider closure in projection');}};
  const installed={environment:{wire:original.environmentWire},generationCid:cid('d'),mappings:[{
    write:{resource:'records',kind:'create'},body:JSON.stringify({target_ref:selected.target}),
    mappingRef:selected.mappingRef,mappingCid:selected.mappingCid}]};
  const projection=project(original,installed,site,'owner-0','original-account',()=>({bindingCid:cid('1')}),
    ()=>assert.fail('No target read in projection'),retainInstalledRowEffectAdapter);
  assert.equal(projection.prepareManagedPlan,original.prepareManagedPlan);
  composeInstalledRowEffectOwners([projection,f.effects[1]],f.descriptors,'{}')
    .assertPrepared({moon:f.moon,compilation:program});
  assert.deepEqual(f.calls,[]);
});
