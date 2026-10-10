import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {googleScalarLaws, updateGoogleScalarContracts, updateTrimScalarLaw} from './google-scalar-expression-contract.mjs';

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
const grammar = 'function_name = "contains" | "starts_with" | "ends_with" | "strpos" | "abs" | "sign" | "round" | "trunc" | "trim" | "ltrim" | "rtrim" ;\n';

test('GoogleSQL scalar schemas preserve exact arities, local references and original operators', () => {
  const [expression, protocol] = bodies();
  const original = structuredClone(expression.schemas);
  assert.deepEqual(updateGoogleScalarContracts(expression, protocol, grammar, true), {
    starts_with: {source: 2, node: 1}, ends_with: {source: 2, node: 1}, strpos: {source: 2, node: 1}, sign: {source: 2, node: 1}, round: {source: 2, node: 1}, trunc: {source: 2, node: 1}, trim: {source: 2, node: 1}, ltrim: {source: 2, node: 1}, rtrim: {source: 2, node: 1},
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
  for (const name of ['sign', 'round', 'trunc', 'trim', 'ltrim', 'rtrim']) {
    const source = expression.schemas.source.oneOf.find(shape => shape.required[0] === name);
    assert.deepEqual(source.properties[name], {$ref: '#/$defs/source_expression'});
    const node = expression.schemas.node.oneOf.find(shape => shape.properties.op.const === name);
    assert.deepEqual(node.properties.body, {$ref: '#/$defs/machine_expression'});
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
    expression => { expression.laws.ltrim.value = 'both ends'; },
    expression => { expression.laws.rtrim.value = 'leading end'; },
    expression => { expression.laws.ltrim.signature = 'optional character set'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'ltrim').properties.ltrim = {type: 'array'}; },
    expression => { expression.schemas.node.oneOf.find(s => s.properties.op.const === 'rtrim').properties.body = {type: 'array'}; },
    expression => { expression.laws.trim.value = 'ascii-whitespace'; },
    expression => { expression.laws.trim.signature = 'optional character set'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'trim').properties.trim = {type: 'array'}; },
    expression => { expression.schemas.node.oneOf.find(s => s.properties.op.const === 'trim').properties.body = {type: 'array'}; },
    expression => { expression.laws.round.value = 'ties to even'; },
    expression => { expression.laws.trunc.value = 'floor'; },
    expression => { expression.laws.round.signature = 'optional precision and rounding mode'; },
    expression => { expression.schemas.source.oneOf.find(s => s.required[0] === 'round').properties.round = {type: 'array'}; },
    expression => { expression.schemas.node.oneOf.find(s => s.properties.op.const === 'trunc').properties.body = {type: 'array'}; },
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
  // Freeze the post-STRPOS side as well: a future operation must not mutate
  // the meaning of this older transition by subtracting STRPOS from current.
  const following = read('portability/corpus/historical/pre-round-trunc-contract-identities.json');
  const adopted = Object.fromEntries(following.contracts.map(item => [item.id, item.body]));
  const expression = adopted.expression_contract;
  const program = adopted.program_schema;
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


test('ROUND/TRUNC preserve exact predecessor bodies and extend only closed unary schemas', () => {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : value !== null && typeof value === 'object'
      ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
      : JSON.stringify(value);
  const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const history = read('portability/corpus/historical/pre-round-trunc-contract-identities.json');
  assert.equal(history.source_revision, '3900058027b0095b6851161aa4e1c65aa1ef754f');
  assert.equal(cid(history), 'sha256:aa79e13fe0d2a33dac97853cb52270b29d6964fe96ae4d18841a3dcecc06f792');
  const expected = {
    "expression_contract": "sha256:8c6821fcf336dbefcf1c8ae3b848fb3d827e6c79ed078e6104efeea6092d3546",
    "program_schema": "sha256:64e8361cab632650d7b58e38a5535db6a02b19c179adb44eb0b08e48ed5541d3",
    "pipeline_registry": "sha256:2a3eb0f605415ab27321177d3c4629b7bd33928d74b4cd5d206d38bdc696305e",
    "ordered_derive_contract": "sha256:300bbcc3909a60302795f5f2061716c0381aca8175962be4e59ccd15ac9c3057",
    "fragment_execution_contract": "sha256:4f933b8f3d7eb70d875dbb38defeac428a00641d941eae1083c6d9457549be0a",
    "check_environment_contract": "sha256:b64696a6cef4054a71a780827bccb3b9a1bb6af4c8f51b7a0b7ad38fbe9c7a60",
    "aoa_contract": "sha256:691c103b8cbb9f8a388a6b89ba86bd8e7d9568e5b4371600307c92e6f46e5975"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  // Freeze both sides of this adopted transition before later semantic changes.
  const following = read('portability/corpus/historical/pre-trim-contract-identities.json');
  const adopted = Object.fromEntries(following.contracts.map(item => [item.id, item.body]));
  const expression = adopted.expression_contract;
  const program = adopted.program_schema;
  function withoutRounding(value) {
    if (Array.isArray(value)) return value.map(withoutRounding);
    if (value === null || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, withoutRounding(item)]));
    if (result.oneOf) result.oneOf = result.oneOf.filter(item =>
      !(item.required?.length === 1 && ['round', 'trunc'].includes(item.required[0])) &&
      !['round', 'trunc'].includes(item.properties?.op?.const));
    return result;
  }
  const predecessor = withoutRounding(expression);
  delete predecessor.laws.round;
  delete predecessor.laws.trunc;
  predecessor.grammar_sha256 = earlier.expression_contract.grammar_sha256;
  assert.deepEqual(predecessor, earlier.expression_contract);
  assert.deepEqual(withoutRounding(program), earlier.program_schema);
  assert.notEqual(cid(expression), expected.expression_contract);
  assert.notEqual(cid(program), expected.program_schema);
  for (const entry of history.expression_fragments.cases) {
    assert.equal(canonical(entry.body), entry.canonical);
    assert.equal(cid(entry.body), entry.cid);
    assert.equal(Buffer.byteLength(entry.canonical), entry.bytes);
  }
  for (const entry of history.ordered_fragment.preimages) {
    assert.equal(canonical(history.ordered_fragment[entry.id]), entry.canonical);
    assert.equal(cid(history.ordered_fragment[entry.id]), entry.cid);
  }
  assert.equal(cid(history.policy_candidates.body), history.policy_candidates.expected_cid);
  const preimages = read('portability/corpus/historical/pre-round-trunc-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:2ea2fc7b8e97246d5e62a2ae99feecf3f9c09095a2dbf50b371e7e8979279d32');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(cid(entry.envelope), entry.expected_cid, entry.name);
    assert.equal(canonical(entry.envelope), entry.canonical, entry.name);
  }
});


test('TRIM scalar owner pins the independent Unicode 16.0 White_Space set', () => {
  const scalar = JSON.parse(readFileSync('spec/dependencies/aoa-rela-scalar-laws.json', 'utf8'));
  assert.equal(scalar.unicode.trim, 'unicode-white-space');
  assert.equal(scalar.unicode.ltrim, 'unicode-white-space-leading');
  assert.equal(scalar.unicode.rtrim, 'unicode-white-space-trailing');
  const actual = scalar.unicode.trim_white_space_code_points.flatMap(range => {
    const [first, last = first] = range.split('..').map(point => parseInt(point, 16));
    return Array.from({length: last - first + 1}, (_, offset) => first + offset);
  });
  assert.deepEqual(actual, [9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192,
    8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232,
    8233, 8239, 8287, 12288]);
  assert.ok(!actual.includes(0xfeff));
  assert.ok(!actual.includes(0x200b));
  updateTrimScalarLaw(scalar);
  for (const mutate of [
    body => { body.unicode.trim = 'ascii-whitespace'; },
    body => { body.unicode.ltrim = 'unicode-white-space'; },
    body => { body.unicode.rtrim = 'unicode-white-space-leading'; },
    body => { body.unicode.trim_white_space_code_points.push('FEFF'); },
    body => { body.unicode.trim_white_space_code_points.splice(2, 1); },
    body => { body.unicode.data_version = '15.0'; },
  ]) {
    const invalid = structuredClone(scalar);
    mutate(invalid);
    assert.throws(() => updateTrimScalarLaw(invalid));
  }
});

test('TRIM preserves exact predecessor bodies and existing unary schema shapes', () => {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : value !== null && typeof value === 'object'
      ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
      : JSON.stringify(value);
  const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const history = read('portability/corpus/historical/pre-trim-contract-identities.json');
  assert.equal(history.source_revision, '6ba8bbc9d962ce04450d2f58e944847a668ee6a8');
  assert.equal(cid(history), 'sha256:116a90d670045946fda2504063da3561a920eb1b3c6d669df96b7ab412a69b1a');
  const expected = {
    "scalar_law_manifest": "sha256:5afa312c0fa9b1e5620bc3556b17aa8da9e50646097ab84a2c04aa8a24575574",
    "expression_contract": "sha256:99eb8896d61317e04b39b54eaad9cecb64abe7c08fb6e79bbaaa113547d855cf",
    "program_schema": "sha256:9661df29c89c8b303df3957fac205e4ec9a27e7f35a25e22e3e0680fe1623b3c",
    "pipeline_registry": "sha256:1419a9859c985731ba784fd0eea6f7cf13004f7300c2debfff56f66e21cc1983",
    "ordered_derive_contract": "sha256:aa2573c9d065224b3fe4b013823c3f01d41ed5de872e539f975b7f222e602b45",
    "fragment_execution_contract": "sha256:021569b50cdd8e909ce67e38f12484c14aeb757883412b2171a00fc5e59eace9",
    "check_environment_contract": "sha256:3d0d958d6aa9a7f620afbcda89396aa43c1ae300268a7f041bf64fd708124a34",
    "aoa_contract": "sha256:6b681d8f15e1dea9e005910f636e923a7288c83e92484d31a5f8aa741f6550c9"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  assert.equal(earlier.scalar_law_manifest.unicode.trim, 'ascii-whitespace');
  assert.equal(earlier.expression_contract.laws.trim, undefined);
  // This adopted transition is frozen against the exact pre-side-trim bodies.
  const following = read('portability/corpus/historical/pre-side-trim-contract-identities.json');
  const adopted = Object.fromEntries(following.contracts.map(item => [item.id, item.body]));
  const expression = adopted.expression_contract;
  const program = adopted.program_schema;
  const expectedCurrent = structuredClone(earlier.expression_contract);
  expectedCurrent.laws.trim = googleScalarLaws.trim;
  assert.deepEqual(expression, expectedCurrent);
  assert.deepEqual(program, earlier.program_schema);
  assert.equal(cid(program), expected.program_schema);
  assert.notEqual(cid(expression), expected.expression_contract);
  const scalar = adopted.scalar_law_manifest;
  assert.notEqual(cid(scalar), expected.scalar_law_manifest);
  const aoa = adopted.aoa_contract;
  assert.equal(aoa.expression_contract_cid, cid(expression));
  assert.equal(aoa.rela_scalar_law_manifest_cid, cid(scalar));
  assert.notEqual(cid(aoa), expected.aoa_contract);
  for (const entry of history.expression_fragments.cases) {
    assert.equal(canonical(entry.body), entry.canonical);
    assert.equal(cid(entry.body), entry.cid);
    assert.equal(Buffer.byteLength(entry.canonical), entry.bytes);
  }
  for (const entry of history.ordered_fragment.preimages) {
    assert.equal(canonical(history.ordered_fragment[entry.id]), entry.canonical);
    assert.equal(cid(history.ordered_fragment[entry.id]), entry.cid);
  }
  assert.equal(cid(history.policy_candidates.body), history.policy_candidates.expected_cid);
  const preimages = read('portability/corpus/historical/pre-trim-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:b97fb9c3d23259b5eaf640e331f95e774ca05300fa2e3aa5e726bf6593ea8e51');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(canonical(entry.envelope), entry.canonical);
    assert.equal(cid(entry.envelope), entry.expected_cid);
  }
});


test('LTRIM/RTRIM preserve exact predecessor bodies and admit only closed unary STRING forms', () => {
  const read = path => JSON.parse(readFileSync(path, 'utf8'));
  const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : value !== null && typeof value === 'object'
      ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
      : JSON.stringify(value);
  const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
  const history = read('portability/corpus/historical/pre-side-trim-contract-identities.json');
  assert.equal(history.source_revision, 'bea64a0c5c90d36689aa08fb9f01813daeafb685');
  assert.equal(cid(history), 'sha256:14cd3d5827000552bd970c9af7118ebb1108b9bbca1306ca180aabcf2f07b05d');
  const expected = {
  "scalar_law_manifest": "sha256:aa70f420d765ab707a5ec0607d58e0a4104022ca8113866bd7d18447dedde2f6",
  "expression_contract": "sha256:a6d2c257b61167db55ca87f4985e89c2c098b33ef0123bf6639878972fa081e8",
  "program_schema": "sha256:9661df29c89c8b303df3957fac205e4ec9a27e7f35a25e22e3e0680fe1623b3c",
  "pipeline_registry": "sha256:d6d977099973c73d06e5fe3ed05485d8578fdb1fe687df7c4fb73ae73ad0596e",
  "ordered_derive_contract": "sha256:ee8b9636da689912be14f1e47a655e40b19be72c480c8ad4084a630fbd844c75",
  "fragment_execution_contract": "sha256:a1a1640463d683e11617125767018e6832b19b13e6cb342c1e09f9cf6cc8b488",
  "check_environment_contract": "sha256:5b79e240d35cee688905d48cd464c9b3c6a543dee3232ad3baed72e969696604",
  "aoa_contract": "sha256:a7acd15dc5a9005c4928a77122bdf7bd19264b24b5223bbd59e16fc3c58a61b2"
};
  assert.deepEqual(history.contracts.map(item => item.id).sort(), Object.keys(expected).sort());
  for (const item of history.contracts) {
    assert.equal(item.cid, expected[item.id]);
    assert.equal(cid(item.body), item.cid);
  }
  const earlier = Object.fromEntries(history.contracts.map(item => [item.id, item.body]));
  const expression = read('spec/contracts/actql-expressions.json');
  const protocol = read('spec/contracts/actql-protocol-schemas.json');
  const program = protocol.artifact_schemas.executable_plan.properties.execution_material.properties.program;
  assert.equal(earlier.expression_contract.laws.ltrim, undefined);
  assert.equal(earlier.expression_contract.laws.rtrim, undefined);
  assert.deepEqual(expression.laws, {...earlier.expression_contract.laws,
    ltrim: googleScalarLaws.ltrim, rtrim: googleScalarLaws.rtrim});
  // Compare all retained cases directly with captured bodies; do not manufacture
  // a predecessor by deleting new operations from the installed contract.
  function checkExtension(before, current) {
    if (Array.isArray(before)) {
      if (current.length === before.length) return before.forEach((value, index) => checkExtension(value, current[index]));
      assert.equal(current.length, before.length + 2);
      const added = item => ['ltrim', 'rtrim'].includes(item.properties?.op?.const ?? item.required?.[0]);
      assert.deepEqual(current.filter(item => !added(item)), before);
      for (const name of ['ltrim', 'rtrim']) {
        const shape = current.find(item => (item.properties?.op?.const ?? item.required?.[0]) === name);
        assert.equal(shape.additionalProperties, false);
        if (shape.properties.op) {
          assert.deepEqual(shape.required, ['op', 'body']);
          assert.deepEqual(shape.properties.body, before.find(item => item.properties?.op?.const === 'trim').properties.body);
        } else {
          assert.deepEqual(shape.required, [name]);
          assert.deepEqual(shape.properties[name], before.find(item => item.required?.[0] === 'trim').properties.trim);
        }
      }
      return;
    }
    if (before === null || typeof before !== 'object') return assert.deepEqual(current, before);
    assert.deepEqual(Object.keys(current).sort(), Object.keys(before).sort());
    for (const key of Object.keys(before)) checkExtension(before[key], current[key]);
  }
  checkExtension(earlier.expression_contract.schemas, expression.schemas);
  checkExtension(earlier.program_schema, program);
  assert.notEqual(cid(program), expected.program_schema);
  assert.notEqual(cid(expression), expected.expression_contract);
  const scalar = read('spec/dependencies/aoa-rela-scalar-laws.json');
  const expectedScalar = structuredClone(earlier.scalar_law_manifest);
  Object.assign(expectedScalar.unicode, {ltrim: 'unicode-white-space-leading', rtrim: 'unicode-white-space-trailing'});
  assert.deepEqual(scalar, expectedScalar);
  assert.notEqual(cid(scalar), expected.scalar_law_manifest);
  const aoa = read('spec/contracts/actql-aoa.json');
  assert.equal(aoa.expression_contract_cid, cid(expression));
  assert.equal(aoa.rela_scalar_law_manifest_cid, cid(scalar));
  assert.notEqual(cid(aoa), expected.aoa_contract);
  for (const entry of history.expression_fragments.cases) {
    assert.equal(canonical(entry.body), entry.canonical);
    assert.equal(cid(entry.body), entry.cid);
    assert.equal(Buffer.byteLength(entry.canonical), entry.bytes);
  }
  for (const entry of history.ordered_fragment.preimages) {
    assert.equal(canonical(history.ordered_fragment[entry.id]), entry.canonical);
    assert.equal(cid(history.ordered_fragment[entry.id]), entry.cid);
  }
  assert.equal(cid(history.policy_candidates.body), history.policy_candidates.expected_cid);
  const preimages = read('portability/corpus/historical/pre-side-trim-preimages.json');
  assert.equal(preimages.source_revision, history.source_revision);
  assert.equal(preimages.expression_contract_cid, expected.expression_contract);
  assert.equal(cid(preimages), 'sha256:3970c78a03b05c891fa14f57b96d4d4cccfce7ba266541c1ff10780fb4dc2694');
  assert.equal(preimages.sources.length, 17);
  assert.equal(new Set(preimages.sources.map(entry => entry.source)).size, 17);
  for (const entry of preimages.sources) assert.equal(cid(entry.body), entry.cid, entry.source);
  assert.equal(preimages.identity_envelopes.length, 21);
  for (const entry of preimages.identity_envelopes) {
    assert.equal(canonical(entry.envelope), entry.canonical);
    assert.equal(cid(entry.envelope), entry.expected_cid);
  }
});
