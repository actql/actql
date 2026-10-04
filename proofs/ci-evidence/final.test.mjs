import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse as yaml} from 'yaml';
import {encode} from '../bounded-session/action-inputs.mjs';
import {readCatalog} from './actions.mjs';
import {hash} from './inputs.mjs';
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
  const certificate = {version: 'actql-verification-family-certificate/0.1', mode: 'comparison', context,
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
});
