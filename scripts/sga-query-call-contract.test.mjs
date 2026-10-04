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
  // Literal expectations bind the independent normative preimage above, not
  // generated runtime output. Label selection changes the Program schema
  // role, combined with the traverse node-source query rules. Historical preimages
  // retain the rule digest that actually produced each earlier identity.
  assert.equal(body.query_text_grammar_sha256,
    '7cd11ce7c1e58b585756ef3c8ac0eb078cf2bbb7003086263f665e26251b7f0e');
  assert.equal(body.query_text_rules_sha256,
    '65b078b5222afb74121a0785ffc2f3b3acba8642dbbb67e56477cb924fe20933');
  assert.equal(body.source_grammar_cid,
    'sha256:487b95656a825703baa75f2e108ac94d3d8a38fa113bb2ef12a3532cac2654ae');
  const priorRules = 'e4639cbce44c77135b0f162475ca653b9774ef593a4c02434f6ea30b34ff2eb2';
  assert.equal(cid({...body, query_text_rules_sha256: priorRules, source_grammar_cid:
    'sha256:50527c1472e91aa673ad57bcd43141b0e679a2de24cc6bf19efb9e8e32c2607a'}),
    'sha256:cb357b785390fb3e581a6ece8e61d49d9d93676666df77dd18a2d7f72f381bff');
  assert.equal(cid({...body, query_text_rules_sha256: priorRules, source_grammar_cid:
    'sha256:f80202113bbde534d6e2f20451da9c486092c710320c67535b4bc1c0fb513d9f'}),
    'sha256:2422e7815a6d6f6cbc2dd4289da3ba5d98eeb58545c356d45e897627e7ac3a8e');
  assert.equal(cid({...body, query_text_rules_sha256: priorRules, source_grammar_cid:
    'sha256:31be8958c4486232811be583c3674b8aacfa1cdcd300a35e12ad67dc023e1ef4'}),
    'sha256:b17d94092c747a21caea0eb25ea01d48160d3ed3cacafc0e5a6e1de79307325c');
  assert.equal(cid({...body, query_text_rules_sha256: priorRules, source_grammar_cid:
    'sha256:5cfed3155edea075796e6be985026b6f3d5b59ecc6937540d86c6af7ffc77351'}),
    'sha256:ae383655950a9e0f2d292ffd546e6bf9eb5cb1e9a9d72e86f6086bb917f681b6');
  assert.equal(cid({...body, query_text_rules_sha256: priorRules, source_grammar_cid:
    'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:caad49cf67bec4b67c2cb6beed69e7c9f71a80b19f2e8e04535d0d7f1c12cd90');
  assert.equal(cid({...body, query_text_rules_sha256: priorRules}),
    'sha256:2a5854a264c13c65bf7c2ecbc6f59f9ec09e0c590aacc1c8aed6ec247da80067');
  const predecessor = {...body,
    query_text_rules_sha256: '803a87b786e68fe64cc79a49abe359659dc32f5373168ae868b310d2dbb47927'};
  assert.equal(cid({...predecessor, source_grammar_cid:
    'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:4ac81bd72c110d09c286a0f2d4c5d68d4340a2e6843d75deabd8dbbd9fb26b77');
  assert.equal(cid({...predecessor, source_grammar_cid:
    'sha256:5cfed3155edea075796e6be985026b6f3d5b59ecc6937540d86c6af7ffc77351'}),
    'sha256:d825ab855369e92f2e4da5e9af19567cdc89e431784b09d19c3b57ef2e9f301a');
  assert.equal(cid(predecessor),
    'sha256:d18da5382cb511e80f179cb24090bec8e6ce5db6601e1acd49727ef31bc947d7');
  assert.equal(cid({...body, source_grammar_cid:
    'sha256:e9b7efcdee0ef6c06bfb6cbc7805f595e030ecbd79e5afeb0ffa17b755710b7a'}),
    'sha256:37e9fadf9ae65bc194ad17b790ce208450550defcdbfb8354ef3c5c9c0cf4f6d');
  const expected = 'sha256:d0207424274d6a5549eff6c16cd7cfa5a1e63e66c627c23bb63f24ec82154180';
  assert.equal(cid(body), expected);
  const {grammar_manifest_cid, ...pinned} = read('spec/manifests/actql-grammar-0.1.json');
  assert.deepEqual(pinned, body);
  assert.equal(grammar_manifest_cid, expected);
  for (const field of ['query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(cid({...body, [field]: '0'.repeat(64)}), expected);
  }
});
