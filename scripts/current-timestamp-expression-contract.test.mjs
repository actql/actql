import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateCurrentTimestampContracts, updateQueryTimeScalarLaw} from './current-timestamp-expression-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
// Independent UTF-16 key order and canonical preimages, never compiler output.
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const cid = value => hash(canonical(value));
const retained = read('scripts/fixtures/query-time-source/predecessor.json');
const before = Object.fromEntries(retained.contracts.map(item => [item.id, item.body]));
const inputs = () => ['actql-expressions', 'actql-protocol-schemas']
  .map(name => read(`spec/contracts/${name}.json`));
const paths = [
  [0, 'schemas/expression/$defs/expression', 'source'],
  [0, 'schemas/expression_node/$defs/expression', 'node'],
  [0, 'schemas/fragment/$defs/source_expression', 'source'],
  [0, 'schemas/fragment/$defs/machine_expression', 'node'],
  [0, 'schemas/predicate_consumer/$defs/source_expression', 'source'],
  [0, 'schemas/predicate_consumer/$defs/machine_expression', 'node'],
  ...['executable_plan', 'plan_document'].flatMap(name => ['predicate', 'value_expression'].map(part =>
    [1, `artifact_schemas/${name}/${name === 'plan_document' ? 'properties/plan/' : ''}properties/execution_material/properties/program/$defs/${part}`, 'source'])),
];
const at = (bodies, [owner, path]) => path.split('/').reduce((value, key) => value[key], bodies[owner]);
const temporalNames = ['current_timestamp', 'timestamp_add', 'timestamp_sub'];
const isTime = shape => temporalNames.includes(shape.properties?.op?.const)
  || temporalNames.some(name => shape.required?.includes(name));
function strip(value) {
  if (Array.isArray(value)) return value.map(strip);
  if (!value || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, strip(child)]));
  if (result.oneOf) result.oneOf = result.oneOf.filter(shape => !isTime(shape));
  return result;
}

test('query time retains complete preceding expression, scalar, containing schemas and grammar identities', () => {
  assert.equal(retained.source_revision, '68b63f0aad3d4fcf831c180ba3eed9d4e08490de');
  const fixed = {
    expression_contract: 'sha256:707fd38ee8c0e32b24b700b55364414362b6cbf01f99405d4fde455a8243cd35',
    scalar_law_manifest: 'sha256:b4a275e783675e1d0bbfa9a6b87db5fbfd79901c8887c40b6b7fbfea5a719c87',
    aoa_contract: 'sha256:0f0af6fe71e99c6f57999097203bd50eb370e09fb448768438c1397ce6de7136',
    grammar_manifest: 'sha256:added296f2a4758fb897ae3add7928e85456375e8f770346b47f47d1ccaa9114',
    executable_plan: 'sha256:9780f9423f41edecb7d920e49b3b6dd122dc916c1ab7ee3720de790357b43d4c',
    plan_document: 'sha256:b7ef9aa8bde3be48f82ba74b6cdb253fa936050881285fe5f53f942946b65f08',
  };
  assert.equal(retained.contracts.length, 6);
  for (const record of retained.contracts) {
    assert.equal(record.cid, fixed[record.id]);
    assert.equal(cid(record.body), record.cid);
  }
  assert.equal(hash(retained.query_rules).slice(7), retained.query_rules_sha256);
  assert.equal(hash(retained.expression_grammar).slice(7), before.expression_contract.grammar_sha256);
  const [expressions, protocol] = inputs();
  const prior = strip(expressions);
  for (const name of temporalNames) delete prior.laws[name];
  prior.grammar_sha256 = before.expression_contract.grammar_sha256;
  assert.deepEqual(prior, before.expression_contract);
  for (const name of ['executable_plan', 'plan_document']) {
    assert.deepEqual(strip(protocol.artifact_schemas[name]), before[name]);
    assert.equal(protocol.artifact_schema_cids[name], cid(protocol.artifact_schemas[name]));
    assert.notEqual(protocol.artifact_schema_cids[name], retained.artifact_schema_cids[name]);
  }
  assert.equal(protocol.artifact_registry_cid, cid(protocol.artifact_schemas));
});

test('query time and fixed intervals own their exact ten closed embeddings without changing previous alternatives', () => {
  const bodies = inputs();
  const grammar = readFileSync(bodies[0].grammar, 'utf8');
  const snapshot = structuredClone(bodies);
  assert.deepEqual(updateCurrentTimestampContracts(...bodies, grammar), {source: 21, node: 9});
  assert.deepEqual(bodies, snapshot);
  for (const path of paths) {
    const matches = at(bodies, path).oneOf.filter(isTime);
    assert.equal(matches.length, 3);
    const current = matches.find(shape => shape.properties?.op?.const === 'current_timestamp' || shape.required?.includes('current_timestamp'));
    const empty = {type: 'array', minItems: 0, maxItems: 0, items: false};
    assert.deepEqual(current, path[2] === 'source'
      ? {type: 'object', additionalProperties: false, required: ['current_timestamp'], properties: {current_timestamp: empty}}
      : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: 'current_timestamp'}, body: empty}});
  }
});

test('query time preflight refuses missing, duplicated and foreign expression scopes before mutation', () => {
  const grammar = readFileSync(inputs()[0].grammar, 'utf8');
  for (const path of paths) for (const mutate of [
    scope => {delete scope.oneOf;},
    scope => {scope.oneOf.push(structuredClone(scope.oneOf.find(isTime)));},
    scope => {const original = scope.oneOf.find(shape => shape.properties?.op?.const === 'len' || shape.required?.includes('len')); original.additionalProperties = true;},
  ]) {
    const bodies = inputs(); mutate(at(bodies, path));
    const before = structuredClone(bodies);
    assert.throws(() => updateCurrentTimestampContracts(...bodies, grammar, true));
    assert.deepEqual(bodies, before);
  }
  const bodies = inputs(); bodies[0].schemas.foreign = structuredClone(at(bodies, paths[0]));
  const snapshot = structuredClone(bodies);
  assert.throws(() => updateCurrentTimestampContracts(...bodies, grammar, true), /unregistered/u);
  assert.deepEqual(bodies, snapshot);
});

test('query time preserves date arithmetic and authority clocks under its separate original-Run law', () => {
  const scalar = read('spec/dependencies/aoa-rela-scalar-laws.json');
  const {query_time: rule, fixed_interval: interval, ...time} = scalar.time;
  assert.match(interval.amount, /original integral source token/u);
  assert.match(interval.duration, /without binary64 conversion/u);
  assert.deepEqual({...scalar, time}, before.scalar_law_manifest);
  assert.match(rule.signature, /Zero operands/u);
  assert.match(rule.value, /same admitted Run definition created_at/u);
  assert.match(rule.binding, /fresh original wall-clock/u);
  assert.match(rule.recovery, /winning saved Run/u);
  assert.match(rule.source, /UnboundRequest/u);
  assert.match(rule.evaluation, /without its original execution context is unavailable/u);
  assert.match(rule.authority, /computation data only/u);
  const unchanged = structuredClone(scalar);
  updateQueryTimeScalarLaw(scalar);
  assert.deepEqual(scalar, unchanged);
  const aoa = read('spec/contracts/actql-aoa.json');
  assert.equal(aoa.rela_scalar_law_manifest_cid, cid(scalar));
  assert.equal(aoa.expression_contract_cid, cid(inputs()[0]));
  const prior = structuredClone(aoa);
  prior.rela_scalar_law_manifest_cid = before.aoa_contract.rela_scalar_law_manifest_cid;
  prior.expression_contract_cid = before.aoa_contract.expression_contract_cid;
  const ordered = prior.execution_contracts['REL.derive.ordered'];
  const oldOrdered = before.aoa_contract.execution_contracts['REL.derive.ordered'];
  for (const [name, value] of Object.entries({
    expression_contract: inputs()[0], expression_node: inputs()[0].schemas.expression_node,
    source_expression: inputs()[0].schemas.expression,
  })) {
    assert.equal(ordered.dependencies[name].cid, cid(value));
    ordered.dependencies[name].cid = oldOrdered.dependencies[name].cid;
  }
  assert.deepEqual(ordered, oldOrdered);
  const registry = read(aoa.pipeline_registry_file);
  const currentPin = registry['REL.derive'].execution_extensions.ordered_bindings;
  assert.equal(currentPin.cid, cid(aoa.execution_contracts['REL.derive.ordered']));
  assert.deepEqual(aoa.target_registry_requirements['REL.derive'].execution_extensions.ordered_bindings, currentPin);
  prior.target_registry_requirements['REL.derive'] = before.aoa_contract.target_registry_requirements['REL.derive'];
  assert.equal(aoa.pipeline_registry_cid, cid(registry));
  registry['REL.derive'].execution_extensions.ordered_bindings = prior.target_registry_requirements['REL.derive'].execution_extensions.ordered_bindings;
  assert.equal(cid(registry), before.aoa_contract.pipeline_registry_cid);
  prior.pipeline_registry_cid = cid(registry);
  assert.deepEqual(prior, before.aoa_contract);
});

test('query time changes only declared Stage and Program identity dependencies with complete old envelopes retained', () => {
  const history = read('scripts/fixtures/query-time-source/stage-predecessors.json');
  assert.equal(history.source_revision, retained.source_revision);
  assert.equal(history.expression_contract_cid, cid(before.expression_contract));
  const names = Object.keys(history.corpora);
  assert.equal(names.length, 6);
  const old = structuredClone(history.corpora);
  const next = structuredClone(history.corpora);
  const newExpression = cid(inputs()[0]);
  for (const name of ['stage-semantics', 'local-unit-stage-body']) for (const row of next[name].cases) {
    assert.equal(row.envelope.expression_contract_cid, history.expression_contract_cid);
    assert.equal(cid(row.envelope), row.expected_cid);
    row.envelope.expression_contract_cid = newExpression;
    row.expected_cid = cid(row.envelope);
  }
  function programEnvelope(corpora, expression, row) {
    const [a, b] = corpora['stage-semantics'].cases.slice(0, 2).map(item => structuredClone(item.envelope));
    const port = row.import_mode === 1 ? {result: {stage: 'a', result: 'r'}}
      : row.import_mode === 2 ? {receipt: {stage: 'a', effect: 'd'}} : null;
    if (port) b.local_body.inputs.rows = port;
    return {version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
      expression_contract_cid: expression, parameters: a.parameters, bindings: a.bindings,
      parameter_references: [a, b].flatMap((stage, index) => stage.parameter_references
        .map(reference => ({...reference, path: `/stages/${index}${reference.path}`}))),
      binding_references: a.binding_references.map(reference => ({...reference, path: `/stages/0${reference.path}`})),
      program_template: {stages: [
        {id: 'a', after: 'initial', imports: {}, stage_semantics_cid: cid(a)},
        {id: 'b', after: row.accepted ? 'accepted' : 'completed', imports: port ? {rows: port} : {}, stage_semantics_cid: cid(b)},
      ], exports: {out: {from: {stage: 'b', result: 'r'}}}}};
  }
  for (const [index, row] of next['stage-definition'].cases.entries()) {
    const envelope = corpora => ({version: 'actql-stage-definition/0.1', id: row.id,
      stage_semantics_cid: corpora['stage-semantics'].cases.find(item => item.name === row.stage_case).expected_cid});
    assert.equal(cid(envelope(old)), old['stage-definition'].cases[index].expected_cid);
    row.expected_cid = cid(envelope(next));
  }
  for (const [index, row] of next['program-semantics'].cases.entries()) {
    assert.equal(cid(programEnvelope(old, history.expression_contract_cid, row)), old['program-semantics'].cases[index].expected_cid);
    row.expected_cid = cid(programEnvelope(next, newExpression, row));
  }
  for (const [index, row] of next['program-definition'].cases.entries()) {
    const envelope = corpora => ({version: 'actql-program-definition/0.1', id: row.id,
      program_semantics_cid: corpora['program-semantics'].cases.find(item => item.import_mode === row.import_mode && item.accepted === row.accepted).expected_cid});
    assert.equal(cid(envelope(old)), old['program-definition'].cases[index].expected_cid);
    row.expected_cid = cid(envelope(next));
  }
  for (const name of names) assert.deepEqual(read(`portability/corpus/${name}.json`), next[name]);
});

test('query time retains fixed independent source and machine data preimages without a sampled value', () => {
  const records = read('scripts/fixtures/query-time-source/preimages.json');
  assert.deepEqual(records.map(row => row.kind), ['source', 'machine']);
  assert.deepEqual(records[0].body, {current_timestamp: []});
  assert.deepEqual(records[1].body, {body: [], op: 'current_timestamp'});
  for (const row of records) {
    assert.equal(canonical(row.body), row.canonical);
    assert.equal(hash(row.canonical), row.data_cid);
    assert.doesNotMatch(row.canonical, /created_at|\$param|literal/u);
  }
});

test('fixed interval schemas close all units and independent exact integer preimages', () => {
  const bodies = inputs();
  for (const path of paths) for (const name of ['timestamp_add', 'timestamp_sub']) {
    const schema = at(bodies, path).oneOf.find(shape => shape.properties?.op?.const === name || shape.required?.includes(name));
    const args = path[2] === 'source' ? schema.properties[name] : schema.properties.body;
    assert.equal(args.minItems, 3); assert.equal(args.maxItems, 3); assert.equal(args.items, false);
    const unit = args.prefixItems[2];
    assert.equal(unit.additionalProperties, false);
    assert.deepEqual(path[2] === 'source' ? unit.properties.literal.enum : unit.properties.body.enum,
      ['ns', 'us', 'ms', 's', 'm', 'h', 'd']);
    assert.deepEqual(args.prefixItems.slice(0, 2), Array(2).fill({$ref: '#/$defs/' + (path[2] === 'node' && path[1].includes('machine_expression') ? 'machine_expression' : path[1].includes('source_expression') ? 'source_expression' : path[1].includes('artifact_schemas') ? 'value_expression' : 'expression')}));
  }
  const exact = 9007199254740993n;
  assert.equal(exact / 1000000000n, 9007199n);
  assert.equal(exact % 1000000000n, 254740993n);
  const minimum = -9223372036854775808n;
  assert.equal(-minimum, 9223372036854775808n);
  const source = {timestamp_sub: [{current_timestamp: []}, {literal: '-9223372036854775808'}, {literal: 'ns'}]};
  assert.equal(canonical(source), '{"timestamp_sub":[{"current_timestamp":[]},{"literal":"-9223372036854775808"},{"literal":"ns"}]}');
});
