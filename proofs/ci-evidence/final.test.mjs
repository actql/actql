import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse as yaml} from 'yaml';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog} from './actions.mjs';
import {hash, actionInputs, sharedFiles, mutationSnapshotExtras} from './inputs.mjs';
import {canonicalReceipt, sealReceipt, mutationIds} from './receipts.mjs';
import {checkApplications} from './applications.mjs';
import {checkPlan} from './check.mjs';
import {checkCertificate} from './final.mjs';

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

test('all 30 fresh obligations, including the Bridge, reach the real Lean checker and bound final certificate', async () => {
  // Controlled receipt/source fixture, not an assertion that these commands
  // ran on a physical Host. The plan checker itself executes the pinned Lean.
  const catalog = readCatalog();
  const context = {candidateRevision: 'a'.repeat(40), runHeadRevision: 'a'.repeat(40),
    repository: 'actql/actql', repositoryId: 1, workflowId: 2, runId: 3, runAttempt: 1, ancestors: []};
  const source = new Map([...sharedFiles, ...mutationSnapshotExtras].map(path => [path, path]));
  source.set('proofs/ci-evidence/bounded-session-actions.json', encode(catalog));
  for (const directory of ['proofs/bounded-session', 'proofs/events-bridge'])
    for (const file of ['check.mjs', 'Session.lean', 'Composition.lean', 'CompositionClaims.lean',
      'Events.lean', 'Claims.lean', 'lean-toolchain', 'setup-lean.mjs', 'evidence.mjs', 'mutations.mjs'])
      source.set(`${directory}/${file}`, `controlled source ${file}`);
  for (const action of catalog.actions) if (action.package) source.set(`${action.package}/moon.pkg`, '');
  const tree = {entries: new Map([...source].map(([path]) => [path, {mode: '100644', kind: 'blob'}])),
    read: path => Buffer.from(source.get(path))};
  const runtime = {profile: 'controlled-test-runtime', unresolved: []};
  const origin = {repository: context.repository, repositoryId: 1, workflowId: 2,
    workflowPath: '.github/workflows/ci.yml', runId: 3, runAttempt: 1, jobId: 4,
    testedRevision: context.candidateRevision, runHeadRevision: context.runHeadRevision, branch: 'main', event: 'workflow_dispatch'};
  const receipts = new Map(catalog.actions.map(action => {
    const output = action.kind === 'formal-model'
      ? `Checked ${action.minimumUnits} theorems, expected claim types and axiom dependencies\n`
      : action.id === 'mutations-js' ? mutationIds.map(id => `${id}: detected by replacement tests`).join('\n')
        : `Total tests: ${action.minimumUnits}, passed: ${action.minimumUnits}, failed: 0.\n`;
    const receipt = sealReceipt({origin, action,
      inputs: actionInputs({tree, revision: context.candidateRevision, action, runtime}),
      output, status: 0, milliseconds: 10});
    return [action.id, {receipt, receiptDigest: hash(canonicalReceipt(receipt)), artifactId: 6, archiveDigest: 'e'.repeat(64)}];
  }));
  let output, required, applications;
  const request = {context, runtime, protectedRevision: context.candidateRevision, treeAt: () => tree,
    entries: catalog.actions.map(action => ({actionId: action.id, acquisition: 'fresh', archive: '/controlled.zip', artifactId: 6})),
    read: async ({action}) => receipts.get(action.id), prove: (r, a) => {
      required = r; applications = a;
      return checkPlan(r, a, {onOutput: bytes => {output = Buffer.from(bytes);}});
    }};
  const result = await checkApplications(request);
  assert.equal(result.requiredActions.length, 30);
  assert.equal(applications.filter(value => value.action.startsWith('events-')).length, 4);
  assert(applications.every(value => !value.reused));
  const receiptDigests = result.applications.map(value => ({actionId: value.actionId, digest: value.originReceiptDigest}));
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'scoped-execution',
    context, catalogDigest: result.catalogDigest, receiptDigests, lean: result.lean};
  assert.equal(checkCertificate({certificate, output, context, catalog, required, applications, receiptDigests}).accepted, true);
  for (const id of ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']) {
    await assert.rejects(checkApplications({...request, entries: request.entries.filter(entry => entry.actionId !== id)}), /Incomplete/u);
    assert.throws(() => checkPlan(required, applications.filter(entry => entry.action !== id)), /Lean rejected/u);
  }
  const swapped = structuredClone(applications);
  swapped.find(value => value.action === 'events-connection-js').target = 'native';
  assert.throws(() => checkPlan(required, swapped), /Lean rejected/u);
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
