import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateRepeatReverseContracts} from './repeat-reverse-expression-contract.mjs';
const names = ['repeat', 'reverse'];
const grammar = 'function_name = "len" | "repeat" | "reverse" ;\n';
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
  assert.deepEqual(updateRepeatReverseContracts(...input, grammar, true), {source: 14, node: 6});
  return input;
};

test('REPEAT and REVERSE own exact binary and unary shapes across all ten embeddings', () => {
  const input = ready();
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) {
      const child = {$ref: `#/$defs/${path[2]}`};
      const body = name === 'repeat' ? {type: 'array', minItems: 2, maxItems: 2, items: child} : child;
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: name}, body}};
      assert.deepEqual(find(at(input, path), kind, name), expected);
    }
  }
  assert.equal(input[0].grammar_sha256, createHash('sha256').update(grammar).digest('hex'));
  const before = structuredClone(input);
  updateRepeatReverseContracts(...input, grammar);
  assert.deepEqual(input, before);
  updateRepeatReverseContracts(...input, grammar, true);
  assert.deepEqual(input, before);
});

test('REPEAT/REVERSE laws independently specify Number adaptation and scalar preservation', () => {
  const laws = ready()[0].laws;
  for (const name of names) {
    assert.match(laws[name].evaluation, /exactly once/u);
    assert.match(laws[name].evaluation, /before strict NULL propagation/u);
    assert.match(laws[name].evaluation, /lazy demand/u);
    assert.match(laws[name].evaluation, /cooperative cancellation/u);
    assert.match(laws[name].identity, /without folding or duplication/u);
    assert.match(laws[name].signature, /No implicit conversion/u);
  }
  assert.match(laws.repeat.signature, /STRING followed by finite Number/u);
  assert.match(laws.repeat.signature, /union of operand nullabilities/u);
  assert.match(laws.repeat.typing, /drop input minimum and maximum length bounds/u);
  assert.match(laws.repeat.value, /nonnegative integral Number count/u);
  assert.match(laws.repeat.value, /without a safe-integer or INT64 cap/u);
  assert.match(laws.repeat.value, /Reject negative and fractional counts before an empty-input shortcut/u);
  assert.match(laws.repeat.value, /including empty input with a very large valid count/u);
  assert.match(laws.repeat.evaluation, /left to right/u);
  assert.match(laws.repeat.evaluation, /existing storage limits before narrowing/u);
  assert.match(laws.repeat.evaluation, /resource owners before allocation/u);
  assert.match(laws.repeat.evaluation, /do not impose a new scalar count cap/u);
  assert.match(laws.reverse.value, /Unicode scalar sequence in reverse order/u);
  assert.match(laws.reverse.value, /including astral characters and U\+0000/u);
  assert.match(laws.reverse.value, /without normalization or grapheme segmentation/u);
  assert.match(laws.reverse.value, /Do not reverse UTF-16 code units or encoded bytes/u);
  assert.match(laws.reverse.typing, /min_length, max_codepoints and max_utf8_bytes/u);
});

test('REPEAT/REVERSE freshness refuses every open, wrong arity, body or child-reference mutation', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) {
      const key = kind === 'source' ? name : 'body';
      const mutations = [
        s => {s.additionalProperties = true;},
        s => {s.properties[key] = name === 'repeat' ? {$ref: `#/$defs/${path[2]}`} : {type: 'array', minItems: 1, maxItems: 1, items: {$ref: `#/$defs/${path[2]}`}};},
        s => {(name === 'repeat' ? s.properties[key].items : s.properties[key]).$ref = '#/$defs/wrong';},
      ];
      if (name === 'repeat') mutations.push(
        s => {s.properties[key].minItems = 1;},
        s => {s.properties[key].maxItems = 3;},
        s => {delete s.properties[key].maxItems;},
      );
      for (const mutate of mutations) {
        const input = ready(); mutate(find(at(input, path), kind, name));
        const before = structuredClone(input);
        assert.throws(() => updateRepeatReverseContracts(...input, grammar), /stale/u);
        assert.deepEqual(input, before);
      }
    }
  }
});

test('REPEAT/REVERSE preflight refuses missing duplicate and comment-only tokens atomically', () => {
  for (const name of names) for (const invalid of [
    grammar.replace(` | "${name}"`, ''),
    grammar.replace(`"${name}"`, `(* "${name}" *)`),
    grammar.replace(`"${name}"`, `"${name}" | "${name}"`),
  ]) {
    const input = bodies(), before = structuredClone(input);
    assert.throws(() => updateRepeatReverseContracts(...input, invalid, true));
    assert.deepEqual(input, before);
  }
});

test('REPEAT/REVERSE preflight refuses missing scopes duplicate nodes and wrong unary templates', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) for (const mutate of [
    scope => {delete scope.oneOf;},
    scope => {scope.oneOf.push(structuredClone(find(scope, kind, 'reverse')));},
    scope => {find(scope, kind, 'len').additionalProperties = true;},
    scope => {find(scope, kind, 'len').properties[kind === 'source' ? 'len' : 'body'].$ref = '#/$defs/wrong';},
  ]) {
    const input = ready(); mutate(at(input, path));
    const before = structuredClone(input);
    assert.throws(() => updateRepeatReverseContracts(...input, grammar, true));
    assert.deepEqual(input, before);
  }
  const input = ready(); input[0].schemas.unregistered = structuredClone(at(input, sources[0]));
  const before = structuredClone(input);
  assert.throws(() => updateRepeatReverseContracts(...input, grammar, true), /unregistered/u);
  assert.deepEqual(input, before);
});

test('REPEAT/REVERSE freshness refuses semantic law grammar and identity mutations', () => {
  for (const mutate of [
    ...names.flatMap(name => Object.keys(ready()[0].laws[name]).map(key => b => {b[0].laws[name][key] = 'invalid';})),
    b => {b[0].grammar_sha256 = '0'.repeat(64);},
    b => {b[1].artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);},
    b => {b[1].artifact_registry_cid = 'sha256:' + '0'.repeat(64);},
  ]) {
    const input = ready(); mutate(input); const before = structuredClone(input);
    assert.throws(() => updateRepeatReverseContracts(...input, grammar));
    assert.deepEqual(input, before);
  }
});

test('REPEAT/REVERSE registration preserves all other laws schemas and profiles', () => {
  const input = bodies(), before = structuredClone(input);
  updateRepeatReverseContracts(...input, grammar, true);
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) {
    for (const b of [input, before]) at(b, path).oneOf = at(b, path).oneOf.filter(s => !names.some(name => s === find(at(b, path), kind, name)));
  }
  for (const name of names) {delete input[0].laws[name]; delete before[0].laws[name];}
  input[0].grammar_sha256 = before[0].grammar_sha256;
  input[1].artifact_schema_cids = before[1].artifact_schema_cids;
  input[1].artifact_registry_cid = before[1].artifact_registry_cid;
  assert.deepEqual(input, before);
});

test('REPEAT/REVERSE updater accepts the real common EBNF registration', () => {
  const input = bodies(), actual = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  updateRepeatReverseContracts(...input, actual, true);
  assert.deepEqual(updateRepeatReverseContracts(...input, actual), {source: 14, node: 6});
});
