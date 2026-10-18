// Bounded selection over the original whole Preview; the Moon methods below
// observe decoder inputs only and issue no request, grant or physical result.
import assert from 'node:assert/strict';
import test from 'node:test';
import {recoverPreparedSalesforceSingleRequests} from '../host/salesforce-effect-request-recovery.mjs';

function fixture() {
  const calls = [];
  const preview = {};
  const moon = {
    salesforceAdmitRecoveryPreview: () => ({$tag: 1, _0: preview}),
    salesforceRecoveryPreviewMemberCount: original => {
      assert.equal(original, preview);
      return 3;
    },
    salesforceRecoveryPreviewRowCount: (original, index) => {
      calls.push(['rows', original, index]);
      return 1;
    },
    salesforceRecoverSingleWriteRequest: (original, index, row) => {
      calls.push(['request', original, index, row]);
      return {$tag: 1, _0: {index, row}};
    },
  };
  const member = {projection: {}, apiVersion: 'v62.0', resourceOrigin: 'https://example.test',
    claims: [{canonicalRequestCid: 'original-request'}]};
  const options = {moon, previewWire: 'whole-original-preview', runIdentityCid: 'original-run',
    authoringContextCid: 'original-author', members: [member, member],
    previewLimits: {maxWireBytes: 1024, maxNodes: 64, maxDepth: 8},
    bodyLimits: {maxBytes: 1024, maxNodes: 64, maxDepth: 8},
    requestLimits: {maxPathBytes: 1024, maxTargetBytes: 1024, maxBodyBytes: 1024},
    maxMembers: 3, maxRows: 3};
  return {calls, preview, options};
}

test('selected recovery keeps original global indices and ignores caller Array methods', () => {
  const {calls, preview, options} = fixture();
  const selection = [0, 2];
  selection.slice = selection.map = selection[Symbol.iterator] = () => assert.fail('caller method');
  const result = recoverPreparedSalesforceSingleRequests({...options, memberIndexes: selection});
  assert.deepEqual(result.requests, [[{index: 0, row: 0}], [{index: 2, row: 0}]]);
  assert.deepEqual(calls, [['rows', preview, 0], ['request', preview, 0, 0],
    ['rows', preview, 2], ['request', preview, 2, 0]]);
});

test('selection length and each index are captured once before request decoding', () => {
  const {calls, options} = fixture();
  let lengths = 0;
  const reads = [];
  const selection = new Proxy([0, 2], {get(target, key) {
    if (key === 'length') return ++lengths === 1 ? 2 : 1_000_000;
    if (key === '0' || key === '1') {
      reads.push(key);
      assert.equal(reads.filter(value => value === key).length, 1);
    } else assert.fail(`unexpected read ${String(key)}`);
    return target[key];
  }});
  recoverPreparedSalesforceSingleRequests({...options, memberIndexes: selection});
  assert.equal(lengths, 1);
  assert.deepEqual(reads, ['0', '1']);
  assert.equal(calls.length, 4);
});

test('foreign, repeated, reversed and excessive indices refuse before request decoding', () => {
  for (const selection of [[0, 3], [0, 0], [2, 0], [0, 1, 2, 3], '02', new Set([0, 2]),
    new Proxy([], {get() { return Number.MAX_SAFE_INTEGER; }})]) {
    const {calls, options} = fixture();
    assert.throws(() => recoverPreparedSalesforceSingleRequests({...options,
      memberIndexes: selection}), {code: 'InvalidSalesforcePreparedRequestRecovery'});
    assert.deepEqual(calls, []);
  }
});
