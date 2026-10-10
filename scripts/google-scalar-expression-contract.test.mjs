import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {googleScalarLaws, updateGoogleScalarContracts} from './google-scalar-expression-contract.mjs';

function bodies() {
  const source = {oneOf: ['contains', 'abs'].map(name => ({type: 'object',
    additionalProperties: false, required: [name], properties: {[name]: name === 'abs'
      ? {$ref: '#/$defs/source_expression'}
      : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/source_expression'}}}}))};
  const node = {oneOf: ['contains', 'abs'].map(name => ({type: 'object',
    additionalProperties: false, required: ['op', 'body'], properties: {
      op: {const: name}, body: name === 'abs' ? {$ref: '#/$defs/machine_expression'}
        : {type: 'array', minItems: 2, maxItems: 2, items: {$ref: '#/$defs/machine_expression'}}}}))};
  return [{schemas: {source, node}, laws: {}, grammar_sha256: ''},
    {artifact_schemas: {program: structuredClone(source)}, artifact_schema_cids: {}}];
}
const grammar = 'function_name = "contains" | "starts_with" | "ends_with" | "strpos" | "abs" | "sign" ;\n';

test('GoogleSQL scalar schemas preserve exact arities, local references and original operators', () => {
  const [expression, protocol] = bodies();
  const original = structuredClone(expression.schemas);
  assert.deepEqual(updateGoogleScalarContracts(expression, protocol, grammar, true), {
    starts_with: {source: 2, node: 1}, ends_with: {source: 2, node: 1}, strpos: {source: 2, node: 1}, sign: {source: 2, node: 1},
  });
  for (const [kind, schema] of Object.entries(original)) {
    for (const shape of schema.oneOf) assert.ok(expression.schemas[kind].oneOf
      .some(candidate => JSON.stringify(candidate) === JSON.stringify(shape)));
  }
  for (const name of ['starts_with', 'ends_with', 'strpos']) {
    const source = expression.schemas.source.oneOf.find(shape => shape.required[0] === name);
    assert.deepEqual(source.properties[name], {type: 'array', minItems: 2, maxItems: 2,
      items: {$ref: '#/$defs/source_expression'}});
    const node = expression.schemas.node.oneOf.find(shape => shape.properties.op.const === name);
    assert.deepEqual(node.properties.body.items, {$ref: '#/$defs/machine_expression'});
  }
  assert.deepEqual(expression.laws, googleScalarLaws);
  const prepared = structuredClone([expression, protocol]);
  updateGoogleScalarContracts(expression, protocol, grammar, true);
  assert.deepEqual([expression, protocol], prepared);
  updateGoogleScalarContracts(expression, protocol, grammar);
});

test('GoogleSQL scalar verification rejects missing, duplicate, widened and stale contracts', () => {
  for (const mutate of [
    expression => { expression.laws.starts_with.value = 'case-insensitive'; },
    expression => { expression.laws.ends_with.signature = 'any value'; },
    expression => { expression.laws.strpos.value = 'UTF-16 offset'; },
    expression => { expression.laws.strpos.signature = 'INT64 and BYTES'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'strpos').properties.strpos.minItems = 1; },
    expression => { expression.laws.sign.value = 'negative zero'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'starts_with').properties.starts_with.maxItems = 3; },
    expression => { expression.schemas.node.oneOf.find(s => s.properties.op.const === 'sign').properties.body = {type: 'array'}; },
    expression => { expression.schemas.source.oneOf.push(structuredClone(expression.schemas.source.oneOf.find(s => s.required[0] === 'ends_with'))); },
    expression => { expression.grammar_sha256 = '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_registry_cid = 'sha256:' + '0'.repeat(64); },
    (_, protocol) => { protocol.artifact_schema_cids.program = 'sha256:' + '0'.repeat(64); },
  ]) {
    const [expression, protocol] = bodies();
    updateGoogleScalarContracts(expression, protocol, grammar, true);
    mutate(expression, protocol);
    assert.throws(() => updateGoogleScalarContracts(expression, protocol, grammar));
  }
  for (const name of Object.keys(googleScalarLaws)) {
    assert.throws(() => updateGoogleScalarContracts(...bodies(), grammar.replace(`| "${name}" `, ''), true));
  }
});

// Independently retained predecessor bodies prove that extending the initial
// contract baseline never relabels earlier schema or execution identities.
test('STRPOS retains exact predecessor contract and expression preimages', () => {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : value !== null && typeof value === 'object'
      ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
      : JSON.stringify(value);
  const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const history = read('portability/corpus/historical/pre-strpos-contract-identities.json');
  assert.equal(history.source_revision, '30d0b1cb0250aeb57a60c748fd0e5dc9d7d6a525');
  const expected = {
    aoa_contract: 'sha256:898b57fca972f2e832f2f19eba2561bacd30838a5d492dfedf75436e8490ad32',
    check_environment_contract: 'sha256:ea7317cdf6ab512d97c64d76478eefe40dcc7eb608916950b3fb5ad6487fac1b',
    expression_contract: 'sha256:f9a2ed26d8bf19e399fc94c64737ce2f1c76b890e173d51f8584b0fd9253b47a',
    program_schema: 'sha256:5f67400cee99f7f718eb812bae8d39bb6058cd81038bd805f00e33e84a84c893',
    pipeline_registry: 'sha256:2e626ff5cf238111abb35bb36c49c2ff220458437045991fcfafca412c7bee8a',
    ordered_derive_contract: 'sha256:8bf0e2035a755e764c33784ab140d987773c966064837f890bb0d3208ae1124d',
    fragment_execution_contract: 'sha256:22808b94321acf2d93cb1f75a5043a2fc4a288bc9d01bbc1d63ce31b035db52c',
  };
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  assert.equal(history.policy_candidates.expected_cid,
    'sha256:c31ad8bc7f322320fff823ab05563daf582bf71c10d029d8ac766829a698bbee');
  assert.equal(cid(history.policy_candidates.body), history.policy_candidates.expected_cid);
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  const expression = read('spec/contracts/actql-expressions.json');
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const program = protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program;
  function withoutStrpos(value) {
    if (Array.isArray(value)) return value.map(withoutStrpos);
    if (value === null || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, withoutStrpos(item)]));
    if (result.oneOf) result.oneOf = result.oneOf.filter(item =>
      item.required?.length !== 1 || item.required[0] !== 'strpos').filter(item => item.properties?.op?.const !== 'strpos');
    return result;
  }
  const predecessor = withoutStrpos(expression);
  delete predecessor.laws.strpos;
  predecessor.grammar_sha256 = earlier.expression_contract.grammar_sha256;
  assert.deepEqual(predecessor, earlier.expression_contract);
  assert.deepEqual(withoutStrpos(program), earlier.program_schema);
  assert.notEqual(cid(expression), expected.expression_contract);
  assert.notEqual(cid(program), expected.program_schema);
  const fragmentCids = {
    ordered_node: 'sha256:e1f5fbbf43277368d680a6f00ba710e31b0d1efe7d98691be4e287d4e0e4bb82',
    complete_fragment: 'sha256:82dca856e196145945cbd83b0e23ba5c070096deaccbf1a84c87b9c01946f09e',
  };
  assert.deepEqual(history.expression_fragments.cases.map(entry => entry.id).sort(),
    Object.keys(fragmentCids).sort());
  for (const entry of history.expression_fragments.cases) {
    assert.equal(entry.cid, fragmentCids[entry.id]);
    assert.equal(canonical(entry.body), entry.canonical);
    assert.equal(cid(entry.body), entry.cid);
    assert.equal(Buffer.byteLength(entry.canonical), entry.bytes);
  }
  const orderedCids = {
    source_step: 'sha256:e39d10ef6f96f4e7dd9790d9e050d73e471fd60bb2ca7b3a2764110081a1e281',
    graph_step: 'sha256:0f5f8b725a3d9837a7a3e054e2a289a27380a0a8e7a342d10c4b2a133a17968d',
  };
  assert.deepEqual(history.ordered_fragment.preimages.map(entry => entry.id).sort(),
    Object.keys(orderedCids).sort());
  for (const entry of history.ordered_fragment.preimages) {
    assert.equal(entry.cid, orderedCids[entry.id]);
    assert.equal(canonical(history.ordered_fragment[entry.id]), entry.canonical);
    assert.equal(cid(history.ordered_fragment[entry.id]), entry.cid);
  }
  assert.equal(history.ordered_fragment.expected_aoa_node_cid,
    cid(history.ordered_fragment.graph_step));
});
