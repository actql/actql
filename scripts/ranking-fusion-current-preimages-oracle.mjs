// Independent hand-assembled Values Run fixture; this reuses the fixed input
// rows and policy slots, never product/compiler/issuer output or generated pins.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {valuesDependencyOracle, valuesProgramOracle} from './client-values-dependency-oracle.mjs';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
const cid=value=>'sha256:'+createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
const seal=(body,field)=>({...body,[field]:cid(body)});
const pin=hex=>'sha256:'+hex;
const fixed=read('scripts/fixtures/submitted-nearest-join-values-identities.json');
const material=fixed.run_preimages.executable.execution_material;
const environment=material.check_environment_cid;
const bindings=material.invocation_bindings_cid;
const parameterValues=material.parameter_values_cid;
const program=material.program;
const logical=fixed.run_preimages.compiled.aoa_logical_cid;
const {rows,schema}=fixed.run_preimages.executable.nodes[0].pipeline.steps[0].params;
const policy=fixed.run_preimages.executable.bound_witnesses.find(w=>w.role==='host_ceiling').source.policy_cid;
const ceiling=measure=>seal({version:'actql-bound-witness/0.1',dependencies:[policy],derivation:{op:'source'},law_id:`actql.host.artifact-${measure}`,role:'host_ceiling',source:{field:`max_artifact_${measure}`,kind:'host_policy',policy_cid:policy},unit:measure,value:1000},'witness_cid');
const rowCeiling=ceiling('rows'),byteCeiling=ceiling('bytes');
const limit=(measure,candidates,maximum,unit)=>seal({version:'actql-resolved-limit/0.1',author_guard_binding:'absent',breach:'fail',candidates,effective_max:maximum,enforcement:'engine_atomic',subject_ref:`unit:${unit}#/results/rows/${measure}`,unit:measure},'resolved_limit_cid');
function vector(grammar, aoa, dependencies, barrierCid, identity, {canonicalCandidates=true}={}) {
  const {programCid, semanticsCid} = identity;
  const {unit,proof,resultPlan} = dependencies;
  const upper = seal({version: 'actql-bound-witness/0.1', dependencies: [proof],
    derivation: {op: 'source'}, law_id: 'actql.bound.values', role: 'proven_upper_bound',
    source: {kind: 'program', proof_cid: proof, semantic_ref: `unit:${unit}#/steps/0`},
    unit: 'rows', value: 2}, 'witness_cid');
  // Retained vectors keep their exact recorded candidate order. Current
  // limits sort newly identified witnesses before hashing the containing body.
  const rowCandidates = [rowCeiling, upper];
  if (canonicalCandidates) rowCandidates.sort((a, b) =>
    a.witness_cid < b.witness_cid ? -1 : a.witness_cid > b.witness_cid ? 1 : 0);
  const limits = [limit('rows', rowCandidates, 2, unit),
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

export function currentValuesPreimages(grammar,sourceRevision) {
  const values_dependencies=valuesDependencyOracle();
  const program_identity=valuesProgramOracle();
  const aoa_contract_cid=cid(read('spec/contracts/actql-aoa.json'));
  const barrier_contract_manifest_cid=read('spec/manifests/actql-barrier-contracts-0.1.json').barrier_contract_manifest_cid;
  return {source_revision:sourceRevision,prepared:false,grammar,values_dependencies,program_identity,
    aoa_contract_cid,barrier_contract_manifest_cid,
    run_preimages:vector(grammar.grammar_manifest_cid,aoa_contract_cid,values_dependencies,barrier_contract_manifest_cid,program_identity)};
}
