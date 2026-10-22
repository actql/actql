// Independent normative preimages, never emitted compiler or runtime output.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
import {independentCid, valuesResultPlan} from './fixtures/string-contract-identities.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const source = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
const sorted = value => Array.isArray(value) ? value.map(sorted)
  : value && typeof value === 'object' ? Object.fromEntries(
    Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const canonical = value => JSON.stringify(sorted(value));

test('current Values publication fixture follows the complete normative Unit preimage', () => {
  const expected = valuesDependencyOracle();
  assert.equal(expected.unit,
    'sha256:912cb8f818d0b8c62c439cb926ee38cec74aa5c45233becbe47728b8788fe6d3');
  assert.equal(expected.resultPlan,
    'sha256:c456c24df410e168c65881a00f6ed18f8c63519a6e7ff831e72a4b86d1e9a472');
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
    'sha256:54329326f84b8638db98114ab72095dc248b097654e3d3449f9566017884b77f');
  assert.equal(independentCid(identity.semantics), identity.semanticsCid);
  assert.equal(independentCid(identity.definition), identity.programCid);
  const intent = independentCid({version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: 'sha256:' + 'b'.repeat(64),
    parameter_values_cid: 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    program_definition_cid: identity.programCid});
  assert.equal(intent,
    'sha256:a6a661228f758afe4a1811367f9b673260961a9a93231ff82860d6a9f3e58268');
  assert.ok(source.includes(`    "${identity.programCid}",`));
  assert.ok(source.includes(`    "${intent}",`));
});

test('preceding complete Values identities retain their original contract bodies', () => {
  const revision = '5d98418cdd7cd0f8e82192500808851f91089002';
  const oldBodies = new Map();
  const historical = path => {
    if (!oldBodies.has(path)) oldBodies.set(path, JSON.parse(execFileSync('git',
      ['show', `${revision}:${path}`], {encoding: 'utf8', maxBuffer: 8 * 1024 * 1024})));
    return oldBodies.get(path);
  };
  const roles = Object.keys(read('scripts/fixtures/pre-published-store-values-identities.json').contract_cids);
  const retainedContractCids = Object.fromEntries(roles.map(role => {
    let [path, pointer] = role.split('#');
    if (path === 'spec/dependencies/aoa-sga-identity-laws.json') path = 'spec/dependencies/actql-graph-laws.json';
    const body = pointer.split('/').slice(1).reduce((value, key) =>
      value[key.replaceAll('~1', '/').replaceAll('~0', '~')], historical(path));
    return [role, independentCid(body)];
  }));
  const previous = valuesDependencyOracle({retainedContractCids});
  assert.equal(previous.unit,
    'sha256:4fe9feeccd65724c402eff5fa54dcb6cddcfcc526b6bacaa310e96c13c3279a8');
  assert.equal(previous.resultPlan,
    'sha256:60999f9d69e9cfdbc483e01d7d85de8596bd7e91d68a00e23297c3aa7bf116c8');
  const oldPlan = valuesResultPlan(previous.unit);
  assert.equal(oldPlan.result_plan_logical_cid, previous.resultPlan);
  const oldIdentity = valuesProgramOracle({retainedContractCids});
  assert.equal(oldIdentity.programCid,
    'sha256:b3c4f1c8fef1b88fdb6ef12fde88d535b4ff5a9c92a505e1615c0ab289a185fe');
  assert.equal(independentCid(oldIdentity.definition), oldIdentity.programCid);
  assert.equal(independentCid({version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: 'sha256:' + 'b'.repeat(64),
    parameter_values_cid: 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    program_definition_cid: oldIdentity.programCid}),
  'sha256:3a5539d3ffaa793b3e804d13498d4cbd33cc16340387c1fd513dbf49a6a17a7f');
  const oldSource = execFileSync('git', ['show', `${revision}:src/run_publication_host/client_program_test.mbt`], {encoding: 'utf8'});
  assert.ok(oldSource.includes(canonical(oldPlan)));
  const enumeration = read('portability/corpus/text-enumeration-identities.json').valuesExecution;
  assert.equal(independentCid(enumeration.body), enumeration.cid);
  assert.equal(enumeration.cid,
    'sha256:493be37a957c68a479a4f91c2b9028d04b7320cfaa64414328d6af38df3d2f64');
  assert.notEqual(enumeration.cid,
    independentCid(read('spec/contracts/actql-aoa.json').execution_contracts['REL.values']));
  const registrySource = '02174392f19c815ce95cf95a1e9b84b6c9780daa';
  const oldAoA = JSON.parse(execFileSync('git', ['show',
    `${registrySource}:spec/contracts/actql-aoa.json`], {maxBuffer: 8 * 1024 * 1024}));
  const oldRegistry = JSON.parse(execFileSync('git', ['show',
    `${registrySource}:${oldAoA.pipeline_registry_file}`], {maxBuffer: 8 * 1024 * 1024}));
  assert.equal(independentCid(oldRegistry), oldAoA.pipeline_registry_cid);
  assert.equal(oldAoA.pipeline_registry_cid,
    'sha256:e22e68346562f75943e37453469d40c378bfe6994b124977f73addc1c23e76b6');
  assert.deepEqual(oldAoA.execution_contracts['REL.values'], enumeration.body);
  assert.equal(independentCid(oldAoA.execution_contracts['REL.derive.ordered']),
    'sha256:3b114d0baed2fa990d9420ae5af7fe742d5bf3fd0dfde20ef991af06c416df6e');
});
