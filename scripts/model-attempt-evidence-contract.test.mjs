import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {checkModelAttemptEvidenceSchemas} from './model-attempt-evidence-contract.mjs';

const pin = digit => `sha256:${digit.repeat(64)}`;
const authority = {version: 'actql-model-dispatch-authority/0.1',
  program_definition_cid: pin('1'), run_definition_cid: pin('2'),
  run_authorization_cid: pin('3'), account_configuration_cid: pin('4'),
  model_task_cid: pin('5'), fixed_request_cid: pin('6'),
  execution_context_cid: pin('7'), host_policy_cid: pin('8'),
  principal: 'fixture-principal', connection: 'models/fixture', resource: pin('5'),
  operation: 'infer', entry_id: 'model-policy', basis: 'account_allow',
  answering_authority: null, satisfied_claims: []};
const attempt = {version: 'actql-model-call-attempt/0.1',
  slot_cid: pin('9'), run_definition_cid: pin('2'), model_task_cid: pin('5'),
  fixed_request_cid: pin('6'), authority_evidence_cid: machineCid(authority),
  attempt: 1, provider_id: 'models/fixture'};
const accounting = {version: 'actql-model-attempt-accounting/0.1',
  attempt_cid: machineCid(attempt), slot_cid: pin('9'),
  cumulative_work: 23, uncertain_wire_bytes: 66536,
  input_tokens: null, output_tokens: null, cost_units: null, duration_ms: null};
const outcome = {version: 'actql-model-attempt-outcome/0.1',
  attempt_cid: machineCid(attempt), slot_cid: pin('9'),
  category: 'provider_failure', failure: 'timeout'};
const bodies = [['model_dispatch_authority', authority],
  ['model_call_attempt', attempt], ['model_attempt_accounting', accounting],
  ['model_attempt_outcome', outcome],
  ['model_attempt_outcome', {...outcome, category: 'cancelled', failure: 'cancelled'}],
  ['model_attempt_accounting', {...accounting, input_tokens: 1, output_tokens: 2}],
  ['model_attempt_accounting', {...accounting,
    reservation: {tokens: 33, cost_units: 7, duration_ms: 19}}],
  ['model_attempt_accounting', {...accounting, input_tokens: 1, output_tokens: 2,
    reservation: {tokens: 33, cost_units: 7, duration_ms: 19}}],
  ['model_attempt_outcome', {...outcome, category: 'contract_violation',
    failure: 'budget_exceeded'}]];
const corpus = {version: 'actql-model-attempt-evidence-vectors/0.1',
  cases: bodies.map(([kind, body]) => ({kind, body,
    expected_canonical_bytes: canonicalText(body), expected_cid: machineCid(body)}))};
const corpusPath = 'portability/corpus/model-attempt-evidence.json';
const moonPath = 'src/run_publication/model_attempt_evidence.generated_test.mbt';
let moon = '// Generated independent model attempt evidence vectors.\n';
for (const [index, fixture] of corpus.cases.entries()) {
  moon += `\n///|\ntest "independent model attempt evidence ${index}" {\n` +
    `  let value = seal_run_evidence_value(${JSON.stringify(fixture.kind)},\n` +
    `    ${JSON.stringify(fixture.expected_canonical_bytes)}, 16384, 256, 8).unwrap()\n` +
    `  assert_eq(run_evidence_value_identity(value), ${JSON.stringify(fixture.expected_cid)})\n` +
    `  let restored = admit_run_evidence_value(${JSON.stringify(fixture.kind)},\n` +
    `    run_evidence_value_json(value), 16384, 256, 8).unwrap()\n` +
    `  assert_eq(run_evidence_value_identity(restored), ${JSON.stringify(fixture.expected_cid)})\n` +
    `}\n`;
}
for (const [kind, body] of [['model_attempt_accounting', {...accounting, input_tokens: -1}],
  ['model_call_attempt', {...attempt, attempt: 0}],
  ['model_attempt_outcome', {...outcome, failure: 'invented'}],
  ['model_attempt_accounting', {...accounting,
    reservation: {tokens: -1, cost_units: 7, duration_ms: 19}}],
  ['model_attempt_accounting', {...accounting,
    reservation: {tokens: 33, cost_units: 7}}]]) {
  moon += `\n///|\ntest ${JSON.stringify('invalid model attempt evidence ' + kind + ' ' + machineCid(body).slice(7, 15))} {\n` +
    `  assert_true(seal_run_evidence_value(${JSON.stringify(kind)},\n` +
    `    ${JSON.stringify(canonicalText(body))}, 16384, 256, 8) is Err(RunEvidenceInvalidShape))\n}\n`;
}
moon = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
  : 'moonfmt', ['-'], {input: moon, encoding: 'utf8'});
if (process.argv.includes('--write')) {
  writeFileSync(corpusPath, JSON.stringify(corpus, null, 2) + '\n');
  writeFileSync(moonPath, moon);
}
assert.deepEqual(JSON.parse(readFileSync(corpusPath, 'utf8')), corpus);
assert.equal(readFileSync(moonPath, 'utf8'), moon);

test('registered attempt bodies and independent identities are exact', () => {
  checkModelAttemptEvidenceSchemas(JSON.parse(readFileSync(
    'spec/contracts/actql-protocol-schemas.json', 'utf8')));
  for (const fixture of corpus.cases) verifyIdentity(fixture.body,
    fixture.expected_cid, fixture.expected_canonical_bytes);
});

test('attempt identity excludes future observations and changes with its Run', () => {
  for (const forbidden of ['response_artifact_cid', 'observation_set_cid',
    'slot_capture_cid', 'invocation_cid', 'accounting_evidence_cid']) {
    assert.equal(Object.hasOwn(attempt, forbidden), false);
  }
  for (const field of ['slot_cid', 'run_definition_cid', 'model_task_cid',
    'fixed_request_cid', 'authority_evidence_cid']) {
    assert.notEqual(machineCid(attempt), machineCid({...attempt, [field]: pin('f')}));
  }
  assert.notEqual(machineCid(accounting), machineCid({...accounting, input_tokens: 0}));
});
