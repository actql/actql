import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {updateTranslateInstrContracts, type translateInstrLaws, type TranslateInstrSchema} from './translate-instr-expression-contract.mjs';
type Contract = Parameters<typeof updateTranslateInstrContracts>;
type Input = [Contract[0] & {laws: Partial<Record<keyof typeof translateInstrLaws, typeof translateInstrLaws.translate & Record<string, string>>>}, Contract[1]];
type Embedding = [owner: 0 | 1, path: string, reference: string];
type SchemaScope = TranslateInstrSchema & {oneOf: TranslateInstrSchema[]};
type Kind = 'source' | 'node';
const names = ['translate', 'instr'] as const;
const grammar = 'function_name = "len" | "translate" | "instr" ;\n';
const bodies = (): Input => [
  JSON.parse(readFileSync('spec/contracts/actql-expressions.json', 'utf8')),
  JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8')),
];
// Independent exhaustive list of existing owner embeddings and local refs.
const sources: [Embedding, ...Embedding[]] = [
  [0, 'schemas/expression/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/source_expression', 'source_expression'],
  [0, 'schemas/predicate_consumer/$defs/source_expression', 'source_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/executable_plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/predicate', 'value_expression'],
  [1, 'artifact_schemas/plan_document/properties/plan/properties/execution_material/properties/program/$defs/value_expression', 'value_expression'],
];
const nodes: Embedding[] = [
  [0, 'schemas/expression_node/$defs/expression', 'expression'],
  [0, 'schemas/fragment/$defs/machine_expression', 'machine_expression'],
  [0, 'schemas/predicate_consumer/$defs/machine_expression', 'machine_expression'],
];
const scopes: [Kind, Embedding[]][] = [['source', sources], ['node', nodes]];
const at = (input: Input, [owner, path]: Embedding): SchemaScope =>
  path.split('/').reduce<unknown>((v, key) => (v as Record<string, unknown>)[key], input[owner]) as SchemaScope;
const find = (scope: SchemaScope, kind: Kind, name: string) => scope.oneOf.find(v =>
  kind === 'source' ? v.required?.includes(name) : v.properties?.op?.const === name)!;
const ready = () => {
  const input = bodies();
  assert.deepEqual(updateTranslateInstrContracts(...input, grammar, true), {source: 14, node: 6});
  return input;
};

test('TRANSLATE/INSTR own exact exact authored-arity array shapes across all ten embeddings', () => {
  const input = ready();
  for (const [kind, paths] of scopes) {
    for (const path of paths) for (const name of names) {
      const child = {$ref: `#/$defs/${path[2]}`};
      const body = {type: 'array', minItems: name === 'translate' ? 3 : 2, maxItems: name === 'translate' ? 3 : 4, items: child};
      const expected = kind === 'source'
        ? {type: 'object', additionalProperties: false, required: [name], properties: {[name]: body}}
        : {type: 'object', additionalProperties: false, required: ['op', 'body'], properties: {op: {const: name}, body}};
      assert.deepEqual(find(at(input, path), kind, name), expected);
    }
  }
  assert.equal(input[0].grammar_sha256, createHash('sha256').update(grammar).digest('hex'));
  const before = structuredClone(input);
  updateTranslateInstrContracts(...input, grammar);
  assert.deepEqual(input, before);
  updateTranslateInstrContracts(...input, grammar, true);
  assert.deepEqual(input, before);
});

test('TRANSLATE/INSTR laws independently preserve exact scalars domains and authored omission', () => {
  const laws = ready()[0].laws;
  for (const law of [laws.translate, laws.instr]) {
    assert.ok(law);
    assert.match(law.signature, /No implicit conversion/u);
    assert.match(law.typing, /without evaluating it/u);
    assert.match(law.evaluation, /exactly once/u);
    assert.match(law.evaluation, /before strict NULL propagation/u);
    assert.match(law.evaluation, /lazy demand/u);
    assert.match(law.evaluation, /cooperative cancellation/u);
    assert.match(law.identity, /earlier pinned contract bodies retain their identities/i);
  }
  assert.match(laws.translate!.value, /simultaneous, not cascading/u);
  assert.match(laws.translate!.value, /Reject every duplicate source scalar even when unused or when the value is empty/u);
  assert.match(laws.translate!.value, /ignore surplus target scalars/u);
  assert.match(laws.translate!.typing, /Preserve only the value input max_codepoints/u);
  assert.match(laws.translate!.typing, /drop min_length/u);
  assert.match(laws.translate!.typing, /max_utf8_bytes/u);
  assert.match(laws.instr!.value, /without a safe-integer or INT64 cap/u);
  assert.match(laws.instr!.value, /overlapping matches/u);
  assert.match(laws.instr!.value, /scalar length plus position plus two/u);
  assert.match(laws.instr!.value, /Empty value and empty subvalue return one/u);
  assert.match(laws.instr!.evaluation, /before shortcuts or bounded integer conversion/u);
  assert.match(laws.instr!.identity, /Preserve authored omission and explicit defaults as distinct identities/u);
  assert.match(laws.instr!.identity, /do not insert synthetic default children/u);
});

test('TRANSLATE/INSTR freshness refuses every open, wrong arity, body or child-reference mutation', () => {
  for (const [kind, paths] of scopes) {
    for (const path of paths) for (const name of names) {
      const key = kind === 'source' ? name : 'body';
      const mutations: Array<(shape: TranslateInstrSchema) => void> = [
        s => {s.additionalProperties = true;},
        s => {s.properties![key] = {$ref: `#/$defs/${path[2]}`};},
        s => {s.properties![key]!.minItems = 1;},
        s => {s.properties![key]!.maxItems = 5;},
        s => {delete s.properties![key]!.maxItems;},
        s => {s.properties![key]!.items!.$ref = '#/$defs/wrong';},
      ];
      for (const mutate of mutations) {
        const input = ready(); mutate(find(at(input, path), kind, name));
        const before = structuredClone(input);
        assert.throws(() => updateTranslateInstrContracts(...input, grammar), /stale/u);
        assert.deepEqual(input, before);
      }
    }
  }
});

test('TRANSLATE/INSTR preflight refuses missing duplicate and comment-only tokens atomically', () => {
  for (const name of names) for (const invalid of [
    grammar.replace(` | "${name}"`, ''),
    grammar.replace(`"${name}"`, `(* "${name}" *)`),
    grammar.replace(`"${name}"`, `"${name}" | "${name}"`),
  ]) {
    const input = bodies(), before = structuredClone(input);
    assert.throws(() => updateTranslateInstrContracts(...input, invalid, true));
    assert.deepEqual(input, before);
  }
});

test('TRANSLATE/INSTR preflight refuses missing scopes duplicate nodes and wrong unary templates', () => {
  for (const [kind, paths] of scopes) for (const path of paths) for (const mutate of [
    (scope: SchemaScope) => {Reflect.deleteProperty(scope, 'oneOf');},
    (scope: SchemaScope) => {scope.oneOf.push(structuredClone(find(scope, kind, 'instr')));},
    (scope: SchemaScope) => {find(scope, kind, 'len').additionalProperties = true;},
    (scope: SchemaScope) => {find(scope, kind, 'len').properties![kind === 'source' ? 'len' : 'body']!.$ref = '#/$defs/wrong';},
  ]) {
    const input = ready(); mutate(at(input, path));
    const before = structuredClone(input);
    assert.throws(() => updateTranslateInstrContracts(...input, grammar, true));
    assert.deepEqual(input, before);
  }
  const input = ready(); input[0].schemas.unregistered = structuredClone(at(input, sources[0]));
  const before = structuredClone(input);
  assert.throws(() => updateTranslateInstrContracts(...input, grammar, true), /unregistered/u);
  assert.deepEqual(input, before);
});

test('TRANSLATE/INSTR freshness refuses semantic law grammar and identity mutations', () => {
  for (const mutate of [
    ...names.flatMap(name => Object.keys(ready()[0].laws[name]!).map(key => (b: Input) => {b[0].laws[name]![key] = 'invalid';})),
    (b: Input) => {b[0].grammar_sha256 = '0'.repeat(64);},
    (b: Input) => {b[1].artifact_schema_cids.executable_plan = 'sha256:' + '0'.repeat(64);},
    (b: Input) => {b[1].artifact_registry_cid = 'sha256:' + '0'.repeat(64);},
  ]) {
    const input = ready(); mutate(input); const before = structuredClone(input);
    assert.throws(() => updateTranslateInstrContracts(...input, grammar));
    assert.deepEqual(input, before);
  }
});

test('TRANSLATE/INSTR registration preserves all other laws schemas and profiles', () => {
  const input = bodies(), before = structuredClone(input);
  updateTranslateInstrContracts(...input, grammar, true);
  for (const [kind, paths] of scopes) for (const path of paths) {
    for (const b of [input, before]) at(b, path).oneOf = at(b, path).oneOf.filter(s => !names.some(name => s === find(at(b, path), kind, name)));
  }
  for (const name of names) {delete input[0].laws[name]; delete before[0].laws[name];}
  input[0].grammar_sha256 = before[0].grammar_sha256;
  input[1].artifact_schema_cids = before[1].artifact_schema_cids;
  input[1].artifact_registry_cid = before[1].artifact_registry_cid;
  assert.deepEqual(input, before);
});

test('TRANSLATE/INSTR updater accepts the real common EBNF registration', () => {
  const input = bodies(), actual = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  updateTranslateInstrContracts(...input, actual, true);
  assert.deepEqual(updateTranslateInstrContracts(...input, actual), {source: 14, node: 6});
});

test('fixed INSTR optional forms retain exact complete-fragment identities and predecessor control', () => {
  // The fixture is hand-assembled from authored request, graph, root and limit
  // forms. These checks hash fixed preimages, never compiler or runtime output.
  const canonical = (value: unknown): string => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
      .map(key => JSON.stringify(key) + ':' + canonical((value as Record<string, unknown>)[key])).join(',') + '}' : JSON.stringify(value);
  const cid = (value: unknown) => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const wire = readFileSync('portability/corpus/translate-instr-identities.json', 'utf8');
  assert.equal(createHash('sha256').update(wire).digest('hex'),
    'f0d2dfe30ec14d858b22c321c141df68b8743bf01257282d7ae3bc075a149889');
  assert.equal(createHash('sha256').update(readFileSync('portability/corpus/historical/pre-integration-translate-instr-identities.json')).digest('hex'),'99c5077481337f5379176a3faf23447ae1cf0d59d85ac099db7484728e467b36');
  type ExpressionSteps = {steps: [{params: {exprs: {x: unknown}}}, ...unknown[]]};
  type Limit = {
    request_pointer: string;
    resolved_limit: {
      effective_max: number;
      resolved_limit_cid: string;
      enforcement: string;
      breach: string;
      candidates: {
        witness_cid: string;
        dependencies: string[];
        source: {contract_cid: string; field: string};
        law_id: string;
      }[];
    };
  };
  type Body = {
    expression_contract_cid: string;
    request: {pipeline: ExpressionSteps};
    graph: ExpressionSteps;
    roots: [{source: unknown; node: unknown; demand_paths: unknown; contract: unknown}, ...unknown[]];
    limits: Limit[];
  };
  type Identity = {cid: string; canonical: string; bytes: number; body: Body};
  type FixtureCase = Identity & {id: string; expected_value: number; source: unknown; node: unknown};
  const fixture: {
    expression_contract_cid: string;
    published_predecessor: string;
    cases: [FixtureCase, FixtureCase, FixtureCase, FixtureCase];
    predecessor_control: Identity;
  } = JSON.parse(wire);
  const expected = [
    ['instr_default', 2, 'sha256:576b4802d1c57547c061b8559873a6df14789545fa578e9f00dd4cd3914ec165'],
    ['instr_position', 3, 'sha256:e7cabe28686dac621c33bde5274a16453437a49f949e7a735f7784f5dabf0375'],
    ['instr_occurrence', 4, 'sha256:7e5e6e381992969e1e2fb69c14d5fb1dc0019fe228439f909a7f7879aecf5908'],
    ['strpos_control', 2, 'sha256:8bdcec19bae24a9dd04e08d6686357a6fa3af2b8e1f712b2e3c114be15710323'],
  ] as const;
  // This retained introduction fixture is not the later current contract.
  assert.equal(fixture.expression_contract_cid, 'sha256:a49aba23a30514b63c9f7bcd05663dcacf2e5646c56073e7d00a34d6abe402b7');
  assert.notEqual(fixture.expression_contract_cid, cid(bodies()[0]));
  assert.equal(fixture.published_predecessor, '21505177a8a7b54a2c273186b7d30456f757fcc4');
  assert.equal(fixture.cases.length, 4);
  for (const [index, [id, arity, expectedCid]] of expected.entries()) {
    const item = fixture.cases[index];
    assert.ok(item);
    const op = id === 'strpos_control' ? 'strpos' : 'instr';
    const children = [{literal: 'banana'}, {literal: 'an'}, ...Array.from({length: arity - 2}, () => ({literal: 1}))];
    const node = {op, body: children.map(child => ({op: 'literal', body: child.literal}))};
    assert.equal(item.id, id); assert.equal(item.expected_value, 2);
    assert.deepEqual(item.source, {[op]: children}); assert.deepEqual(item.node, node);
    assert.equal(item.cid, expectedCid); assert.equal(cid(item.body), expectedCid);
    assert.equal(canonical(item.body), item.canonical);
    assert.equal(Buffer.byteLength(item.canonical), item.bytes);
    assert.equal(item.body.expression_contract_cid, fixture.expression_contract_cid);
    assert.deepEqual(item.body.request.pipeline.steps[0].params.exprs.x, item.source);
    assert.deepEqual(item.body.graph.steps[0].params.exprs.x, item.node);
    assert.deepEqual(item.body.roots[0].source, item.source);
    assert.deepEqual(item.body.roots[0].node, item.node);
    assert.deepEqual(item.body.roots[0].demand_paths, {'/roots/0/source': [],
      ...Object.fromEntries(children.map((_, child) => [`/roots/0/source/${op}/${child}`, []]))});
    assert.deepEqual(item.body.roots[0].contract, {type: 'number', nullable: false});
    const requestCid = cid(item.body.request);
    assert.deepEqual(item.body.limits.map(limit => [limit.request_pointer, limit.resolved_limit.effective_max]),
      [['/max_rows', 10], ['/max_value_bytes', 1000]]);
    for (const limit of item.body.limits) {
      const {resolved_limit_cid: limitCid, ...limitBody} = limit.resolved_limit;
      assert.equal(cid(limitBody), limitCid);
      assert.equal(limitBody.enforcement, 'engine_atomic'); assert.equal(limitBody.breach, 'fail');
      for (const candidate of limitBody.candidates) {
        const {witness_cid: witnessCid, ...witnessBody} = candidate;
        assert.equal(cid(witnessBody), witnessCid);
        assert.deepEqual(witnessBody.dependencies, [requestCid]);
        assert.equal(witnessBody.source.contract_cid, requestCid);
        assert.equal(witnessBody.source.field, limit.request_pointer);
        assert.equal(witnessBody.law_id, 'actql.expression-fragment.capacity');
      }
    }
  }
  assert.equal(new Set(fixture.cases.map(item => item.cid)).size, 4);
  const previous = fixture.predecessor_control;
  assert.equal(previous.cid, 'sha256:eedc9a812983a0de1bd1da9db6f8bf7c7cd1a7c8acc9843d5c51507428b2ddf2');
  assert.equal(cid(previous.body), previous.cid); assert.equal(canonical(previous.body), previous.canonical);
  assert.equal(Buffer.byteLength(previous.canonical), previous.bytes);
  const historical: {contracts: {id: string; body: unknown}[]} = JSON.parse(readFileSync('portability/corpus/historical/pre-translate-instr-contract-identities.json', 'utf8'));
  const oldExpression = historical.contracts.find(item => item.id === 'expression_contract');
  assert.ok(oldExpression);
  assert.equal(previous.body.expression_contract_cid, cid(oldExpression.body));
  const moved = structuredClone(previous.body); moved.expression_contract_cid = fixture.expression_contract_cid;
  assert.deepEqual(moved, fixture.cases[3].body);
  assert.notEqual(previous.cid, fixture.cases[3].cid);
});
