// Independent, hand-assembled preimages for the fixed MoonBit Values fixture.
// No product compiler/issuer/output is imported. Unchanged dependency CIDs
// are the baseline vector's pins; all affected bodies are rehashed here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {valuesResultPlan} from './fixtures/string-contract-identities.mjs';
import {valuesDependencyOracle} from './client-values-dependency-oracle.mjs';

const canonical = value => JSON.stringify(normalize(value));
function normalize(value) {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') return Object.fromEntries(
    Object.keys(value).sort().map(key => [key, normalize(value[key])]));
  return value;
}
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const pin = hex => 'sha256:' + hex;
const seal = (body, field) => ({...body, [field]: cid(body)});
const programCid = pin('f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c');
const semanticsCid = pin('b1f21c4233445f6ba90ee54729213a87322e69b8eccf4318aeba5c5e4798400e');
const priorDependencies = valuesDependencyOracle({legacy:true});
const policy = pin('38a92017de0e3e13901d328ab622696708aab0563dd980b04bfc9a2b6c451853');
const environment = pin('aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904');
const parameterValues = pin('c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52');
const bindings = pin('5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f');
const barrier = pin('075ce7af21828f3a298162c90140b0bdcc1f225e7fec3922b89ceaddf2185443');
// Frozen pre-keyed-profile root. Historical vectors must not silently rebind
// to a later registry merely because that registry is installed today.
const priorAoA = pin('bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea');
const logical = pin('5e502ceb8e7f0833fd2491ac223453d9204e99a3c29642cad6d782cee9ff7723');
const schema = {id: {nullable: false, type: 'number'}};
const rows = [{id: 1}, {id: 2}];
const program = {version: 'actql/0.1', id: 'client-values',
  stages: [{id: 'source', inputs: {}, steps: [{as: 'selected', values: {schema, rows}}],
    results: {rows: {fields: ['id'], from: 'selected'}}}],
  results: {answer: {from: {stage: 'source', result: 'rows'}}}};
const ceiling = measure => seal({version: 'actql-bound-witness/0.1',
  dependencies: [policy], derivation: {op: 'source'},
  law_id: `actql.host.artifact-${measure}`, role: 'host_ceiling',
  source: {field: `max_artifact_${measure}`, kind: 'host_policy', policy_cid: policy},
  unit: measure, value: 1000}, 'witness_cid');
const rowCeiling = ceiling('rows');
const byteCeiling = ceiling('bytes');
const limit = (measure, candidates, maximum, unit) => seal({version: 'actql-resolved-limit/0.1',
  // The wire contract orders candidates by witness CID, not issuance order.
  author_guard_binding: 'absent', breach: 'fail',
  candidates: [...candidates].sort((a, b) => a.witness_cid < b.witness_cid ? -1 :
    a.witness_cid > b.witness_cid ? 1 : 0), effective_max: maximum,
  enforcement: 'engine_atomic', subject_ref: `unit:${unit}#/results/rows/${measure}`,
  unit: measure}, 'resolved_limit_cid');
function vector(grammar, aoa, dependencies=priorDependencies) {
  const {unit,proof,resultPlan} = dependencies;
  const upper = seal({version: 'actql-bound-witness/0.1', dependencies: [proof],
    derivation: {op: 'source'}, law_id: 'actql.bound.values', role: 'proven_upper_bound',
    source: {kind: 'program', proof_cid: proof, semantic_ref: `unit:${unit}#/steps/0`},
    unit: 'rows', value: 2}, 'witness_cid');
  const limits = [limit('rows', [rowCeiling, upper], 2, unit),
    limit('bytes', [byteCeiling], 1000, unit)];
  const limitBindings = limits.map(value => seal({version: 'actql-execution-limit-binding/0.1',
    effective_max: value.effective_max, resolved_limit_cid: value.resolved_limit_cid,
    subject_ref: value.subject_ref, target: {kind: 'result_publication', measure: value.unit,
      result_name: 'rows', unit_definition_cid: unit}, unit: value.unit}, 'binding_cid'));
  const facts = limits.map(value => ({kind: 'resolved_limit', value}));
  const factManifest = cid({plan_facts: facts, version: 'actql-plan-fact-manifest/0.1'});
  const template = seal({version: 'actql-bound-invocation-template/0.1',
    barrier_contract_manifest_cid: barrier, check_environment_cid: environment,
    grammar_manifest_cid: grammar, invocation_bindings_cid: bindings,
    parameter_values_cid: parameterValues, program_definition_cid: programCid,
    required_profile_contracts: [], source_evidence: 'unbound'}, 'bound_invocation_template_cid');
  const executable = seal({version: 'actql-executable-plan/0.1',
    bound_witnesses: [upper, rowCeiling, byteCeiling], data_edges: [],
    execution_material: {aoa_contract_cid: aoa, barrier_contract_manifest_cid: barrier,
      check_environment_cid: environment, effect_plan_logical_cids: {},
      grammar_manifest_cid: grammar, invocation_binding_names: [],
      invocation_bindings_cid: bindings, invocation_template_cid: template.bound_invocation_template_cid,
      parameter_names: [], parameter_values_cid: parameterValues, program,
      program_definition_cid: programCid, result_plan_logical_cids: {
        answer: resultPlan}},
    limit_bindings: limitBindings, nodes: [{input_contracts: {}, kind: 'aoa_fragment',
      logical_cid: logical, node_id: 'values_0', output_contracts: {
        values_0: pin('999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c')},
      pipeline: {output: 'values_0', sources: {}, steps: [{id: 'values_0', in: [],
        op: 'REL.values', params: {rows, schema}}], version: 'aoa-pipeline/0.1'}}],
    plan_fact_manifest_cid: factManifest, plan_facts: facts, required_profiles: [],
    resolved_limits: limits, root_refs: [{name: 'answer',
      ref: {node_id: 'values_0', port: 'values_0'}, role: 'requested_result'}],
    source_state_requirements: []}, 'executable_plan_cid');
  const compiled = seal({version: 'actql-compiled-plan/0.1', aoa_contract_cid: aoa,
    aoa_ir_version: 'aoa-pipeline:0.1', aoa_logical_cid: logical,
    compiler_version: 'actql-moonbit-0.0.1', executable_plan_cid: executable.executable_plan_cid,
    program_definition_cid: programCid, program_semantics_cid: semanticsCid}, 'compiled_plan_cid');
  const run = seal({version: 'actql-run-definition/0.1',
    authorization_context_cid: pin('a'.repeat(64)), compiled_plan_cid: compiled.compiled_plan_cid,
    created_at: '2026-09-30T00:00:00.000Z', input_artifact_set_cid:
      cid({version: 'actql-initial-input-artifact-set/0.1', captured_artifact_cids: []}),
    invocation_template_cid: template.bound_invocation_template_cid, run_id: 'cloud-run-1',
    scope_id: 'cloud-scope', valid_until: '2099-01-01T00:00:00.000Z'}, 'run_definition_cid');
  return {template, executable, compiled, run};
}

// Frozen Unit identifiers anchor predecessor preimages. Proof and Result
// bodies are independently assembled; no compiler output is imported.
function historicalDependencies(unit) {
  return {unit, proof: cid({version:'actql-bound-proof/0.1',inputs:[],
    law_id:'actql.bound.values',semantic_ref:`unit:${unit}#/steps/0`,unit:'rows',value:2}),
    resultPlan:valuesResultPlan(unit).result_plan_logical_cid};
}

test('baseline preimages and changed normative pins independently determine the Run CID', () => {
  const baseline = vector(pin('15a180c744c81eea1368e7e31813bb2b3712b9496ba48748973cb94135184914'),
    pin('4b6f51d57ca1d3cb16e28e04eeef20bebee34d4d3b89271de84b982a8ac74005'));
  assert.equal(baseline.template.bound_invocation_template_cid,
    pin('4555d08a720eb232c16ddae70b40cab4b37f8f05bb7b59b754b5981892c3d2dc'));
  assert.equal(baseline.executable.executable_plan_cid,
    pin('9b62027cd9e7ba5b1b8809330a5ff812657f8dae56f238654d4fdff6a4dadf8d'));
  assert.equal(baseline.run.run_definition_cid,
    pin('e80cf974a2d99757867e3d087e88f48245aab36df049d0dd6959d264ec6be7b5'));
  // Pins are checked in normative contracts, not read from generated runtime.
  const grammar = JSON.parse(readFileSync('spec/manifests/actql-grammar-0.1.json', 'utf8'));
  const aoaContract = JSON.parse(readFileSync('spec/contracts/actql-aoa.json', 'utf8'));
  const {grammar_manifest_cid: grammarCid, ...grammarPreimage} = grammar;
  assert.equal(cid(grammarPreimage), grammarCid);
  assert.equal(priorDependencies.unit,
    pin('63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9'));
  assert.equal(priorDependencies.proof,
    pin('22eca16bd792feacf027e5c5e60463882ad90ad4ac88d19b77719dc174292609'));
  assert.equal(priorDependencies.resultPlan,
    pin('8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38'));
  const dependencies = valuesDependencyOracle();
  const current = vector(grammarCid, cid(aoaContract), dependencies);
  // Preserve the prior WITH/Pipe vector; the new policy changes no Values body.
  assert.equal(vector(pin('a8f1bbabb5eeda9287716c651b398d1c0954201c985b5c70ccb78d96a9ed1416'),
    priorAoA).run.run_definition_cid,
  pin('47752e67dd0f083b491b0110dd181af4fd312905f5ec67952badf7a8adb832fe'));
  // Keep the merged text-retirement vector as an independent baseline.
  assert.equal(vector(pin('8fc336e2b475104366fea9024c38d171a3d18743a63f05b254272e14bedd886d'),
    priorAoA).run.run_definition_cid,
    pin('1a7ded9110cb3d2c27f151ccc75f1c6683c3a4e0316fc0570706a3c169934baf'));
  // Preserve the prior SELECT-headed-Pipe grammar vector independently.
  assert.equal(vector(pin('ecf842ba6846f2dbac5cb8fa42b5b708c14e0ec170fc14d05043a351c0300582'),
    priorAoA).run.run_definition_cid,
    pin('b8f4539c6741e24dd20bdd1ce77f5dc9d0c0466684c6e151e4441bccaaaaca9c'));
  // Preserve the previous derived-query vector; this change only binds the
  // expanded query grammar/profile, not a new Values or AoA numeric meaning.
  assert.equal(vector(pin('3c8ac36faac086564fc41c468477c5ea3bfb2aedd1d86b4996220d43ad337356'),
    priorAoA).run.run_definition_cid,
    pin('dbbc63ad3aad5cc0f47ccad3112138b9a3e3056d4d8d5e83d7a2781f77cd560d'));
  // Preserve the initial composite-query vector before the lexical CTE-scope
  // rules were made explicit in the normative document.
  assert.equal(vector(pin('72fc89e110c5597c976be9aad63418cb03faf0b1ddeeeb021a124fb5ffd67aa2'),
    priorAoA).run.run_definition_cid,
    pin('e50e7c8bd772eed517264aa3d946da1696e98328b22879f32a5980172e2b5c7c'));
  // Preserve both submitted branches before combining their dependency roots.
  assert.equal(vector(pin('5df79a1521ff009f2a54b8a12e259ac287b048961828c4901f066ad169fac975'),
    priorAoA).run.run_definition_cid,
    pin('012e0a4567a1a9fb115d6476031e6f635f924f1f3ca9c1aeabb03cd0e06d9e55'));
  assert.equal(vector(pin('cd2261b7c336e0d713dcb1c2c19d9dab89d928f134883857b48e9c5b2494cffa'),
    pin('072c1c6e630f683e41a1c814b3a000d0544506ae25c5d89210fa8982ff73c5ff'),
    historicalDependencies(pin('582a2d4805db0a13b1b02544eca5b21a4ce63b0c901679762ea11c5555ea07a5'))).run.run_definition_cid,
    pin('f171d251195c262096577393afc6d51390ca7b4b7b63bda8b17c74a13a6d54f6'));
  // Keep both submitted branches before combining Graph and String roots.
  assert.equal(vector(pin('85ee0fd6d4d689e1038c4d754faf9721107835361b0ec38d804b9d6dc694fdf4'),
    pin('072c1c6e630f683e41a1c814b3a000d0544506ae25c5d89210fa8982ff73c5ff'),
    historicalDependencies(pin('582a2d4805db0a13b1b02544eca5b21a4ce63b0c901679762ea11c5555ea07a5'))).run.run_definition_cid,
    pin('9cb879cebfe85960516d52e34932fe236bdab7d703150de865caaaaedccbee8c'));
  assert.equal(vector(pin('b176b995f5dc309487656b334cb34e21409f6a9f67f8a10b89ac9c5d6e5db7c2'),
    pin('ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4'),
    historicalDependencies(pin('0ec8026865253c45b26d8eb0b9df6e4cb63b64bf7ae19590e6f1fc2aff10879c'))).run.run_definition_cid,
    pin('857742abdfaf8e4e90e07c4f60f37b771ea62ef44e41f0bdb078bf3d0134069b'));
  // Preserve the integrated predecessor, with its fixed Unit and grammar.
  assert.equal(vector(pin('a008ad4bb4aa68f02a688b00306bc3818de0dae7beae81d977e54e76f156ad5d'),
    pin('2a06d014da3ce71fc643f995bf0d0acc2b296fdbeb9016dca935539b6cbe8ade'),
    historicalDependencies(pin('0894114a68047606a91d50d53b3a3a33f50ab402341ed7d6acdd692cf74a2f92'))).run.run_definition_cid,
    pin('33b9fb4c38a1a0dce33674944cdef96b01c4a3ace604854ed175e7de8cb59065'));
  // Current DATA/constructor grammar: Values and AoA meanings are unchanged.
  assert.equal(current.run.run_definition_cid,
    'sha256:b956c4d981b3011254a442aec64602473e016be109d0d4443c38ab416ca6a2dc');
  const source = readFileSync('src/run_publication_host/client_values_run_materials_wbtest.mbt', 'utf8');
  assert.ok(source.includes(current.run.run_definition_cid), 'MoonBit fixed expected CID must follow independent preimage');
  const resultSource = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
  assert.ok(resultSource.includes(dependencies.unit));
  assert.ok(resultSource.includes(dependencies.resultPlan), 'MoonBit fixed Result Plan must follow independent preimage');
});
