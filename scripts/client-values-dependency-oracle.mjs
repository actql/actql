// Independent hand-assembled Values Unit dependencies. No compiler, issuer,
// runtime package or generated MoonBit output is imported. These are the
// normative roles selected for this fixture, not an inventory from a Plan.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';

const normalize = value => Array.isArray(value) ? value.map(normalize)
  : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key=>[key,normalize(value[key])]))
    : value;
const hash = value => 'sha256:' + createHash('sha256')
  .update(JSON.stringify(normalize(value))).digest('hex');
const body = (file, pointer='') => pointer.split('/').slice(1)
  .reduce((value,key)=>value[key.replaceAll('~1','/').replaceAll('~0','~')],
    JSON.parse(readFileSync(new URL('../'+file,import.meta.url),'utf8')));

const roles = [
  ['spec/contracts/actql-stage-contracts.json','/source'],
  ['spec/contracts/actql-stage-contracts.json','/laws'],
  ['spec/contracts/actql-stage-contracts.json','/schemas/local_contracts'],
  ['spec/contracts/actql-stage-contracts.json','/schemas/local_dependencies'],
  ['spec/contracts/actql-expressions.json'],
  ['spec/contracts/actql-expressions.json','/schemas/fragment/properties/request/properties/text_time_policy'],
  ['spec/contracts/actql-protocol-schemas.json','/schemas/canonical_value_contract'],
  ['spec/contracts/actql-protocol-schemas.json','/artifact_schemas/executable_plan/properties/execution_material/properties/program'],
  ['spec/contracts/actql-check-environment.json'],
  ['spec/contracts/actql-capacity-host-policy.json'],
  ['spec/contracts/actql-consumer-capacity.json'],
  ['spec/contracts/actql-bound-values-law.json'],
  ['spec/contracts/actql-bound-values-wire-law.json'],
  ['spec/contracts/actql-bound-transfer-laws.json'],
  ['spec/contracts/actql-aoa.json','/execution_contracts/REL.values'],
  ['spec/dependencies/aoa-kernel-laws.json'],
  ['spec/dependencies/aoa-rela-scalar-laws.json'],
  ['spec/dependencies/aoa-rela-primitive-laws.json'],
  ['spec/dependencies/aoa-sga-identity-laws.json'],
  ['spec/dependencies/actql-text-time-base.json'],
  ['spec/dependencies/actql-text-time-base.json','/barrier_schema'],
  ['spec/dependencies/actql-text-time-base.json','/source_schema'],
  ['spec/dependencies/actql-text-time-base.json','/evaluation_envelope_schema'],
  ['spec/dependencies/actql-text-time-base-dependencies.json','/regex_grammar'],
  ['spec/dependencies/actql-text-time-base-dependencies.json','/regex_ast_schema'],
  ['spec/dependencies/actql-text-time-base-dependencies.json','/timestamp_pattern_grammar'],
  ['spec/dependencies/actql-text-time-base-dependencies.json','/timestamp_pattern_ast_schema'],
  ['spec/dependencies/actql-text-time-base-dependencies.json','/unicode_semantics'],
  ['spec/dependencies/actql-text-time-unicode-data.json'],
  ['spec/contracts/actql-regex-ast.json'],
  ['spec/grammar/actql-regex-ast-0.1.schema.json'],
  ['spec/contracts/actql-production-profile-schemas.json','/schemas/regex_replacement_ast'],
];

function expressionCid(beforeMembership) {
  const expression = body('spec/contracts/actql-expressions.json');
  if (beforeMembership) delete expression.laws.membership;
  return hash(expression);
}

function contractCid(file, pointer, legacy, beforeMembership=legacy) {
    // Membership alignment changes the containing expression contract.
    // Historical fixtures retain their original normative body and role pins.
    if (beforeMembership && file === 'spec/contracts/actql-expressions.json' && !pointer) {
      return expressionCid(true);
    }
    if (beforeMembership && !legacy && file === 'spec/contracts/actql-check-environment.json') {
      const environment = body(file);
      environment.pushdown_contract_bodies.semantic_dependencies.expression_contract.cid = expressionCid(true);
      return hash(environment);
    }
    // The current Catalog selects the owned Property Graph law even when the
    // fixture itself uses only Relation values. Keep the historical role/body
    // for predecessor vectors; do not silently repin those preimages.
    if (!legacy && file === 'spec/dependencies/aoa-sga-identity-laws.json') {
      return hash(body('spec/dependencies/actql-property-graph-laws.json'));
    }
    // Historical fixtures retain pre-String bodies as well as the original
    // Program grammar and count law. Never rebind old preimages to current laws.
    if (legacy && file === 'spec/dependencies/aoa-kernel-laws.json') {
      return 'sha256:5a79d6cb9b012d0c3871c72e496eec7183948ac81d8ebff91b4f7ee6a59ae19d';
    }
    if (legacy && file === 'spec/dependencies/aoa-rela-scalar-laws.json') {
      return 'sha256:a866ed224e15da7e25b45d4e166b25b6bd6749a31bd7dfacb185391ad3f80122';
    }
    if (legacy && pointer === '/execution_contracts/REL.values') {
      return 'sha256:9dec7cf1abedfb23b0af130ec5e25c7442d28c205a94cad0218b2f5982d44b44';
    }
    if (legacy && file==='spec/contracts/actql-bound-transfer-laws.json') {
      return 'sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911';
    }
    if (legacy && pointer?.endsWith('/properties/program')) {
      return 'sha256:a6bfc4b6c00d89f521ccee9e99e1dbbd7385675fd55478f1536f36f860b1ef0a';
    }
    if (legacy && file === 'spec/contracts/actql-check-environment.json') {
      // Pre-Property-Graph body, independently hashed from main 16d93c2.
      return 'sha256:50a14e0c2454d439df53fc4be570d6e008299ba1005cc442838a985337cb3dd8';
    }
    return hash(body(file,pointer));
}

// The fixed acquired Relation fixture uses the same foundational roles, but
// filter/select do not depend on the Values execution or cardinality laws.
export function relationFixtureContracts({legacy=false,acquired=false}={}) {
  const relationRoles = roles.filter(([file,pointer]) =>
    !file.endsWith('actql-bound-values-law.json') &&
    !file.endsWith('actql-bound-values-wire-law.json') &&
    pointer !== '/execution_contracts/REL.values');
  relationRoles.push(['spec/contracts/actql-bound-relation-laws.json']);
  relationRoles.push(...(acquired ? [
    ['spec/contracts/actql-source-response-policy.json'],
    ['spec/contracts/actql-effective-data-policy.json'],
  ] : [
    ['spec/contracts/actql-stage-contracts.json','/schemas/gate_requirement'],
    ['spec/contracts/actql-stage-contracts.json','/schemas/result_import_interface'],
  ]));
  return relationRoles.map(([file,pointer])=>contractCid(file,pointer,legacy));
}

export function valuesDependencyOracle({legacy=false,beforeMembership=legacy,resultName='rows'}={}) {
  const contracts = roles.map(([file,pointer])=>contractCid(file,pointer,legacy,beforeMembership)).sort();
  const local = {version:'actql-stage-semantics/0.1',binding_references:[],
    bindings:{},parameter_references:[],parameters:{},
    expression_contract_cid:expressionCid(beforeMembership),
    local_body:{effects:{},inputs:{},results:{[resultName]:{fields:['id'],from:'selected'}},
      steps:[{as:'selected',values:{rows:[{id:1},{id:2}],schema:{id:{nullable:false,type:'number'}}}}]}};
  const unit = hash({version:'actql-local-unit-dependencies/0.1',
    import_interface_cids:[],incoming_gate_contract_cids:[],
    local_body_cid:hash(local),used_parameter_declarations_cid:hash({}),
    local_contract_closure_cid:hash({version:'actql-local-contracts/0.1',contracts}),
    unit_namespace:{node_id:'source',program_id:'client-values'}});
  const proof = hash({version:'actql-bound-proof/0.1',inputs:[],
    law_id:'actql.bound.values',semantic_ref:`unit:${unit}#/steps/0`,unit:'rows',value:2});
  // Unchanged row/value contracts are the independently pinned baseline.
  const resultPlan = hash({version:'actql-result-plan/0.1',
    order:{strategy:'inherited',terms:[]},
    projection:[{input:'id',output:'id',value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    result_name:'answer',unit_definition_cid:unit,unit_result_name:resultName,unit_result_ordinal:0,
    typed_output_port:{carrier:'relation',name:resultName,row_contract_cid:
      'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c'}});
  return {unit,proof,resultPlan,contracts,local};
}

// Publication limits for the same synthetic fixture, authored independently
// of the product's bound-witness and publication issuers.
export function valuesPublicationOracle(options={}) {
  const dependencies = valuesDependencyOracle(options);
  const {unit,proof} = dependencies;
  const resultName = options.resultName ?? 'rows';
  const escaped = resultName.replaceAll('~','~0').replaceAll('/','~1');
  const policy = 'sha256:38a92017de0e3e13901d328ab622696708aab0563dd980b04bfc9a2b6c451853';
  const seal = (value,field) => ({...value,[field]:hash(value)});
  const ceiling = measure => seal({version:'actql-bound-witness/0.1',
    dependencies:[policy],derivation:{op:'source'},
    law_id:`actql.host.artifact-${measure}`,role:'host_ceiling',
    source:{field:`max_artifact_${measure}`,kind:'host_policy',policy_cid:policy},
    unit:measure,value:1000},'witness_cid');
  const upper = seal({version:'actql-bound-witness/0.1',dependencies:[proof],
    derivation:{op:'source'},law_id:'actql.bound.values',role:'proven_upper_bound',
    source:{kind:'program',proof_cid:proof,semantic_ref:`unit:${unit}#/steps/0`},
    unit:'rows',value:2},'witness_cid');
  const limits = ['rows','bytes'].map(measure => seal({
    version:'actql-resolved-limit/0.1',author_guard_binding:'absent',breach:'fail',
    candidates:measure==='rows' ? [ceiling(measure),upper] : [ceiling(measure)],
    effective_max:measure==='rows' ? 2 : 1000,enforcement:'engine_atomic',
    subject_ref:`unit:${unit}#/results/${escaped}/${measure}`,unit:measure},
  'resolved_limit_cid'));
  const bindings = limits.map(value => seal({version:'actql-execution-limit-binding/0.1',
    effective_max:value.effective_max,resolved_limit_cid:value.resolved_limit_cid,
    subject_ref:value.subject_ref,target:{kind:'result_publication',measure:value.unit,
      result_name:resultName,unit_definition_cid:unit},unit:value.unit},'binding_cid'));
  return {...dependencies,limits,bindings};
}

// Closed Program/Definition envelopes for the same independently authored
// two-row fixture. Historical identity inputs remain selectable explicitly.
export function valuesProgramOracle(options={}) {
  const {local} = valuesDependencyOracle(options);
  const semantics = {version:'actql-program-semantics/0.1',actql_version:'actql/0.1',
    expression_contract_cid:local.expression_contract_cid,
    parameters:{},parameter_references:[],bindings:{},binding_references:[],
    program_template:{stages:[{id:'source',after:'initial',imports:{},
      stage_semantics_cid:hash(local)}],
    exports:{answer:{from:{stage:'source',result:'rows'}}}}};
  const semanticsCid = hash(semantics);
  const definition = {version:'actql-program-definition/0.1',id:'client-values',
    program_semantics_cid:semanticsCid};
  return {semantics,semanticsCid,definition,programCid:hash(definition)};
}
