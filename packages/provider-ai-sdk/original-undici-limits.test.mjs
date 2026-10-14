import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';

// Separate test process; count the original constructor without changing its
// newTarget/layout. No invoke, TCP, SDK, Core grant or Store is exercised.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const OriginalClient = undici.Client;
let constructions = 0;
undici.Client = new Proxy(OriginalClient, {
  construct(target, args) {
    constructions++;
    return Reflect.construct(target, args, target);
  },
});
let physical;
try {
  physical = await import('./_internal/original-undici-transport.mjs');
} finally { undici.Client = OriginalClient; }

const endpoint = 'https://fixture.invalid/v1/chat/completions';
const responseLimits = {maxBytes: 2048, maxChunkBytes: 512, maxChunks: 16,
  maxHeaderBytes: 128, observedHeaders: ['content-type', 'x-fixture']};
const create = () => physical.createOriginalUndiciFetch({endpoint,
  requestLimits: {maxBytes: 1000, maxHeaderBytes: 4096, maxHeaders: 16}, responseLimits,
  physicalAcquisitionLimits: {maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
const prepare = (fetch, limits) => physical.prepareOriginalUndiciFetch(fetch, endpoint,
  {method: 'POST', body: '{}', headers: [], redirect: 'error',
    signal: new AbortController().signal}, limits);

test('each original response scalar mismatch refuses before Client construction', () => {
  const fetch = create();
  const before = constructions;
  for (const [name, value] of [['maxBytes', 2049], ['maxChunkBytes', 511],
    ['maxChunks', 17], ['maxHeaderBytes', 129]]) {
    assert.throws(() => prepare(fetch, {...responseLimits, [name]: value}),
      {code: 'UndiciOriginalRequestMismatch'});
    assert.equal(constructions, before);
  }
});

test('original observed headers retain exact cardinality names and order before Client construction', () => {
  const fetch = create();
  const before = constructions;
  for (const observedHeaders of [[], ['content-type'],
    ['x-fixture', 'content-type'], ['content-type', 'x-other']]) {
    assert.throws(() => prepare(fetch, {...responseLimits, observedHeaders}),
      {code: 'UndiciOriginalRequestMismatch'});
    assert.equal(constructions, before);
  }
});

test('equivalent original declarations prepare one Client and settle unstarted cleanup', async () => {
  const fetch = create();
  const before = constructions;
  const call = prepare(fetch, {...responseLimits,
    observedHeaders: [...responseLimits.observedHeaders]});
  try {
    assert.equal(constructions, before + 1);
    assert.equal(typeof call.invoke, 'function');
  } finally {
    assert.equal(await call.cleanup(), true);
    assert.equal(await call.cleanup(), true);
  }
  assert.equal(constructions, before + 1);
});
