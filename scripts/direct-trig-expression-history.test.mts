import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
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
const history = read<History>('portability/corpus/historical/pre-direct-trig-contract-identities.json');
const earlier = Object.fromEntries(history.contracts.map(value => [value.id, value.body]));
const earlierExpression = earlier.expression_contract;
const earlierProgram = earlier.program_schema;
assert.ok(earlierExpression && earlierProgram);

test('direct-trig retains complete predecessor bodies and identity preimages',()=>{
  assert.equal(history.source_revision,"745a2003524fc4000d978674e0a095ee46f038d1");
  assert.equal(history.source_revision_kind, 'published-parent-with-exact-recovery-tree-match');
  assert.equal(history.recovery_revision, '6502831d5b81de11b8486282cae39cb4faa01fd7');
  assert.equal(history.source_tree, 'c4d0ce434a62490bcef6b6287b58d4a120448dd7');
  assert.equal(cid(history),"sha256:4bd4518680f424877aafaefa8b25114a432d6bc38b41027ade89aca87d55ed07");
  assert.equal(history.contracts.length,12);
  for(const item of history.contracts)assert.equal(cid(item.body),item.cid,item.id);
  for(const item of history.expression_fragments.cases){assert.equal(canonical(item.body),item.canonical);assert.equal(cid(item.body),item.cid);assert.equal(Buffer.byteLength(item.canonical),item.bytes);}
  for(const item of history.ordered_fragment.preimages){assert.equal(canonical(history.ordered_fragment[item.id]!),item.canonical);assert.equal(cid(history.ordered_fragment[item.id]!),item.cid);}
  assert.equal(cid(history.policy_candidates.body),history.policy_candidates.expected_cid);
  const preimages=read<RetainedPreimages>('portability/corpus/historical/pre-direct-trig-preimages.json');
  assert.equal(cid(preimages),"sha256:87ae66ebf46d376f0ff61de57e30e61a83c9b9b7c8da7746db9c16921b81e822");
  assert.equal(preimages.source_revision,history.source_revision);
  assert.equal(preimages.expression_contract_cid,cid(earlierExpression));
  assert.equal(preimages.sources.length,17);assert.equal(new Set(preimages.sources.map(v=>v.source)).size,17);
  for(const item of preimages.sources)assert.equal(cid(item.body),item.cid,item.source);
  assert.equal(preimages.identity_envelopes.length,21);
  for(const item of preimages.identity_envelopes){assert.equal(canonical(item.envelope),item.canonical);assert.equal(cid(item.envelope),item.expected_cid);}
});

test('direct-trig adds only its exact closed source and machine alternatives and laws',()=>{
  const successor=Object.fromEntries(read<ContractHistory>('portability/corpus/historical/pre-translate-instr-contract-identities.json').contracts.map(v=>[v.id,v.body]));
  const expression=successor.expression_contract!;
  const program=successor.program_schema!;
  const names = new Set(['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2',
    'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh']);
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
        if (name === 'atan2') {
          assert.equal(body.type, 'array');
          assert.equal(body.minItems, 2);
          assert.equal(body.maxItems, 2);
          assert.ok(body.items);
          assert.deepEqual(Object.keys(body.items), ['$ref']);
          assert.match(body.items.$ref, /^#\/\$defs\/(expression|source_expression|machine_expression|value_expression)$/u);
        } else {
          assert.deepEqual(Object.keys(body), ['$ref']);
          assert.match(body.$ref, /^#\/\$defs\/(expression|source_expression|machine_expression|value_expression)$/u);
        }
        counts[name] = (counts[name] ?? 0) + 1;
        return false;
      });
    }
    return result;
  }
  const before = withoutIncrement(expression) as ContractBody;
  for(const name of names){assert.ok(expression.laws[name]);delete before.laws[name];}
  before.grammar_sha256=earlierExpression.grammar_sha256;
  // The earlier public parent retains its original target-selected laws.
  // The normally adopted #1375 repair is a separate, byte-pinned increment;
  // never rewrite that predecessor or infer this delta from product output.
  const kernel=read<{source_revision: string; laws: Record<string, JsonValue>}>('portability/corpus/historical/adopted-portable-numeric-kernel-laws.json');
  assert.equal(cid(kernel), 'sha256:78336d1cbf683b75363fd316cbf52b9880c6ed6092ba6d908b28b231cfa4b286');
  assert.equal(kernel.source_revision, '4dff63ffc946926dd17b100aea445b4ef5a31ef5');
  for(const [name,law] of Object.entries(kernel.laws)){
    assert.deepEqual(read<ContractBody>('spec/contracts/actql-expressions.json').laws[name], law, name+' adopted kernel law');
    assert.deepEqual(before.laws[name],earlierExpression.laws[name],name+' immutable predecessor law');
    before.laws[name]=structuredClone(earlierExpression.laws[name]!);
  }
  // The CBRT integration adopted the same existing portable scalar Owner.
  // Validate that separate immutable law before comparing the earlier raw recipe.
  const cbrtRepair=read<{source_revision: string; laws: {cbrt: JsonValue}}>('portability/corpus/historical/adopted-portable-cbrt-law.json');
  assert.equal(cid(cbrtRepair),'sha256:91d644b0fee614e94da4ec9eae7c424e038806433370da61af2020fa148f3b8d');
  assert.equal(cbrtRepair.source_revision,'52c7b73424ff08f2cf1acc45506152405eda2efd');
  // The retained successor predates this separate portable-CBRT adoption.
  assert.equal(cid(cbrtRepair.laws.cbrt),cid(read<ContractBody>('spec/contracts/actql-expressions.json').laws.cbrt!));
  assert.deepEqual(before.laws.cbrt,earlierExpression.laws.cbrt);
  before.laws.cbrt=structuredClone(earlierExpression.laws.cbrt!);
  assert.deepEqual(before,earlierExpression);
  assert.deepEqual(withoutIncrement(program),earlierProgram);
  assert.deepEqual(Object.keys(counts).sort(),[...names].sort());
  for(const count of Object.values(counts))assert.equal(count,8);
  assert.notEqual(cid(expression),cid(earlierExpression));assert.notEqual(cid(program),cid(earlierProgram));
  for (const id of ['scalar_law_manifest', 'production_profile_registry', 'barrier_manifest']) {
    const body = id === 'scalar_law_manifest'
      ? read<ContractHistory>('portability/corpus/historical/pre-exact-utc-timestamp.json').contracts.find(contract => contract.id === id)!.body
      : successor[id];
    assert.deepEqual(body, earlier[id]);
  }
});
