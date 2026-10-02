// Independently selected dependencies for the fixed source-free Values Unit.
// Selection: source grammar/environment, Stage semantics, expression closure,
// Values count/wire/execution, bound transfer and Result primitive rules.
// No compiler, emitted Unit or generated runtime is used.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const ordered = v => Array.isArray(v) ? v.map(ordered) : v && typeof v === 'object'
  ? Object.fromEntries(Object.keys(v).sort().map(k => [k, ordered(v[k])])) : v;
export const independentCid = v => 'sha256:' + createHash('sha256')
  .update(JSON.stringify(ordered(v))).digest('hex');
const selections = [
  [
    "spec/grammar/actql-timestamp-pattern-ast-0.1.schema.json",
    []
  ],
  [
    "spec/grammar/actql-regex-ast-0.1.schema.json",
    []
  ],
  [
    "spec/contracts/actql-regex-ast.json",
    []
  ],
  [
    "spec/contracts/actql-stage-contracts.json",
    [
      "source"
    ]
  ],
  [
    "spec/contracts/actql-stage-contracts.json",
    [
      "schemas",
      "local_contracts"
    ]
  ],
  [
    "spec/contracts/actql-stage-contracts.json",
    [
      "schemas",
      "local_dependencies"
    ]
  ],
  [
    "spec/contracts/actql-stage-contracts.json",
    [
      "laws"
    ]
  ],
  [
    "spec/contracts/actql-capacity-host-policy.json",
    []
  ],
  [
    "spec/contracts/actql-check-environment.json",
    []
  ],
  [
    "spec/contracts/actql-bound-transfer-laws.json",
    []
  ],
  [
    "spec/contracts/actql-aoa.json",
    [
      "execution_contracts",
      "REL.values"
    ]
  ],
  [
    "spec/contracts/actql-bound-values-wire-law.json",
    []
  ],
  [
    "spec/contracts/actql-expressions.json",
    []
  ],
  [
    "spec/contracts/actql-expressions.json",
    [
      "schemas",
      "fragment",
      "properties",
      "request",
      "properties",
      "text_time_policy"
    ]
  ],
  [
    "spec/contracts/actql-bound-values-law.json",
    []
  ],
  [
    "spec/contracts/actql-protocol-schemas.json",
    [
      "schemas",
      "canonical_value_contract"
    ]
  ],
  [
    "spec/contracts/actql-protocol-schemas.json",
    [
      "artifact_schemas",
      "executable_plan",
      "properties",
      "execution_material",
      "properties",
      "program"
    ]
  ],
  [
    "spec/contracts/actql-production-profile-schemas.json",
    [
      "schemas",
      "text_time_expression"
    ]
  ],
  [
    "spec/contracts/actql-production-profile-schemas.json",
    [
      "schemas",
      "text_time_evaluation_envelope"
    ]
  ],
  [
    "spec/contracts/actql-production-profile-schemas.json",
    [
      "schemas",
      "regex_replacement_ast"
    ]
  ],
  [
    "spec/contracts/actql-consumer-capacity.json",
    []
  ],
  [
    "spec/dependencies/aoa-rela-scalar-laws.json",
    []
  ],
  [
    "spec/dependencies/actql-text-time-unicode-data.json",
    []
  ],
  [
    "spec/dependencies/actql-text-time-base-dependencies.json",
    [
      "regex_grammar"
    ]
  ],
  [
    "spec/dependencies/actql-text-time-base-dependencies.json",
    [
      "regex_ast_schema"
    ]
  ],
  [
    "spec/dependencies/actql-text-time-base-dependencies.json",
    [
      "timestamp_pattern_grammar"
    ]
  ],
  [
    "spec/dependencies/actql-text-time-base-dependencies.json",
    [
      "unicode_semantics"
    ]
  ],
  [
    "spec/dependencies/aoa-sga-identity-laws.json",
    []
  ],
  [
    "spec/dependencies/aoa-rela-primitive-laws.json",
    []
  ],
  [
    "spec/dependencies/aoa-kernel-laws.json",
    []
  ],
  [
    "spec/dependencies/actql-text-time-base.json",
    []
  ],
  [
    "spec/dependencies/actql-text-time-base.json",
    [
      "barrier_schema"
    ]
  ]
];
export function valuesContractCids() {
  return selections.map(([path, keys]) => {
    const root = JSON.parse(readFileSync(new URL('../../' + path, import.meta.url), 'utf8'));
    return independentCid(keys.reduce((v, key) => v[key], root));
  }).sort();
}
export const oldStringPins = [
  'sha256:5a79d6cb9b012d0c3871c72e496eec7183948ac81d8ebff91b4f7ee6a59ae19d',
  'sha256:a866ed224e15da7e25b45d4e166b25b6bd6749a31bd7dfacb185391ad3f80122',
  'sha256:9dec7cf1abedfb23b0af130ec5e25c7442d28c205a94cad0218b2f5982d44b44',
];
export function stringPinReplacements() {
  const read = path => JSON.parse(readFileSync(new URL('../../' + path, import.meta.url)));
  return new Map(oldStringPins.map((old, i) => [old, independentCid([
    read('spec/dependencies/aoa-kernel-laws.json'),
    read('spec/dependencies/aoa-rela-scalar-laws.json'),
    read('spec/contracts/actql-aoa.json').execution_contracts['REL.values'],
  ][i])]));
}
export function valuesUnitIdentity(program, old = false) {
  const stage = program.stages[0];
  const expressions = JSON.parse(readFileSync(new URL('../../spec/contracts/actql-expressions.json', import.meta.url)));
  const {id, meta, after, ...localBody} = stage;
  localBody.effects ??= {};
  const body = {version: 'actql-stage-semantics/0.1',
    expression_contract_cid: independentCid(expressions), parameters: {}, bindings: {},
    parameter_references: [], binding_references: [], local_body: localBody};
  let contracts = valuesContractCids();
  if (old) {
    const reverse = new Map([...stringPinReplacements()].map(([a,b]) => [b,a]));
    // The historical pre-exact-string Unit also predates the coordinated
    // bounded-transfer and embedded Program schema changes. Freeze those
    // roles as well; a historical vector must not read their current bodies.
    const read = path => JSON.parse(readFileSync(new URL('../../' + path, import.meta.url)));
    reverse.set(independentCid(read('spec/contracts/actql-bound-transfer-laws.json')),
      'sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911');
    reverse.set(independentCid(read('spec/contracts/actql-protocol-schemas.json')
      .artifact_schemas.executable_plan.properties.execution_material.properties.program),
      'sha256:a6bfc4b6c00d89f521ccee9e99e1dbbd7385675fd55478f1536f36f860b1ef0a');
    contracts = contracts.map(c => reverse.get(c) ?? c).sort();
  }
  return independentCid({version: 'actql-local-unit-dependencies/0.1',
    unit_namespace: {program_id: program.id, node_id: stage.id},
    local_body_cid: independentCid(body), used_parameter_declarations_cid: independentCid({}),
    local_contract_closure_cid: independentCid({version: 'actql-local-contracts/0.1', contracts}),
    import_interface_cids: [], incoming_gate_contract_cids: []});
}

// Hand-authored capacity and Result preimages for the same two-row Unit.
// Port names use RFC 6901 escaping; neither the limit nor its binding is read
// from the runtime under test. Historical fixed CIDs anchor the derivation.
export function valuesPublicationRowsBinding(unit, resultName, measure = 'rows') {
  assert.ok(['rows', 'bytes'].includes(measure));
  const seal = (body, field) => ({...body, [field]: independentCid(body)});
  const policy = 'sha256:38a92017de0e3e13901d328ab622696708aab0563dd980b04bfc9a2b6c451853';
  const proof = independentCid({version: 'actql-bound-proof/0.1', inputs: [],
    law_id: 'actql.bound.values', semantic_ref: `unit:${unit}#/steps/0`,
    unit: 'rows', value: 2});
  const ceiling = seal({version: 'actql-bound-witness/0.1',
    dependencies: [policy], derivation: {op: 'source'},
    law_id: `actql.host.artifact-${measure}`, role: 'host_ceiling',
    source: {field: `max_artifact_${measure}`, kind: 'host_policy', policy_cid: policy},
    unit: measure, value: 1000}, 'witness_cid');
  const upper = seal({version: 'actql-bound-witness/0.1', dependencies: [proof],
    derivation: {op: 'source'}, law_id: 'actql.bound.values', role: 'proven_upper_bound',
    source: {kind: 'program', proof_cid: proof, semantic_ref: `unit:${unit}#/steps/0`},
    unit: 'rows', value: 2}, 'witness_cid');
  const port = resultName.replaceAll('~', '~0').replaceAll('/', '~1');
  const subject = `unit:${unit}#/results/${port}/${measure}`;
  const maximum = measure === 'rows' ? 2 : 1000;
  const limit = seal({version: 'actql-resolved-limit/0.1',
    author_guard_binding: 'absent', breach: 'fail',
    candidates: (measure === 'rows' ? [ceiling, upper] : [ceiling])
      .sort((a,b) => a.witness_cid < b.witness_cid ? -1 : a.witness_cid > b.witness_cid ? 1 : 0),
    effective_max: maximum, enforcement: 'engine_atomic', subject_ref: subject,
    unit: measure}, 'resolved_limit_cid');
  return seal({version: 'actql-execution-limit-binding/0.1', effective_max: maximum,
    resolved_limit_cid: limit.resolved_limit_cid, subject_ref: subject,
    target: {kind: 'result_publication', measure, result_name: resultName,
      unit_definition_cid: unit}, unit: measure}, 'binding_cid');
}

export function valuesResultPlan(unit) {
  const body = {version: 'actql-result-plan/0.1', result_name: 'answer',
    unit_definition_cid: unit, unit_result_name: 'rows', unit_result_ordinal: 0,
    projection: [{input: 'id', output: 'id', value_contract_cid:
      'sha256:8a7be765d273ccfa06d916976f27fcb0404d814371e72c058502335b51b9bd3d'}],
    order: {strategy: 'inherited', terms: []},
    typed_output_port: {carrier: 'relation', name: 'rows', row_contract_cid:
      'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c'}};
  return {...body, result_plan_logical_cid: independentCid(body)};
}

// Fixed acquired/filter/select fixture: independent semantic expressions,
// imported row contracts and prior-Stage success gates, not compiler output.
export function acquiredUnitIdentities(program, environment, old = false) {
  const read = path => JSON.parse(readFileSync(new URL('../../' + path, import.meta.url)));
  const changed = stringPinReplacements();
  let common = valuesContractCids().filter(c => ![
    independentCid(read('spec/contracts/actql-bound-values-law.json')),
    independentCid(read('spec/contracts/actql-bound-values-wire-law.json')),
    changed.get(oldStringPins[2]),
  ].includes(c));
  common.push(independentCid(read('spec/contracts/actql-bound-relation-laws.json')));
  const stages = read('spec/contracts/actql-stage-contracts.json');
  const expressions = independentCid(read('spec/contracts/actql-expressions.json'));
  const reverse = new Map([...changed].map(([a,b]) => [b,a]));
  const units = new Map();
  const predicates = [
    {gt: [{field: 'id'}, {$param: 'minimum'}]},
    {gt: [{field: 'id'}, {literal: 2}]},
    {gt: [{field: 'id'}, {literal: 0}]},
    {lt: [{field: 'id'}, {literal: 9}]},
  ];
  for (const [i, stage] of program.stages.entries()) {
    const {id, meta, after, ...local} = structuredClone(stage);
    local.effects = {};
    local.steps[0].filter = predicates[i];
    const parameters = i === 0 ? program.params : {};
    const body = {version: 'actql-stage-semantics/0.1',
      expression_contract_cid: expressions, local_body: local,
      parameters, bindings: {}, binding_references: [],
      parameter_references: i === 0 ? [{name: 'minimum', path: '/steps/0/filter/gt/1',
        type: parameters.minimum}] : []};
    const extra = i === 0 ? [
      independentCid(read('spec/contracts/actql-effective-data-policy.json')),
      independentCid(read('spec/contracts/actql-source-response-policy.json')),
      ...environment.connector_catalogs[0].contracts.map(c => c.cid),
    ] : [independentCid(stages.schemas.gate_requirement),
      independentCid(stages.schemas.result_import_interface)];
    let contracts = [...new Set([...common, ...extra])];
    if (old) contracts = contracts.map(c => reverse.get(c) ?? c);
    contracts.sort();
    const imports = i === 0 ? [] : [independentCid({
      version: 'actql-result-import-interface/0.1', availability: 'stage_success',
      input_name: 'x', producer_namespace: {program_id: program.id,
        node_id: stage.inputs.x.result.stage}, producer_result: 'r',
      producer_unit_definition_cid: units.get(stage.inputs.x.result.stage),
      value_contract_cid: independentCid({type: 'object', nullable: false,
        additional_properties: false, fields: {id: {type: 'number', nullable: false}}}),
    })];
    const gates = i === 0 ? [] : [independentCid({
      version: 'actql-graph-success-requirement/0.1', completion_contracts: {},
      completion_nodes: {}, effect_contracts: {}, effect_nodes: {},
      empty_items: 'require-successful-computation-and-preflight', milestone: 'completed',
      producer_node_id: program.stages[i - 1].id})];
    units.set(id, independentCid({version: 'actql-local-unit-dependencies/0.1',
      unit_namespace: {program_id: program.id, node_id: id},
      local_body_cid: independentCid(body), used_parameter_declarations_cid: independentCid(parameters),
      local_contract_closure_cid: independentCid({version: 'actql-local-contracts/0.1', contracts}),
      import_interface_cids: imports, incoming_gate_contract_cids: gates}));
  }
  return units;
}
