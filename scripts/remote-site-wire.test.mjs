import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const registry = read('spec/contracts/actql-remote-site-wire.json');
const vectors = read('spec/fixtures/remote-site-wire-vectors.json').vectors;
const canonical = value => value && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const validate = new Function(structuralValidatorSource() + '\nreturn valid;')();

test('Remote Site fixed preimages and transitive identities are independent', () => {
  for (const vector of vectors) {
    assert.equal(canonical(vector.body), vector.canonical);
    assert.equal(hash(vector.canonical), vector.cid);
  }
  const byName = Object.fromEntries(vectors.map(v => [v.name, v]));
  assert.equal(byName.managed_subject.body.dispatch_request_cid, byName.dispatch.cid);
  assert.equal(byName.managed_subject.body.holding_evidence_cid, byName.holding.cid);
  assert.equal(byName.managed_evidence.body.evidence_subject_cid, byName.managed_subject.cid);
  assert.equal(hash(byName.poll_dispatch.body.request_json),
    byName.poll_dispatch.body.dispatch_request_cid);
});

test('Remote Site schema pins retain full current fields without aliases', () => {
  const names = {dispatch_request: 'dispatch',
    managed_output_subject: 'managed_subject', poll_dispatch: 'poll_dispatch'};
  for (const [name, vectorName] of Object.entries(names)) {
    const schema = registry.schemas[name];
    assert.equal(hash(canonical(schema)), registry.schema_cids[name]);
    const body = vectors.find(vector => vector.name === vectorName).body;
    const shape = project(schema);
    assert(validate(body, shape));
    assert(!validate({...body, version: body.version.replace('/0.1', '/0.2')}, shape));
    assert(!validate({...body, obsolete: true}, shape));
    for (const key of Object.keys(body)) {
      const missing = {...body};
      delete missing[key];
      assert(!validate(missing, shape), `${name}: missing ${key}`);
    }
  }
});
