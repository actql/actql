import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateUnicodeScalarContracts} from './unicode-scalars-expression-contract.mjs';
const names = ['byte_length', 'unicode', 'chr'];
const grammar = 'function_name = "len" | "byte_length" | "octet_length" | "unicode" | "chr" ;\n';
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
  assert.deepEqual(updateUnicodeScalarContracts(...input, grammar, true), {source: 21, node: 9});
  return input;
};

test('Unicode scalars own three direct unary shapes across all ten embeddings', () => {
  const input = ready();
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) {
      const body = {$ref: `#/$defs/${path[2]}`};
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: name}, body}};
      assert.deepEqual(find(at(input, path), kind, name), expected);
      assert.equal(find(at(input, path), kind, 'octet_length'), undefined);
    }
  }
  assert.equal(input[0].grammar_sha256, createHash('sha256').update(grammar).digest('hex'));
  const before = structuredClone(input);
  updateUnicodeScalarContracts(...input, grammar);
  assert.deepEqual(input, before);
  updateUnicodeScalarContracts(...input, grammar, true);
  assert.deepEqual(input, before);
});

test('Unicode scalar laws independently specify bytes, first scalar, CHR domain and boundaries', () => {
  const laws = ready()[0].laws;
  for (const name of names) {
    assert.match(laws[name].evaluation, /sole child exactly once/u);
    assert.match(laws[name].evaluation + laws[name].value, /strict NULL propagation/u);
    assert.match(laws[name].evaluation, /lazy demand/u);
    assert.match(laws[name].evaluation, /cooperative cancellation/u);
    assert.match(laws[name].identity, /without folding or duplication/u);
    assert.match(laws[name].signature, /operand nullability/u);
    assert.match(laws[name].signature, /No implicit conversion/u);
  }
  assert.match(laws.byte_length.value, /exact UTF-8 byte count of the complete String/u);
  assert.match(laws.byte_length.value, /zero for empty/u);
  assert.match(laws.byte_length.identity, /BYTE_LENGTH and OCTET_LENGTH select this same unary operation/u);
  assert.match(laws.unicode.value, /first scalar/u);
  assert.match(laws.unicode.value, /Empty input and a first U\+0000 both return zero/u);
  assert.match(laws.unicode.value, /not a UTF-16 surrogate or UTF-8 byte/u);
  assert.match(laws.chr.value, /integral Number in \[0, 55295\] or \[57344, 1114111\]/u);
  assert.match(laws.chr.value, /Reject fractions, negative values, surrogate code points/u);
  assert.match(laws.chr.value, /Zero returns the empty String/u);
  assert.match(laws.chr.value, /including noncharacters/u);
  assert.match(laws.chr.typing, /max_codepoints 1 and max_utf8_bytes 4/u);
  assert.match(laws.chr.evaluation, /before bounded conversion/u);
  assert.match(laws.chr.evaluation, /before construction/u);
});

test('Unicode scalar freshness refuses every open, array, child-ref or alias mutation', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) {
    for (const path of paths) for (const name of names) for (const mutate of [
      s => {s.additionalProperties = true;},
      s => {s.properties[kind === 'source' ? name : 'body'] = {type: 'array', minItems: 1, maxItems: 1, items: {$ref: `#/$defs/${path[2]}`}};},
      s => {s.properties[kind === 'source' ? name : 'body'].$ref = '#/$defs/wrong';},
    ]) {
      const input = ready(); mutate(find(at(input, path), kind, name));
      const before = structuredClone(input);
      assert.throws(() => updateUnicodeScalarContracts(...input, grammar), /stale/u);
      assert.deepEqual(input, before);
    }
    for (const path of paths) {
      const input = ready(), shape = structuredClone(find(at(input, path), kind, 'byte_length'));
      if (kind === 'source') {shape.required = ['octet_length']; shape.properties = {octet_length: shape.properties.byte_length};}
      else shape.properties.op.const = 'octet_length';
      at(input, path).oneOf.push(shape);
      const before = structuredClone(input);
      assert.throws(() => updateUnicodeScalarContracts(...input, grammar, true), /alias/u);
      assert.deepEqual(input, before);
    }
  }
});

test('Unicode scalar preflight refuses missing duplicate and comment-only tokens atomically', () => {
  for (const name of [...names, 'octet_length']) for (const invalid of [
    grammar.replace(` | "${name}"`, ''),
    grammar.replace(`"${name}"`, `(* "${name}" *)`),
    grammar.replace(`"${name}"`, `"${name}" | "${name}"`),
  ]) {
    const input = bodies(), before = structuredClone(input);
    assert.throws(() => updateUnicodeScalarContracts(...input, invalid, true));
    assert.deepEqual(input, before);
  }
});

test('Unicode scalar preflight refuses missing scopes duplicate nodes and wrong unary templates', () => {
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) for (const mutate of [
    scope => {delete scope.oneOf;},
    scope => {scope.oneOf.push(structuredClone(find(scope, kind, 'chr')));},
    scope => {find(scope, kind, 'len').additionalProperties = true;},
    scope => {find(scope, kind, 'len').properties[kind === 'source' ? 'len' : 'body'].$ref = '#/$defs/wrong';},
  ]) {
    const input = ready(); mutate(at(input, path));
    const before = structuredClone(input);
    assert.throws(() => updateUnicodeScalarContracts(...input, grammar, true));
    assert.deepEqual(input, before);
  }
  const input = ready(); input[0].schemas.unregistered = structuredClone(at(input, sources[0]));
  const before = structuredClone(input);
  assert.throws(() => updateUnicodeScalarContracts(...input, grammar, true), /unregistered/u);
  assert.deepEqual(input, before);
});

test('Unicode scalar freshness refuses semantic law grammar and identity mutations', () => {
  for (const mutate of [
    ...names.flatMap(name => Object.keys(ready()[0].laws[name]).map(key => b => {b[0].laws[name][key] = 'invalid';})),
    b => {b[0].grammar_sha256 = '0'.repeat(64);},
    b => {b[1].artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);},
    b => {b[1].artifact_registry_cid = 'sha256:' + '0'.repeat(64);},
  ]) {
    const input = ready(); mutate(input); const before = structuredClone(input);
    assert.throws(() => updateUnicodeScalarContracts(...input, grammar));
    assert.deepEqual(input, before);
  }
});

test('Unicode scalar registration preserves all other laws schemas and profiles', () => {
  const input = bodies(), before = structuredClone(input);
  updateUnicodeScalarContracts(...input, grammar, true);
  for (const [kind, paths] of [['source', sources], ['node', nodes]]) for (const path of paths) {
    for (const b of [input, before]) at(b, path).oneOf = at(b, path).oneOf.filter(s => !names.some(name => s === find(at(b, path), kind, name)));
  }
  for (const name of names) {delete input[0].laws[name]; delete before[0].laws[name];}
  input[0].grammar_sha256 = before[0].grammar_sha256;
  input[1].artifact_schema_cids = before[1].artifact_schema_cids;
  input[1].artifact_registry_cid = before[1].artifact_registry_cid;
  assert.deepEqual(input, before);
});

test('Unicode scalar updater accepts the real common EBNF registration', () => {
  const input = bodies(), actual = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  updateUnicodeScalarContracts(...input, actual, true);
  assert.deepEqual(updateUnicodeScalarContracts(...input, actual), {source: 21, node: 9});
});
