import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitDispatchJson, pollCancelJson} from './index.mjs';

// Fixed contract preimages, not expectations generated from this issuer.
const vectors = JSON.parse(readFileSync(new URL('../../spec/fixtures/remote-site-wire-vectors.json', import.meta.url))).vectors;
const dispatch = vectors.find(value => value.name === 'dispatch');
const cancel = vectors.find(value => value.name === 'poll_cancel');

test('public Cancel issuer preserves the exact dispatch and fixed wire', () => {
  const request = admitDispatchJson(dispatch.canonical, dispatch.cid);
  const body = pollCancelJson(request);
  assert.equal(body, cancel.canonical);
  assert.equal('sha256:' + createHash('sha256').update(body).digest('hex'), cancel.cid);
  const wire = JSON.parse(body);
  assert.equal(wire.request_json, dispatch.canonical);
  assert.equal(wire.dispatch_request_cid, dispatch.cid);
  assert.deepEqual(Object.keys(wire), ['dispatch_request_cid', 'request_json', 'version']);
});
