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
  for (const name of ['poll_dispatch', 'poll_cancel']) {
    assert.equal(hash(byName[name].body.request_json), byName[name].body.dispatch_request_cid);
    if (name === 'poll_cancel') assert.equal(byName[name].body.dispatch_request_cid, byName.dispatch.cid);
  }
});

test('Remote Site schema pins retain full current fields without aliases', () => {
  const names = {dispatch_request: 'dispatch',
    managed_output_subject: 'managed_subject', poll_dispatch: 'poll_dispatch',
    poll_cancel: 'poll_cancel'};
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

test('Retained input intent fixed preimages preserve original dispatch identity', () => {
  const fixed = read('spec/fixtures/remote-retained-input-wire-vectors.json').vectors;
  for (const vector of fixed) {
    assert.equal(canonical(vector.body), vector.canonical);
    assert.equal(hash(vector.canonical), vector.cid);
  }
  const [intent, poll] = fixed;
  assert.equal(hash(poll.body.intent_json), intent.cid);
  assert.equal(hash(poll.body.request_json), intent.body.dispatch_request_cid);
  assert.equal(poll.body.dispatch_request_cid, intent.body.dispatch_request_cid);
  assert(!('result_definition_cid' in intent.body));
  assert(!('publication_attempt_cid' in intent.body));
  const [planIntent, plan] = fixed.slice(2);
  assert.equal(hash(plan.body.evidence_json), planIntent.body.producer_evidence_cid);
  assert.equal(hash(plan.body.subject_json), planIntent.body.producer_subject_cid);
  assert.equal(hash(plan.body.physical_manifest_json), plan.body.physical_manifest_cid);
  assert.equal(hash(plan.body.transfer_request_json), plan.body.transfer_request_cid);
  assert.equal(plan.body.intent_cid, planIntent.cid);
});

test('Retained input wire pins enforce exact fields and separate value identity', () => {
  const wire = read('spec/contracts/actql-remote-retained-input-wire.json');
  const fixed = read('spec/fixtures/remote-retained-input-wire-vectors.json').vectors;
  for (const [name, schema] of Object.entries(wire.schemas)) {
    assert.equal(hash(canonical(schema)), wire.schema_cids[name]);
  }
  for (const vector of fixed) {
    const shape = project(wire.schemas[vector.name === 'plan_intent' ? 'intent' : vector.name]);
    assert(validate(vector.body, shape));
    assert(!validate({...vector.body, unexpected: true}, shape));
    for (const key of Object.keys(vector.body)) {
      const missing = {...vector.body};
      delete missing[key];
      assert(!validate(missing, shape), `${vector.name}: missing ${key}`);
    }
  }
  const intent = fixed[0].body;
  assert.notEqual(hash(canonical({...intent, transfer_attempt: 'e\u0301\r\n'})),
    hash(canonical({...intent, transfer_attempt: 'é\n'})));
});
