import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateDirectTrigContracts} from './direct-trig-expression-contract.mjs';
const names = ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh'];
const grammar = 'function_name = "len" | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "atan2" | "sinh" | "cosh" | "tanh" | "asinh" | "acosh" | "atanh" ;\n';
const bodies = () => ['actql-expressions', 'actql-protocol-schemas']
  .map(name => JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8')));
// Independent exhaustive list of existing owner embeddings and local refs.
const sources = [
  [0, 'schemas/expression/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/source_expression', 'source_expression'],
  [0, 'schemas/predicate_consumer/$defs/source_expression', 'source_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
];
const nodes = [
  [0, 'schemas/expression_node/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/machine_expression', 'machine_expression'],
  [0, 'schemas/predicate_consumer/$defs/machine_expression', 'machine_expression'],
];
const at = (input, [owner, path]) => path.split('/').reduce((v, key) => v[key], input[owner]);
const find = (scope, kind, name) => scope.oneOf.find(v =>
  kind === 'source' ? v.required?.includes(name) : v.properties?.op?.const === name);
const ready = () => {
  const input = bodies();
  assert.deepEqual(updateDirectTrigContracts(...input, grammar, true), {source: 91, node: 39});
  return input;
};

test('direct trigonometric operations own exact direct unary and ordered binary shapes across all ten embeddings', () => {
  const input = ready();
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) {
      const child = {$ref: `#/$defs/${path[2]}`};
      const body = name === 'atan2' ? {type: 'array', minItems: 2, maxItems: 2, items: child} : child;
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: name}, body}};
      assert.deepEqual(find(at(input, path), kind, name), expected);
    }
  }
  assert.equal(input[0].grammar_sha256, createHash('sha256').update(grammar).digest('hex'));
  const before = structuredClone(input);
  updateDirectTrigContracts(...input, grammar);
  assert.deepEqual(input, before);
  updateDirectTrigContracts(...input, grammar, true);
  assert.deepEqual(input, before);
});

test('direct trigonometric laws independently preserve numeric and demand obligations', () => {
  const laws = ready()[0].laws;
  for (const name of names) {
    const law = laws[name];
    assert.match(law.signature, /finite binary64 Number operand/u);
    assert.match(law.signature, /nullable exactly when/u);
    assert.match(law.signature, /No implicit conversion/u);
    assert.match(law.typing, /without evaluating it/u);
    assert.match(law.value, /NULL produces NULL after all demanded children succeed/u);
    assert.match(law.value, /Reject non-finite operands/u);
    assert.match(law.value, /Canonicalize every zero result to positive zero/u);
    assert.match(law.value, /existing arithmetic failure/u);
    assert.match(law.algorithm, new RegExp(`pinned portable MoonBit core Double ${name} primitive`, 'u'));
    assert.match(law.algorithm, /Do not reconstruct it/u);
    assert.match(law.algorithm, /Preserve every existing numeric accuracy and exception contract/u);
    assert.match(law.algorithm, /exact logical Number bits across targets/u);
    assert.match(law.algorithm, /source manifest sha256:254e734f8e44242b835b0a6c2505011b5eea6b9883dfa3db8c1b74e061757e0b/u);
    assert.match(law.algorithm, /no live-BigQuery last-bit equivalence/u);
    assert.match(law.evaluation, /exactly once/u);
    assert.match(law.evaluation, /before strict NULL propagation/u);
    assert.match(law.evaluation, /lazy demand/u);
    assert.match(law.evaluation, /cooperative cancellation/u);
    assert.match(law.identity, /without folding or duplication/u);
    assert.match(law.identity, /including constants/u);
  }
  for (const name of ['asin', 'acos']) assert.match(laws[name].value, /fail outside \[-1, 1\]/u);
  assert.match(laws.acosh.value, /fail for values less than 1/u);
  assert.match(laws.atanh.value, /-1 < value < 1, including failure at both endpoints/u);
  assert.match(laws.atan2.value, /Pass first then second directly to core atan2, without dividing or swapping/u);
  assert.match(laws.atan2.value, /\(\+0, -0\) selects positive pi and \(-0, -0\) selects negative pi/u);
  assert.match(laws.atan2.value, /Canonical public Number zero is positive/u);
  assert.match(laws.atan2.evaluation, /authored left-to-right order/u);
});

test('direct trigonometric operations freshness refuses every open, wrong arity, body or child-reference mutation', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) {
      const key = kind === 'source' ? name : 'body';
      const mutations = [
        s => {s.additionalProperties = true;},
        s => {s.properties[key] = name === 'atan2' ? {$ref: `#/$defs/${path[2]}`} : {type: 'array', minItems: 1, maxItems: 1, items: {$ref: `#/$defs/${path[2]}`}};},
        s => {(name === 'atan2' ? s.properties[key].items : s.properties[key]).$ref = '#/$defs/wrong';},
      ];
      if (name === 'atan2') mutations.push(
        s => {s.properties[key].minItems = 1;},
        s => {s.properties[key].maxItems = 3;},
        s => {delete s.properties[key].maxItems;},
      );
      for (const mutate of mutations) {
        const input = ready(); mutate(find(at(input, path), kind, name));
        const before = structuredClone(input);
        assert.throws(() => updateDirectTrigContracts(...input, grammar), /stale/u);
        assert.deepEqual(input, before);
      }
    }
  }
});

test('direct trigonometric operations preflight refuses missing duplicate and comment-only tokens atomically', () => {
  for (const name of names) for (const invalid of [
    grammar.replace(` | "${name}"`, ''),
    grammar.replace(`"${name}"`, `(* "${name}" *)`),
    grammar.replace(`"${name}"`, `"${name}" | "${name}"`),
  ]) {
    const input = bodies(), before = structuredClone(input);
    assert.throws(() => updateDirectTrigContracts(...input, invalid, true));
    assert.deepEqual(input, before);
  }
});

test('direct trigonometric operations preflight refuses missing scopes duplicate nodes and wrong unary templates', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) for (const mutate of [
    scope => {delete scope.oneOf;},
    scope => {scope.oneOf.push(structuredClone(find(scope, kind, 'atan2')));},
    scope => {find(scope, kind, 'len').additionalProperties = true;},
    scope => {find(scope, kind, 'len').properties[kind === 'source' ? 'len' : 'body'].$ref = '#/$defs/wrong';},
  ]) {
    const input = ready(); mutate(at(input, path));
    const before = structuredClone(input);
    assert.throws(() => updateDirectTrigContracts(...input, grammar, true));
    assert.deepEqual(input, before);
  }
  const input = ready(); input[0].schemas.unregistered = structuredClone(at(input, sources[0]));
  const before = structuredClone(input);
  assert.throws(() => updateDirectTrigContracts(...input, grammar, true), /unregistered/u);
  assert.deepEqual(input, before);
});

test('direct trigonometric operations freshness refuses semantic law grammar and identity mutations', () => {
  for (const mutate of [
    ...names.flatMap(name => Object.keys(ready()[0].laws[name]).map(key => b => {b[0].laws[name][key] = 'invalid';})),
    b => {b[0].grammar_sha256 = '0'.repeat(64);},
    b => {b[1].artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);},
    b => {b[1].artifact_registry_cid = 'sha256:' + '0'.repeat(64);},
  ]) {
    const input = ready(); mutate(input); const before = structuredClone(input);
    assert.throws(() => updateDirectTrigContracts(...input, grammar));
    assert.deepEqual(input, before);
  }
});

test('direct trigonometric operations registration preserves all other laws schemas and profiles', () => {
  const input = bodies(), before = structuredClone(input);
  updateDirectTrigContracts(...input, grammar, true);
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) {
    for (const b of [input, before]) at(b, path).oneOf = at(b, path).oneOf.filter(s => !names.some(name => s === find(at(b, path), kind, name)));
  }
  for (const name of names) {delete input[0].laws[name]; delete before[0].laws[name];}
  input[0].grammar_sha256 = before[0].grammar_sha256;
  input[1].artifact_schema_cids = before[1].artifact_schema_cids;
  input[1].artifact_registry_cid = before[1].artifact_registry_cid;
  assert.deepEqual(input, before);
});

test('direct trigonometric operations updater accepts the real common EBNF registration', () => {
  const input = bodies(), actual = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  updateDirectTrigContracts(...input, actual, true);
  assert.deepEqual(updateDirectTrigContracts(...input, actual), {source: 91, node: 39});
});
