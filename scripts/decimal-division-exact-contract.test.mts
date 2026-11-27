import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';
import {updateDecimalDivisionContracts} from './decimal-division-exact-contract.mjs';
type Snapshot = {source: string; bodies: Record<string, unknown>};
type DivisionExpression = {decimal_divide: {left: unknown; right: unknown; precision: number; scale: number; rounding: string}};
type Preimage = {value: DivisionExpression; preimage: string; cid: string};
type Ratio = {left: string; right: string; scale: number; coefficient: string | null};
type Schema = {required?: string[]; properties?: Record<string, Schema>; const?: unknown; enum?: string[]};
type TypeCorpus = {types: Record<string, unknown>; positive: {source: string; type: string}[];
  negative: {source: string; issue: string}[]};
type ExpressionInputs = Parameters<typeof updateDecimalDivisionContracts>;
type Stages = {cases: {name: string; envelope: {expression_contract_cid: string; parameters: unknown; bindings: unknown;
  parameter_references: {path: string}[]; binding_references: {path: string}[];
  local_body: {inputs: {rows?: unknown}}}; expected_cid: string}[]};
type ProgramCase = {id: string; import_mode: number; accepted: boolean; expected_cid: string};
type CorpusMap = {'stage-semantics': Stages; 'local-unit-stage-body': Stages;
  'stage-definition': {cases: {id: string; stage_case: string; expected_cid: string}[]};
  'stage-parameter-declarations': unknown; 'program-semantics': {cases: ProgramCase[]};
  'program-definition': {cases: ProgramCase[]}};
const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
const readSnapshot = (path: string): Snapshot => JSON.parse(gunzipSync(readFileSync(path)).toString('utf8'));
const before = readSnapshot('scripts/fixtures/decimal-division-exact/predecessor.json.gz');
const beforeNumberIdentity = readSnapshot('scripts/fixtures/try-number-identity/predecessor.json.gz');
const expressionPath = 'spec/contracts/actql-expressions.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const scalarPath = 'spec/dependencies/aoa-rela-scalar-laws.json';
const canonical = (value: unknown): string => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical((value as Record<string, unknown>)[key])).join(',') + '}' : JSON.stringify(value);
const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
function removeExact(value: unknown) {
  if (!value || typeof value !== 'object') return;
  const properties = (value as Schema).properties;
  const schema = properties?.decimal_divide ??
    (properties?.op?.const === 'decimal_divide' ? properties.body : undefined);
  if (schema) {
    assert.deepEqual(schema.required, ['left', 'right', 'precision', 'scale', 'rounding']);
    const policies = schema.properties?.rounding?.enum;
    assert.ok(policies);
    assert.deepEqual(policies, ['half_even', 'half_up', 'toward_zero', 'floor', 'ceiling', 'exact']);
    policies.pop();
  }
  if (properties?.quantize) assert.deepEqual(properties.quantize.properties?.rounding?.enum,
    ['half_even', 'half_up', 'toward_zero', 'floor', 'ceiling']);
  for (const child of Object.values(value)) removeExact(child);
}

test('exact division restores the complete original expression/protocol/scalar bodies and five-mode bytes', () => {
  assert.equal(before.source, '2d59f72f7ef3d288415e93db445146b1a2d48847');
  // Current division admission is still checked. The complete-body historical
  // comparison stops before the independently tested Number identity extension.
  assert.ok(updateDecimalDivisionContracts(read(expressionPath), read(protocolPath), read(scalarPath)).source > 0);
  const expression = structuredClone(beforeNumberIdentity.bodies[expressionPath] as ExpressionInputs[0]);
  const protocol = structuredClone(beforeNumberIdentity.bodies[protocolPath] as ExpressionInputs[1]);
  const scalar = structuredClone(beforeNumberIdentity.bodies[scalarPath] as ExpressionInputs[2]);
  assert.ok(updateDecimalDivisionContracts(expression, protocol, scalar).source > 0);
  removeExact(expression); delete expression.laws.decimal_divide;
  assert.deepEqual(expression, before.bodies[expressionPath]);
  removeExact(protocol);
  const changed = Object.keys(protocol.artifact_schemas).filter(key =>
    cid(protocol.artifact_schemas[key]) !== protocol.artifact_schema_cids[key]).sort();
  assert.deepEqual(changed, ['executable_plan', 'plan_document']);
  for (const [name, schema] of Object.entries(protocol.artifact_schemas)) protocol.artifact_schema_cids[name] = cid(schema);
  protocol.artifact_registry_cid = cid(protocol.artifact_schemas);
  assert.deepEqual(protocol, before.bodies[protocolPath]);
  delete scalar.decimal.division;
  assert.deepEqual(scalar, before.bodies[scalarPath]);
  for (const record of read<Preimage[]>('scripts/fixtures/decimal-division-source/expressions.json')) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(cid(record.value), record.cid);
  }
});

test('exact division has independently authored complete preimages and exact-rational vectors', () => {
  const vectors = read<Preimage[]>('scripts/fixtures/decimal-division-exact/expressions.json');
  for (const entry of vectors) {
    assert.equal(canonical(entry.value), entry.preimage);
    assert.equal(cid(entry.value), entry.cid);
    assert.deepEqual(Object.keys(entry.value.decimal_divide).sort(), ['left', 'precision', 'right', 'rounding', 'scale']);
    assert.equal(entry.value.decimal_divide.precision, 38);
    assert.equal(entry.value.decimal_divide.rounding, 'exact');
  }
  const ratios = read<Ratio[]>('scripts/fixtures/decimal-division-exact/ratios.json');
  for (const {left, right, scale, coefficient} of ratios) {
    const n = BigInt(left) * 10n ** BigInt(scale), d = BigInt(right);
    const q = d === 0n ? null : n / d;
    const expected = q === null || n % d !== 0n || q >= 10n ** 38n || q <= -(10n ** 38n) ? null : String(q);
    assert.equal(coefficient, expected);
  }
});

test('literal NULL exception changes only the two contradicted vectors and explicit new context cases', () => {
  const old = before.bodies['portability/corpus/actql-expression-typing-v0.1.json'] as TypeCorpus;
  const current = beforeNumberIdentity.bodies['portability/corpus/actql-expression-typing-v0.1.json'];
  const resolved = ["decimal_divide(NULL,n,8,2,'half_even')", "decimal_divide(d,NULL,8,2,'half_even')"];
  assert.deepEqual(old.negative.filter(entry => resolved.includes(entry.source)), resolved.map(source => ({source, issue: 'NullTypeUnresolved'})));
  assert.deepEqual(current, {...old,
    types: {...old.types, decimal38_3: {type:'decimal',nullable:false,precision:38,scale:3},
      'decimal38_3?': {type:'decimal',nullable:true,precision:38,scale:3}},
    positive: [...old.positive, ...resolved.map(source => ({source, type:'decimal8_2?'})),
      {source:'decimal_divide(d,n,3)',type:'decimal38_3'}, {source:'decimal_divide(NULL,NULL,3)',type:'decimal38_3?'}],
    negative: [...old.negative.filter(entry => !resolved.includes(entry.source)),
      {source:'decimal_divide(unknown_division,n,3)',issue:'UnknownField'},
      {source:'decimal_divide(d,$missing_division,3)',issue:'UnknownParameter'},
      {source:'decimal_divide(n,d,3)',issue:'TypeMismatch'},
      {source:"decimal_divide(d,'8',3)",issue:'TypeMismatch'}]});
});

function programEnvelope(stages: Stages, expression: string, row: ProgramCase) {
  const [a,b] = stages.cases.slice(0,2).map(item => structuredClone(item.envelope));
  assert.ok(a && b);
  const port = row.import_mode === 1 ? {result:{stage:'a',result:'r'}} : row.import_mode === 2 ? {receipt:{stage:'a',effect:'d'}} : null;
  if (port) b.local_body.inputs.rows = port;
  return {version:'actql-program-semantics/0.1',actql_version:'actql/0.1',expression_contract_cid:expression,
    parameters:a.parameters,bindings:a.bindings,
    parameter_references:[a,b].flatMap((stage,index)=>stage.parameter_references.map(ref=>({...ref,path:`/stages/${index}${ref.path}`}))),
    binding_references:a.binding_references.map(ref=>({...ref,path:`/stages/0${ref.path}`})),
    program_template:{stages:[{id:'a',after:'initial',imports:{},stage_semantics_cid:cid(a)},
      {id:'b',after:row.accepted?'accepted':'completed',imports:port?{rows:port}:{},stage_semantics_cid:cid(b)}],
      exports:{out:{from:{stage:'b',result:'r'}}}}};
}

test('exact division preserves complete original Stage and Program bodies while repinning only declared expression dependencies', () => {
  const oldExpression = cid(before.bodies[expressionPath]), newExpression = cid(read(expressionPath));
  const names = ['stage-semantics','stage-definition','stage-parameter-declarations','program-semantics','program-definition','local-unit-stage-body'] as const;
  const old = Object.fromEntries(names.map(name => [name,before.bodies[`portability/corpus/${name}.json`]])) as CorpusMap;
  const next = structuredClone(old);
  for (const name of ['stage-semantics','local-unit-stage-body'] as const) for (const row of next[name].cases) {
    assert.equal(row.envelope.expression_contract_cid,oldExpression); assert.equal(cid(row.envelope),row.expected_cid);
    row.envelope.expression_contract_cid=newExpression;row.expected_cid=cid(row.envelope);
  }
  for (const [index,row] of next['stage-definition'].cases.entries()) {
    const shape = (data: CorpusMap) => {
      const stage = data['stage-semantics'].cases.find(item => item.name === row.stage_case);
      assert.ok(stage);
      return {version:'actql-stage-definition/0.1',id:row.id,stage_semantics_cid:stage.expected_cid};
    };
    assert.equal(cid(shape(old)),old['stage-definition'].cases[index]?.expected_cid);row.expected_cid=cid(shape(next));
  }
  for (const [index,row] of next['program-semantics'].cases.entries()) {
    assert.equal(cid(programEnvelope(old['stage-semantics'],oldExpression,row)),old['program-semantics'].cases[index]?.expected_cid);
    row.expected_cid=cid(programEnvelope(next['stage-semantics'],newExpression,row));
  }
  for (const [index,row] of next['program-definition'].cases.entries()) {
    const shape = (data: CorpusMap) => {
      const program = data['program-semantics'].cases.find(item => item.import_mode === row.import_mode && item.accepted === row.accepted);
      assert.ok(program);
      return {version:'actql-program-definition/0.1',id:row.id,program_semantics_cid:program.expected_cid};
    };
    assert.equal(cid(shape(old)),old['program-definition'].cases[index]?.expected_cid);row.expected_cid=cid(shape(next));
  }
  for(const name of names) assert.deepEqual(read(`portability/corpus/${name}.json`),next[name]);
  type Managed = {dependencies: {fixed_compute_capacity: {cid: string}}};
  const managed = read<Managed>('spec/contracts/actql-managed-retained-execution.json');
  const prior = before.bodies['spec/contracts/actql-managed-retained-execution.json'] as Managed;
  assert.equal(managed.dependencies.fixed_compute_capacity.cid,cid(read('spec/contracts/actql-fixed-compute-capacity.json')));
  managed.dependencies.fixed_compute_capacity.cid=prior.dependencies.fixed_compute_capacity.cid;
  assert.deepEqual(managed,prior);
});
