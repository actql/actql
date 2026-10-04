// Independent, hand-assembled preimages for the fixed MoonBit Values fixture.
// No product compiler/issuer/output is imported. Unchanged dependency CIDs
// are the baseline vector's pins; all affected bodies are rehashed here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
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
test('merged Frontend and exact-String predecessor vectors retain their historical pins', () => {
  // The previous Unit and containing contract are immutable fixture identities,
  // not the current installed registry. Rebuild all dependent bodies here.
  const unit = pin('0ec8026865253c45b26d8eb0b9df6e4cb63b64bf7ae19590e6f1fc2aff10879c');
  const proof = cid({version: 'actql-bound-proof/0.1', inputs: [],
    law_id: 'actql.bound.values', semantic_ref: `unit:${unit}#/steps/0`, unit: 'rows', value: 2});
  const resultPlan = cid({version: 'actql-result-plan/0.1',
    order: {strategy: 'inherited', terms: []},
    projection: [{input: 'id', output: 'id',
      value_contract_cid: pin('8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d')}],
    result_name: 'answer', typed_output_port: {carrier: 'relation', name: 'rows',
      row_contract_cid: pin('999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c')},
    unit_definition_cid: unit, unit_result_name: 'rows', unit_result_ordinal: 0});
  const predecessors = [
  [
    "a8f1bbabb5eeda9287716c651b398d1c0954201c985b5c70ccb78d96a9ed1416",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "47752e67dd0f083b491b0110dd181af4fd312905f5ec67952badf7a8adb832fe"
  ],
  [
    "8fc336e2b475104366fea9024c38d171a3d18743a63f05b254272e14bedd886d",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "1a7ded9110cb3d2c27f151ccc75f1c6683c3a4e0316fc0570706a3c169934baf"
  ],
  [
    "ecf842ba6846f2dbac5cb8fa42b5b708c14e0ec170fc14d05043a351c0300582",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "b8f4539c6741e24dd20bdd1ce77f5dc9d0c0466684c6e151e4441bccaaaaca9c"
  ],
  [
    "3c8ac36faac086564fc41c468477c5ea3bfb2aedd1d86b4996220d43ad337356",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "dbbc63ad3aad5cc0f47ccad3112138b9a3e3056d4d8d5e83d7a2781f77cd560d"
  ],
  [
    "72fc89e110c5597c976be9aad63418cb03faf0b1ddeeeb021a124fb5ffd67aa2",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "e50e7c8bd772eed517264aa3d946da1696e98328b22879f32a5980172e2b5c7c"
  ],
  [
    "5df79a1521ff009f2a54b8a12e259ac287b048961828c4901f066ad169fac975",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "012e0a4567a1a9fb115d6476031e6f635f924f1f3ca9c1aeabb03cd0e06d9e55"
  ],
  [
    "ecf842ba6846f2dbac5cb8fa42b5b708c14e0ec170fc14d05043a351c0300582",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "e7c495589dedf6a62557d8594eb50994bfa38e9d61b17f18176d277de484240b"
  ],
  [
    "6b812b128f53bee2b1f0edc8e2c2084a9c12044f0455c502640563ebad1fbf75",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "cbbe25f3a540b4c917e555bcbc67875c7a68d8279af8c344e8c950a49b77988f"
  ],
  [
    "69bfc5ff4846f34bf910fcbdbb3a1d8e21750797e1a1c4b578d97571da1afd1f",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "f835722f8d8fc55b5f325e101aa38c43b5783bf807161d6d2cb58a3091437dd5"
  ],
  [
    "74823e16a311511bb8078beedb472b6fc8ce0dcda0cceae9432bc0d6da4c3871",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "535f3d5b34ee29911cc3d258e9fe2c8324e34a8f75cd4db799f31323fad2d0a3"
  ],
  [
    "03794c261f577cea8c9070af363f74b65e2994bba7152bc57bb2cabfb8a0f7db",
    "bfb017e25670c872293a2a4eec302b7d1217c3cb1adf74637c2339286d5c39ea",
    false,
    "3042e2f2933416c5e4c2c3d99f202d2cab406672e6438454c30f127fe23c5762"
  ],
  [
    "5fb2cacd6bbea4c6aa32de0f9a157f072723eb96d251d4f09b8a86513001b976",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "8574f5eb487efe877f5d11cda228d63ba737c3ef8821f7cd20ce804b964b3810"
  ],
  [
    "b176b995f5dc309487656b334cb34e21409f6a9f67f8a10b89ac9c5d6e5db7c2",
    "ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4",
    true,
    "857742abdfaf8e4e90e07c4f60f37b771ea62ef44e41f0bdb078bf3d0134069b"
  ]
];
  for (const [grammar, contract, exactString, expected] of predecessors) {
    assert.equal(vector(pin(grammar), pin(contract),
      exactString ? {unit, proof, resultPlan} : priorDependencies).run.run_definition_cid,
    pin(expected));
  }
});
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
  author_guard_binding: 'absent', breach: 'fail', candidates, effective_max: maximum,
  enforcement: 'engine_atomic', subject_ref: `unit:${unit}#/results/rows/${measure}`,
  unit: measure}, 'resolved_limit_cid');
function vector(grammar, aoa, dependencies=priorDependencies, barrierCid=barrier) {
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
    barrier_contract_manifest_cid: barrierCid, check_environment_cid: environment,
    grammar_manifest_cid: grammar, invocation_bindings_cid: bindings,
    parameter_values_cid: parameterValues, program_definition_cid: programCid,
    required_profile_contracts: [], source_evidence: 'unbound'}, 'bound_invocation_template_cid');
  const executable = seal({version: 'actql-executable-plan/0.1',
    bound_witnesses: [upper, rowCeiling, byteCeiling], data_edges: [],
    execution_material: {aoa_contract_cid: aoa, barrier_contract_manifest_cid: barrierCid,
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
  const barrierManifest = JSON.parse(readFileSync('spec/manifests/actql-barrier-contracts-0.1.json', 'utf8'));
  const {barrier_contract_manifest_cid: barrierCid, ...barrierPreimage} = barrierManifest;
  assert.equal(cid(barrierPreimage), barrierCid);
  const current = vector(grammarCid, cid(aoaContract), dependencies, barrierCid);
  // Preserve the prior WITH/Pipe vector; the new policy changes no Values body.
  assert.equal(vector(pin('a8f1bbabb5eeda9287716c651b398d1c0954201c985b5c70ccb78d96a9ed1416'),
    priorAoA).run.run_definition_cid,
  pin('47752e67dd0f083b491b0110dd181af4fd312905f5ec67952badf7a8adb832fe'));
  // Keep the merged text-retirement vector as an independent baseline.
  assert.equal(vector(pin('8fc336e2b475104366fea9024c38d171a3d18743a63f05b254272e14bedd886d'),
    priorAoA).run.run_definition_cid,
    pin('1a7ded9110cb3d2c27f151ccc75f1c6683c3a4e0316fc0570706a3c169934baf'));
  assert.equal(vector(pin('ecf842ba6846f2dbac5cb8fa42b5b708c14e0ec170fc14d05043a351c0300582'),
    priorAoA).run.run_definition_cid,
    pin('b8f4539c6741e24dd20bdd1ce77f5dc9d0c0466684c6e151e4441bccaaaaca9c'));
  // Freeze the pre-refresh Property Graph vectors as history. The later
  // query grammar pin changes compilation/Run identity, not this Values
  // Unit, cardinality proof or Result Plan. No product issuer is consulted.
  const preRefreshDependencies = {
    unit: pin('bd1d8948bb65f17b94e971ec556f43add62bec77e59fdb3723f588cfe7b76810'),
    proof: pin('b71c7850a144cc4c855e3093c1c198fdcddec92ee8547480e689b74f6e36d563'),
    resultPlan: pin('457f27fe1a1f226e1ebab73824370e2242c003886619e37e4f18ed866c897d3f'),
  };
  const preRefreshGrammar = pin('a008ad4bb4aa68f02a688b00306bc3818de0dae7beae81d977e54e76f156ad5d');
  const preRefreshContract = pin('b1b5ca9f0cbfee0ec8e9502e7b7eba33c0bddb31d6a0284076ec176ebb9cd73f');
  assert.equal(vector(preRefreshGrammar, preRefreshContract,
    preRefreshDependencies).run.run_definition_cid,
    pin('838a90f1bb3ee17c4e8a25db56d1756c5201897f7a1128498832796ff8c18a90'));
  assert.equal(vector(preRefreshGrammar, preRefreshContract,
    preRefreshDependencies,
    pin('8e3203948952a96d5153e9b0300431d29f5c209ce113f14c7f7149d3abac4818')).run.run_definition_cid,
    pin('f2b1556c0f99714896e7ea77c817f174797d3a5e66b3a8c593315ad4365ed77a'));
  // key_columns changes the installed Graph execution contract and hence the
  // current registry-bound Unit. Historical preimages retain their own pins.
  assert.equal(dependencies.unit,
    pin('9a0e59c162b656a2196ee404011eb7a4ec763c8b402dfda359b2cc6dd5aa0e96'));
  assert.equal(dependencies.proof,
    pin('efcf93f32e510db6482caa901dd99a17bbbba43ce64d3be922901a318bcb479b'));
  assert.equal(dependencies.resultPlan,
    pin('f2bc4e444acdf0ff644c912506c021619caa331091bba1d49ec8dd1b67b603ae'));
  const constructorGrammar = pin('2bf8ef0846b81f91fec96548d10dddd8c7e5a82b7db05444b38eefa316779c11');
  assert.equal(vector(constructorGrammar, preRefreshContract, preRefreshDependencies).run.run_definition_cid,
    pin('3e86d58da98d5af468f0cd07aaef40562c46117c099dfa1cb41a2de052f983f3'));
  assert.equal(vector(constructorGrammar, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('6feea7b7aec5bf825c5db7e46123c9b08f72f5fa85e795968e707d4e4d6c16c4'));

  // Preserve the independent INFER predecessor with its original dependency closure.
  assert.equal(vector(pin('8fc336e2b475104366fea9024c38d171a3d18743a63f05b254272e14bedd886d'),
    priorAoA, priorDependencies, barrierCid).run.run_definition_cid,
    pin('7c8730fc4b50e0ae4b5d5b0494d64b6e5b8fe85fe2d3f41c36735642317d0d6c'));
  // Preserve merged main's independently derived INFER vector as history,
  // rather than treating its pre-Property-Graph Unit as a current authority.
  const predecessorUnit = pin('0ec8026865253c45b26d8eb0b9df6e4cb63b64bf7ae19590e6f1fc2aff10879c');
  const predecessorDependencies = {
    unit: predecessorUnit,
    proof: cid({version: 'actql-bound-proof/0.1', inputs: [],
      law_id: 'actql.bound.values', semantic_ref: `unit:${predecessorUnit}#/steps/0`,
      unit: 'rows', value: 2}),
    resultPlan: cid({version: 'actql-result-plan/0.1',
      order: {strategy: 'inherited', terms: []},
      projection: [{input: 'id', output: 'id',
        value_contract_cid: pin('8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d')}],
      result_name: 'answer', unit_definition_cid: predecessorUnit,
      unit_result_name: 'rows', unit_result_ordinal: 0,
      typed_output_port: {carrier: 'relation', name: 'rows',
        row_contract_cid: pin('999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c')}}),
  };
  assert.equal(vector(pin('b176b995f5dc309487656b334cb34e21409f6a9f67f8a10b89ac9c5d6e5db7c2'),
    pin('ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4'),
    predecessorDependencies, barrierCid).run.run_definition_cid,
    pin('be53b8665c7381ddaad2edddf62c211ae07b9eddefa07ec743ce57ea108cac18'));
  // B's DATA and named-SGA checkpoints retain their pre-unification dependency
  // closure. Replacing the current registry must not rewrite their history.
  for (const [grammar, expected] of [
    ['170329dc75f0246794c3c2209461b743f6bb7c856cf81d1cfa34f8154a680741',
      '6e124bb879d2de1400c1113a68f77416134c941de8edd29337ff74839069e631'],
    ['4e911e389d7c72405b29e2ef2ee8051aa5eb397b67e5e6c2bfe6df7e4bf9d7cc',
      'c807da4c26a523be68bdfe1a6d144a3ca799c4c30a5c433af02392ce04bc9901'],
  ]) {
    assert.equal(vector(pin(grammar),
      pin('ce0e1e8935e1c65b8992f2fb0272da80b192d54616c546efd80a0cad87bd4ec4'),
      predecessorDependencies, barrierCid).run.run_definition_cid, pin(expected));
  }
  // The default-WALK grammar changes the template/Plan/Run preimages only.
  // Keep the preceding explicit-mode vector and its unchanged Values roles.
  assert.equal(vector(pin('f8803129b22ca89d078e90e530aaf6238bb3aa8a1da02555fd67a1c5929029b3'),
    preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('784c1a8f2cbc868cf8b4eca126380e29ae2ab2674fd1c111f8c118a8f58edd02'));
  // DATA/CTE/JOIN rule pins likewise leave the Values Unit and Result intact.
  // Retain the intervening default-WALK Run identity, not only its new value.
  assert.equal(vector(pin('f62ef6968a835996f50a9a23da1c1a711943971995208db0906c68523ed7c485'),
    preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('4947c86a57b25e4c12b95b3a549b337f4a7676d77bf04e66e7b8a4c14a801a59'));
  // Preserve main's preceding grammar-bound vector. JOIN scope documentation
  // changes the grammar preimage, not the Values Unit or Result Plan.
  assert.equal(vector(pin('6f98988807520ccf18a96d72b418ca70dcf845bc1f3c1f35458b1adea18c6157'),
    preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('7b2561667a301294b394ce0d5b64e905b9e8fbd30c0d07f8969c4070de53fe72'));
  // Preserve the Graph/definition-row predecessor. Connecting the existing
  // row bridges changes the grammar pin, not the Values dependency closure.
  const rowPredecessor = pin('24f53c1f64028206dbc01f6c3d0c11d991c8c9d512581fdfd007a250315f8bbd');
  assert.equal(vector(rowPredecessor, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('5347f97a234b92717a8495614590b5e4b0a87a4b8bd796f051952ef164988663'));
  assert.equal(vector(rowPredecessor, cid(aoaContract), dependencies, barrierCid).run.run_definition_cid,
    pin('ac34b3b002f08db23c1a394241c6b2666379e27e17ffda269f20d025cbbba97a'));
  assert.equal(vector(grammarCid, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('7e2ae717cb6fa6b82328da3688ee0a4083dc3d78ad2793a4e02da135aceb14c7'));
  assert.equal(current.run.run_definition_cid,
    pin('97c4dacbf36c4d15cd0b936c07a24d75b1d033d92d587e376c2c50ee598ea918'));
  const source = readFileSync('src/run_publication_host/client_values_run_materials_wbtest.mbt', 'utf8');
  assert.ok(source.includes(current.run.run_definition_cid), 'MoonBit fixed expected CID must follow independent preimage');
  const resultSource = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
  assert.ok(resultSource.includes(dependencies.unit));
  assert.ok(resultSource.includes(dependencies.resultPlan), 'MoonBit fixed Result Plan must follow independent preimage');
});
