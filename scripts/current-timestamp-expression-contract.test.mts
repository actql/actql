import {gunzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateCurrentTimestampContracts, updateQueryTimeScalarLaw} from './current-timestamp-expression-contract.mjs';

type Inputs = Parameters<typeof updateCurrentTimestampContracts>;
type Scalar = Parameters<typeof updateQueryTimeScalarLaw>[0];
type OwnerPin = {cid: string};
type OrderedContract = {dependencies: Record<string, OwnerPin>};
type RegistryOwner = {execution_extensions: {ordered_bindings: OwnerPin}};
type Registry = {'REL.derive': RegistryOwner};
type AoA = {rela_scalar_law_manifest_cid: string; expression_contract_cid: string;
  execution_contracts: {'REL.derive.ordered': OrderedContract}; target_registry_requirements: {'REL.derive': RegistryOwner};
  pipeline_registry_file: string; pipeline_registry_cid: string};
type GrammarManifest = {query_text_grammar_sha256: string};
type PreviousBodies = {expression_contract: {grammar_sha256: string}; scalar_law_manifest: unknown;
  aoa_contract: AoA; grammar_manifest: GrammarManifest; executable_plan: unknown; plan_document: unknown};
type Retained = {source_revision: string; contracts: {id: keyof PreviousBodies; body: unknown; cid: string}[];
  query_rules: string; query_rules_sha256: string; expression_grammar: string; query_grammar: string;
  query_grammar_sha256: string; artifact_schema_cids: Record<string, string>};
type Schema = {oneOf?: Schema[]; required?: string[]; properties?: Record<string, Schema>; const?: unknown;
  additionalProperties?: boolean; minItems?: number; maxItems?: number; items?: false; prefixItems?: Schema[]; enum?: string[]};
type SchemaPath = [owner: 0 | 1, path: string, kind: 'source' | 'node'];
type Stages = {cases: {name: string; envelope: {expression_contract_cid: string; parameters: unknown; bindings: unknown;
  parameter_references: {path: string}[]; binding_references: {path: string}[];
  local_body: {inputs: {rows?: unknown}}}; expected_cid: string}[]};
type ProgramCase = {id: string; import_mode: number; accepted: boolean; expected_cid: string};
type Corpora = {'stage-semantics': Stages; 'local-unit-stage-body': Stages;
  'stage-definition': {cases: {id: string; stage_case: string; expected_cid: string}[]};
  'stage-parameter-declarations': unknown; 'program-semantics': {cases: ProgramCase[]}; 'program-definition': {cases: ProgramCase[]}};
type StageHistory = {source_revision: string; expression_contract_cid: string; corpora: Corpora};
const readCurrent = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
// Exact division is a later semantic extension. History assertions retain the
// complete actual accepted successor before that extension; current scope
// admission and mutation checks still read current contracts.
const divisionPredecessor: {bodies: Record<string, unknown>} =
  JSON.parse(gunzipSync(readFileSync('scripts/fixtures/decimal-division-exact/predecessor.json.gz')).toString('utf8'));
function readAccepted<Value>(path: string): Value {
  assert.ok(Object.hasOwn(divisionPredecessor.bodies, path), path);
  return structuredClone(divisionPredecessor.bodies[path]) as Value;
}
// Independent UTF-16 key order and canonical preimages, never compiler output.
const canonical = (value: unknown): string => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical((value as Record<string, unknown>)[key])).join(',') + '}' : JSON.stringify(value);
const hash = (text: string) => 'sha256:' + createHash('sha256').update(text).digest('hex');
const cid = (value: unknown) => hash(canonical(value));
const retained = readCurrent<Retained>('scripts/fixtures/query-time-source/predecessor.json');
const before = Object.fromEntries(retained.contracts.map(item => [item.id, item.body])) as PreviousBodies;
function inputs(read: typeof readCurrent = readCurrent): [Inputs[0], Inputs[1]] {
  return [read('spec/contracts/actql-expressions.json'), read('spec/contracts/actql-protocol-schemas.json')];
}
const paths: SchemaPath[] = [
  [0, 'schemas/expression/$defs/expression', 'source'],
  [0, 'schemas/expression_node/$defs/expression', 'node'],
  [0, 'schemas/fragment/$defs/source_expression', 'source'],
  [0, 'schemas/fragment/$defs/machine_expression', 'node'],
  [0, 'schemas/predicate_consumer/$defs/source_expression', 'source'],
  [0, 'schemas/predicate_consumer/$defs/machine_expression', 'node'],
  ...['executable_plan', 'plan_document'].flatMap(name => ['predicate', 'value_expression'].map<SchemaPath>(part =>
    [1, `artifact_schemas/${name}/${name === 'plan_document' ? 'properties/plan/' : ''}properties/execution_material/properties/program/$defs/${part}`, 'source'])),
];
function at(bodies: [Inputs[0], Inputs[1]], [owner, path]: SchemaPath): Schema {
  const value = path.split('/').reduce<unknown>((node, key) =>
    node && typeof node === 'object' ? (node as Record<string, unknown>)[key] : undefined, bodies[owner]);
  assert.ok(value && typeof value === 'object', path);
  return value as Schema;
}
function choices(scope: Schema): Schema[] {
  assert.ok(Array.isArray(scope.oneOf));
  return scope.oneOf;
}
const temporalNames = ['current_timestamp', 'timestamp_add', 'timestamp_sub'] as const;
const isTime = (shape: Schema) => temporalNames.some(name =>
  shape.properties?.op?.const === name || shape.required?.includes(name));
function strip(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(strip);
  if (!value || typeof value !== 'object') return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, strip(child)]));
  if (Array.isArray(result.oneOf)) result.oneOf = (result.oneOf as Schema[]).filter(shape => !isTime(shape));
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
  const [expressions, protocol] = inputs(readAccepted);
  const prior = strip(expressions) as Inputs[0];
  for (const name of temporalNames) delete prior.laws[name];
  prior.grammar_sha256 = before.expression_contract.grammar_sha256;
  assert.deepEqual(prior, before.expression_contract);
  for (const name of ['executable_plan', 'plan_document'] as const) {
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
    const matches = choices(at(bodies, path)).filter(isTime);
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
  const mutations: ((scope: Schema) => void)[] = [
    scope => {delete scope.oneOf;},
    scope => {
      const matches = choices(scope), original = matches.find(isTime);
      assert.ok(original);
      matches.push(structuredClone(original));
    },
    scope => {
      const original = choices(scope).find(shape => shape.properties?.op?.const === 'len' || shape.required?.includes('len'));
      assert.ok(original);
      original.additionalProperties = true;
    },
  ];
  for (const path of paths) for (const mutate of mutations) {
    const bodies = inputs(); mutate(at(bodies, path));
    const before = structuredClone(bodies);
    assert.throws(() => updateCurrentTimestampContracts(...bodies, grammar, true));
    assert.deepEqual(bodies, before);
  }
  const bodies = inputs(); bodies[0].schemas.foreign = structuredClone(at(bodies, paths[0]!));
  const snapshot = structuredClone(bodies);
  assert.throws(() => updateCurrentTimestampContracts(...bodies, grammar, true), /unregistered/u);
  assert.deepEqual(bodies, snapshot);
});

test('query time preserves date arithmetic and authority clocks under its separate original-Run law', () => {
  const scalar = readAccepted<Scalar>('spec/dependencies/aoa-rela-scalar-laws.json');
  const {query_time: rule, fixed_interval: interval, ...time} = scalar.time;
  assert.ok(rule && interval);
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
  const aoa = readAccepted<AoA>('spec/contracts/actql-aoa.json');
  const [expressions] = inputs(readAccepted);
  assert.equal(aoa.rela_scalar_law_manifest_cid, cid(scalar));
  assert.equal(aoa.expression_contract_cid, cid(expressions));
  const prior = structuredClone(aoa);
  prior.rela_scalar_law_manifest_cid = before.aoa_contract.rela_scalar_law_manifest_cid;
  prior.expression_contract_cid = before.aoa_contract.expression_contract_cid;
  const ordered = prior.execution_contracts['REL.derive.ordered'];
  const oldOrdered = before.aoa_contract.execution_contracts['REL.derive.ordered'];
  for (const [name, value] of Object.entries({
    expression_contract: expressions, expression_node: expressions.schemas.expression_node,
    source_expression: expressions.schemas.expression,
  })) {
    const pin = ordered.dependencies[name], priorPin = oldOrdered.dependencies[name];
    assert.ok(pin && priorPin);
    assert.equal(pin.cid, cid(value));
    pin.cid = priorPin.cid;
  }
  assert.deepEqual(ordered, oldOrdered);
  const registry = readAccepted<Registry>(aoa.pipeline_registry_file);
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
  const history = readCurrent<StageHistory>('scripts/fixtures/query-time-source/stage-predecessors.json');
  assert.equal(history.source_revision, retained.source_revision);
  assert.equal(history.expression_contract_cid, cid(before.expression_contract));
  const names = Object.keys(history.corpora) as (keyof Corpora)[];
  assert.equal(names.length, 6);
  const old = structuredClone(history.corpora);
  const next = structuredClone(history.corpora);
  const newExpression = cid(inputs(readAccepted)[0]);
  for (const name of ['stage-semantics', 'local-unit-stage-body'] as const) for (const row of next[name].cases) {
    assert.equal(row.envelope.expression_contract_cid, history.expression_contract_cid);
    assert.equal(cid(row.envelope), row.expected_cid);
    row.envelope.expression_contract_cid = newExpression;
    row.expected_cid = cid(row.envelope);
  }
  function programEnvelope(corpora: Corpora, expression: string, row: ProgramCase) {
    const [a, b] = corpora['stage-semantics'].cases.slice(0, 2).map(item => structuredClone(item.envelope));
    assert.ok(a && b);
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
    const envelope = (corpora: Corpora) => {
      const stage = corpora['stage-semantics'].cases.find(item => item.name === row.stage_case);
      assert.ok(stage);
      return {version: 'actql-stage-definition/0.1', id: row.id, stage_semantics_cid: stage.expected_cid};
    };
    assert.equal(cid(envelope(old)), old['stage-definition'].cases[index]?.expected_cid);
    row.expected_cid = cid(envelope(next));
  }
  for (const [index, row] of next['program-semantics'].cases.entries()) {
    assert.equal(cid(programEnvelope(old, history.expression_contract_cid, row)), old['program-semantics'].cases[index]?.expected_cid);
    row.expected_cid = cid(programEnvelope(next, newExpression, row));
  }
  for (const [index, row] of next['program-definition'].cases.entries()) {
    const envelope = (corpora: Corpora) => {
      const program = corpora['program-semantics'].cases.find(item => item.import_mode === row.import_mode && item.accepted === row.accepted);
      assert.ok(program);
      return {version: 'actql-program-definition/0.1', id: row.id, program_semantics_cid: program.expected_cid};
    };
    assert.equal(cid(envelope(old)), old['program-definition'].cases[index]?.expected_cid);
    row.expected_cid = cid(envelope(next));
  }
  for (const name of names) assert.deepEqual(readAccepted(`portability/corpus/${name}.json`), next[name]);
});

test('query time retains fixed independent source and machine data preimages without a sampled value', () => {
  const records = readCurrent<{kind: string; body: unknown; canonical: string; data_cid: string}[]>(
    'scripts/fixtures/query-time-source/preimages.json');
  assert.deepEqual(records.map(row => row.kind), ['source', 'machine']);
  assert.deepEqual(records[0]?.body, {current_timestamp: []});
  assert.deepEqual(records[1]?.body, {body: [], op: 'current_timestamp'});
  for (const row of records) {
    assert.equal(canonical(row.body), row.canonical);
    assert.equal(hash(row.canonical), row.data_cid);
    assert.doesNotMatch(row.canonical, /created_at|\$param|literal/u);
  }
});

test('fixed interval schemas close all units and independent exact integer preimages', () => {
  const bodies = inputs();
  for (const path of paths) for (const name of ['timestamp_add', 'timestamp_sub'] as const) {
    const schema = choices(at(bodies, path)).find(shape => shape.properties?.op?.const === name || shape.required?.includes(name));
    const args = path[2] === 'source' ? schema?.properties?.[name] : schema?.properties?.body;
    assert.ok(args?.prefixItems);
    assert.equal(args.minItems, 3); assert.equal(args.maxItems, 3); assert.equal(args.items, false);
    const unit = args.prefixItems[2];
    assert.ok(unit);
    assert.equal(unit.additionalProperties, false);
    assert.deepEqual(path[2] === 'source' ? unit.properties?.literal?.enum : unit.properties?.body?.enum,
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


test('fixed interval grammar and later selected productions preserve the authenticated predecessor', () => {
  assert.equal(hash(retained.query_grammar).slice(7), retained.query_grammar_sha256);
  assert.equal(retained.query_grammar_sha256, before.grammar_manifest.query_text_grammar_sha256);
  const current = readFileSync('spec/grammar/actql-query-0.1.ebnf', 'utf8');
  const fixedInterval = `
(* A fixed interval is an operand role only at the shared Timestamp consumers;
   integral tokens retain their exact signed spelling before Common admission. *)
fixed_interval = "INTERVAL", ( [ "+" | "-" ], interval_integer | parameter_token | path ), fixed_interval_unit ;
interval_integer = ? exact decimal or 0x/0X hexadecimal integer token, admitted in signed64 context without binary64 conversion ? ;
fixed_interval_unit = "NANOSECOND" | "MICROSECOND" | "MILLISECOND"
                    | "SECOND" | "MINUTE" | "HOUR" | "DAY" ;
`;
  assert.ok(current.endsWith(fixedInterval));
  let predecessor = current.slice(0, -fixedInterval.length);
  // Each later form must match its independently stated production exactly.
  // Reversing only those edits leaves the entire original grammar for comparison.
  const selectedExtensions: [added: string, original: string][] = [
    ['cte_pipe      = "FROM", carrier_source, { from_join }, { "|>", cte_pipe_item } ;',
      'cte_pipe      = "FROM", carrier_source, { join }, { "|>", cte_pipe_item } ;'],
    [`select_core   = "SELECT", [ "ALL" | "DISTINCT" ], ( scalar_subquery_projection | exists_subquery_projection
                | select_list, [ "FROM", source, { from_join } ],
                  [ select_where_clause ], [ group_clause ],
                  [ having_clause ], [ qualify_clause ], [ window_clause ] ) ;
(* The child starts with SELECT or WITH, yields one column and has its own scope. *)
scalar_subquery_projection = "(", relational_body, ")", [ [ "AS" ], identifier ] ;
exists_subquery_projection = exists_subquery, [ [ "AS" ], identifier ] ;
exists_subquery = "EXISTS", "(", relational_body, ")" ;`,
    `select_core   = "SELECT", [ "DISTINCT" ], select_list, [ "FROM", source, { join } ],
                [ where_clause ], [ group_clause ],
                [ having_clause ], [ qualify_clause ], [ window_clause ] ;`],
    ['pipe_query    = "FROM", carrier_source, { from_join }, { "|>", pipe_item } ;',
      'pipe_query    = "FROM", carrier_source, { join }, { "|>", pipe_item } ;'],
    ['from_join     = join | ",", ( table_source, [ join_bound ] | unnest_source ) ;\n', ''],
    [`select_where_clause = where_clause
                    | "WHERE", expression, "IN", "(", relational_body, ")"
                    | "WHERE", exists_subquery ;
`, ''],
    [`group_clause  = "GROUP", "BY", ( "ALL" | "(", ")" | rollup | expression, { ",", expression } ) ;
rollup        = "ROLLUP", "(", grouping_item, { ",", grouping_item }, ")" ;
grouping_item = expression | "(", expression, ",", expression, { ",", expression }, ")" ;`,
    'group_clause  = "GROUP", "BY", ( "ALL" | "(", ")" | expression, { ",", expression } ) ;'],
    [`expression    = ? closed query expression grammar in query-text.md, including date_literal and timestamp_literal ? ;
date_literal  = "DATE", ? STRING literal chunks decoding to YYYY-[M]M-[D]D ? ;
timestamp_literal = "TIMESTAMP", ? STRING literal chunks decoding to a civil date with optional time and fixed UTC offset ? ;`,
    'expression    = ? closed query expression grammar in query-text.md ? ;'],
  ];
  for (const [added, original] of selectedExtensions) {
    assert.equal(predecessor.split(added).length, 2, added);
    predecessor = predecessor.replace(added, original);
  }
  assert.equal(predecessor, retained.query_grammar);
  assert.equal(readCurrent<GrammarManifest>('spec/manifests/actql-grammar-0.1.json').query_text_grammar_sha256, hash(current).slice(7));
});
