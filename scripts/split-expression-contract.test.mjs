import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateSplitContracts} from './split-expression-contract.mjs';

// Real retained embedding owners, independently listed here. Unit writes are
// in-memory only; passing these tests is not generated-contract freshness.
const bodies = () => ['actql-expressions', 'actql-protocol-schemas']
  .map(name => JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8')));
const grammar = 'function_name = "replace" | "split" | "split_part" ;\n';
const sourcePaths = [
  [0, 'schemas/expression/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/source_expression', 'source_expression'],
  [0, 'schemas/predicate_consumer/$defs/source_expression', 'source_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
];
const nodePaths = [
  [0, 'schemas/expression_node/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/machine_expression', 'machine_expression'],
  [0, 'schemas/predicate_consumer/$defs/machine_expression', 'machine_expression'],
];
const at = (b, [owner, path]) => path.split('/').reduce((v, key) => v[key], b[owner]);
const find = (scope, kind, name = 'split') => scope.oneOf.find(s =>
  kind === 'source' ? s.required?.includes(name) : s.properties?.op?.const === name);
const ready = () => {
  const input = bodies();
  assert.deepEqual(updateSplitContracts(...input, grammar, true), {source: 7, node: 3});
  return input;
};

test('SPLIT declares closed one-or-two arrays with all ten independent local refs', () => {
  const input = ready();
  for (const [kind, paths] of [['source', sourcePaths], ['node', nodePaths]]) {
    for (const path of paths) {
      const body = {type: 'array', minItems: 1, maxItems: 2,
        items: {$ref: `#/$defs/${path[2]}`}};
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: ['split'], properties: {split: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'],
          properties: {op: {const: 'split'}, body}};
      assert.deepEqual(find(at(input, path), kind), expected, path[1]);
    }
  }
  assert.equal(input[0].grammar_sha256, createHash('sha256').update(grammar).digest('hex'));
  const before = structuredClone(input);
  updateSplitContracts(...input, grammar);
  assert.deepEqual(input, before, 'read-only check');
  updateSplitContracts(...input, grammar, true);
  assert.deepEqual(input, before, 'idempotent writer');
});

test('SPLIT law independently retains String, Array, dynamic delimiter, demand and budget owners', () => {
  const law = ready()[0].laws.split;
  assert.deepEqual(Object.keys(law).sort(), ['admission', 'evaluation', 'identity', 'signature', 'typing', 'value']);
  for (const [key, patterns] of Object.entries({
    signature: [/optional ordinary STRING delimiter expression/u, /non-null String elements/u,
      /nullable exactly when any supplied operand is nullable/u, /No implicit conversion, BYTES/u],
    value: [/non-overlapping literal/u, /leading, adjacent and trailing empty parts/u,
      /Omitted delimiter is U\+002C COMMA/u, /Empty input produces one empty String/u,
      /empty delimiter on nonempty input produces one String per Unicode scalar/u,
      /does not restrict the delimiter expression to a literal or parameter/u],
    typing: [/max_codepoints and max_utf8_bytes/u, /drop min_length/u,
      /safe-integer bound domain; otherwise omit max_items/u, /Do not evaluate either child/u],
    evaluation: [/exactly once in authored order/u, /before strict NULL propagation/u,
      /NULL does not suppress a later demanded child failure/u, /first child failure and enclosing lazy demand/u,
      /retains operand roots, logical operand\/result charges/u, /cooperative cancellation/u],
    identity: [/one-element array for omission/u, /distinct from explicit NULL and explicit comma/u,
      /without folding, sorting or duplication/u, /Earlier pinned contract bodies retain/u],
    admission: [/no split-specific text-time profile, policy or envelope/u,
      /before allocating output builders or storage/u, /No eager whole-input split or retained boundary array/u,
      /split_part retains its separately owned text-time law/u],
  })) for (const pattern of patterns) assert.match(law[key], pattern);
});

test('SPLIT freshness refuses each embedded arity, open shape, child-ref and unary mutation', () => {
  for (const [kind, paths] of [['source', sourcePaths], ['node', nodePaths]]) {
    for (const path of paths) for (const mutate of [
      s => {s.additionalProperties = true;},
      s => {s.properties[kind === 'source' ? 'split' : 'body'].minItems = 0;},
      s => {s.properties[kind === 'source' ? 'split' : 'body'].maxItems = 3;},
      s => {s.properties[kind === 'source' ? 'split' : 'body'].items.$ref = '#/$defs/wrong';},
      s => {s.properties[kind === 'source' ? 'split' : 'body'] = {$ref: `#/$defs/${path[2]}`};},
    ]) {
      const input = ready(); mutate(find(at(input, path), kind));
      const before = structuredClone(input);
      assert.throws(() => updateSplitContracts(...input, grammar), /stale .* split shape/u, path[1]);
      assert.deepEqual(input, before, 'failed read-only check must not repair input');
    }
  }
});

test('SPLIT freshness refuses semantic-law and declared-identity mutations', () => {
  for (const mutate of [
    b => {b[0].laws.split.signature = 'accept BYTES';},
    b => {b[0].laws.split.value = 'empty delimiter preserves whole input';},
    b => {b[0].laws.split.typing = 'inherit minimum length';},
    b => {b[0].laws.split.evaluation = 'return NULL before delimiter';},
    b => {b[0].laws.split.identity = 'insert comma child on omission';},
    b => {b[0].laws.split.admission = 'allocate output then measure';},
    b => {b[0].grammar_sha256 = '0'.repeat(64);},
    b => {b[1].artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);},
    b => {b[1].artifact_registry_cid = 'sha256:' + '0'.repeat(64);},
  ]) {
    const input = ready(); mutate(input);
    const before = structuredClone(input);
    assert.throws(() => updateSplitContracts(...input, grammar));
    assert.deepEqual(input, before);
  }
});

test('SPLIT preflight refuses absent, duplicate or comment-only grammar before writes', () => {
  for (const invalid of [
    'function_name = "replace" | "split_part" ;\n',
    'function_name = "replace" ; (* | "split" *)\n',
    'other = "split" ; function_name = "replace" ;\n',
    'function_name = "split" | "split" ;\n',
  ]) {
    const input = bodies(), before = structuredClone(input);
    assert.throws(() => updateSplitContracts(...input, invalid, true));
    assert.deepEqual(input, before);
  }
});

test('SPLIT preflight refuses missing scopes, duplicate shapes and wrong templates atomically', () => {
  for (const [kind, paths] of [['source', sourcePaths], ['node', nodePaths]]) {
    for (const path of paths) for (const mutate of [
      scope => {delete scope.oneOf;},
      scope => {scope.oneOf.push(structuredClone(find(scope, kind)));},
      scope => {find(scope, kind, 'replace').additionalProperties = true;},
      scope => {find(scope, kind, 'replace').properties[kind === 'source' ? 'replace' : 'body'].items.$ref = '#/$defs/wrong';},
    ]) {
      const input = ready(); mutate(at(input, path));
      const before = structuredClone(input);
      assert.throws(() => updateSplitContracts(...input, grammar, true));
      assert.deepEqual(input, before, 'preflight failure must precede every mutation');
    }
  }
  const input = ready();
  input[0].schemas.unregistered = structuredClone(at(input, sourcePaths[0]));
  const before = structuredClone(input);
  assert.throws(() => updateSplitContracts(...input, grammar, true), /unregistered/u);
  assert.deepEqual(input, before);
});

test('SPLIT registration preserves every unrelated law, schema and split_part profile', () => {
  const input = bodies(), before = structuredClone(input);
  updateSplitContracts(...input, grammar, true);
  for (const [kind, paths] of [['source', sourcePaths], ['node', nodePaths]]) {
    for (const path of paths) {
      const scope = at(input, path);
      scope.oneOf = scope.oneOf.filter(value => value !== find(scope, kind));
      // This test supports running after SPLIT closure as well as before it.
      const prior = at(before, path);
      prior.oneOf = prior.oneOf.filter(value => value !== find(prior, kind));
    }
  }
  delete input[0].laws.split; delete before[0].laws.split;
  input[0].grammar_sha256 = before[0].grammar_sha256;
  input[1].artifact_schema_cids = before[1].artifact_schema_cids;
  input[1].artifact_registry_cid = before[1].artifact_registry_cid;
  assert.deepEqual(input, before);
});

test('SPLIT updater accepts the declared common EBNF with in-memory registration only', () => {
  const actualGrammar = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const input = bodies();
  updateSplitContracts(...input, actualGrammar, true);
  assert.deepEqual(updateSplitContracts(...input, actualGrammar), {source: 7, node: 3});
});
