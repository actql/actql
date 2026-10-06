import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent JSON spelling and hashing; no runtime or product issuer.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const at = (value, pointer) => pointer.split('/').slice(1).reduce(
  (body, key) => body[key.replaceAll('~1', '/').replaceAll('~0', '~')], value);

for (const path of ['scripts/fixtures/pre-typed-json-values-contracts.json',
  'scripts/fixtures/pre-typed-json-membership-values-contracts.json']) {
  test(`Graph migration leaves ${path} bound to its original revision`, () => {
    const fixture = read(path);
    const revision = fixture.base ?? fixture.source_revision;
    assert.match(revision, /^[a-f0-9]{40}$/);
    const files = new Map();
    for (const [reference, expected] of Object.entries(fixture.contract_cids)) {
      const [file, pointer] = reference.split('#');
      if (!files.has(file)) files.set(file, JSON.parse(execFileSync('git',
        ['show', `${revision}:${file}`], {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024})));
      assert.equal(cid(at(files.get(file), pointer)), expected, `${revision}:${reference}`);
    }
    if (fixture.aoa_contract_cid !== undefined) {
      assert.equal(cid(files.get('spec/contracts/actql-aoa.json')), fixture.aoa_contract_cid);
    }
  });
}

test('Graph identity migration hashes an authored definition rather than relabeling the old CID', () => {
  const preimage = {
    constructor: {edges: [], nodes: [{input_occurrence: 0, key: ['id'], name: 'N'}],
      version: 'actql-graph-constructor/0.1'},
    producer_definitions: [{body: {values: {schema: {id: {nullable: false, type: 'number'}},
      rows: [{id: 1}]}}, dependencies: []}],
    version: 'actql-graph-definition/0.1',
  };
  const before = structuredClone(preimage);
  before.constructor.version = 'actql-property-graph-constructor/0.1';
  before.version = 'actql-property-graph-definition/0.1';
  assert.equal(cid(before), 'sha256:0b9c0345677606c4a3e2fbac68f9eaf42a4c050b7b977a60049ae286821f45c6');
  assert.equal(cid(preimage), 'sha256:0c1a084f78d22363b9e947f74b39dae80bfc69b505d33156253397519bcf8a6f');
  assert.notEqual(cid(before), cid(preimage));
});
