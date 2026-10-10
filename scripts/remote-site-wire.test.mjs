import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';

import {checkEffectCheckpointContract} from './remote-effect-checkpoint-contract.mjs';

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


test('Retained handoff preserves the saved plan and exact committed receipt', () => {
  const fixed = read('spec/fixtures/remote-retained-input-wire-vectors.json').vectors;
  const byName = Object.fromEntries(fixed.map(vector => [vector.name, vector]));
  const poll = byName.poll_transfer.body;
  const result = byName.result.body;
  assert.equal(poll.plan_json, byName.plan.canonical);
  assert.equal(poll.plan_cid, byName.plan.cid);
  assert.equal(poll.intent_json, byName.plan_intent.canonical);
  assert.equal(hash(poll.request_json), poll.dispatch_request_cid);
  assert.equal(result.plan_cid, poll.plan_cid);
  assert.equal(result.intent_cid, poll.intent_cid);
  assert.equal(result.dispatch_request_cid, poll.dispatch_request_cid);
  const receipt = JSON.parse(result.destination_receipt_json);
  assert.equal(hash(result.destination_receipt_json), result.destination_receipt_cid);
  assert.equal(receipt.request_cid, result.transfer_request_cid);
  assert.equal(receipt.physical_manifest_cid, byName.plan.body.physical_manifest_cid);
  const reply = JSON.parse(result.transfer_reply_json);
  assert.equal(reply.requestCid, result.transfer_request_cid);
  // DirectStream has no Store object use; that release bit is true at admission.
  assert.deepEqual(reply.state, [3, 2, 0, 1, 0, 1, 1, 1, 1]);
});


test('Effect Checkpoint report and ACK use pinned closed identity fields', () => {
  checkEffectCheckpointContract(registry);
  for (const name of ['effect_checkpoint_report', 'effect_checkpoint_reply']) {
    const schema = registry.schemas[name];
    assert.equal(hash(canonical(schema)), registry.schema_cids[name]);
    const body = name === 'effect_checkpoint_report'
      ? {checkpoint_wire: '{"original":"checkpoint"}', dispatch_request_cid: hash('original-dispatch'), version: 'actql-remote-effect-checkpoint-report/0.1'}
      : {checkpoint_cid: hash('checkpoint'), dispatch_request_cid: hash('original-dispatch'), outcome: 'accepted', reason: '', report_cid: hash('original-report'), version: 'actql-remote-effect-checkpoint-reply/0.1'};
    const shape = project(schema);
    assert(validate(body, shape));
    assert(!validate({...body, credential: 'must-not-be-sent'}, shape));
    for (const key of Object.keys(body)) {
      const missing = {...body}; delete missing[key];
      assert(!validate(missing, shape), `${name}: missing ${key}`);
    }
  }
});

test('Effect review fixed preimages bind original dispatch, Checkpoint and ACK', () => {
  const fixed = read('spec/fixtures/remote-effect-checkpoint-vectors.json');
  const byName = Object.fromEntries(fixed.vectors.map(vector => {
    assert.equal(canonical(vector.body), vector.canonical);
    assert.equal(hash(vector.canonical), vector.cid);
    return [vector.name, vector];
  }));
  assert.equal(hash(canonical(fixed.checkpoint_preimage)), byName.checkpoint.body.checkpoint_cid);
  assert.equal(byName.report.body.checkpoint_wire, byName.checkpoint.canonical);
  assert.equal(byName.report.body.dispatch_request_cid, byName.dispatch.cid);
  assert.equal(byName.reply.body.report_cid, byName.report.cid);
  assert.equal(byName.reply.body.checkpoint_cid, byName.checkpoint.body.checkpoint_cid);
  assert.equal(byName.reply.body.dispatch_request_cid, byName.dispatch.cid);
  assert(validate(byName.report.body, project(registry.schemas.effect_checkpoint_report)));
  assert(validate(byName.reply.body, project(registry.schemas.effect_checkpoint_reply)));
});

test('Effect resume delivery pins original custody and canonical claim fields', () => {
  checkEffectCheckpointContract(registry);
  const fixed = read('spec/fixtures/remote-effect-resume-vectors.json');
  const {body} = fixed.delivery;
  assert.equal(canonical(body), fixed.delivery.canonical);
  assert.equal(hash(canonical(body)), fixed.delivery.cid);
  assert.equal(body.checkpoint_cid, fixed.checkpoint.checkpoint_cid);
  assert.equal(body.report_cid, hash(canonical(fixed.report)));
  assert.equal(body.dispatch_request_cid, hash(canonical(fixed.dispatch)));
  assert.equal(body.resolution_cid, fixed.resolution.resolution_cid);
  assert.equal(body.resolution_wire, canonical(fixed.verified_resolution));
  assert.equal(body.resume_intent_id, hash(canonical({checkpoint_cid: body.checkpoint_cid,
    resolution_cid: body.resolution_cid})));
  const schema = registry.schemas.effect_resume_delivery;
  assert.equal(hash(canonical(schema)), registry.schema_cids.effect_resume_delivery);
  const shape = project(schema);
  assert(validate(body, shape));
  for (const key of Object.keys(body)) {
    const missing = {...body}; delete missing[key];
    assert(!validate(missing, shape), `missing ${key}`);
  }
  for (const generation of ['0', '-1', '01', '1.0']) assert(!validate({...body, generation}, shape));
  assert(!validate({...body, credential: 'must-not-be-sent'}, shape));
  assert(!validate({...body, version: body.version.replace('/0.1', '/0.2')}, shape));
});

test('Effect resume poll preserves exact original delivery and dispatch bytes', () => {
  const fixed = read('spec/fixtures/remote-effect-resume-vectors.json');
  const {body, canonical: text, cid} = fixed.poll;
  assert.equal(canonical(body), text);
  assert.equal(hash(text), cid);
  assert.equal(body.delivery_json, fixed.delivery.canonical);
  assert.equal(body.request_json, canonical(fixed.dispatch));
  assert.equal(hash(body.request_json), body.dispatch_request_cid);
  assert.equal(JSON.parse(body.delivery_json).dispatch_request_cid, body.dispatch_request_cid);
  const schema = registry.schemas.poll_effect_resume;
  assert.equal(hash(canonical(schema)), registry.schema_cids.poll_effect_resume);
  const shape = project(schema);
  assert(validate(body, shape));
  assert(!validate({...body, credential: 'must-not-be-sent'}, shape));
  for (const key of Object.keys(body)) {
    const missing = {...body}; delete missing[key];
    assert(!validate(missing, shape), `missing ${key}`);
  }
});
