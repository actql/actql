import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse as yaml} from 'yaml';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog} from './actions.mjs';
import {hash, actionInputs, compareInputs, sharedFiles, mutationSnapshotExtras} from './inputs.mjs';
import {canonicalReceipt, sealReceipt, mutationIds} from './receipts.mjs';
import {checkApplications} from './applications.mjs';
import {checkPlan} from './check.mjs';
import {checkCertificate} from './final.mjs';
import {acquisitionPlan, verifyAcquisition} from './acquisition.mjs';

test('final certificate binds the actual Lean input, output, catalog and original receipt digests', () => {
  const context = {candidateRevision: 'a'.repeat(40), runId: 1, runAttempt: 2};
  const required = [{action: 'session-js', candidate: context.candidateRevision, kind: 'tested-refinement', target: 'js',
    scope: 'b'.repeat(64), premises: 'c'.repeat(64), inputs: 'd'.repeat(64), minimumUnits: 1}];
  const applications = [{action: 'session-js', origin: context.candidateRevision, kind: 'tested-refinement', target: 'js',
    scope: 'b'.repeat(64), premises: 'c'.repeat(64), inputs: 'd'.repeat(64), units: 7,
    authenticated: true, successful: true, reused: false, closed: false, mainOrigin: false}];
  const catalog = readCatalog(), receiptDigests = [{actionId: 'session-js', digest: 'e'.repeat(64)}];
  let output;
  const lean = checkPlan(required, applications, {onOutput: bytes => { output = Buffer.from(bytes); }});
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution', context,
    catalogDigest: hash(encode(catalog)), receiptDigests, lean};
  const request = {certificate, output, context, catalog, required, applications, receiptDigests};
  assert.equal(checkCertificate(request).accepted, true);
  for (const patch of [
    {context: {...context, runAttempt: 3}}, {catalogDigest: 'f'.repeat(64)},
    {receiptDigests: []}, {lean: {...lean, inputDigest: 'f'.repeat(64)}},
    {lean: {...lean, toolchain: 'unreviewed-pin'}},
  ]) assert.throws(() => checkCertificate({...request, certificate: {...certificate, ...patch}}));
  assert.throws(() => checkCertificate({...request, output: Buffer.from('different output')}));
  assert.throws(() => checkCertificate({...request, required: [{...required[0], target: 'native'}]}));
});

function familyFixture({mixed = false, changed = false, originEvent = 'workflow_dispatch', originBranch = 'main'} = {}) {
  // Controlled receipt/source fixture, not an assertion that these commands
  // ran on a physical Host. The plan checker itself executes the pinned Lean.
  const catalog = readCatalog();
  const context = {candidateRevision: 'a'.repeat(40), runHeadRevision: 'a'.repeat(40),
    repository: 'actql/actql', repositoryId: 1, workflowId: 2, runId: 30, runAttempt: 1, ancestors: ['b'.repeat(40)]};
  const source = new Map([...sharedFiles, ...mutationSnapshotExtras].map(path => [path, path]));
  source.set('proofs/ci-evidence/bounded-session-actions.json', encode(catalog));
  for (const directory of ['proofs/bounded-session', 'proofs/events-bridge'])
    for (const file of ['check.mjs', 'Session.lean', 'Composition.lean', 'CompositionClaims.lean',
      'Events.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'evidence.mjs', 'mutations.mjs'])
      source.set(`${directory}/${file}`, `controlled source ${file}`);
  for (const action of catalog.actions) if (action.package) source.set(`${action.package}/moon.pkg`, '');
  source.set('src/bounded_execution/session.mbt', 'controlled original Session');
  const candidateSource = new Map(source);
  candidateSource.set('docs/controlled-unrelated-change.md', 'outside the action input boundary');
  if (changed) candidateSource.set('src/bounded_execution/session.mbt', 'controlled changed Session');
  const tree = files => ({entries: new Map([...files].map(([path]) => [path, {mode: '100644', kind: 'blob'}])),
    read: path => Buffer.from(files.get(path))});
  const originTree = tree(source), candidateTree = tree(candidateSource);
  const runtime = {profile: 'controlled-test-runtime', unresolved: []};
  const origin = {repository: context.repository, repositoryId: 1, workflowId: 2,
    workflowPath: '.github/workflows/ci.yml', runId: 3, runAttempt: 1, jobId: 4,
    testedRevision: 'b'.repeat(40), runHeadRevision: 'b'.repeat(40), branch: originBranch, event: originEvent};
  function original(action, fresh) {
    const output = action.kind === 'formal-model'
      ? `Checked ${action.minimumUnits} theorems, expected claim types and axiom dependencies\n`
      : action.id === 'mutations-js' ? mutationIds.map(id => `${id}: detected by replacement tests`).join('\n')
        : `Total tests: ${action.minimumUnits}, passed: ${action.minimumUnits}, failed: 0.\n`;
    const owner = fresh ? {...origin, testedRevision: context.candidateRevision,
      runHeadRevision: context.runHeadRevision, runId: context.runId, runAttempt: context.runAttempt,
      event: 'pull_request', branch: 'controlled-candidate'} : origin;
    const receipt = sealReceipt({origin: owner, action,
      inputs: actionInputs({tree: fresh ? candidateTree : originTree, revision: owner.testedRevision, action, runtime}),
      output, status: 0, milliseconds: 10});
    return {receipt, receiptDigest: hash(canonicalReceipt(receipt)), artifactId: fresh ? 7 : 6,
      archiveDigest: (fresh ? 'f' : 'e').repeat(64)};
  }
  const receipts = new Map(catalog.actions.map(action => [action.id, original(action, !mixed || action.id !== 'mutations-js')]));
  const checked = {};
  const request = {context, runtime, protectedRevision: origin.testedRevision,
    treeAt: revision => revision === origin.testedRevision ? originTree : candidateTree,
    entries: catalog.actions.map(action => ({actionId: action.id,
      acquisition: mixed && action.id === 'mutations-js' ? 'reused' : 'fresh', archive: '/controlled.zip',
      artifactId: receipts.get(action.id).artifactId})),
    read: async ({action}) => receipts.get(action.id), prove: (required, applications) => {
      Object.assign(checked, {required, applications});
      return checkPlan(required, applications, {onOutput: bytes => {checked.output = Buffer.from(bytes);}});
    }};
  return {catalog, context, runtime, request, receipts, checked, original, originTree, candidateTree};
}

function finalCertificate(fixture, result) {
  const {context, catalog, checked: {output, required, applications}} = fixture;
  const receiptDigests = result.applications.map(value => ({actionId: value.actionId, digest: value.originReceiptDigest}));
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution',
    context, catalogDigest: result.catalogDigest, receiptDigests, lean: result.lean};
  const request = {certificate, output, context, catalog, required, applications, receiptDigests};
  assert.equal(checkCertificate(request).accepted, true);
  return request;
}

test('all 30 fresh obligations, including the Bridge, reach the real Lean checker and bound final certificate', async () => {
  const fixture = familyFixture(), {request} = fixture;
  const result = await checkApplications(request);
  const {required, applications} = fixture.checked;
  assert.equal(result.requiredActions.length, 30);
  assert.equal(applications.filter(value => value.action.startsWith('events-')).length, 4);
  assert(applications.every(value => !value.reused));
  finalCertificate(fixture, result);
  for (const id of ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']) {
    await assert.rejects(checkApplications({...request, entries: request.entries.filter(entry => entry.actionId !== id)}), /Incomplete/u);
    assert.throws(() => checkPlan(required, applications.filter(entry => entry.action !== id)), /Lean rejected/u);
  }
  const swapped = structuredClone(applications);
  swapped.find(value => value.action === 'events-connection-js').target = 'native';
  assert.throws(() => checkPlan(required, swapped), /Lean rejected/u);
});

async function selectFixture(fixture) {
  const {catalog, context, runtime, receipts, originTree, candidateTree} = fixture;
  const original = receipts.get('mutations-js');
  const origin = {revision: original.receipt.origin.testedRevision, runId: original.receipt.origin.runId,
    runAttempt: original.receipt.origin.runAttempt, actionKey: original.receipt.inputs.key,
    receiptDigest: original.receiptDigest, scientificDigest: original.receipt.execution.observationDigest};
  const comparison = {context, catalogDigest: hash(encode(catalog)), reuseAuthorized: false,
    artifact: {id: 6, digest: `sha256:${original.archiveDigest}`}, actions: catalog.actions.map(action => {
      const previous = actionInputs({tree: originTree, revision: origin.revision, action, runtime});
      const current = actionInputs({tree: candidateTree, revision: context.candidateRevision, action, runtime});
      const inputs = compareInputs(previous, current);
      return {actionId: action.id, candidateActionKey: current.key, closed: inputs.eligible,
        equal: inputs.equal, status: inputs.eligible ? 'closed-inputs-match' : 'different-inputs', origin};
    })};
  // Ready evidence is a controlled seam, not an authenticated Actions artifact.
  // The actual selector, application reconstruction and Lean checker execute.
  let readyReads = 0;
  const readReady = async () => {
    readyReads++;
    return {artifactId: 8, archiveDigest: 'd'.repeat(64),
      ready: [{actionId: 'mutations-js', actionKey: origin.actionKey,
        receiptDigest: origin.receiptDigest, scientificDigest: origin.scientificDigest}]};
  };
  const selection = {context, catalog, comparison, event: 'pull_request', readReady};
  const plan = await acquisitionPlan(selection);
  await verifyAcquisition({...selection, plan});
  fixture.request.entries = plan.actions.map(entry => {
    if (entry.acquisition === 'fresh') {
      const action = catalog.actions.find(value => value.id === entry.actionId);
      receipts.set(entry.actionId, fixture.original(action, true));
    }
    return {actionId: entry.actionId, acquisition: entry.acquisition, archive: '/controlled.zip',
      artifactId: receipts.get(entry.actionId).artifactId};
  });
  return {plan, readyReads};
}

test('manual main reuse passes the full mixed plan and actual Lean into the bound final certificate', async () => {
  const fixture = familyFixture({mixed: true});
  const original = canonicalReceipt(fixture.receipts.get('mutations-js').receipt);
  const {plan, readyReads} = await selectFixture(fixture);
  assert.equal(readyReads, 2, 'Producer and final selector independently consult ready evidence');
  assert.deepEqual(plan.actions.filter(entry => entry.acquisition === 'reused').map(entry => entry.actionId), ['mutations-js']);
  const result = await checkApplications(fixture.request);
  const reused = fixture.checked.applications.filter(entry => entry.reused);
  assert.equal(reused.length, 1); assert.equal(reused[0].mainOrigin, true);
  assert.equal(reused[0].origin, 'b'.repeat(40));
  assert.equal(fixture.checked.applications.filter(entry => !entry.reused).length, fixture.catalog.actions.length - 1);
  const certificate = finalCertificate(fixture, result);
  assert(canonicalReceipt(fixture.receipts.get('mutations-js').receipt).equals(original));
  assert.throws(() => checkCertificate({...certificate, receiptDigests: certificate.receiptDigests.filter(entry => entry.actionId !== 'mutations-js')}));
  assert.throws(() => checkCertificate({...certificate, applications: fixture.checked.applications.map(entry =>
    entry.reused ? {...entry, reused: false, origin: fixture.context.candidateRevision} : entry)}));
});

test('non-main manual and PR origins fail the actual mixed-plan Lean check', async () => {
  for (const origin of [{originBranch: 'feature', originEvent: 'workflow_dispatch'},
    {originBranch: 'main', originEvent: 'pull_request'}]) {
    const fixture = familyFixture({mixed: true, ...origin});
    await selectFixture(fixture);
    await assert.rejects(checkApplications(fixture.request), /Lean rejected action plan/u);
    assert.equal(fixture.checked.applications.find(entry => entry.reused).mainOrigin, false);
  }
});

test('a related source change returns to full fresh acquisition and actual final acceptance', async () => {
  const fixture = familyFixture({mixed: true, changed: true});
  await assert.rejects(checkApplications(fixture.request), /Different\/open source or runtime input boundary/u);
  const {plan, readyReads} = await selectFixture(fixture);
  assert.equal(readyReads, 0, 'Changed inputs cannot consult comparison authorization');
  assert(plan.actions.every(entry => entry.acquisition === 'fresh'));
  const result = await checkApplications(fixture.request);
  assert(fixture.checked.applications.every(entry => !entry.reused && entry.origin === fixture.context.candidateRevision));
  finalCertificate(fixture, result);
});

test('workflow retains campaigns, collects actual existing executions, and requires the archive consumer', () => {
  const workflow = yaml(readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const family = workflow.jobs['session-evidence'], gate = workflow.jobs.check;
  assert.deepEqual(family.permissions, {contents: 'read', actions: 'read'});
  assert.deepEqual(gate.permissions, {contents: 'read', actions: 'read'});
  const steps = family.steps;
  const position = command => steps.findIndex(step => step.run === command);
  assert(position('node proofs/ci-evidence/collect.mjs init') < position('node proofs/ci-evidence/collect.mjs mutations'));
  const finalRun = steps.findLastIndex(step => step.run === 'node proofs/bounded-session/run.mjs all');
  assert(finalRun < position('node proofs/ci-evidence/collect.mjs finish'));
  assert.equal(steps[finalRun].env.ACTQL_SESSION_COLLECT, 'true');
  for (const path of ['relation-chain/mutations.mjs', 'relation-capacity/mutations.mjs', 'relation-chain/run.mjs all', 'relation-capacity/run.mjs all'])
    assert(steps.some(step => step.run === `node proofs/${path}`));
  assert(steps.some(step => step.id === 'session-actions' && step.with.name.includes('github.run_attempt')));
  const consumer = gate.steps.find(step => step.run === 'node proofs/ci-evidence/final.mjs');
  assert(consumer && consumer.if === "${{ needs.session-evidence.result == 'success' }}");
  assert.equal(consumer.env.SESSION_ARTIFACT_ID, '${{ needs.session-evidence.outputs.artifact-id }}');
  const retained = gate.steps.find(step => step.with?.name?.startsWith('session-applicability-'));
  assert(retained && retained.if.includes('steps.session-acceptance-check.outcome'));
  assert.equal(retained.with.path, '.artifacts/session-applicability/verified-family.json');
  assert.equal(retained.with['if-no-files-found'], 'error');
  assert.equal(consumer.id, 'session-acceptance-check');
});
