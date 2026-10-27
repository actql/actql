import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {holderTerminalReports, dispatchCid, dispatchRoute} from './index.mjs';
const vector = JSON.parse(readFileSync(new URL('../../scripts/fixtures/holder-terminal-vector.json', import.meta.url), 'utf8'));

test('holder terminal facade consumes the original shared canonical report in one namespace', () => {
  const original = holderTerminalReports.admit(vector.wire, 65536);
  assert.deepEqual(holderTerminalReports.facts(original), {reportCid:vector.reportCid, rootDispatchCid:vector.rootCid});
  const requests = holderTerminalReports.requests(original);
  assert.deepEqual(requests.map(dispatchCid), vector.dispatchCids);
  assert.deepEqual(dispatchRoute(requests[0]), ['holder-test-coordinator','holder-test-site','1','terminal-root','sha256:'+'a'.repeat(64),'task_0','1']);
  assert(Object.isFrozen(requests));
  assert.throws(() => requests.pop(), TypeError);
  assert.equal(holderTerminalReports.acceptedJson(original), vector.replyWire);
  holderTerminalReports.admitReplyJson(original, vector.replyWire);
});

test('holder terminal facade refuses copied values malformed bounds and foreign receipts', () => {
  const original = holderTerminalReports.admit(vector.wire, 65536);
  for (const value of [{...original}, {}, null]) assert.throws(() => holderTerminalReports.facts(value));
  for (const limit of [0, -1, 1.5, Infinity, 262145]) assert.throws(() => holderTerminalReports.admit(vector.wire, limit));
  assert.throws(() => holderTerminalReports.admit(vector.wire, Buffer.byteLength(vector.wire)-1));
  assert.throws(() => holderTerminalReports.admit(' '+vector.wire, 65536));
  const body = JSON.parse(vector.wire);
  assert.throws(() => holderTerminalReports.admit(JSON.stringify({...body, root_request_cid:'sha256:'+'0'.repeat(64)}), 65536));
  assert.throws(() => holderTerminalReports.admitReplyJson(original, '{}'));
  assert.throws(() => holderTerminalReports.admitReplyJson(original, vector.replyWire.replace(vector.reportCid,'sha256:'+'0'.repeat(64))));
  assert.throws(() => holderTerminalReports.admitReplyJson(original, vector.replyWire.replace(vector.rootCid,'sha256:'+'0'.repeat(64))));
});
