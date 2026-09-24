import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';
import {admitEnvironment, compileValues, prepare,
  privateCompilationWires} from './index.mjs';

const read = name => readFileSync(new URL(`../sdk/fixtures/${name}`,
  import.meta.url), 'utf8');
const environmentWire = read('values.environment.json').trimEnd();
const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
const cid = body => `sha256:${createHash('sha256')
  .update(canonicalText(body)).digest('hex')}`;
const without = (value, key) => {
  const body = {...value};
  delete body[key];
  return cid(body);
};

test('portable Host package compiles the ordinary Values Program', () => {
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  const prepared = prepare(read('values.json'), 'json', environment);
  const compilation = compileValues(prepared);
  const wires = privateCompilationWires(compilation);
  const plan = JSON.parse(wires.executablePlan);
  const facts = JSON.parse(wires.factManifest);
  const template = JSON.parse(wires.boundTemplate);
  const compiled = JSON.parse(wires.compiledPlan);
  assert.equal(plan.version, 'actql-executable-plan/0.1');
  assert.equal(plan.executable_plan_cid, without(plan, 'executable_plan_cid'));
  assert.equal(facts.plan_fact_manifest_cid,
    without(facts, 'plan_fact_manifest_cid'));
  assert.deepEqual(plan.plan_facts, facts.plan_facts);
  assert.deepEqual(plan.root_refs.map(root => root.name), ['answer']);
  assert.deepEqual(plan.execution_material.result_plan_logical_cids,
    {answer: 'sha256:db7320fcd0090a93ced0c41a6936103a1d2ab02f87beb95d8c99733c95713d53'});
  assert.equal(template.bound_invocation_template_cid,
    without(template, 'bound_invocation_template_cid'));
  assert.equal(compiled.compiled_plan_cid,
    without(compiled, 'compiled_plan_cid'));
  assert.equal(compiled.executable_plan_cid, plan.executable_plan_cid);
  assert.equal(compiled.aoa_contract_cid,
    'sha256:26fbe956d369ada84612a9c93414c8c04bd20f3e11dccf3308f4b5e2a296658d');
  assert.throws(() => compileValues({kind: 'prepared-program'}),
    {name: 'TypeError', message: 'ForeignRunHostHandle'});
});

test('portable Host rejects unadmitted environment and invalid Program', () => {
  assert.throws(() => admitEnvironment(environmentWire, evidenceCid,
    {rela: true, future: true}),
  {name: 'TypeError', message: 'InvalidRunHostEnvironment'});
  assert.throws(() => admitEnvironment(environmentWire,
    `sha256:${'0'.repeat(64)}`, {rela: true}),
  {code: 'RunHostEnvironmentRejected'});
  const environment = admitEnvironment(environmentWire, evidenceCid,
    {rela: true});
  assert.throws(() => prepare('{"version":"actql/0.1"}', 'json',
    environment), {code: 'RunHostPreparationRejected'});
  assert.throws(() => prepare(read('values.json'), 'future', environment),
    {name: 'TypeError', message: 'InvalidRunHostPreparation'});
});
