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
    'sha256:54d801eeb94b6acbf002bdac78ce42f5d76e0831225b7908908f71185354826c');
  assert.equal(expected.resultPlan,
    'sha256:978a042607f89e34538d18c040fc175f385fcef9b63835a53e347745c25e0de6');
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
    'sha256:3332449b1276d347af6c8acdbed8852070cbccb967d7752b2502f3b68b2dfe29');
  assert.equal(independentCid(identity.semantics), identity.semanticsCid);
  assert.equal(independentCid(identity.definition), identity.programCid);
  const intent = independentCid({version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: 'sha256:' + 'b'.repeat(64),
    parameter_values_cid: 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    program_definition_cid: identity.programCid});
  assert.equal(intent,
    'sha256:84d80e11d1ded456420a04e75e199d80040bc45aa7d9b28b294f2b798727e534');
  assert.ok(source.includes(`    "${identity.programCid}",`));
  assert.ok(source.includes(`    "${intent}",`));
});
