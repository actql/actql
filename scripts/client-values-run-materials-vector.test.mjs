// Independent, hand-assembled preimages for the fixed MoonBit Values fixture.
// No product compiler/issuer/output is imported. Unchanged dependency CIDs
// are the baseline vector's pins; all affected bodies are rehashed here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {copyFile, mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {valuesDependencyOracle, valuesProgramOracle, valuesPublicationOracle} from './client-values-dependency-oracle.mjs';
import {valuesUnitIdentity, valuesPublicationRowsBinding, valuesResultPlan} from
  './fixtures/string-contract-identities.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

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

test('Values bridge identities retain the pre-String closure and follow current contracts separately', () => {
  const historical = valuesPublicationOracle({legacy: true});
  const oldUnit = valuesUnitIdentity(program, true);
  assert.equal(oldUnit,
    pin('63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9'));
  assert.equal(oldUnit, historical.unit);
  assert.equal(valuesResultPlan(oldUnit).result_plan_logical_cid,
    pin('8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38'));
  assert.deepEqual(['rows', 'bytes'].map(measure =>
    valuesPublicationRowsBinding(oldUnit, 'rows', measure)), historical.bindings);
  const current = valuesPublicationOracle();
  const currentUnit = valuesUnitIdentity(program);
  assert.equal(currentUnit, current.unit);
  assert.notEqual(currentUnit, oldUnit);
  assert.equal(valuesResultPlan(currentUnit).result_plan_logical_cid,
    current.resultPlan);
  assert.deepEqual(['rows', 'bytes'].map(measure =>
    valuesPublicationRowsBinding(currentUnit, 'rows', measure)), current.bindings);
});

test('pre-String Values identities need no installed contract files', async () => {
  const scratch = await createOwnedScratch({parent: '_build/values-history-tests',
    prefix: 'isolated-', label: 'pre-String Values identity'});
  const fixtureRoot = join(scratch.path, 'scripts/fixtures');
  await mkdir(fixtureRoot, {recursive: true});
  for (const name of ['string-contract-identities.mjs', 'pre-string-values-contracts.json']) {
    await copyFile(new URL('./fixtures/' + name, import.meta.url), join(fixtureRoot, name));
  }
  const isolated = await import(pathToFileURL(join(fixtureRoot, 'string-contract-identities.mjs')));
  assert.equal(isolated.valuesUnitIdentity(program, true),
    pin('63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9'));
  const renamed = structuredClone(program);
  renamed.stages[0].results = {'a~/b': renamed.stages[0].results.rows};
  assert.equal(isolated.valuesUnitIdentity(renamed, true),
    pin('87fbe52e6d002927b0ef3808c1e34b64cc05f5fe72636a7b3e3b1bc26b4c55d0'));
  // The current oracle still requires actual installed normative inputs.
  assert.throws(() => isolated.valuesUnitIdentity(program), {code: 'ENOENT'});
  scratch.passed();
});

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
function vector(grammar, aoa, dependencies=priorDependencies, barrierCid=barrier,
  identity={programCid, semanticsCid}) {
  const {programCid, semanticsCid} = identity;
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
  // Freeze all preceding vectors at their pre-membership normative closure.
  const dependencies = valuesDependencyOracle({beforeMembership: true, preTypedJson: true});
  const preMembershipAoA = pin('5f1c2b3b1fc7fb76383ab1ac7cada0c1734bb5d8e21d37b42b6172938c09e951');
  // Retain the complete independent closure from 9e6c8994f. Table text changed
  // the containing source/Program contracts, including source-free Values.
  const currentDependencies = JSON.parse(readFileSync(
    'scripts/fixtures/pre-table-text-values-dependencies.json', 'utf8'));
  const preIntegrated = JSON.parse(readFileSync(
    'scripts/fixtures/pre-abs-integrated-values-identities.json', 'utf8'));
  const installedDependencies = preIntegrated.values_dependencies;
  const prePivot = JSON.parse(readFileSync(
    'scripts/fixtures/pre-pivot-cell-values-identities.json', 'utf8'));
  assert.equal(cid({version: 'actql-local-unit-dependencies/0.1',
    import_interface_cids: [], incoming_gate_contract_cids: [],
    local_body_cid: cid(currentDependencies.local), used_parameter_declarations_cid: cid({}),
    local_contract_closure_cid: cid({version: 'actql-local-contracts/0.1',
      contracts: currentDependencies.contracts}),
    unit_namespace: {node_id: 'source', program_id: 'client-values'}}), currentDependencies.unit);
  assert.equal(cid({version: 'actql-bound-proof/0.1', inputs: [],
    law_id: 'actql.bound.values', semantic_ref: `unit:${currentDependencies.unit}#/steps/0`,
    unit: 'rows', value: 2}), currentDependencies.proof);
  assert.equal(installedDependencies.unit,
    'sha256:57baac1094a6409a29694a5710773734290c763939f7197cada36fd355dc89b1');
  assert.equal(installedDependencies.proof,
    'sha256:7d4194dae4c3cdf2c1832d22f1560821972241ce6e8fcd4094806fafa202cb25');
  assert.equal(installedDependencies.resultPlan,
    'sha256:7874afb01b75c4de3b5b45fc31bfba9b6dfeda257be02495fdd877a12f4a269c');
  const barrierManifest = JSON.parse(readFileSync('spec/manifests/actql-barrier-contracts-0.1.json', 'utf8'));
  const {barrier_contract_manifest_cid: barrierCid, ...barrierPreimage} = barrierManifest;
  assert.equal(cid(barrierPreimage), barrierCid);
  const currentIdentity = preIntegrated.program_identity;
  assert.equal(valuesProgramOracle({beforeMembership:true,preTypedJson:true}).programCid, programCid);
  assert.equal(valuesProgramOracle({beforeMembership:true,preTypedJson:true}).semanticsCid, semanticsCid);
  assert.equal(currentIdentity.programCid, pin('666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac'));
  assert.equal(currentIdentity.semanticsCid, pin('a0c4c52c89c99f580394bf1991b31e543f9789fc6fd0b99cbea2bffb947abc70'));

  const requestIntent = {version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: pin('b'.repeat(64)), parameter_values_cid: parameterValues,
    program_definition_cid: currentIdentity.programCid};
  assert.equal(cid(requestIntent), pin('72ee31475f76b775c75b3911e0d7cc03b05a3eeba0dec0448d2f745a5ca51cfb'));
  const current = vector(grammarCid, cid(aoaContract), valuesDependencyOracle(), barrierCid,
    valuesProgramOracle());
  const graphRowsDependencies = {
    unit:pin('9a0e59c162b656a2196ee404011eb7a4ec763c8b402dfda359b2cc6dd5aa0e96'),
    proof:pin('efcf93f32e510db6482caa901dd99a17bbbba43ce64d3be922901a318bcb479b'),
    resultPlan:pin('f2bc4e444acdf0ff644c912506c021619caa331091bba1d49ec8dd1b67b603ae'),
  };
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
  // Freeze the pre-refresh Graph vectors as history. The later
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
  // Label selection changes the Program schema in the current closure.
  // These values are independently assembled, not copied from compiler output.
  assert.equal(dependencies.unit,
    pin('35a56f0af27269b982e10c93b1afbfaffb4d626ee13ec0eb9692dbbeb0410163'));
  assert.equal(dependencies.proof,
    pin('969de0c587309bab81fe2ec1f77ad3924b5d5a5e08b093c97528401e6455f238'));
  assert.equal(dependencies.resultPlan,
    pin('00db7ecd331e76ca9cd5bc590e3ce59f747ee697b9ea783e82578cf282899d6e'));
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
  assert.equal(vector(rowPredecessor, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('ac34b3b002f08db23c1a394241c6b2666379e27e17ffda269f20d025cbbba97a'));
  // Keep both integrated parents' vectors with their own grammar pins.
  const rowGrammar = pin('dc6a79192190098180af67a8726ecad1519d0c93037e43ad41d45cc288d0ef09');
  const compositionGrammar = pin('cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(vector(rowGrammar, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('7e2ae717cb6fa6b82328da3688ee0a4083dc3d78ad2793a4e02da135aceb14c7'));
  assert.equal(vector(rowGrammar, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('97c4dacbf36c4d15cd0b936c07a24d75b1d033d92d587e376c2c50ee598ea918'));
  assert.equal(vector(compositionGrammar, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('07ba9ca36c06c85c6fdc3e88aaed22d02dff38348fb1d7003aa6ab4108b3654e'));
  assert.equal(vector(compositionGrammar, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('8e2f3659d83e5bdc7058fb2c1044879fea2fdf23bb1ab7266f8b07d544abf0b4'));
  assert.equal(vector(pin("bd3b6c7767656a531df52628453cbff90762a8d6013af432ced62d241d8fdb0a"), preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('fb0b9d9c1e2d0645859c0ce278205aa086b0f6daddf6f12ac2cb568d756b0ed8'));
  const predecessorGrammar = rowPredecessor;
  const beforeSelectionDependencies = {
    unit:pin('9a0e59c162b656a2196ee404011eb7a4ec763c8b402dfda359b2cc6dd5aa0e96'),
    proof:pin('efcf93f32e510db6482caa901dd99a17bbbba43ce64d3be922901a318bcb479b'),
    resultPlan:pin('f2bc4e444acdf0ff644c912506c021619caa331091bba1d49ec8dd1b67b603ae'),
  };
  assert.equal(vector(predecessorGrammar, preMembershipAoA,
    beforeSelectionDependencies, barrierCid).run.run_definition_cid,
    pin('ac34b3b002f08db23c1a394241c6b2666379e27e17ffda269f20d025cbbba97a'));
  // Preserve both normal-merge parents with their original grammar and Unit
  // dependencies. Current text grammar plus definition selection has a new CID.
  const mainGrammar = pin('cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(vector(mainGrammar, preRefreshContract, preRefreshDependencies,
    barrierCid).run.run_definition_cid,
    pin('07ba9ca36c06c85c6fdc3e88aaed22d02dff38348fb1d7003aa6ab4108b3654e'));
  assert.equal(vector(mainGrammar, preMembershipAoA, beforeSelectionDependencies,
    barrierCid).run.run_definition_cid,
    pin('8e2f3659d83e5bdc7058fb2c1044879fea2fdf23bb1ab7266f8b07d544abf0b4'));
  const definitionDependencies = {
    unit:pin('aef305d463bd57cdd2d84c0d89c5494dc3cea2773e1e8fb9dfd6a4dfc6bca115'),
    proof:pin('29635233b75d1ec087bfca5b2b706be26454d4322456b61d820dbf1310317bc4'),
    resultPlan:pin('7bce35b89c9c21d1f9ecd506e7bf103009425557249abb641aab8e7150d5f3eb'),
  };
  assert.equal(vector(pin('7ecc0f8b6d170d5e3452b18912e03892c0e6ca68b5e640b2b03aeacd9dbbb612'),
    preMembershipAoA, definitionDependencies, barrierCid).run.run_definition_cid,
    pin('6a5c24d7320c4edfcd61609c5490463b38df1f0c73b398f01b196f1feff35c80'));
  assert.equal(vector(pin('2422e7815a6d6f6cbc2dd4289da3ba5d98eeb58545c356d45e897627e7ac3a8e'),
    preMembershipAoA, definitionDependencies, barrierCid).run.run_definition_cid,
    pin('33063a0c0762a010768e79c8d6de94682c4dddf66657b3681d9ae57e71630e4e'));
  const labelPredecessorDependencies = {
    unit:pin('d33e17249369d1cfa53e387b80ec7eaa5fd46b985625b64bd81fd0d9e81b04b1'),
    proof:pin('80e66b1b397cf1a0204403c35b46baa56f1873e07da44f5d6a29580f19450d63'),
    resultPlan:pin('01ee6af54d54f1a2db63d43f07d6d930d253c5f54c271172964241ab761f9ed1'),
  };
  assert.equal(vector(pin('b17d94092c747a21caea0eb25ea01d48160d3ed3cacafc0e5a6e1de79307325c'),
    preMembershipAoA, labelPredecessorDependencies, barrierCid).run.run_definition_cid,
    pin('9b4c99b1a37ed73ebb95b51a470c490a15b950740dcc4773f92b8dab979ade6f'));
  const traversalDependencies = {
    unit:pin('18dc8e9fc34fa63d1e5973243b019bda7446f2247c1ed2c5f945366bea8a520a'),
    proof:pin('54124219997d78cedc627fd7f05f4cc236deb36700ab4942f710a1524e3bcc0e'),
    resultPlan:pin('b073b5030c6a53eca1062d6acfeac9d6b8c41efbddc6b7d4d192fc7e3308e366'),
  };
  assert.equal(vector(pin('b631f06f2ad3b4972d2ac2211819a55d40b1ffd4c5ff6e56b726a20f512c106d'),
    preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('b37addde56c74a96dcf6ba4161c6c36a8d66f8bf6d77cc476ed753c29d123042'));
  assert.equal(vector(pin('b631f06f2ad3b4972d2ac2211819a55d40b1ffd4c5ff6e56b726a20f512c106d'),
    preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid,
    pin('33cfcb3f25ea4ace4092ddc986cf36501136c845caa6dc7d6453ed5bf3931fbf'));
  assert.equal(vector(pin('ae383655950a9e0f2d292ffd546e6bf9eb5cb1e9a9d72e86f6086bb917f681b6'),
    preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid,
    pin('81d0f20687086a3a17a81541a6042c1f4c6afb3d4a9a09fceca1f69236e374d2'));
  const mergedDefinitionDependencies = {
    unit:pin('56ea51419a5f42a23d41b6e6e58d0496fabe58da6d6bea1be555bfd0cbbe00fa'),
    proof:pin('c71b51eff535dc79152ac6458b4e3d21758aa3bb0335d143ad5a0899220524d2'),
    resultPlan:pin('4bee979f2e9c5b6bed478ba9df66c3cc677a3af0d3609c0a2d415770d4badd1a'),
  };
  assert.equal(vector(pin('caad49cf67bec4b67c2cb6beed69e7c9f71a80b19f2e8e04535d0d7f1c12cd90'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('4ac75ab91130a87f439df5621d673c5aec12fbe67f3ccc033691d4af5e4abc3b'));
  assert.equal(vector(pin("bd3b6c7767656a531df52628453cbff90762a8d6013af432ced62d241d8fdb0a"), preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid, pin("cb619661631f118d81c0ae5fdfe60240ccde214ca7dd0b6f8c50719adbec95b1"));
  assert.equal(vector(pin("d825ab855369e92f2e4da5e9af19567cdc89e431784b09d19c3b57ef2e9f301a"), preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid, pin("4d639cb6924c87b916878498ce98e61156414ead2b3f974084ae1c9cc92cb9a6"));
  // Retain the label-selection parent's independent preimage.
  assert.equal(vector(pin('2a5854a264c13c65bf7c2ecbc6f59f9ec09e0c590aacc1c8aed6ec247da80067'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('15eabd454afdd1ca560cfef0c575de3207187c972570ce62472afa54dc7593f0'));
  assert.equal(vector(pin('d18da5382cb511e80f179cb24090bec8e6ce5db6601e1acd49727ef31bc947d7'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('cd5765ebdb354d9eee28ccfd922b208d86c275ef83ed06ef898dc89f1ed5b9d6'));
  // Preserve the current main/definition-row parent's independent vector.
  assert.equal(vector(pin('4ac81bd72c110d09c286a0f2d4c5d68d4340a2e6843d75deabd8dbbd9fb26b77'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('48ef7cfc48aa9303ffd61e0820cbec0f32bd767fb5a2d4e5b0fdb1d60bdd290d'));
  // Retain the prior integration and current main as immutable preimages.
  assert.equal(vector(pin('d0207424274d6a5549eff6c16cd7cfa5a1e63e66c627c23bb63f24ec82154180'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('ce86fb3d6d861cac9a29da60c1ede5230e2eb4af39b059137fb6f416938316a4'));
  assert.equal(vector(pin('37e9fadf9ae65bc194ad17b790ce208450550defcdbfb8354ef3c5c9c0cf4f6d'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('cfd9395735fcb60fa33631944f54a49b5865dd7f55116bc26759b0ee72a037b4'));
  assert.equal(vector(pin('542afdc74f52bbb3d9fa721434c2ac54641e01995eb46abee1dbd44252898374'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d798266b5638e543550903b2cc400fcede71b9056fcc9fbac2f1f18ea2e4a503'));
  // Identifier decoding changes the grammar pin, not the Values body.
  // Retain the previous independent preimage; no product issuer is consulted.
  assert.equal(vector(pin('8ac5a6bdc47a98eca02efae3ca1ceadc613bc930bb523c0013fc73a9bb81dcdc'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('3dce46175daa5fb3da4a54fac92158c7be33a0611158ffc6a84b2b5d8c53e13a'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('326eba3f9a470d6a0c5efc2170e7080f9c07af70e4d53ec8e77f1fa2190ee1db'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('f18cc670d9641a309394b03a5fbfae37bc2aaeae1b79be26d0265d3dd77ad225'));
  assert.equal(vector(pin('db34ec6cd234161b5ab72699adfd1bf0cdc1c76673dff09e952bc0255ec3be3b'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('07ff4d409d1ddd89ff0ad64fb8d85ef11129113436bb9bea199a75217b62a194'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('7e6f07d6483d11f68bd0307165b42905695aa7b8960a658b55dab867414b90e2'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('6142f1ad8ada2b424d3ca082151e65f13aa394d92cb026716a21b1d39b4477e8'));
  assert.equal(vector(pin('5ece7453ce5f14cae14389ce1f999bff6fbc1a65cb0f1a3d719c438818795cb9'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d93f8e21b7eae3d9efc48616b4a641f0c063bd9ccad0f5fd71cfa095a3bcd687'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('eb1e2c6f90ed75c3bd443ce1a5f91097c41e13e7a6cc08ccc04bdbdf57476c10'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('86f88781a706f347aaad843f81412335878da151c4258856290b93b1e99b9989'));
  assert.equal(vector(pin('6eadd94b7226575a88196089cb8a63fe54e0a01630d1dfbf7252806f3474d36e'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('205f8330784cae5c7af4cde8f6269e947b46d1f679ed1653512f3e8ef6b7d829'));
  assert.equal(vector(pin('f2bfb4752851d8bf2d92ccb6a239800ffa662d49a60903f6bc9aee7247f8bfad'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d5bd82839e01d0e9866db382b248ce9ed02d24a83dc17f1165403bac604fa5c2'));
  // Preserve each Graph feature parent's complete grammar-bound Run vector.
  assert.equal(vector(pin('064c917539e8fdbf2e0de59a9cfd553e9d645623a56d39ea710f6e2e348193c2'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('012fc2e9a94494173838836f5347a3d2e2aa1cd87d8f3da01a8410ce7cd32a9d'));
  assert.equal(vector(pin('2afc5d41a26a51589b3ad3b647c08dae6ebdb8f135834c227ab97bfd6197bf8a'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('975bce1f654d8967d1f28f3370e3a89cf27c40745749f99d5bebca82bc5d7e15'));
  // Preserve the pre-frame-parameter rules and their independent Run identity.
  assert.equal(vector(pin('88b3e10e85fa88630900251773eb7b2fe5eb00e0714f3668843145fd82e68a8c'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('51ecc5fb9c556efbca40505459a5432303d0bc368879a6859bda4098d38b9166'));
  // Preserve the frame parent's pre-membership Run exactly.
  assert.equal(vector(pin('cb47f1587dd7cb896f57d56d2aab4eacca6cd6fb673ab8f258b777947b142f14'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('8a5db028aab616c7d31ba9bce6a4e1f6249dc434fad5f3720290475a04097e85'));
  // Retain the clean typed-JSON predecessor with its complete admitted closure.
  const priorJsonUnit = pin('97fd52c0bb0ceda3966aac1c36c8cbae802251ba6a33bd0d86694d2382c0414b');
  const priorJsonDependencies = {
    unit: priorJsonUnit,
    proof: cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
      semantic_ref:`unit:${priorJsonUnit}#/steps/0`,unit:'rows',value:2}),
    resultPlan: pin('1aae680fda4f1a0eaee2004e462827d0e8f1feb15cc8c3e002569b73eeeb4aa2'),
  };
  assert.equal(vector(pin('f0f51ba98d23a0b498cf8f4688b64bd77fc30f0702d9a28397efea5c9d758ea7'),
    pin('c75a9f71b8ee159bc77dd4db81d3dc2ba36756af4abfcaf5e32bd88751a9c93f'),
    priorJsonDependencies, barrierCid, {
      programCid:pin('ed4ad86f18214721af7ba7531060f91b918d4976c5d76737aa0793e188dd0137'),
      semanticsCid:pin('b5aaea89158ff2369b6d3d4a2a9468af6b9a7c7be1fbbf8e653c5f5f986d783f'),
    }).run.run_definition_cid,
    pin('809c490a2351d8c474cd9fe8edecd84ebcee7aca6bd25b19128691b35133d790'));
  const priorTypedDependencies = {
    unit: pin('70a8b6f174373e258c106a0a8e8b66d5b61f85de377cda9f11fe87b1f09e2168'),
    resultPlan: pin('2d37e465bf372e6115235bd843172cd85367704c4ba728a7ad1ce57523c81738'),
  };
  priorTypedDependencies.proof = cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
    semantic_ref:`unit:${priorTypedDependencies.unit}#/steps/0`,unit:'rows',value:2});
  assert.equal(vector(pin('e891f9c133e66fbc4649b0cea7968f431e3285fd7f265f3304701eb0110e6816'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', priorTypedDependencies, barrierCid, {
      programCid:pin('666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac'),
      semanticsCid:pin('a0c4c52c89c99f580394bf1991b31e543f9789fc6fd0b99cbea2bffb947abc70'),
    }).run.run_definition_cid,
    pin('3aab6f9f328e3bffb381569f9a10bc93fa88a60785da835ceb2921b1feb6122d'));
  const mainDependencies = valuesDependencyOracle({preTypedJson:true});
  const mainIdentity = valuesProgramOracle({preTypedJson:true});
  assert.equal(mainDependencies.unit, pin('f6226df1609774ec846240e766c1cb44e7b6accad9ebefdc41797147137c9105'));
  assert.equal(mainIdentity.programCid, pin('1be70a67bfbb6438998862777b118114f9c091a9bb4312a14963dd85edc228cd'));
  assert.equal(vector(pin('cf717bd4a252742b0f29f3badb6b0bd1a876833879fc30e6fefec15f95506fb5'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('c344da464982c016fecef4f705743a0fab9937b6dfbbaf5d7d97168a657c6600'));
  // Preserve the prior IFNULL and Graph-difference source closures independently.
  assert.equal(vector(pin('2ab971016048d6d5f3c15dd4f18319b2f7239af4fdfc1829fe0869233be323bb'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('10f3c4f2a1906ab3ee3f4734d2287e9541283f9142f10346a80bce031045da58'));
  assert.equal(vector(pin('efd71d7d2e6495894932d871a093f184332c4c1a8f0350ad9d42d47e391176a0'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('84cb8a6b9e339b8b19658fc149759e92fccba918557900065530a6bf5f78b3c6'));
  assert.equal(vector(pin('a421b76ba7ecd9fcdf5a237643d1af26d9c0bd58075892c61a0e86840891c6e5'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('7f758c489ad5ab297eebaf2615449d163352e7fa8cf69fac14ed3c2b9595bce9'));
  assert.equal(vector(pin('a2fb073e8a80ea2647ac70c61b567c4ba00e692119e5bed3e389622b2920bfa7'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('fd116ad92f5970ff13c332f184638f4486e2ff78aa13e3fbc341d28a9110c142'));
  assert.equal(vector(pin('b43a9bd5a9e433dd164afd4760f583cee1d29e63e8eb65200dc9adbfd54bc095'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('aeaec36c0401892a5b3ccb6b09ded8f9d077a500e36eb9f4650c6cd14a97ea80'));
  assert.equal(vector(pin('2b32c93b38b2741b740f0f960b99995b4551cbfbb3c5a4ca9058e9c897082f75'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('5634ddf170543faa4ad615006ade5a7a1dd268c6d9f077d707458bd210b1cc04'));
  assert.equal(vector(pin('e36194fdba1c86643169c8f10888a05a39ecc0fea7e1189ac1dfaaf1f4ac01f0'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('c43c9af213d8c24dc132f500cadc213814f461912038b362a79dc2d116470d2f'));
  // Freeze the complete pre-JSON Frontend closure at 6ddbe0d3f.
  const beforeJsonAoA = 'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397';
  const beforeJsonDependencies = {
    unit: pin('f6226df1609774ec846240e766c1cb44e7b6accad9ebefdc41797147137c9105'),
    resultPlan: pin('7bcbf32a7cf9af21a5357b41d97634a8ebc75ae14a51465769de4e432e0589d5'),
  };
  beforeJsonDependencies.proof = cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
    semantic_ref:`unit:${beforeJsonDependencies.unit}#/steps/0`,unit:'rows',value:2});
  const beforeJsonIdentity = {programCid:pin('1be70a67bfbb6438998862777b118114f9c091a9bb4312a14963dd85edc228cd'),
    semanticsCid:pin('28d4c59497fdb5603596ab64b674915f4fde1a23e3d1d42db6712cc38f116b2d')};
  // Preserve the pre-statistical-signature grammar-bound Run.
  assert.equal(vector('sha256:33b5a9ea6214ae40f224b7f105632b933b6394dbd6d3f337cbdae20c9c1608ed',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    pin('cd459a94b139de3909f0b0376bdfb42fe2885fe9d7959fe67d2d0bd75ce18176'));
  // Preserve the statistical-signature grammar-bound Run.
  assert.equal(vector('sha256:cfb9547ce2d09997b65f3dc9496985e80c9e51210333b8dc7d5d911a0c3bb29d',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:59d7c9a31639edee1087c0ba2e8dc6e2067e4730c4c7bfc14f41cebd065e0c90');
  // Preserve the union-source grammar-bound Run.
  assert.equal(vector('sha256:8cef04355f736983a0fcb4ce73551596ce04f370be0ab9c1d4400f81263842ae',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:6b74c71135148ba3f6eff9ee0cc6e6ec786658242c1dc9cf874dc5cb66f3bd3f');
  // Preserve the Graph subtraction parent's Run identity.
  assert.equal(vector('sha256:f6691d7e84028f06cef976870509421ba61d6f6310f7f32171f8ad5cf6ad422e',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:9ae3da3e9ce0fbc9dc678c2d5a0d00ba7321f47693249f8c51b67fefe0018af7');
  assert.equal(vector('sha256:76c09e292bf9def41ddb0d40fe5bf59b60483e1a6c2ebde654a54bb3153c4ead',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:7c37b6c976ba6501b6f942b50543ec3894c1b5ab723c7201478d87ea9e165aa4');
  assert.equal(vector(pin('c7db9149ce04b3f85a273f97b5e4b1647e62e352484fb56309f5a347744fe37b'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('2624f666695d785e72040453976d086dc98e7778ac5dfeb5a75ba93cc8f67891'));
  // Preserve the typed-JSON parent with its original complete grammar body.
  // Its dependency closure also retains the predecessor Program schema.
  // These pins come from the independent normative-preimage oracle at
  // d460a16df6e19ffc231e863830e11597a9ca64c1, before the Values cell repair.
  const previousCellDependencies = {
    unit: pin('70a8b6f174373e258c106a0a8e8b66d5b61f85de377cda9f11fe87b1f09e2168'),
    proof: pin('d196a1e53a23de1987933c71ae0047476d855a3911930f0c612267147d57c086'),
    resultPlan: pin('2d37e465bf372e6115235bd843172cd85367704c4ba728a7ad1ce57523c81738'),
  };
  assert.equal(vector(pin('cbf544dd2f03bbf120cb4181a861e3ee5bad66c73680414f563c13ecba2254a6'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('36560241fceee9447094100569f3c391e28ac5a0dcce70ef3cd1d446f8bc7ace'));
  assert.equal(vector(pin('a5d5cf748d303dd303d92b2dede9e60d23ee5fc8439173fd916a2d8d1c702fb6'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('2273330bbd1b44ddc60f67167b8ba9c6a37dd28460c1b303a0c3b87a941ef63b'));
  assert.equal(vector(pin('d53377fb0065ffa0e12bcbd92664d50c03c6ef317e148d632c593cce65d4b922'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('8d0f3153f18ba0d64478dd83dbed1d9141ddf57b5d2176465b3b28c6dbcafdc9'));
  const beforeGraphDependencies = {
  "unit": "sha256:86b9e82b02cce7df5c0a861c7e48f3689ceb65db7e9946ef62e876bf161c16a3",
  "proof": "sha256:4ff04aa1cb1ba627265867e8d8666b12d334310f0b30708f0b22b06c341ada35",
  "resultPlan": "sha256:8ae7b346cc776132bf1dfc3354e30eaee3bc555cbef2358e6b59d21cc745940d"
};
  assert.equal(vector('sha256:f97f4aab9869f21b5d8c75e13bed93c69fa671602020167f68eb196bc65e1ead',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:0f55021c0394bc5cd6b6fa37fa3f30ebad510678911822e8c7b3da6fd557e659');
  // Keep the ordinary typed-JSON/main integration predecessor intact.
  assert.equal(vector('sha256:75eff2143c075f817ae4bc93022b34f3b6a84a48092cb8ec4726a42b791c5c52',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:80cca8baf237d7c1d546d91d221ade151cb78961ffc467dacad95ef2f7b15b91');
  assert.equal(vector('sha256:e8cb271a8e74c8900258d53c9443bbc6bb78694b313a282a1f2807b3ca5137d5',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:e9e1315ed7d55af5076ef8b6507364f7727cf6556d6ee5ad19f3694f4e7813b2');
  // Keep the pre-closure Program schema's complete Values/Run preimage.
  // Current schema requirements change the Unit dependency closure even when
  // this source-free Values Program contains no Graph operation.
  const beforeSchemaClosure = {
    unit: pin('1e8e7830dddd545a741135b8a2eb43d2a96b54d54e97b0d0f01588de0160151d'),
    proof: pin('2218b7cfadddf232c29ccd2e5cc21d9ae1d6d4a1aea6c1fde528f46083d0cb62'),
    resultPlan: pin('1a20a8bf0cacf27e2567535833edaa39ea58eb3a12f1fd0e0b5ccbdb72de1564'),
  };
  assert.equal(vector(pin('3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSchemaClosure, barrierCid, currentIdentity).run.run_definition_cid,
    pin('53df3a5cf53905e1f34890c6a078ad1a59efb035b6d44c602006f44be2290e8b'));
  // Freeze the closure before saved Relation schema declarations changed the
  // Check Environment body. Historical Runs must not inherit current inputs.
  const beforeSavedSchemaDependencies = {
    unit: pin('0561273ab8c70a496f1013d6984da39ce2da7138d1bd912bbf5c3042b61a78ca'),
    proof: pin('1678c0611223e04e8cfcdda054ae370b2d40033706eedc16cae080511f770650'),
    resultPlan: pin('6c75c3eb2ca8dd0e06247cbec633bf787bd3f90882fde43268abcac88f30fce8'),
  };
  // Freeze the source-contract closure before Table-private inputs. Adding a
  // source field changes its registered contract even for this Values-only Unit.
  const beforeTableDependencies = {
    unit: pin('8005b84110e571bd881c8f153f104b6a35e476a7ef6302dc53224d086492b471'),
    proof: pin('0a5ee06cede8dbd3fbefeb008249b49b39d07c694a50c433cd201cb9be9adad2'),
    resultPlan: pin('d6b68f1a47ee1c233db5d072fe8210d89bf942b97236a37dae7acd491882994e'),
  };
  assert.equal(currentDependencies.unit,
    pin('54f5a2da3c5f2439a13630dec8a8098ef550d9befcca8ac298ac22aac3cecd8f'));
  assert.equal(currentDependencies.proof,
    pin('b9b589e8f084c3ba2b8abaf6d888f037d76e56c2ceb23a0120ffe8c027912e8e'));
  assert.equal(currentDependencies.resultPlan,
    pin('6286d2d4d7603a61da71d464c0043b98647e94b1997ae9b1dc94bda51fa34a3a'));
  // Preserve the schema-closure predecessor before qualified-star text routing.
  assert.equal(vector(pin('1b837dfa56c76782890525a6a4d39239a5675d719223c7de0c70231f89efd7d7'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('38827de4f4b56e91af5bdaa6bf3597602ebe53f2ed6947553bc329b08a7e260e'));
  // Freeze the qualified-star predecessor before adding REPLACE grammar.
  assert.equal(vector(pin('efa41daa81570153a600aa1459bf498135d4ac67b1df4555651d6ff879229062'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('7b2ee1d01a0ffe34498c4fc5b5e9d37a4835f139f81125c21728282d7c90b8a2'));
  assert.equal(vector(pin('1995b1527e69dfc30daff86098b01d0fcef393d703c58e4fbf4f6fa980bf890c'),
    preIntegrated.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('e8ccbde9474f668615917422ae4c63081144a1a82ab4ae0f14d2d647aa872f56'));
  assert.equal(vector(pin('a395e9d881fd75019ff99db18016a4cf72f19f14f52856b8f313462e0489c09a'),
    preIntegrated.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('31dc7d61b6fe40c4662a836eecc194ef96aa50548b8327a49b4d95dd0d32f896'));
  // Preserve the fixed-hop predecessor before adding any-direction edge syntax.
  assert.equal(vector(pin('675ce07e2792ad6736f526ffb894e987463ff1eee7f94dfd8e391bcfbfc3dd20'),
    preIntegrated.aoa_contract_cid, beforeTableDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('35c252c2f80d29f142d35879ca8fb1f828e218266faf062494db1f21f4ace648'));
  // Retain the any-direction full-edge Run preimage under its grammar pin.
  assert.equal(vector(pin('3766a009afd7d8e22904ace1507becb871c62c5fb0dd969f7ee0886c17892c55'),
    preIntegrated.aoa_contract_cid, beforeTableDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('f17353ea4d0b6c8c65a30a3069582c42b396dfebf24bbbe7231423c59e4f5e9f'));
  // Retain the abbreviated-edge predecessor without rebinding its saved Run.
  assert.equal(vector(pin('e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3'),
    preIntegrated.aoa_contract_cid, beforeTableDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('21982c4ae013552cb120f9e32e35c672b6c23092e8fa47323d4fabbe5ca00033'));
  // Preserve the constructor-only ARRAY profile before closing reference and
  // aggregate type bypasses. Rehash the complete independent Run preimage.
  assert.equal(vector(pin('eb7c8d7239e90b612a3bca095d29d74a828e47187609a893ff4d7406ac6512a6'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('c46844e63f6f33150c8312b057491f00a6ab775d62ae36bba779c929cdcbae2d'));
  assert.equal(vector(pin('4ce6abb00008cc0752dda4797487ef815287e30d21bc6e1ae5fca3941f7005a9'),
    preIntegrated.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('26501230bde03bc47e0e4e772e4971b048de85af47b9626771a1904375eddd92'));
  // Keep the finite-quantifier predecessor under its original source closure.
  assert.equal(vector(pin('883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135'),
    preIntegrated.aoa_contract_cid, beforeTableDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('ea1d3abc7d1e52de2b35574a26c62cfe8fea84beed67a4e1c6c0afba5d30ffa2'));
  // Preserve main's abbreviated-edge vector with the current Table closure.
  assert.equal(vector(pin('e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('d16ec26dbce7f1c96129d0810e11e437583e31560e3ad7b3e5bf681b0599107a'));
  // Keep both independently authored parent closures after integration.
  assert.equal(vector(pin('3fe077253a1f7ec230316eb1d6cca21d464c5292ea63f95f19ca53052b03ee9f'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('d7a36674c603fb1d3a1b9216e9284222315552dc40d8660b942c308af4c24f48'));
  assert.equal(vector(pin('883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('ebd0959e213d515f8fe993989cc39976660e5a45918ea6fa8951a5a41e08cc4c'));
  // Keep the independently pinned literal-membership parent; it did not
  // include the adopted finite Graph spelling grammar.
  assert.equal(vector(pin('2fca45d69a94d9d91a6903f72007bccb09bf2c945cfca7187d61808222eac60f'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('1e580903177ae141bc703bead4e9164bd200f4d60e7cde63d89dd04ea5be3bf6'));
  // Preserve the combined ARRAY/finite Graph parent before this integration.
  assert.equal(vector(pin('422c4edd4dd34bbf715e3d464a07f8654e51af7bf5bba74c93a13aa6de999968'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('082b73d16ed8513f88c55ce75cd1d1a78043ec08c57c02a757a3eba5e0e4dd54'));
  // Retain the independently authored correlated-expansion parent.
  assert.equal(vector(pin('669a907108617a89e253dcf5d5f5ef88fe14ec46fe84df18bb6e4d22638347f5'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('4ca80c7d99dd7834c8fc281ce2aff63833e52711eb52702c2cc628c361a01af4'));
  // Keep current main's complete parent before combining correlation syntax.
  assert.equal(vector(pin('383eb60f32169402f128cb1e0187b8445ebb33931e75ab035e20d1e434b52ad4'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('8eb2bb63ec3c66f0457ad25820daa0e49bce63c368536b640b2e38b6d79e7bc3'));
  // Keep both complete adopted grammar parents as independent preimages.
  assert.equal(vector(pin('39ed3dd3cca9b11c128c369308bdbd340ee69a5b82c43bc5408b9b66b8e6f0ac'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('d48070d700e2e74ce504796caefec6fc0255d8b998f8f570e02723580949f5b3'));
  assert.equal(vector(pin('38b2c821bd3b65aeeac218ef8300f9bc25a8dba90956fdfda1313651fdebef15'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('9bd9abd436fd9564578f921adcb16ba105274cdaaad118717d08b13d30183a2d'));
  // Preserve the adopted checked-ARRAY parent independently of this integration.
  assert.equal(vector(pin('865d1183ed31a4fe8b1be4e685563b932b6bc65580ed7968f8883ddc82003722'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('561ebef800dd3c16dbd971fe4c709ebf78678133926ec110d6a60714ae04e9ba'));
  // Keep main's complete grammar/Run preimage before the grouping-only surface.
  assert.equal(vector(pin('e14a88db3f98d88cb24edefca31ecd1c0d63f81e152a61d464756a83c5850329'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('3ed63e2c45d68425784a904b0378099fe284027a35e2c3e78d016bdc854f6903'));
  // Grouping-only parent remains an immutable full normative preimage.
  assert.equal(vector(pin('bb311179f5afee3d6e03181b66113f045cbd6190ce4174b32d40ac9a67459a8d'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('af4b746a75926ddcf8a506348a9df55147a10bf9c0b64e4f950d0ec6d513e9d5'));
  // Preserve the grouping-output-alias parent as an independent full preimage.
  assert.equal(vector(pin('4ac55d221c3878197277681acc425497bc6705a864745d4ae004bbcc17915444'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('732a5690b7573d96b3c54114780ee1255ddeab06d15514f65ec24236c1107251'));
  // Preserve the shorthand-ordering Run with its original grammar closure.
  assert.equal(vector(pin('fc3d401cf6db3bf3349114cc019111bbc32a112317d1e397b9573776d9ee7d6b'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('7b7be234b94ec1a22ed33e054e503320c171d39d58c4ed9cf6246e0988f5a460'));
  // Retain the Pipe scalar-aggregate original grammar closure.
  assert.equal(vector(pin('2a433f295994301675ad42d4acc1859474b8e0e31b3583482f057602164c8951'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('13bb9883431cd034e3e9056e249f5c25c01604506736da187bd0d506171d0a07'));
  // Preserve main's complete grammar closure before GROUP BY ALL.
  assert.equal(vector(pin('582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('e5068efe3ea2216fc07cd3373f3ca0ba9af030ea9b7514aa33e75067d209e869'));
  // Retain both published feature closures before the normal main merge.
  assert.equal(vector(pin('209990ef9c813fa9c15f88d4b0898be472b4e4f0068e281512ecfe71769a5d0e'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('0c8106e879020aa6541115ce2199187148b73e07b18170b65ff4c703e8092374'));
  // Both normal-merge parents retain their complete grammar-bound Run.
  assert.equal(vector(pin('de630432fb2b6f3700294801070100e3340fc6ad295c2671fe9c0b3222f16169'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('54454a972b8c176f336e748bff947d614133fc09e4e7ee9138492c7a0f2e748c'));
  assert.equal(vector(pin('ba59c48eb915694484664a7daf7f839e492c36eae44137993f39130793c59672'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('afb2b3cedb82f86b5296376ac0dd10cee8991082c1f05971768059bb52d77e2b'));
  // Preserve both complete BY NAME ON and adopted shorthand-ROWS parents.
  assert.equal(vector(pin('e42554bffefec21c3d2ca451aba842fb7b353b1c2580477916c02a13a540b90c'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('c7f33c1d74c88186b8354a28021c1146e4042115d7e17ae62f9edccf49ddffa4'));
  assert.equal(vector(pin('440dfe0c1508b744e4ce22e6729dc362678785119932aa142aba313dc57b8680'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('64f4e1246e3493acf214c0010568f156f7fefc026fb3c0bb07bf59c5d9dcea2f'));
  // Retain the complete published BY NAME ON grammar-bound original.
  assert.equal(vector(pin('06af2bb4ef4b70809d026cce5a051ad442eba4484a4defd49a097aecdbc9b34e'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('1341bd6588f20cde58f0b89676618dad7fff8e589ea245b622b3d7b1a409d9bb'));
  // Retain the adopted GROUP BY ALL + Table integrated closure separately.
  assert.equal(vector(pin('54d4cdb8d0565a3ddba0098fa7c2066a67d65bb4523de480fc231bb09300478e'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('e853cc5da66441b448d65f7c2fa8b2285daa9b0c1eebf4c8edb2792b01db671d'));
  // Preserve the published INNER original at its independent pre-Table closure.
  assert.equal(vector(pin('bbeffcd367c6ae1a43cafdb7a08a17dc30eb277205a0f461afafab7967990317'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('eed9783fdb6055043260a0e5399d4f544d6f45f4454a1b5f78fec5f44d4ef065'));
  // Preserve the complete adopted strict named-set integrated parent.
  assert.equal(vector(pin('9906ca99d992584822b5450fd7b3a4c898942d57fed790ab02a8a5555454f3ae'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('daf9145193294b0c6f5f98df5b9f8a8b4066d3f85543be47122131bffd0de273'));
  // Preserve the CORRESPONDING author vector at its immutable pre-Table closure.
  assert.equal(vector(pin('4e22dcbfa0254dced78456e62a6e6a002602d510f6acf3116f3d52e41806524f'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('20e54d94d54d3803aba993288e2ce2210dad0c0b18203a3a7cc2e1947c3e6624'));
  // Keep the independently fixed integrated INNER parent before this grammar.
  assert.equal(vector(pin('9b263643848b163c45ca846775d1fa20e91023b694638794959335d284d4c3ff'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('ac0a16e48c0578b1ae4e5c63405220579592cc2fa220461f1f066f05b27b84b8'));
  // Keep the original Pipe DISTINCT grammar under its fixed pre-Table closure.
  assert.equal(vector(pin('49d6bf9a27842b2d8d9c2709677f62d65a359285de99a83f881f109263c65aec'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('d2834b5d214993feb6280e176d6c9310aecfa1a5c59092484293d00a4371e528'));
  // Retain the adopted CORRESPONDING parent with its installed Table closure.
  assert.equal(vector(pin('527460015f7b5021f104bddf356d629de4da58036886e1e28c03df78a52fddbf'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('73b3565c96d7cee01a72fcbb0a7ab76f876dd0745661df556a01f449660a9abe'));
  // Preserve the original MIN MAX DISTINCT vector with its fixed dependency generation.
  assert.equal(vector(pin('63ff6bfc27444dcfefa9b2eac663907c405a58042d681e8afe458f69ddd9356e'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('e40cd007bd1358901d5b312c0f8a9eb2ed3c16667aad81aeeeaa50b88a7d5d91'));
  // Preserve the independently reviewed adopted main grammar and Run preimage.
  assert.equal(vector(pin('a527c53f87782e495ab4e9e53bd4e32c9bb287eecae3887978ece9b908597736'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('1ab3973704c07a95422f01944bff0786c119e082a5a534f4854dcc20c286043f'));
  // Preserve the original COUNTIF DISTINCT vector with its fixed dependency generation.
  assert.equal(vector(pin('8067b40c487a905f89d3c4fb66d6d3deebe7fc9d5e3f52649e2db64465cf91e2'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('c6ac1828f0e78900aba0ef156f9823ae26917f64ffb6802ceeeb87cb645f2000'));
  // Preserve the independently reviewed adopted main grammar and Run preimage.
  assert.equal(vector(pin('36144f485ec2de4496dbb1555a870bd556d5a383466f97633661698575293368'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('eae3c3079613858817d49619cc7b72e87990e39995ab6373b3140125ffd2c6b6'));
  // Preserve the original analytic DISTINCT frame vector with its fixed dependency generation.
  assert.equal(vector(pin('45f35630a2ce2014080976f94214548ae07cc9ef86f005229e3a830bc816411f'),
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('7609abd9743fa5a382782196df757b5ccc7e7808249525ef7995051ea8292259'));
  // Preserve the independently reviewed adopted main grammar and Run preimage.
  assert.equal(vector(pin('b6830c1efdd87ed4ba755a3416c8430f583f5cafc88e2411d62f7aebf0e96d68'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('94b776cf38c8c8468d1b2a2c51b53dea2950a0799f37e83497ecc348bbedae88'));
  // Preserve the original DISTINCT aggregate ORDER vector with its fixed dependency generation.
  assert.equal(vector(pin('9ac12fc761a195c9ad3943da462c356b87f125ddcf42b961dd0f6b41c9e557a1'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('cc2b7721096b7a8c6601dd68b8737809d053e5a3f0cd50955a7fa3a8569e8aeb'));
  // Preserve the independently reviewed adopted main grammar and Run preimage.
  assert.equal(vector(pin('dd0cf33c4527b25af461f42a4f4bd057dcdfa4b50ae017bb92155690b5a5ac73'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('3f22e96d512f36bde8dde361640530ce5a749fb68dc15396faa32cf60bd2a89b'));
  // Preserve the signed-order source and additional fixed parent preimages.
  assert.equal(vector('sha256:f36b20c837ff42642c5ccb147fc236c2c04d99e5dfa08cc63370a9f230d98ece',
    preIntegrated.aoa_contract_cid, currentDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:6aa682a0996249db7e4925fe71838dd078b242dd30efd193d34b35faa22c5ff4');
  assert.equal(vector('sha256:5cd2e4e1e6b40930a9df5addd8486027d22a4e930d682f02ac7eaa44d0d5e329',
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:abc035d01c1cc5622311cbba12c56c960e6eb169aeaf7a2618cd8aa617c96ad3');
  assert.equal(vector(pin('17b95025f2fe4b83389c467ea0b35fb5fcfb571a146ee862ddcc91fea10cb131'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('bfeaee4389acbd2a5f74ff3b909fc1a1255abf4954b2a083ab2d4b8e2cc9ebf8'));
  // The submitted object-star parent predates ABS. Keep its original AoA,
  // Unit and Program dependencies rather than rebinding it to the new schema.
  assert.equal(vector(pin('4943caba75b011ab9aebfc07d4f30ea4a5aefa72c50bc2eab44724cc3e6aaff9'),
    preIntegrated.aoa_contract_cid, installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    pin('093170ff7e898c3ef58a1fd5d3930222b06aafd64bda70ab62f311d1b9ac56df'));
  const objectStarGrammar = JSON.parse(readFileSync(
    'scripts/fixtures/submitted-object-star-grammar.json', 'utf8')).grammar;
  const {grammar_manifest_cid: objectStarCid, ...objectStarBody} = objectStarGrammar;
  assert.equal(cid(objectStarBody), objectStarCid);
  assert.equal(objectStarCid, 'sha256:f403b42dd4a19e8a22629ba7f14f6bb6de754490194277e4f083ae0f08515bb5');
  assert.equal(vector(objectStarCid, preIntegrated.aoa_contract_cid,
    installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:aa93f66a057c74f6f2749d69e9cb0cd580f766e89755e77adb4926779e8aa351');
  // Keep the complete adopted ABS main closure before adding object-star rules.
  assert.equal(vector('sha256:ad974dd510c1491960ebc6c86b0c426fecf6874895e4a0dc00ce07e714e145dc',
    prePivot.aoa_contract_cid, prePivot.values_dependencies,
    prePivot.barrier_contract_manifest_cid, prePivot.program_identity).run.run_definition_cid,
    'sha256:f5f807d4e1879fb67e54f4294afb5525434820e49edae3611d75317a4850c3f2');
  const {grammar_manifest_cid: computedCid, ...computedBody} = JSON.parse(
    readFileSync('scripts/fixtures/submitted-computed-star-grammar.json', 'utf8')).grammar;
  assert.equal(cid(computedBody), computedCid);
  assert.equal(vector(computedCid, preIntegrated.aoa_contract_cid,
    installedDependencies, barrierCid, currentIdentity).run.run_definition_cid,
    'sha256:258d5e590237fc06d812a6ca075f620e6cd5220a5e21b14b949e376462a58838');
  const {grammar_manifest_cid: integratedCid, ...integratedBody} = JSON.parse(
    readFileSync('scripts/fixtures/integrated-object-star-grammar.json', 'utf8')).grammar;
  assert.equal(cid(integratedBody), integratedCid);
  assert.equal(vector(integratedCid, prePivot.aoa_contract_cid, prePivot.values_dependencies,
    prePivot.barrier_contract_manifest_cid, prePivot.program_identity).run.run_definition_cid,
    'sha256:2706813ed3f0c7f86439323e3486f7be49f1377ec955ff9414bb91ead605b74a');
  // Upstream's pre-UNNEST-JOIN report retains its pre-pivot Unit closure.
  const unnestPrior = JSON.parse(readFileSync('scripts/fixtures/pre-unnest-join-grammar.json', 'utf8'));
  assert.deepEqual(unnestPrior.grammar, prePivot.grammar);
  const unnestPriorRun = vector(prePivot.grammar.grammar_manifest_cid, prePivot.aoa_contract_cid,
    prePivot.values_dependencies, prePivot.barrier_contract_manifest_cid,
    prePivot.program_identity);
  assert.deepEqual(unnestPriorRun, unnestPrior.run_preimages);
  assert.equal(unnestPriorRun.run.run_definition_cid,
    'sha256:6e1a597d8e0473c402cca0fd54e582189c4d1da5064aadab98a647bb6888f645');
  const frontier = JSON.parse(readFileSync('scripts/fixtures/pre-b408-spec-repair-values-identities.json', 'utf8'));
  const {grammar_manifest_cid: upstreamGrammarCid, ...upstreamGrammarBody} = frontier.upstream.grammar;
  assert.equal(cid(upstreamGrammarBody), upstreamGrammarCid);
  const upstreamRun = vector(frontier.upstream.grammar.grammar_manifest_cid, prePivot.aoa_contract_cid,
    prePivot.values_dependencies, prePivot.barrier_contract_manifest_cid, prePivot.program_identity);
  assert.deepEqual(upstreamRun, frontier.upstream.run_preimages);
  assert.equal(upstreamRun.run.run_definition_cid,
    'sha256:cf1e1ea739a4345c77648eecf9a605ff2b29d905a99b92e36b8dd923e9a2256f');
  const repair = frontier.prior_repair;
  const {grammar_manifest_cid: repairedGrammarCid, ...repairedGrammarBody} = repair.grammar;
  assert.equal(cid(repairedGrammarBody), repairedGrammarCid);
  assert.equal(repairedGrammarCid,
    'sha256:30e6c2f83ccbeb15f883b544eb6930c305c04f8615a5ddc9c3bf72e48e60c59e');
  const priorRepairRun = vector(repair.grammar.grammar_manifest_cid, repair.aoa_contract_cid,
    repair.values_dependencies, repair.barrier_contract_manifest_cid, repair.program_identity);
  assert.deepEqual(priorRepairRun, repair.run_preimages);
  assert.equal(priorRepairRun.run.run_definition_cid,
    'sha256:9df95b27d6544fc6562aba55125b2ad0107cd901997472ff69d34fbe54d7dfe8');
  // Preserve the historical fixed Values dependency pins independently of
  // the current installed Unit closure and the admitted pre-INNER grammar.
  const beforeInner = JSON.parse(readFileSync('scripts/fixtures/pre-inner-unnest-grammar.json', 'utf8'));
  assert.equal(vector(beforeInner.grammar.grammar_manifest_cid, cid(aoaContract),
    {unit: 'sha256:144ed73757cc9031b73cd0486f071f5665fa3c31fe1c16b1909dc22ab27c5019',
      proof: 'sha256:23556dc2984da89c117f67c9b748e73276ecc3ea127cc5ec65b4ff9099513609',
      resultPlan: 'sha256:052e01a129b2f7b23f7939a250147d5cbf574605929e1fb3bfc7b32ea95e89d0'},
    barrierCid, valuesProgramOracle()).run.run_definition_cid,
    'sha256:c722ca1804be855d18760dcc77cdbb456e9141f8040617c41a0a3e170a4beaab');
  assert.deepEqual(vector(beforeInner.grammar.grammar_manifest_cid, cid(aoaContract),
    valuesDependencyOracle(), barrierCid, valuesProgramOracle()), beforeInner.run_preimages);
  assert.equal(beforeInner.run_preimages.run.run_definition_cid,
    'sha256:1b7df752d0877ff475733274142e95adf2e1e91f790f0932fa529b23d2d8d982');
  // Keep the preceding complete grammar and independently reconstructed Run.
  const beforeExtend = JSON.parse(readFileSync('scripts/fixtures/pre-pipe-extend-window-grammar.json', 'utf8'));
  assert.deepEqual(vector(beforeExtend.grammar.grammar_manifest_cid, cid(aoaContract),
    valuesDependencyOracle(), barrierCid, valuesProgramOracle()), beforeExtend.run_preimages);
  assert.equal(beforeExtend.run_preimages.run.run_definition_cid,
    'sha256:4dcc3babd5aabc3c35d8dc797702bad73e828d8f09881b89c792b394ffcfec10');
  const beforePipeSelect = JSON.parse(readFileSync('scripts/fixtures/pre-pipe-select-window-grammar.json', 'utf8'));
  assert.deepEqual(vector(beforePipeSelect.grammar.grammar_manifest_cid, cid(aoaContract),
    valuesDependencyOracle(), barrierCid, valuesProgramOracle()), beforePipeSelect.run_preimages);
  assert.equal(beforePipeSelect.run_preimages.run.run_definition_cid,
    'sha256:436bf4c3edf01dc70bb6b1258516807ad35c4d9f9fd5485a9876c704c2aba9ec');
  const beforeWhere = JSON.parse(readFileSync('scripts/fixtures/pre-pipe-where-window-grammar.json', 'utf8'));
  assert.deepEqual(vector(beforeWhere.grammar.grammar_manifest_cid, cid(aoaContract),
    valuesDependencyOracle(), barrierCid, valuesProgramOracle()), beforeWhere.run_preimages);
  assert.equal(beforeWhere.run_preimages.run.run_definition_cid,
    'sha256:02061c277b626444a02a26037851c14b49ea2fd7064a423eab92f17e3bc33799');
  assert.equal(current.run.run_definition_cid,
    'sha256:f0fc9b3b44633c03def0118d8d40e4d34068720763fa744e1d161f57541839a5');

  const outputSource = readFileSync('src/run_publication_host/client_values_run_materials_wbtest.mbt','utf8');
  assert.ok(outputSource.includes(current.run.run_definition_cid));
  const source = readFileSync('src/run_publication_host/client_values_run_materials_wbtest.mbt', 'utf8');

  const resultSource = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
  assert.ok(resultSource.includes(valuesDependencyOracle().unit));
  assert.ok(resultSource.includes(valuesDependencyOracle().resultPlan), 'MoonBit fixed Result Plan must follow independent preimage');
});

test('pre-pivot Values closure preserves its complete independent preimages', () => {
  const frozen = JSON.parse(readFileSync('scripts/fixtures/pre-pivot-cell-values-identities.json', 'utf8'));
  const {local, contracts, unit, proof, resultPlan} = frozen.values_dependencies;
  assert.equal(cid({version: 'actql-local-unit-dependencies/0.1',
    import_interface_cids: [], incoming_gate_contract_cids: [],
    local_body_cid: cid(local), used_parameter_declarations_cid: cid({}),
    local_contract_closure_cid: cid({version: 'actql-local-contracts/0.1', contracts}),
    unit_namespace: {node_id: 'source', program_id: 'client-values'}}), unit);
  assert.equal(unit, 'sha256:d1962490d7dde1e5da1d312769b09f0b33d90ad90f6236efeb34432fe71212b7');
  assert.equal(cid({version: 'actql-bound-proof/0.1', inputs: [],
    law_id: 'actql.bound.values', semantic_ref: `unit:${unit}#/steps/0`, unit: 'rows', value: 2}), proof);
  assert.equal(cid({version: 'actql-result-plan/0.1', order: {strategy: 'inherited', terms: []},
    projection: [{input: 'id', output: 'id', value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    result_name: 'answer', unit_definition_cid: unit, unit_result_name: 'rows', unit_result_ordinal: 0,
    typed_output_port: {carrier: 'relation', name: 'rows', row_contract_cid:
      'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c'}}), resultPlan);
  assert.equal(cid(frozen.program_identity.semantics), frozen.program_identity.semanticsCid);
  assert.equal(cid(frozen.program_identity.definition), frozen.program_identity.programCid);
  const {grammar_manifest_cid: grammarCid, ...grammarBody} = frozen.grammar;
  assert.equal(cid(grammarBody), grammarCid);
});

test('current contract inputs independently determine the Values Run and consuming fixtures', () => {
  const grammar = JSON.parse(readFileSync('spec/manifests/actql-grammar-0.1.json', 'utf8'));
  const aoa = JSON.parse(readFileSync('spec/contracts/actql-aoa.json', 'utf8'));
  const barrier = JSON.parse(readFileSync('spec/manifests/actql-barrier-contracts-0.1.json', 'utf8'));
  const dependencies = valuesDependencyOracle();
  const identity = valuesProgramOracle();
  assert.equal(dependencies.unit, "sha256:c92e431247c59c7e95251836a5070c9540104e26de9fa29dcc4982ab3ace22cd");
  assert.equal(dependencies.proof, "sha256:be2d48e3ce95f9af62fac6659bd1ac679ede500a76df56ffef1c6cd2b472e799");
  assert.equal(dependencies.resultPlan, "sha256:58a66ed5c24ea714ae8d7a6533cd231d83a86404749fd2cda8bb52cee9e7a4a2");
  assert.equal(identity.programCid, "sha256:5b60d2728eeab010cd8cb2ce2efe9f1df250e16bea9826703c2157a6c4a7de34");
  assert.equal(identity.semanticsCid, "sha256:3fcd69e5d4f243505da508a12dfca09b5bb9e0104fcc8f0027d88a052fc317bf");
  const requestIntent = {version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: pin('b'.repeat(64)), parameter_values_cid: parameterValues,
    program_definition_cid: identity.programCid};
  assert.equal(cid(requestIntent), "sha256:8291aeda45155c650ced1f803650313d9c5741f97b70672933a57d6fcffdd32b");
  const current = vector(grammar.grammar_manifest_cid, cid(aoa), dependencies,
    barrier.barrier_contract_manifest_cid, identity);
  assert.equal(current.run.run_definition_cid, "sha256:f0fc9b3b44633c03def0118d8d40e4d34068720763fa744e1d161f57541839a5");
  const runSource = readFileSync('src/run_publication_host/client_values_run_materials_wbtest.mbt', 'utf8');
  assert.ok(runSource.includes(current.run.run_definition_cid));
  const resultSource = readFileSync('src/run_publication_host/client_program_test.mbt', 'utf8');
  assert.ok(resultSource.includes(dependencies.unit));
  assert.ok(resultSource.includes(dependencies.resultPlan));
});


function checkPreAbsValuesPreimages(preAbs) {
  const dependencies = preAbs.values_dependencies;
  const identity = preAbs.values_identity;
  // Hash every stored body and reconstruct the complete Unit preimage from
  // this fixed fixture's normative roles. No current contract or runtime is read.
  const localCid = cid(dependencies.local);
  assert.equal(localCid,
    pin('e3ade8272a250ffbc2ce32000015eb197442341ae03f8d2ccf46707076367c17'));
  assert.equal(identity.semantics.program_template.stages[0].stage_semantics_cid,
    localCid);
  assert.equal(identity.semantics.expression_contract_cid,
    dependencies.local.expression_contract_cid);
  assert.equal(identity.semantics.expression_contract_cid,
    preAbs.grammar.expression_contract_cid);
  assert.equal(cid(identity.semantics), identity.semanticsCid);
  assert.equal(identity.semanticsCid,
    pin('a0c4c52c89c99f580394bf1991b31e543f9789fc6fd0b99cbea2bffb947abc70'));
  assert.deepEqual(identity.definition, {
    version: 'actql-program-definition/0.1', id: 'client-values',
    program_semantics_cid: identity.semanticsCid,
  });
  assert.equal(cid(identity.definition), identity.programCid);
  assert.equal(identity.programCid,
    pin('666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac'));
  assert.deepEqual(dependencies.contracts, [...dependencies.contracts].sort());
  assert.equal(new Set(dependencies.contracts).size, dependencies.contracts.length);
  const closure = {version: 'actql-local-contracts/0.1',
    contracts: dependencies.contracts};
  const unit = {version: 'actql-local-unit-dependencies/0.1',
    import_interface_cids: [], incoming_gate_contract_cids: [],
    local_body_cid: localCid,
    used_parameter_declarations_cid: cid(dependencies.local.parameters),
    local_contract_closure_cid: cid(closure),
    unit_namespace: {node_id: 'source', program_id: 'client-values'}};
  assert.equal(cid(unit), dependencies.unit);
  assert.equal(dependencies.unit,
    pin('54f5a2da3c5f2439a13630dec8a8098ef550d9befcca8ac298ac22aac3cecd8f'));
  assert.equal(cid({version: 'actql-bound-proof/0.1', inputs: [],
    law_id: 'actql.bound.values', semantic_ref: `unit:${dependencies.unit}#/steps/0`,
    unit: 'rows', value: 2}), dependencies.proof);
  assert.equal(cid({version: 'actql-result-plan/0.1',
    order: {strategy: 'inherited', terms: []},
    projection: [{input: 'id', output: 'id', value_contract_cid:
      pin('8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d')}],
    result_name: 'answer', unit_definition_cid: dependencies.unit,
    unit_result_name: 'rows', unit_result_ordinal: 0,
    typed_output_port: {carrier: 'relation', name: 'rows', row_contract_cid:
      pin('999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c')},
  }), dependencies.resultPlan);
}

test('pre-ABS fixture validation rejects changed stored bodies and dependency claims', () => {
  const frozen = JSON.parse(readFileSync('scripts/fixtures/pre-abs-values-identities.json', 'utf8'));
  for (const [name, mutate] of [
    ['semantics body', value => { value.values_identity.semantics.program_template.stages[0].id = 'other'; }],
    ['semantics CID', value => { value.values_identity.semanticsCid = pin('0'.repeat(64)); }],
    ['definition body', value => { value.values_identity.definition.id = 'other'; }],
    ['definition link', value => { value.values_identity.definition.program_semantics_cid = pin('0'.repeat(64)); }],
    ['Program CID', value => { value.values_identity.programCid = pin('0'.repeat(64)); }],
    ['local body', value => { value.values_dependencies.local.local_body.steps[0].values.rows[0].id = 3; }],
    ['removed contract', value => { value.values_dependencies.contracts.pop(); }],
    ['changed contract', value => { value.values_dependencies.contracts[0] = pin('0'.repeat(64)); }],
    ['contract order', value => { value.values_dependencies.contracts.reverse(); }],
    ['Unit CID', value => { value.values_dependencies.unit = pin('0'.repeat(64)); }],
    ['proof CID', value => { value.values_dependencies.proof = pin('0'.repeat(64)); }],
    ['Result Plan CID', value => { value.values_dependencies.resultPlan = pin('0'.repeat(64)); }],
  ]) {
    const changed = structuredClone(frozen);
    mutate(changed);
    assert.throws(() => checkPreAbsValuesPreimages(changed),
      {name: 'AssertionError'}, name);
  }
});

test('baseline and pre-ABS Run preimages retain their original contract closures', () => {
  const baseline = vector(pin('15a180c744c81eea1368e7e31813bb2b3712b9496ba48748973cb94135184914'),
    pin('4b6f51d57ca1d3cb16e28e04eeef20bebee34d4d3b89271de84b982a8ac74005'));
  assert.equal(baseline.template.bound_invocation_template_cid,
    pin('4555d08a720eb232c16ddae70b40cab4b37f8f05bb7b59b754b5981892c3d2dc'));
  assert.equal(baseline.executable.executable_plan_cid,
    pin('9b62027cd9e7ba5b1b8809330a5ff812657f8dae56f238654d4fdff6a4dadf8d'));
  assert.equal(baseline.run.run_definition_cid,
    pin('e80cf974a2d99757867e3d087e88f48245aab36df049d0dd6959d264ec6be7b5'));
  // Pins are checked in normative contracts, not read from generated runtime.
  const preAbs = JSON.parse(readFileSync('scripts/fixtures/pre-abs-values-identities.json', 'utf8'));
  checkPreAbsValuesPreimages(preAbs);
  const grammar = preAbs.grammar;
  const {grammar_manifest_cid: grammarCid, ...grammarPreimage} = grammar;
  assert.equal(cid(grammarPreimage), grammarCid);
  assert.equal(priorDependencies.unit,
    pin('63464270481cf4518c2fcc0be076d6ec2cc7986d53031f0d919ab8d57772eca9'));
  assert.equal(priorDependencies.proof,
    pin('22eca16bd792feacf027e5c5e60463882ad90ad4ac88d19b77719dc174292609'));
  assert.equal(priorDependencies.resultPlan,
    pin('8d2ad95f6f8b7be42c550d922d0614e68be2700bba05d7af2c7e03a4fcbbcc38'));
  // Freeze all preceding vectors at their pre-membership normative closure.
  const dependencies = valuesDependencyOracle({beforeMembership: true, preTypedJson: true});
  const preMembershipAoA = pin('5f1c2b3b1fc7fb76383ab1ac7cada0c1734bb5d8e21d37b42b6172938c09e951');
  const preAbsDependencies = preAbs.values_dependencies;
  const barrierManifest = JSON.parse(readFileSync('spec/manifests/actql-barrier-contracts-0.1.json', 'utf8'));
  const {barrier_contract_manifest_cid: barrierCid, ...barrierPreimage} = barrierManifest;
  assert.equal(cid(barrierPreimage), barrierCid);
  const preAbsIdentity = preAbs.values_identity;
  assert.equal(valuesProgramOracle({beforeMembership:true,preTypedJson:true}).programCid, programCid);
  assert.equal(valuesProgramOracle({beforeMembership:true,preTypedJson:true}).semanticsCid, semanticsCid);
  assert.equal(preAbsIdentity.programCid, pin('666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac'));
  assert.equal(preAbsIdentity.semanticsCid, pin('a0c4c52c89c99f580394bf1991b31e543f9789fc6fd0b99cbea2bffb947abc70'));

  const requestIntent = {version: 'actql-logical-request-intent/0.1',
    caller_input_intent_cid: pin('b'.repeat(64)), parameter_values_cid: parameterValues,
    program_definition_cid: preAbsIdentity.programCid};
  assert.equal(cid(requestIntent), pin('72ee31475f76b775c75b3911e0d7cc03b05a3eeba0dec0448d2f745a5ca51cfb'));
  const preAbsRun = vector(grammarCid, preAbs.aoa_contract_cid, preAbsDependencies, barrierCid,
    preAbsIdentity);
  const graphRowsDependencies = {
    unit:pin('9a0e59c162b656a2196ee404011eb7a4ec763c8b402dfda359b2cc6dd5aa0e96'),
    proof:pin('efcf93f32e510db6482caa901dd99a17bbbba43ce64d3be922901a318bcb479b'),
    resultPlan:pin('f2bc4e444acdf0ff644c912506c021619caa331091bba1d49ec8dd1b67b603ae'),
  };
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
  // Freeze the pre-refresh Graph vectors as history. The later
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
  // Label selection changes the Program schema in the current closure.
  // These values are independently assembled, not copied from compiler output.
  assert.equal(dependencies.unit,
    pin('35a56f0af27269b982e10c93b1afbfaffb4d626ee13ec0eb9692dbbeb0410163'));
  assert.equal(dependencies.proof,
    pin('969de0c587309bab81fe2ec1f77ad3924b5d5a5e08b093c97528401e6455f238'));
  assert.equal(dependencies.resultPlan,
    pin('00db7ecd331e76ca9cd5bc590e3ce59f747ee697b9ea783e82578cf282899d6e'));
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
  assert.equal(vector(rowPredecessor, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('ac34b3b002f08db23c1a394241c6b2666379e27e17ffda269f20d025cbbba97a'));
  // Keep both integrated parents' vectors with their own grammar pins.
  const rowGrammar = pin('dc6a79192190098180af67a8726ecad1519d0c93037e43ad41d45cc288d0ef09');
  const compositionGrammar = pin('cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(vector(rowGrammar, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('7e2ae717cb6fa6b82328da3688ee0a4083dc3d78ad2793a4e02da135aceb14c7'));
  assert.equal(vector(rowGrammar, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('97c4dacbf36c4d15cd0b936c07a24d75b1d033d92d587e376c2c50ee598ea918'));
  assert.equal(vector(compositionGrammar, preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('07ba9ca36c06c85c6fdc3e88aaed22d02dff38348fb1d7003aa6ab4108b3654e'));
  assert.equal(vector(compositionGrammar, preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid,
    pin('8e2f3659d83e5bdc7058fb2c1044879fea2fdf23bb1ab7266f8b07d544abf0b4'));
  assert.equal(vector(pin("bd3b6c7767656a531df52628453cbff90762a8d6013af432ced62d241d8fdb0a"), preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('fb0b9d9c1e2d0645859c0ce278205aa086b0f6daddf6f12ac2cb568d756b0ed8'));
  const predecessorGrammar = rowPredecessor;
  const beforeSelectionDependencies = {
    unit:pin('9a0e59c162b656a2196ee404011eb7a4ec763c8b402dfda359b2cc6dd5aa0e96'),
    proof:pin('efcf93f32e510db6482caa901dd99a17bbbba43ce64d3be922901a318bcb479b'),
    resultPlan:pin('f2bc4e444acdf0ff644c912506c021619caa331091bba1d49ec8dd1b67b603ae'),
  };
  assert.equal(vector(predecessorGrammar, preMembershipAoA,
    beforeSelectionDependencies, barrierCid).run.run_definition_cid,
    pin('ac34b3b002f08db23c1a394241c6b2666379e27e17ffda269f20d025cbbba97a'));
  // Preserve both normal-merge parents with their original grammar and Unit
  // dependencies. Current text grammar plus definition selection has a new CID.
  const mainGrammar = pin('cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(vector(mainGrammar, preRefreshContract, preRefreshDependencies,
    barrierCid).run.run_definition_cid,
    pin('07ba9ca36c06c85c6fdc3e88aaed22d02dff38348fb1d7003aa6ab4108b3654e'));
  assert.equal(vector(mainGrammar, preMembershipAoA, beforeSelectionDependencies,
    barrierCid).run.run_definition_cid,
    pin('8e2f3659d83e5bdc7058fb2c1044879fea2fdf23bb1ab7266f8b07d544abf0b4'));
  const definitionDependencies = {
    unit:pin('aef305d463bd57cdd2d84c0d89c5494dc3cea2773e1e8fb9dfd6a4dfc6bca115'),
    proof:pin('29635233b75d1ec087bfca5b2b706be26454d4322456b61d820dbf1310317bc4'),
    resultPlan:pin('7bce35b89c9c21d1f9ecd506e7bf103009425557249abb641aab8e7150d5f3eb'),
  };
  assert.equal(vector(pin('7ecc0f8b6d170d5e3452b18912e03892c0e6ca68b5e640b2b03aeacd9dbbb612'),
    preMembershipAoA, definitionDependencies, barrierCid).run.run_definition_cid,
    pin('6a5c24d7320c4edfcd61609c5490463b38df1f0c73b398f01b196f1feff35c80'));
  assert.equal(vector(pin('2422e7815a6d6f6cbc2dd4289da3ba5d98eeb58545c356d45e897627e7ac3a8e'),
    preMembershipAoA, definitionDependencies, barrierCid).run.run_definition_cid,
    pin('33063a0c0762a010768e79c8d6de94682c4dddf66657b3681d9ae57e71630e4e'));
  const labelPredecessorDependencies = {
    unit:pin('d33e17249369d1cfa53e387b80ec7eaa5fd46b985625b64bd81fd0d9e81b04b1'),
    proof:pin('80e66b1b397cf1a0204403c35b46baa56f1873e07da44f5d6a29580f19450d63'),
    resultPlan:pin('01ee6af54d54f1a2db63d43f07d6d930d253c5f54c271172964241ab761f9ed1'),
  };
  assert.equal(vector(pin('b17d94092c747a21caea0eb25ea01d48160d3ed3cacafc0e5a6e1de79307325c'),
    preMembershipAoA, labelPredecessorDependencies, barrierCid).run.run_definition_cid,
    pin('9b4c99b1a37ed73ebb95b51a470c490a15b950740dcc4773f92b8dab979ade6f'));
  const traversalDependencies = {
    unit:pin('18dc8e9fc34fa63d1e5973243b019bda7446f2247c1ed2c5f945366bea8a520a'),
    proof:pin('54124219997d78cedc627fd7f05f4cc236deb36700ab4942f710a1524e3bcc0e'),
    resultPlan:pin('b073b5030c6a53eca1062d6acfeac9d6b8c41efbddc6b7d4d192fc7e3308e366'),
  };
  assert.equal(vector(pin('b631f06f2ad3b4972d2ac2211819a55d40b1ffd4c5ff6e56b726a20f512c106d'),
    preRefreshContract, preRefreshDependencies, barrierCid).run.run_definition_cid,
    pin('b37addde56c74a96dcf6ba4161c6c36a8d66f8bf6d77cc476ed753c29d123042'));
  assert.equal(vector(pin('b631f06f2ad3b4972d2ac2211819a55d40b1ffd4c5ff6e56b726a20f512c106d'),
    preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid,
    pin('33cfcb3f25ea4ace4092ddc986cf36501136c845caa6dc7d6453ed5bf3931fbf'));
  assert.equal(vector(pin('ae383655950a9e0f2d292ffd546e6bf9eb5cb1e9a9d72e86f6086bb917f681b6'),
    preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid,
    pin('81d0f20687086a3a17a81541a6042c1f4c6afb3d4a9a09fceca1f69236e374d2'));
  const mergedDefinitionDependencies = {
    unit:pin('56ea51419a5f42a23d41b6e6e58d0496fabe58da6d6bea1be555bfd0cbbe00fa'),
    proof:pin('c71b51eff535dc79152ac6458b4e3d21758aa3bb0335d143ad5a0899220524d2'),
    resultPlan:pin('4bee979f2e9c5b6bed478ba9df66c3cc677a3af0d3609c0a2d415770d4badd1a'),
  };
  assert.equal(vector(pin('caad49cf67bec4b67c2cb6beed69e7c9f71a80b19f2e8e04535d0d7f1c12cd90'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('4ac75ab91130a87f439df5621d673c5aec12fbe67f3ccc033691d4af5e4abc3b'));
  assert.equal(vector(pin("bd3b6c7767656a531df52628453cbff90762a8d6013af432ced62d241d8fdb0a"), preMembershipAoA, graphRowsDependencies, barrierCid).run.run_definition_cid, pin("cb619661631f118d81c0ae5fdfe60240ccde214ca7dd0b6f8c50719adbec95b1"));
  assert.equal(vector(pin("d825ab855369e92f2e4da5e9af19567cdc89e431784b09d19c3b57ef2e9f301a"), preMembershipAoA, traversalDependencies, barrierCid).run.run_definition_cid, pin("4d639cb6924c87b916878498ce98e61156414ead2b3f974084ae1c9cc92cb9a6"));
  // Retain the label-selection parent's independent preimage.
  assert.equal(vector(pin('2a5854a264c13c65bf7c2ecbc6f59f9ec09e0c590aacc1c8aed6ec247da80067'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('15eabd454afdd1ca560cfef0c575de3207187c972570ce62472afa54dc7593f0'));
  assert.equal(vector(pin('d18da5382cb511e80f179cb24090bec8e6ce5db6601e1acd49727ef31bc947d7'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('cd5765ebdb354d9eee28ccfd922b208d86c275ef83ed06ef898dc89f1ed5b9d6'));
  // Preserve the current main/definition-row parent's independent vector.
  assert.equal(vector(pin('4ac81bd72c110d09c286a0f2d4c5d68d4340a2e6843d75deabd8dbbd9fb26b77'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('48ef7cfc48aa9303ffd61e0820cbec0f32bd767fb5a2d4e5b0fdb1d60bdd290d'));
  // Retain the prior integration and current main as immutable preimages.
  assert.equal(vector(pin('d0207424274d6a5549eff6c16cd7cfa5a1e63e66c627c23bb63f24ec82154180'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('ce86fb3d6d861cac9a29da60c1ede5230e2eb4af39b059137fb6f416938316a4'));
  assert.equal(vector(pin('37e9fadf9ae65bc194ad17b790ce208450550defcdbfb8354ef3c5c9c0cf4f6d'),
    preMembershipAoA, mergedDefinitionDependencies, barrierCid).run.run_definition_cid,
    pin('cfd9395735fcb60fa33631944f54a49b5865dd7f55116bc26759b0ee72a037b4'));
  assert.equal(vector(pin('542afdc74f52bbb3d9fa721434c2ac54641e01995eb46abee1dbd44252898374'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d798266b5638e543550903b2cc400fcede71b9056fcc9fbac2f1f18ea2e4a503'));
  // Identifier decoding changes the grammar pin, not the Values body.
  // Retain the previous independent preimage; no product issuer is consulted.
  assert.equal(vector(pin('8ac5a6bdc47a98eca02efae3ca1ceadc613bc930bb523c0013fc73a9bb81dcdc'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('3dce46175daa5fb3da4a54fac92158c7be33a0611158ffc6a84b2b5d8c53e13a'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('326eba3f9a470d6a0c5efc2170e7080f9c07af70e4d53ec8e77f1fa2190ee1db'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('f18cc670d9641a309394b03a5fbfae37bc2aaeae1b79be26d0265d3dd77ad225'));
  assert.equal(vector(pin('db34ec6cd234161b5ab72699adfd1bf0cdc1c76673dff09e952bc0255ec3be3b'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('07ff4d409d1ddd89ff0ad64fb8d85ef11129113436bb9bea199a75217b62a194'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('7e6f07d6483d11f68bd0307165b42905695aa7b8960a658b55dab867414b90e2'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('6142f1ad8ada2b424d3ca082151e65f13aa394d92cb026716a21b1d39b4477e8'));
  assert.equal(vector(pin('5ece7453ce5f14cae14389ce1f999bff6fbc1a65cb0f1a3d719c438818795cb9'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d93f8e21b7eae3d9efc48616b4a641f0c063bd9ccad0f5fd71cfa095a3bcd687'));
  // Keep both merged parents' current vectors with their own grammar pins.
  assert.equal(vector(pin('eb1e2c6f90ed75c3bd443ce1a5f91097c41e13e7a6cc08ccc04bdbdf57476c10'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('86f88781a706f347aaad843f81412335878da151c4258856290b93b1e99b9989'));
  assert.equal(vector(pin('6eadd94b7226575a88196089cb8a63fe54e0a01630d1dfbf7252806f3474d36e'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('205f8330784cae5c7af4cde8f6269e947b46d1f679ed1653512f3e8ef6b7d829'));
  assert.equal(vector(pin('f2bfb4752851d8bf2d92ccb6a239800ffa662d49a60903f6bc9aee7247f8bfad'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('d5bd82839e01d0e9866db382b248ce9ed02d24a83dc17f1165403bac604fa5c2'));
  // Preserve each Graph feature parent's complete grammar-bound Run vector.
  assert.equal(vector(pin('064c917539e8fdbf2e0de59a9cfd553e9d645623a56d39ea710f6e2e348193c2'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('012fc2e9a94494173838836f5347a3d2e2aa1cd87d8f3da01a8410ce7cd32a9d'));
  assert.equal(vector(pin('2afc5d41a26a51589b3ad3b647c08dae6ebdb8f135834c227ab97bfd6197bf8a'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('975bce1f654d8967d1f28f3370e3a89cf27c40745749f99d5bebca82bc5d7e15'));
  // Preserve the pre-frame-parameter rules and their independent Run identity.
  assert.equal(vector(pin('88b3e10e85fa88630900251773eb7b2fe5eb00e0714f3668843145fd82e68a8c'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('51ecc5fb9c556efbca40505459a5432303d0bc368879a6859bda4098d38b9166'));
  // Preserve the frame parent's pre-membership Run exactly.
  assert.equal(vector(pin('cb47f1587dd7cb896f57d56d2aab4eacca6cd6fb673ab8f258b777947b142f14'),
    preMembershipAoA, dependencies, barrierCid).run.run_definition_cid,
    pin('8a5db028aab616c7d31ba9bce6a4e1f6249dc434fad5f3720290475a04097e85'));
  // Retain the clean typed-JSON predecessor with its complete admitted closure.
  const priorJsonUnit = pin('97fd52c0bb0ceda3966aac1c36c8cbae802251ba6a33bd0d86694d2382c0414b');
  const priorJsonDependencies = {
    unit: priorJsonUnit,
    proof: cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
      semantic_ref:`unit:${priorJsonUnit}#/steps/0`,unit:'rows',value:2}),
    resultPlan: pin('1aae680fda4f1a0eaee2004e462827d0e8f1feb15cc8c3e002569b73eeeb4aa2'),
  };
  assert.equal(vector(pin('f0f51ba98d23a0b498cf8f4688b64bd77fc30f0702d9a28397efea5c9d758ea7'),
    pin('c75a9f71b8ee159bc77dd4db81d3dc2ba36756af4abfcaf5e32bd88751a9c93f'),
    priorJsonDependencies, barrierCid, {
      programCid:pin('ed4ad86f18214721af7ba7531060f91b918d4976c5d76737aa0793e188dd0137'),
      semanticsCid:pin('b5aaea89158ff2369b6d3d4a2a9468af6b9a7c7be1fbbf8e653c5f5f986d783f'),
    }).run.run_definition_cid,
    pin('809c490a2351d8c474cd9fe8edecd84ebcee7aca6bd25b19128691b35133d790'));
  const priorTypedDependencies = {
    unit: pin('70a8b6f174373e258c106a0a8e8b66d5b61f85de377cda9f11fe87b1f09e2168'),
    resultPlan: pin('2d37e465bf372e6115235bd843172cd85367704c4ba728a7ad1ce57523c81738'),
  };
  priorTypedDependencies.proof = cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
    semantic_ref:`unit:${priorTypedDependencies.unit}#/steps/0`,unit:'rows',value:2});
  assert.equal(vector(pin('e891f9c133e66fbc4649b0cea7968f431e3285fd7f265f3304701eb0110e6816'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', priorTypedDependencies, barrierCid, {
      programCid:pin('666d7674d445fbd6c81cdd499cd8691cf12840b77f90bcff02d7e06af9abfeac'),
      semanticsCid:pin('a0c4c52c89c99f580394bf1991b31e543f9789fc6fd0b99cbea2bffb947abc70'),
    }).run.run_definition_cid,
    pin('3aab6f9f328e3bffb381569f9a10bc93fa88a60785da835ceb2921b1feb6122d'));
  const mainDependencies = valuesDependencyOracle({preTypedJson:true});
  const mainIdentity = valuesProgramOracle({preTypedJson:true});
  assert.equal(mainDependencies.unit, pin('f6226df1609774ec846240e766c1cb44e7b6accad9ebefdc41797147137c9105'));
  assert.equal(mainIdentity.programCid, pin('1be70a67bfbb6438998862777b118114f9c091a9bb4312a14963dd85edc228cd'));
  assert.equal(vector(pin('cf717bd4a252742b0f29f3badb6b0bd1a876833879fc30e6fefec15f95506fb5'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('c344da464982c016fecef4f705743a0fab9937b6dfbbaf5d7d97168a657c6600'));
  // Preserve the prior IFNULL and Graph-difference source closures independently.
  assert.equal(vector(pin('2ab971016048d6d5f3c15dd4f18319b2f7239af4fdfc1829fe0869233be323bb'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('10f3c4f2a1906ab3ee3f4734d2287e9541283f9142f10346a80bce031045da58'));
  assert.equal(vector(pin('efd71d7d2e6495894932d871a093f184332c4c1a8f0350ad9d42d47e391176a0'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('84cb8a6b9e339b8b19658fc149759e92fccba918557900065530a6bf5f78b3c6'));
  assert.equal(vector(pin('a421b76ba7ecd9fcdf5a237643d1af26d9c0bd58075892c61a0e86840891c6e5'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('7f758c489ad5ab297eebaf2615449d163352e7fa8cf69fac14ed3c2b9595bce9'));
  assert.equal(vector(pin('a2fb073e8a80ea2647ac70c61b567c4ba00e692119e5bed3e389622b2920bfa7'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('fd116ad92f5970ff13c332f184638f4486e2ff78aa13e3fbc341d28a9110c142'));
  assert.equal(vector(pin('b43a9bd5a9e433dd164afd4760f583cee1d29e63e8eb65200dc9adbfd54bc095'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('aeaec36c0401892a5b3ccb6b09ded8f9d077a500e36eb9f4650c6cd14a97ea80'));
  assert.equal(vector(pin('2b32c93b38b2741b740f0f960b99995b4551cbfbb3c5a4ca9058e9c897082f75'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('5634ddf170543faa4ad615006ade5a7a1dd268c6d9f077d707458bd210b1cc04'));
  assert.equal(vector(pin('e36194fdba1c86643169c8f10888a05a39ecc0fea7e1189ac1dfaaf1f4ac01f0'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('c43c9af213d8c24dc132f500cadc213814f461912038b362a79dc2d116470d2f'));
  // Freeze the complete pre-JSON Frontend closure at 6ddbe0d3f.
  const beforeJsonAoA = 'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397';
  const beforeJsonDependencies = {
    unit: pin('f6226df1609774ec846240e766c1cb44e7b6accad9ebefdc41797147137c9105'),
    resultPlan: pin('7bcbf32a7cf9af21a5357b41d97634a8ebc75ae14a51465769de4e432e0589d5'),
  };
  beforeJsonDependencies.proof = cid({version:'actql-bound-proof/0.1',inputs:[],law_id:'actql.bound.values',
    semantic_ref:`unit:${beforeJsonDependencies.unit}#/steps/0`,unit:'rows',value:2});
  const beforeJsonIdentity = {programCid:pin('1be70a67bfbb6438998862777b118114f9c091a9bb4312a14963dd85edc228cd'),
    semanticsCid:pin('28d4c59497fdb5603596ab64b674915f4fde1a23e3d1d42db6712cc38f116b2d')};
  // Preserve the pre-statistical-signature grammar-bound Run.
  assert.equal(vector('sha256:33b5a9ea6214ae40f224b7f105632b933b6394dbd6d3f337cbdae20c9c1608ed',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    pin('cd459a94b139de3909f0b0376bdfb42fe2885fe9d7959fe67d2d0bd75ce18176'));
  // Preserve the statistical-signature grammar-bound Run.
  assert.equal(vector('sha256:cfb9547ce2d09997b65f3dc9496985e80c9e51210333b8dc7d5d911a0c3bb29d',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:59d7c9a31639edee1087c0ba2e8dc6e2067e4730c4c7bfc14f41cebd065e0c90');
  // Preserve the union-source grammar-bound Run.
  assert.equal(vector('sha256:8cef04355f736983a0fcb4ce73551596ce04f370be0ab9c1d4400f81263842ae',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:6b74c71135148ba3f6eff9ee0cc6e6ec786658242c1dc9cf874dc5cb66f3bd3f');
  // Preserve the Graph subtraction parent's Run identity.
  assert.equal(vector('sha256:f6691d7e84028f06cef976870509421ba61d6f6310f7f32171f8ad5cf6ad422e',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:9ae3da3e9ce0fbc9dc678c2d5a0d00ba7321f47693249f8c51b67fefe0018af7');
  assert.equal(vector('sha256:76c09e292bf9def41ddb0d40fe5bf59b60483e1a6c2ebde654a54bb3153c4ead',
    beforeJsonAoA, beforeJsonDependencies, barrierCid, beforeJsonIdentity).run.run_definition_cid,
    'sha256:7c37b6c976ba6501b6f942b50543ec3894c1b5ab723c7201478d87ea9e165aa4');
  assert.equal(vector(pin('c7db9149ce04b3f85a273f97b5e4b1647e62e352484fb56309f5a347744fe37b'),
    'sha256:8e3c47ee3e151473304602f49ad1dcdb2c44b3d310a0dac3a41b668d8bdc4397', mainDependencies, barrierCid, mainIdentity).run.run_definition_cid,
    pin('2624f666695d785e72040453976d086dc98e7778ac5dfeb5a75ba93cc8f67891'));
  // Preserve the typed-JSON parent with its original complete grammar body.
  // Its dependency closure also retains the predecessor Program schema.
  // These pins come from the independent normative-preimage oracle at
  // d460a16df6e19ffc231e863830e11597a9ca64c1, before the Values cell repair.
  const previousCellDependencies = {
    unit: pin('70a8b6f174373e258c106a0a8e8b66d5b61f85de377cda9f11fe87b1f09e2168'),
    proof: pin('d196a1e53a23de1987933c71ae0047476d855a3911930f0c612267147d57c086'),
    resultPlan: pin('2d37e465bf372e6115235bd843172cd85367704c4ba728a7ad1ce57523c81738'),
  };
  assert.equal(vector(pin('cbf544dd2f03bbf120cb4181a861e3ee5bad66c73680414f563c13ecba2254a6'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('36560241fceee9447094100569f3c391e28ac5a0dcce70ef3cd1d446f8bc7ace'));
  assert.equal(vector(pin('a5d5cf748d303dd303d92b2dede9e60d23ee5fc8439173fd916a2d8d1c702fb6'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('2273330bbd1b44ddc60f67167b8ba9c6a37dd28460c1b303a0c3b87a941ef63b'));
  assert.equal(vector(pin('d53377fb0065ffa0e12bcbd92664d50c03c6ef317e148d632c593cce65d4b922'),
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', previousCellDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('8d0f3153f18ba0d64478dd83dbed1d9141ddf57b5d2176465b3b28c6dbcafdc9'));
  const beforeGraphDependencies = {
  "unit": "sha256:86b9e82b02cce7df5c0a861c7e48f3689ceb65db7e9946ef62e876bf161c16a3",
  "proof": "sha256:4ff04aa1cb1ba627265867e8d8666b12d334310f0b30708f0b22b06c341ada35",
  "resultPlan": "sha256:8ae7b346cc776132bf1dfc3354e30eaee3bc555cbef2358e6b59d21cc745940d"
};
  assert.equal(vector('sha256:f97f4aab9869f21b5d8c75e13bed93c69fa671602020167f68eb196bc65e1ead',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    'sha256:0f55021c0394bc5cd6b6fa37fa3f30ebad510678911822e8c7b3da6fd557e659');
  // Keep the ordinary typed-JSON/main integration predecessor intact.
  assert.equal(vector('sha256:75eff2143c075f817ae4bc93022b34f3b6a84a48092cb8ec4726a42b791c5c52',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    'sha256:80cca8baf237d7c1d546d91d221ade151cb78961ffc467dacad95ef2f7b15b91');
  assert.equal(vector('sha256:e8cb271a8e74c8900258d53c9443bbc6bb78694b313a282a1f2807b3ca5137d5',
    'sha256:c8768130d38f4999ab2cb4640a273036fe1c822ca580038978d50692f2f0c958', beforeGraphDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    'sha256:e9e1315ed7d55af5076ef8b6507364f7727cf6556d6ee5ad19f3694f4e7813b2');
  // Keep the pre-closure Program schema's complete Values/Run preimage.
  // Current schema requirements change the Unit dependency closure even when
  // this source-free Values Program contains no Graph operation.
  const beforeSchemaClosure = {
    unit: pin('1e8e7830dddd545a741135b8a2eb43d2a96b54d54e97b0d0f01588de0160151d'),
    proof: pin('2218b7cfadddf232c29ccd2e5cc21d9ae1d6d4a1aea6c1fde528f46083d0cb62'),
    resultPlan: pin('1a20a8bf0cacf27e2567535833edaa39ea58eb3a12f1fd0e0b5ccbdb72de1564'),
  };
  assert.equal(vector(pin('3fe450061e6884fc773ecda7492de02dd27a15219a6832e8e490a096e29b1c9a'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSchemaClosure, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('53df3a5cf53905e1f34890c6a078ad1a59efb035b6d44c602006f44be2290e8b'));
  // Freeze the closure before saved Relation schema declarations changed the
  // Check Environment body. Historical Runs must not inherit current inputs.
  const beforeSavedSchemaDependencies = {
    unit: pin('0561273ab8c70a496f1013d6984da39ce2da7138d1bd912bbf5c3042b61a78ca'),
    proof: pin('1678c0611223e04e8cfcdda054ae370b2d40033706eedc16cae080511f770650'),
    resultPlan: pin('6c75c3eb2ca8dd0e06247cbec633bf787bd3f90882fde43268abcac88f30fce8'),
  };
  // Freeze the source-contract closure before Table-private inputs. Adding a
  // source field changes its registered contract even for this Values-only Unit.
  const beforeTableDependencies = {
    unit: pin('8005b84110e571bd881c8f153f104b6a35e476a7ef6302dc53224d086492b471'),
    proof: pin('0a5ee06cede8dbd3fbefeb008249b49b39d07c694a50c433cd201cb9be9adad2'),
    resultPlan: pin('d6b68f1a47ee1c233db5d072fe8210d89bf942b97236a37dae7acd491882994e'),
  };
  assert.equal(preAbsDependencies.unit,
    pin('54f5a2da3c5f2439a13630dec8a8098ef550d9befcca8ac298ac22aac3cecd8f'));
  assert.equal(preAbsDependencies.proof,
    pin('b9b589e8f084c3ba2b8abaf6d888f037d76e56c2ceb23a0120ffe8c027912e8e'));
  assert.equal(preAbsDependencies.resultPlan,
    pin('6286d2d4d7603a61da71d464c0043b98647e94b1997ae9b1dc94bda51fa34a3a'));
  // Preserve the schema-closure predecessor before qualified-star text routing.
  assert.equal(vector(pin('1b837dfa56c76782890525a6a4d39239a5675d719223c7de0c70231f89efd7d7'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('38827de4f4b56e91af5bdaa6bf3597602ebe53f2ed6947553bc329b08a7e260e'));
  // Freeze the qualified-star predecessor before adding REPLACE grammar.
  assert.equal(vector(pin('efa41daa81570153a600aa1459bf498135d4ac67b1df4555651d6ff879229062'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('7b2ee1d01a0ffe34498c4fc5b5e9d37a4835f139f81125c21728282d7c90b8a2'));
  assert.equal(vector(pin('1995b1527e69dfc30daff86098b01d0fcef393d703c58e4fbf4f6fa980bf890c'),
    preAbs.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('e8ccbde9474f668615917422ae4c63081144a1a82ab4ae0f14d2d647aa872f56'));
  assert.equal(vector(pin('a395e9d881fd75019ff99db18016a4cf72f19f14f52856b8f313462e0489c09a'),
    preAbs.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('31dc7d61b6fe40c4662a836eecc194ef96aa50548b8327a49b4d95dd0d32f896'));
  // Preserve the fixed-hop predecessor before adding any-direction edge syntax.
  assert.equal(vector(pin('675ce07e2792ad6736f526ffb894e987463ff1eee7f94dfd8e391bcfbfc3dd20'),
    preAbs.aoa_contract_cid, beforeTableDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('35c252c2f80d29f142d35879ca8fb1f828e218266faf062494db1f21f4ace648'));
  // Retain the any-direction full-edge Run preimage under its grammar pin.
  assert.equal(vector(pin('3766a009afd7d8e22904ace1507becb871c62c5fb0dd969f7ee0886c17892c55'),
    preAbs.aoa_contract_cid, beforeTableDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('f17353ea4d0b6c8c65a30a3069582c42b396dfebf24bbbe7231423c59e4f5e9f'));
  // Retain the abbreviated-edge predecessor without rebinding its saved Run.
  assert.equal(vector(pin('e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3'),
    preAbs.aoa_contract_cid, beforeTableDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('21982c4ae013552cb120f9e32e35c672b6c23092e8fa47323d4fabbe5ca00033'));
  // Preserve the constructor-only ARRAY profile before closing reference and
  // aggregate type bypasses. Rehash the complete independent Run preimage.
  assert.equal(vector(pin('eb7c8d7239e90b612a3bca095d29d74a828e47187609a893ff4d7406ac6512a6'),
    pin('6c90f76196a13202ccc6dde7883ea8dcb17708e9a8f00b13f1b4f95267fa2e85'),
    beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('c46844e63f6f33150c8312b057491f00a6ab775d62ae36bba779c929cdcbae2d'));
  assert.equal(vector(pin('4ce6abb00008cc0752dda4797487ef815287e30d21bc6e1ae5fca3941f7005a9'),
    preAbs.aoa_contract_cid, beforeSavedSchemaDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('26501230bde03bc47e0e4e772e4971b048de85af47b9626771a1904375eddd92'));
  // Keep the finite-quantifier predecessor under its original source closure.
  assert.equal(vector(pin('883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135'),
    preAbs.aoa_contract_cid, beforeTableDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('ea1d3abc7d1e52de2b35574a26c62cfe8fea84beed67a4e1c6c0afba5d30ffa2'));
  // Preserve main's abbreviated-edge vector with the current Table closure.
  assert.equal(vector(pin('e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('d16ec26dbce7f1c96129d0810e11e437583e31560e3ad7b3e5bf681b0599107a'));
  // Keep both independently authored parent closures after integration.
  assert.equal(vector(pin('3fe077253a1f7ec230316eb1d6cca21d464c5292ea63f95f19ca53052b03ee9f'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('d7a36674c603fb1d3a1b9216e9284222315552dc40d8660b942c308af4c24f48'));
  assert.equal(vector(pin('883c032ce81e5a9f4a192a1d3c5af36bfa48a3d108945f832d9e1c4e7c13b135'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('ebd0959e213d515f8fe993989cc39976660e5a45918ea6fa8951a5a41e08cc4c'));
  // Keep the independently pinned literal-membership parent; it did not
  // include the adopted finite Graph spelling grammar.
  assert.equal(vector(pin('2fca45d69a94d9d91a6903f72007bccb09bf2c945cfca7187d61808222eac60f'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('1e580903177ae141bc703bead4e9164bd200f4d60e7cde63d89dd04ea5be3bf6'));
  // Preserve the combined ARRAY/finite Graph parent before this integration.
  assert.equal(vector(pin('422c4edd4dd34bbf715e3d464a07f8654e51af7bf5bba74c93a13aa6de999968'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('082b73d16ed8513f88c55ce75cd1d1a78043ec08c57c02a757a3eba5e0e4dd54'));
  // Retain the independently authored correlated-expansion parent.
  assert.equal(vector(pin('669a907108617a89e253dcf5d5f5ef88fe14ec46fe84df18bb6e4d22638347f5'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('4ca80c7d99dd7834c8fc281ce2aff63833e52711eb52702c2cc628c361a01af4'));
  // Keep current main's complete parent before combining correlation syntax.
  assert.equal(vector(pin('383eb60f32169402f128cb1e0187b8445ebb33931e75ab035e20d1e434b52ad4'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('8eb2bb63ec3c66f0457ad25820daa0e49bce63c368536b640b2e38b6d79e7bc3'));
  // Keep both complete adopted grammar parents as independent preimages.
  assert.equal(vector(pin('39ed3dd3cca9b11c128c369308bdbd340ee69a5b82c43bc5408b9b66b8e6f0ac'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('d48070d700e2e74ce504796caefec6fc0255d8b998f8f570e02723580949f5b3'));
  assert.equal(vector(pin('38b2c821bd3b65aeeac218ef8300f9bc25a8dba90956fdfda1313651fdebef15'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('9bd9abd436fd9564578f921adcb16ba105274cdaaad118717d08b13d30183a2d'));
  // Preserve the adopted checked-ARRAY parent independently of this integration.
  assert.equal(vector(pin('865d1183ed31a4fe8b1be4e685563b932b6bc65580ed7968f8883ddc82003722'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('561ebef800dd3c16dbd971fe4c709ebf78678133926ec110d6a60714ae04e9ba'));
  // Keep main's complete grammar/Run preimage before the grouping-only surface.
  assert.equal(vector(pin('e14a88db3f98d88cb24edefca31ecd1c0d63f81e152a61d464756a83c5850329'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('3ed63e2c45d68425784a904b0378099fe284027a35e2c3e78d016bdc854f6903'));
  // Grouping-only parent remains an immutable full normative preimage.
  assert.equal(vector(pin('bb311179f5afee3d6e03181b66113f045cbd6190ce4174b32d40ac9a67459a8d'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('af4b746a75926ddcf8a506348a9df55147a10bf9c0b64e4f950d0ec6d513e9d5'));
  // Preserve the grouping-output-alias parent as an independent full preimage.
  assert.equal(vector(pin('4ac55d221c3878197277681acc425497bc6705a864745d4ae004bbcc17915444'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('732a5690b7573d96b3c54114780ee1255ddeab06d15514f65ec24236c1107251'));
  // Preserve the shorthand-ordering Run with its original grammar closure.
  assert.equal(vector(pin('fc3d401cf6db3bf3349114cc019111bbc32a112317d1e397b9573776d9ee7d6b'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('7b7be234b94ec1a22ed33e054e503320c171d39d58c4ed9cf6246e0988f5a460'));
  // Retain the Pipe scalar-aggregate original grammar closure.
  assert.equal(vector(pin('2a433f295994301675ad42d4acc1859474b8e0e31b3583482f057602164c8951'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('13bb9883431cd034e3e9056e249f5c25c01604506736da187bd0d506171d0a07'));
  // Preserve the complete pre-short-ROWS grammar and independently derived Run.
  assert.equal(vector(pin('582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('e5068efe3ea2216fc07cd3373f3ca0ba9af030ea9b7514aa33e75067d209e869'));
  // Both normal-merge parents retain their complete grammar-bound Run.
  assert.equal(vector(pin('de630432fb2b6f3700294801070100e3340fc6ad295c2671fe9c0b3222f16169'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('54454a972b8c176f336e748bff947d614133fc09e4e7ee9138492c7a0f2e748c'));
  assert.equal(vector(pin('ba59c48eb915694484664a7daf7f839e492c36eae44137993f39130793c59672'),
    preAbs.aoa_contract_cid, preAbsDependencies, barrierCid, preAbsIdentity).run.run_definition_cid,
    pin('afb2b3cedb82f86b5296376ac0dd10cee8991082c1f05971768059bb52d77e2b'));
  assert.equal(preAbsRun.run.run_definition_cid,
    pin('64f4e1246e3493acf214c0010568f156f7fefc026fb3c0bb07bf59c5d9dcea2f'));

});

test('submitted ABS parent retains its original complete Values Run preimage', () => {
  const frozen = JSON.parse(readFileSync('scripts/fixtures/submitted-abs-values-identities.json', 'utf8'));
  const dependencies = frozen.values_dependencies;
  const identity = frozen.values_identity;
  assert.equal(dependencies.unit, 'sha256:6026e7dde65bf0ecb2a95eb67b622d429536c06127ebfda918828d6758343e6f');
  assert.equal(identity.programCid, 'sha256:5b60d2728eeab010cd8cb2ce2efe9f1df250e16bea9826703c2157a6c4a7de34');
  assert.equal(cid({version: 'actql-local-unit-dependencies/0.1',
    import_interface_cids: [], incoming_gate_contract_cids: [],
    local_body_cid: cid(dependencies.local), used_parameter_declarations_cid: cid({}),
    local_contract_closure_cid: cid({version: 'actql-local-contracts/0.1',
      contracts: dependencies.contracts}),
    unit_namespace: {node_id: 'source', program_id: 'client-values'}}), dependencies.unit);
  assert.equal(cid(identity.semantics), identity.semanticsCid);
  assert.equal(cid(identity.definition), identity.programCid);
  assert.equal(vector("sha256:0325886c76522de57048ef35ac3abb43e843e418d92c3b3d40e73a6d5c669222",
    frozen.aoa_contract_cid,
    dependencies, 'sha256:8e3203948952a96d5153e9b0300431d29f5c209ce113f14c7f7149d3abac4818',
    identity).run.run_definition_cid,
    'sha256:ba3a4a4c7d3a5cdb37d678ea03a7f1cb0d75fb4706fc4af96329f1860f1d0f66');
});
