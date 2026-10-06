import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';

// Fixed wire bytes are authored from the contract, never runtime output.
const corpus = JSON.parse(readFileSync('portability/corpus/typed-json-literals.json', 'utf8'));
assert.equal(corpus.version, 'actql-typed-json-literal-vectors/0.1');
const hash = text => 'sha256:' + createHash('sha256').update(text, 'utf8').digest('hex');
const literal = text => '"' + [...text].map(c => {
  const cp = c.codePointAt(0);
  return cp < 32 || cp > 126 ? '\\u{' + cp.toString(16) + '}'
    : c === '"' || c === '\\' ? '\\' + c : c;
}).join('') + '"';
const lines = ['// Generated from independent fixed vectors. Do not edit.'];
for (const c of corpus.cases) {
  assert.equal(hash(c.wire), c.cid);
  lines.push('', '///|', `test ${literal('typed JSON wire identity: ' + c.id)} {`,
    `  let checked = @value_admission.admit_json_literal(${literal(c.source)}, { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0`,
    '  let writer = @encode.writer(10000, 1000, 100)',
    '  @value_admission.emit_checked_wire_value(checked, writer)',
    '  let wire = @encode.finish(writer)',
    `  assert_eq(wire, ${literal(c.wire)})`,
    '  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)',
    `  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), ${literal(c.cid)})`,
    '}');
}
const wireLaw = JSON.parse(readFileSync('spec/contracts/actql-expressions.json', 'utf8')).laws.typed_json_wire;
const ordered = value => value && typeof value === 'object' && !Array.isArray(value)
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
const wireCid = hash(JSON.stringify(ordered(wireLaw)));
const profileLines = ['// Generated from independent fixed profile preimages. Do not edit.'];
for (const [format, c] of Object.entries(corpus.serialization_contracts)) {
  assert.equal(c.preimage.json_value_wire_contract_cid, wireCid);
  assert.equal(hash(JSON.stringify(ordered(c.preimage))), c.cid);
  profileLines.push('', '///|', `test ${literal('typed JSON serialization identity: ' + format)} {`,
    `  assert_eq(result_serialization_contract_cid(${literal(format)}, 4096, 16, 4).unwrap(), ${literal(c.cid)})`, '}');
}
for (const [path, text] of [
  ['src/value_admission/json_identity.generated_test.mbt', lines.join('\n') + '\n'],
  ['src/run_publication/json_profile_identity.generated_wbtest.mbt', profileLines.join('\n') + '\n'],
]) {
  if (process.argv.includes('--write')) writeFileSync(path, text);
  else assert.equal(readFileSync(path, 'utf8'), text, 'stale typed JSON fixed vectors');
}
console.log(`${corpus.cases.length} typed JSON wire and 3 profile identities verified independently.`);
