import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent contract-only oracle. Do not import compiler/runtime pins or output.
const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]))
    : value;

test('Graph Plan expectation identifies the current normative AoA preimage', () => {
  const preimage = JSON.stringify(canonical(JSON.parse(readFileSync('spec/contracts/actql-aoa.json', 'utf8'))));
  assert.match(preimage, /^[\x00-\x7f]*$/);
  const cid = 'sha256:' + createHash('sha256').update(preimage).digest('hex');
  assert.equal(cid, 'sha256:8af884906323059938ad32b129f7918f18d3c2e852f4ec36072c3b681c7423e4');
  assert.equal(Buffer.byteLength(preimage), 52055);
  const source = readFileSync('src/query_integration/graph_plan_wbtest.mbt', 'utf8');
  assert.ok(source.includes(cid));
  assert.ok(!source.includes('sha256:08826f64b2224dc908b42b6fbb94b1c1e989c6e8f64185d36c108028ff4e0b45'));
});
