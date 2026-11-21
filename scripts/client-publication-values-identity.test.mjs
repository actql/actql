// Independent normative preimages, never emitted compiler or runtime output.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
import {independentCid, valuesResultPlan} from './fixtures/string-contract-identities.mjs';

const source = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
const sorted = value => Array.isArray(value) ? value.map(sorted)
  : value && typeof value === 'object' ? Object.fromEntries(
    Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const canonical = value => JSON.stringify(sorted(value));

test('current Values publication fixture follows the complete normative Unit preimage', () => {
  const expected = valuesDependencyOracle();
  assert.equal(expected.unit,
    'sha256:65973b5e9310a85bf6236f45935df640e124c7f2f9f1d1663483501255f429b0');
  assert.equal(expected.resultPlan,
    'sha256:f3876cf0496d13d8ec51d942938532f51eda929f1a668c8168319d6b19885fb1');
  const plan = valuesResultPlan(expected.unit);
  assert.equal(plan.result_plan_logical_cid, expected.resultPlan);
  const document = source.split('\n').find(line => line.includes('#|{"version":"actql/0.1"'));
  assert.ok(document);
  const authored = JSON.parse(document.trim().slice(2));
  const {id, ...stage} = authored.stages[0];
  stage.effects = {};
  assert.equal(id, 'source');
  assert.equal(authored.id, 'client-values');
  assert.deepEqual(stage, expected.local.local_body);
  const planLine = source.split('\n').find(line => line.includes('#|{"order":'));
  assert.ok(planLine);
  assert.equal(planLine.trim().slice(2), canonical(plan));
  assert.ok(source.includes(`    "${expected.resultPlan}",`));
  const identity = valuesProgramOracle();
  assert.equal(identity.programCid,
    'sha256:6fdfbedacd868aeffe1f134815be31de326c7e268ef54c1105f2e8b5b6728727');
  assert.equal(independentCid(identity.semantics), identity.semanticsCid);
  assert.equal(independentCid(identity.definition), identity.programCid);
  const intent = independentCid({version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: 'sha256:' + 'b'.repeat(64),
    parameter_values_cid: 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    program_definition_cid: identity.programCid});
  assert.equal(intent,
    'sha256:b432fc10b3137dad749146edd6a45a23d5a7c4e5156c561428bdc6306606bc30');
  assert.ok(source.includes(`    "${identity.programCid}",`));
  assert.ok(source.includes(`    "${intent}",`));
});
