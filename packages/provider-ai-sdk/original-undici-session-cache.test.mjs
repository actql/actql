import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {createRequire} from 'node:module';
import test from 'node:test';

// Separate Node test-file process. Retain the actual pinned CJS implementation
// while observing the selected options before its ESM consumer is loaded.
const require = createRequire(new URL('./package.json', import.meta.url));
const undici = require('undici');
const originalBuilder = undici.buildConnector;
const selections = [];
undici.buildConnector = options => {
  const connector = Reflect.apply(originalBuilder, undici, [options]);
  selections.push({options, connector});
  return connector;
};
let physical;
try {
  physical = await import('./_internal/original-undici-transport.mjs');
} finally {
  undici.buildConnector = originalBuilder;
}

function prepared() {
  const responseLimits = {maxBytes: 2048, maxChunkBytes: 512, maxChunks: 16,
    maxHeaderBytes: 1024, observedHeaders: []};
  const endpoint = 'https://fixture.invalid/v1/chat/completions';
  const fetch = physical.createOriginalUndiciFetch({endpoint,
    requestLimits: {maxBytes: 1000, maxHeaderBytes: 1024, maxHeaders: 8},
    responseLimits, physicalAcquisitionLimits: {
      maxPlaintextBytes: 65536, maxBorrowedBackingBytes: 131072, maxReads: 64}});
  return physical.prepareOriginalUndiciFetch(fetch, endpoint,
    {method: 'POST', body: '{}', headers: [], redirect: 'error',
      signal: new AbortController().signal}, responseLimits);
}

test('selected original preparation disables unused TLS session caching before any invoke', async () => {
  const before = selections.length;
  const call = prepared();
  try {
    assert.equal(selections.length, before + 1);
    assert.deepEqual(selections[before].options,
      {allowH2: false, maxCachedSessions: 0});
  } finally {
    // Actual unstarted Client cleanup; not a Model/Store or TLS close witness.
    assert.equal(await call.cleanup(), true);
  }
});

test('actual pinned connector registers default tickets but no selected cache tickets', async t => {
  const call = prepared();
  const selected = selections.at(-1).connector;
  const tls = require('node:tls');
  const originalConnect = tls.connect;
  const originalRegister = FinalizationRegistry.prototype.register;
  let registers = 0;
  let socket;
  let callbackCount = 0;
  FinalizationRegistry.prototype.register = function(...args) {
    registers++;
    return Reflect.apply(originalRegister, this, args);
  };
  // Synthetic Socket events only: no TCP, handshake, credential or Provider.
  // This exercises the unmodified selected connector/session-cache logic;
  // it proves no TLS/native size or physical termination bound.
  tls.connect = options => {
    assert.equal(options.session, null);
    socket = new EventEmitter();
    socket.setKeepAlive = () => socket;
    socket.setNoDelay = () => socket;
    return socket;
  };
  try {
    const exercise = async connector => {
      const returned = connector({hostname: 'fixture.invalid', host: 'fixture.invalid',
        protocol: 'https:', port: 443, servername: 'fixture.invalid'}, (error, current) => {
        assert.equal(error, null);
        assert.equal(current, socket);
        callbackCount++;
      });
      assert.equal(returned, socket);
      socket.emit('secureConnect');
      // Complete the same connector's scheduled timeout retirement.
      await Promise.resolve();
      for (let index = 0; index < 17; index++) {
        socket.emit('session', Buffer.from([index]));
      }
    };
    await exercise(Reflect.apply(originalBuilder, undici, [{allowH2: false}]));
    assert.equal(registers, 17, 'actual default same-key registration control');
    const baseline = registers;
    await exercise(selected);
    assert.equal(registers - baseline, 0, 'same selected connector, no resumption registrations');
    assert.equal(callbackCount, 2);
    t.diagnostic('Actual pinned cache logic/synthetic socket; TLS/native/Model grant/public0');
  } finally {
    tls.connect = originalConnect;
    FinalizationRegistry.prototype.register = originalRegister;
    assert.equal(await call.cleanup(), true);
  }
});
