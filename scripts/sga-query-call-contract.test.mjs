import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

// Independent sorted JSON for these normative JSON bodies. This test does
// not import a product canonicalizer, manifest writer or compiler output.
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

const cid = body => `sha256:${digest(Buffer.from(canonical(body), 'utf8'))}`;
const fileDigest = path => digest(readFileSync(path));

test('SGA query grammar pin matches an independent normative preimage', () => {
  const language = readFileSync('docs/spec/language.md', 'utf8');
  const inventory = language.split('<a id="operation-inventory"></a>')[1]
    .split('<a id="relation-operations"></a>')[0];
  const operations = inventory.split('\n').filter(line => line.startsWith('|'))
    .flatMap(line => [...line.split('|')[2].matchAll(/\[`([a-z_]+)`\]\(#[a-z-]+\)/g)]
      .map(match => match[1])).sort();
  assert.equal(new Set(operations).size, operations.length);
  // The integrated common owner registers property_graph in addition to the
  // 72-operation predecessor. This remains distinct from the historical
  // imported inventory and the 19 named SGA surface operations.
  assert.equal(operations.length, 73);
  assert.ok(operations.includes('property_graph'));
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const program = protocol.artifact_schemas.executable_plan.properties
    .execution_material.properties.program;
  const expression = read('spec/contracts/actql-expressions.json');
  const expressionRules = '<a id="expression-text"></a>' + language
    .split('<a id="expression-text"></a>')[1]
    .split('<a id="predicates"></a>')[0];
  const body = {
    version: 'actql-grammar-manifest/0.1',
    source_grammar_cid: cid(program),
    operations,
    expression_contract_cid: cid(expression),
    expression_text_grammar_sha256: fileDigest(expression.grammar),
    expression_text_rules_sha256: digest(Buffer.from(expressionRules, 'utf8')),
    structural_text_grammar_sha256: fileDigest('spec/grammar/actql-text-0.1.ebnf'),
    structural_text_rules_sha256: fileDigest('docs/spec/structural-text.md'),
    query_text_grammar_sha256: fileDigest('spec/grammar/actql-query-0.1.ebnf'),
    query_text_rules_sha256: fileDigest('docs/spec/query-text.md'),
  };
  // Literal expectations were independently computed with Python hashlib
  // from the normative roles/files above, not read from generated pins.
  assert.equal(body.query_text_grammar_sha256,
    'dd90ea227eb23be7003d70d6ae78403576c972875c838c9cad88451563f7bcfc');
  assert.equal(body.query_text_rules_sha256,
    '5bb6f784249ac4d0045be159779759a3e4c17fce84f3bb7f54c568a14199bbd8');
  const expected = 'sha256:24f53c1f64028206dbc01f6c3d0c11d991c8c9d512581fdfd007a250315f8bbd';
  assert.equal(cid(body), expected);
  const {grammar_manifest_cid, ...pinned} = read('spec/manifests/actql-grammar-0.1.json');
  assert.deepEqual(pinned, body);
  assert.equal(grammar_manifest_cid, expected);
  for (const field of ['query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(cid({...body, [field]: '0'.repeat(64)}), expected);
  }
});
