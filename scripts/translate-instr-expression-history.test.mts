import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
// Independently hash fixed authored JSON and retained envelopes, never runtime output.
type JsonValue = null | boolean | number | string | JsonValue[] | {[key: string]: JsonValue};
type ContractBody = {[key: string]: JsonValue} & {laws: Record<string, JsonValue>; grammar_sha256: string};
type Contract = {id: string; cid: string; body: ContractBody};
type ContractHistory = {contracts: Contract[]};
type Preimage = {canonical: string; cid: string};
type History = ContractHistory & {
  source_revision: string;
  source_revision_kind: string;
  recovery_revision: string;
  source_tree: string;
  expression_fragments: {cases: (Preimage & {body: JsonValue; bytes: number})[]};
  ordered_fragment: {preimages: (Preimage & {id: string})[]} & Record<string, JsonValue>;
  policy_candidates: {body: JsonValue; expected_cid: string};
};
type RetainedPreimages = {
  source_revision: string;
  expression_contract_cid: string;
  sources: {source: string; body: JsonValue; cid: string}[];
  identity_envelopes: {envelope: JsonValue; canonical: string; expected_cid: string}[];
};

function canonical(value: JsonValue): string {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key]!)).join(',') + '}';
  }
  return JSON.stringify(value);
}

const cid = (value: JsonValue) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
function read<T>(path: string): T {
  return JSON.parse(readFileSync(path, 'utf8'));
}
const history = read<History>('portability/corpus/historical/pre-translate-instr-contract-identities.json');
const earlier = Object.fromEntries(history.contracts.map(value => [value.id, value.body]));
const earlierExpression = earlier.expression_contract;
const earlierProgram = earlier.program_schema;
assert.ok(earlierExpression && earlierProgram);

test('translate-instr retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"21505177a8a7b54a2c273186b7d30456f757fcc4");
  assert.equal(history.source_revision_kind, 'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, '7ea785d48033a6b193ca1dc4d0eb951b689a1526');
  assert.equal(history.source_tree, '6180a210f8c80cd7d156f706bd2a230b485c1406');
  assert.equal(cid(history),"sha256:7d93e2fb1aae001453b36df5262992a7652740670cb6e52dac68dfb13f1f560c");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]!),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]!),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read<RetainedPreimages>('portability/corpus/historical/pre-translate-instr-preimages.json');
  assert.equal(cid(preimages),"sha256:4f4970b6064ab225c07744977b56d098cd8b31dc5986a8e7b7a1cf14a4a3b810");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlierExpression));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('translate-instr adds only its exact closed source and machine alternatives and laws',()=>{
  // Bind the exact adopted successor, not later scalar/Content extensions.
  const successor: {source_commit: string; bodies: Record<string, JsonValue> & {program_schema: JsonValue}} =
    JSON.parse(gunzipSync(readFileSync('scripts/fixtures/translate-instr-successor/contracts.json.gz')).toString('utf8'));
  assert.equal(successor.source_commit,'109564ef9a4f8241096292843b875d4c81fbb6f3');
  assert.equal(cid(successor),'sha256:04faa5a190134d528c3a8368d491a394fcd26ed427031f93bb0dea7c1f4d31d2');
  const expression: ContractBody =
    JSON.parse(gunzipSync(readFileSync('scripts/fixtures/native-local-scalar-predecessor/expression.json.gz')).toString('utf8'));
  assert.equal(cid(expression),'sha256:a49aba23a30514b63c9f7bcd05663dcacf2e5646c56073e7d00a34d6abe402b7');
  const program=successor.bodies.program_schema;
  assert.equal(cid(program),'sha256:1e63d8fb2cdfb0a8b54811762a96091ce2b7bc107089fd1682a76b1dbd57919b');
  const names = new Set(['translate', 'instr']);
  const counts: Record<string, number> = {};
  type ChildReference = {$ref: string; items?: {$ref: string}; type?: string; minItems?: number; maxItems?: number};
  type Alternative = {
    required?: string[];
    additionalProperties: boolean;
    properties?: Record<string, ChildReference> & {op?: {const: string}};
  };
  function withoutIncrement(value: JsonValue): JsonValue {
    if (Array.isArray(value)) return value.map(withoutIncrement);
    if (value === null || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, withoutIncrement(child)]));
    if (result.oneOf) {
      result.oneOf = (result.oneOf as (JsonValue & Alternative)[]).filter(shape => {
        const name = shape.properties?.op?.const ?? (shape.required?.length === 1 ? shape.required[0] : null);
        if (name == null || !names.has(name)) return true;
        const node = Boolean(shape.properties?.op);
        const body = shape.properties?.[node ? 'body' : name];
        assert.ok(body);
        assert.equal(shape.additionalProperties, false);
        assert.deepEqual(shape.required, node ? ['op', 'body'] : [name]);
        assert.equal(body.type, 'array');
        assert.equal(body.minItems, name === 'translate' ? 3 : 2);
        assert.equal(body.maxItems, name === 'translate' ? 3 : 4);
        assert.ok(body.items);
        assert.deepEqual(Object.keys(body.items), ['$ref']);
        counts[name] = (counts[name] ?? 0) + 1;
        return false;
      });
    }
    return result;
  }
  const before = withoutIncrement(expression) as ContractBody;
  for(const name of names){assert.ok(expression.laws[name]);delete before.laws[name];}
  before.grammar_sha256=earlierExpression.grammar_sha256;
  // Retain the separate main adoption of the portable numeric Owner.
  const adopted=read<{source_revision: string; laws: Record<string, JsonValue>}>('portability/corpus/historical/adopted-pre-translate-instr-numeric-laws.json');
  assert.equal(cid(adopted),'sha256:fdbe284a0274e4fc7d3359bd3b6e9dd1926b7c7e12cc331f79626aec5ca9b56f');
  assert.equal(adopted.source_revision,'d3555139c482d024d98ae9effd4bc5f3f73a8690');
  for(const [name,law] of Object.entries(adopted.laws)){
    assert.deepEqual(before.laws[name],law);
    before.laws[name]=structuredClone(earlierExpression.laws[name]!);
  }
  assert.deepEqual(before,earlierExpression);
  assert.deepEqual(withoutIncrement(program),earlierProgram);
  assert.deepEqual(Object.keys(counts).sort(),[...names].sort());
  for(const count of Object.values(counts))assert.equal(count,8);
  assert.notEqual(cid(expression),cid(earlierExpression));assert.notEqual(cid(program),cid(earlierProgram));
  for (const [id, path] of [
    ['scalar_law_manifest', 'spec/dependencies/aoa-rela-scalar-laws.json'],
    ['production_profile_registry', 'spec/contracts/actql-production-profile-schemas.json'],
    ['barrier_manifest', 'spec/manifests/actql-barrier-contracts-0.1.json'],
  ] as const) {
    const body = id === 'scalar_law_manifest'
      ? read<ContractHistory>('portability/corpus/historical/pre-exact-utc-timestamp.json').contracts.find(contract => contract.id === id)!.body
      : successor.bodies[path];
    assert.deepEqual(body, earlier[id]);
  }
});
