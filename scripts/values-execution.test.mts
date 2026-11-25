import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {isDeepStrictEqual} from 'node:util';
import {checkExecutionContract} from './values-execution-contract.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import type {ValidValueCase, ValuesCorpus} from './check-values-execution.mjs';

type Schema = boolean | SchemaObject;
type SchemaObject = {
  $ref?: string; type?: string | string[]; const?: unknown; enum?: unknown[];
  oneOf?: Schema[]; anyOf?: Schema[]; allOf?: Schema[]; not?: Schema; if?: Schema; then?: Schema;
  minimum?: number; maximum?: number; pattern?: string; minLength?: number; items?: Schema;
  minProperties?: number; required?: string[]; propertyNames?: Schema;
  properties?: Record<string, Schema>; additionalProperties?: Schema;
};
type AoA = Parameters<typeof checkExecutionContract>[0] & {
  execution_contracts: {'REL.values': {
    params_schema: SchemaObject; dependencies: {canonical_value_contract: {cid: string}};
    semantics: {row_order: string; recursive_resources: {
      selected_root_types: string[]; host_byte_ceiling: string; host_depth_ceiling: string;
    }};
  }};
  target_registry_requirements: {'REL.values': {execution_contract?: unknown}};
};
type ResourceType = {type: string; items?: ResourceType; fields?: Record<string, ResourceType>};
type ResourceCorpus = {cases: {name: string; schema: Record<string, ResourceType>; rows: Record<string, unknown>[];
  bytes: number; depth: number}[]};

const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
const aoa = read<AoA>('spec/contracts/actql-aoa.json');
const protocol = read<Parameters<typeof checkExecutionContract>[1]>('spec/contracts/actql-protocol-schemas.json');
const corpus = read<ValuesCorpus>('portability/corpus/rel-values-execution.json');
const schema = aoa.execution_contracts['REL.values'].params_schema;

test('compiler selects exact values execution and wire interpretation bodies', () => {
  const implementation = readFileSync('src/pipeline_check_context/core_contracts.mbt', 'utf8').replace(/\s+/g, ' ');
  const shared = readFileSync('src/pipeline_check_context/core_contract_shared.mbt', 'utf8').replace(/\s+/g, ' ');
  const execution = aoa.execution_contracts['REL.values'];
  const executionCid = 'sha256:acdc65097f478d6b14126eb2d2e1bdd8df5893de923b3f9db7412b73b4a318fe';
  const wire = read<object>('spec/contracts/actql-bound-values-wire-law.json');
  const wireCid = 'sha256:4c9bfcee52cbb204e8a00ca21e2e39b833cb298d517d498cc6002025cbf9156f';
  verifyIdentity(execution, executionCid);
  verifyIdentity(wire, wireCid);
  assert.ok(implementation.includes(`ValuesExecutionRules => "${executionCid}"`));
  assert.ok(implementation.includes(`ValuesWireLaw => "${wireCid}"`));
  // The collector must not silently treat a new declared dependency as a leaf.
  assert.deepEqual(execution.dependencies, {
    canonical_value_contract: {
      path: 'spec/contracts/actql-protocol-schemas.json',
      pointer: '/schemas/canonical_value_contract',
      cid: 'sha256:0d5ed4927156362554b6ac4fe442158f28063afad953c27755c0f5b5e4c3c7c1',
    },
  });
  verifyIdentity(protocol.schemas.canonical_value_contract,
    execution.dependencies.canonical_value_contract.cid);
  assert.match(shared, /ValuesExecutionRules => \{ let target = CatalogGrammarBody\(@environment\.ValueGrammarBody\) core_contract_edge\(b\) core_contract_body\(b, target\) core_contract_dependency\(b, ValuesExecutionRules, target\) \}/);
  assert.equal(Object.hasOwn(wire, 'dependencies'), false);
});

test('recursive resource scopes have independent fixed byte and type-depth vectors', () => {
  const resources = aoa.execution_contracts['REL.values'].semantics.recursive_resources;
  assert.deepEqual(resources.selected_root_types, ['array','object','vector']);
  assert.equal(resources.host_byte_ceiling, 'max_nested_value_bytes');
  assert.equal(resources.host_depth_ceiling, 'max_nested_value_depth');
  const depth = (t: ResourceType): number => t.type === 'array' ? 1 + depth(t.items!)
    : t.type === 'object' ? 1 + Math.max(0,...Object.values(t.fields!).map(depth))
    : t.type === 'vector' ? 1 : 0;
  for (const c of read<ResourceCorpus>('portability/corpus/values-recursive-resources.json').cases) {
    const names = Object.keys(c.schema).filter(k => ['array','object','vector'].includes(c.schema[k].type));
    const bytes = c.rows.reduce((total,row) => total + names.reduce(
      (n,k) => n + Buffer.byteLength(canonicalText(row[k]), 'utf8'), 0), 0);
    const typeDepth = Math.max(0,...Object.values(c.schema).map(depth));
    assert.equal(bytes,c.bytes,c.name); assert.equal(typeDepth,c.depth,c.name);
    const fits = (b: number,d: number) => bytes <= b && typeDepth <= d;
    assert.equal(fits(c.bytes,c.depth),true,c.name);
    if(c.bytes>0) assert.equal(fits(c.bytes-1,c.depth),false,c.name);
    if(c.depth>0) assert.equal(fits(c.bytes,c.depth-1),false,c.name);
  }
});

// Test-only interpreter for the explicit JSON Schema keyword subset used here.
// Unknown keywords fail loudly; this is neither a product validator nor a
// claim of general JSON Schema implementation conformance.
const supported = new Set(['$schema','$id','$defs','$ref','type','oneOf','anyOf','allOf','not','if','then','const','enum','required','properties','additionalProperties','propertyNames','items','minimum','maximum','minLength','minProperties','pattern']);
function validate(s: Schema, v: unknown, root = schema): boolean {
  if (typeof s === 'boolean') return s;
  for (const k of Object.keys(s)) assert.ok(supported.has(k), 'unsupported schema keyword: ' + k);
  if (s.$ref) {
    assert.ok(s.$ref.startsWith('#/'));
    const target = s.$ref.slice(2).split('/').reduce<unknown>((x,k) => (x as Record<string, unknown>)[k], root) as Schema;
    assert.ok(target);
    if (!validate(target,v,root)) return false;
  }
  const obj = (x: unknown): x is Record<string, unknown> => x !== null && typeof x === 'object' && !Array.isArray(x);
  const isType = (t: string) => t === 'object' ? obj(v) : t === 'array' ? Array.isArray(v) : t === 'null' ? v === null : t === 'integer' ? Number.isInteger(v) : typeof v === t;
  if (s.type && !(Array.isArray(s.type) ? s.type : [s.type]).some(isType)) return false;
  if (Object.hasOwn(s,'const') && !isDeepStrictEqual(s.const,v)) return false;
  if (s.enum && !s.enum.some(x => isDeepStrictEqual(x,v))) return false;
  if (s.oneOf && s.oneOf.filter(x => validate(x,v,root)).length !== 1) return false;
  if (s.anyOf && !s.anyOf.some(x => validate(x,v,root))) return false;
  if (s.allOf && !s.allOf.every(x => validate(x,v,root))) return false;
  if (s.not && validate(s.not,v,root)) return false;
  if (s.if && validate(s.if,v,root) && s.then && !validate(s.then,v,root)) return false;
  if (typeof v === 'number' && (v < (s.minimum ?? -Infinity) || v > (s.maximum ?? Infinity))) return false;
  if (typeof v === 'string' && ((s.pattern && !new RegExp(s.pattern,'u').test(v)) || [...v].length < (s.minLength ?? 0))) return false;
  if (Array.isArray(v) && s.items && !v.every(x => validate(s.items!,x,root))) return false;
  if (obj(v)) {
    if (Object.keys(v).length < (s.minProperties ?? 0)) return false;
    if (s.required?.some(k => !Object.hasOwn(v,k))) return false;
    for (const [k,x] of Object.entries(v)) {
      if (s.propertyNames && !validate(s.propertyNames,k,root)) return false;
      const p = s.properties && Object.hasOwn(s.properties,k) ? s.properties[k] : s.additionalProperties ?? true;
      if (!validate(p,x,root)) return false;
    }
  }
  return true;
}

test('execution contract and registration pin are complete and reproducible', () => {
  checkExecutionContract(aoa,protocol);
  for (const change of [
    a => {delete a.target_registry_requirements['REL.values'].execution_contract;},
    a => {a.execution_contracts['REL.values'].semantics.row_order = 'sort';},
    a => {a.execution_contracts['REL.values'].params_schema.additionalProperties = true;},
    a => {a.execution_contracts['REL.values'].dependencies.canonical_value_contract.cid = 'stale';},
  ] satisfies ((a: AoA) => void)[]) {
    const copy = structuredClone(aoa); change(copy);
    assert.throws(() => checkExecutionContract(copy,protocol));
  }
});

test('standalone schema validates fixed shapes separately from dependent values', () => {
  for (const c of corpus.cases) assert.equal(validate(schema,c.params), c.schema_valid, c.id);
  const decimal = (precision: number,scale: number) => ({schema:{x:{type:'decimal',nullable:false,precision,scale}},rows:[]});
  for (let p=0;p<=39;p++) for (let s=-1;s<=39;s++) {
    assert.equal(validate(schema,decimal(p,s)),p>=1 && p<=38 && s>=0 && s<=p);
  }
  for (const c of corpus.cases.filter(c => c.rows_valid?.some(v => !v))) {
    assert.equal(validate(schema,c.params),true,'shape is insufficient: ' + c.id);
  }
});

test('fixed canonical bytes retain row order and multiplicity, not object key order', () => {
  const cases = new Map(corpus.cases.map(c => [c.id,c]));
  for (const c of corpus.cases.filter(c => c.schema_valid && c.rows_valid.every(Boolean))) {
    verifyIdentity(c.params,c.expected_cid!,c.expected_canonical_json);
  }
  const cid = (id: string) => cases.get(id)!.expected_cid;
  assert.equal(cid('key-order-a'),cid('key-order-b'));
  assert.notEqual(cid('ordinary'),cid('reversed'));
  assert.notEqual(cid('ordinary'),cid('repeated'));
  assert.notEqual(cid('empty'),cid('repeated'));
  assert.equal(cid('plain-scalar'),cid('quoted-scalar'));
  assert.equal(cid('plain-scalar'),cid('bound-parameter'));
  assert.equal(cid('quoted-business-hole'),cid('supplied-business-hole'));
  // Explicit handoff assertions, not a substitute implementation of lowering.
  assert.deepEqual((cases.get('quoted-business-literal') as ValidValueCase).params.rows[0].x,{literal:1});
  assert.deepEqual((cases.get('supplied-business-hole') as ValidValueCase).params.rows[0].x,{$param:'business'});
  const mutated = structuredClone(cases.get('ordinary') as ValidValueCase);
  mutated.params.rows.reverse();
  assert.notEqual(canonicalText(mutated.params),mutated.expected_canonical_json);
  assert.throws(() => verifyIdentity(mutated.params,mutated.expected_cid!));
});
