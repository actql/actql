// Selected Undici allocation/cardinality witness, not normal profile admission.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {Duplex} from 'node:stream';
import test from 'node:test';
const require = createRequire(import.meta.url);
const {Client} = require('undici');
const {kParser} = require('undici/lib/core/symbols');

test('original parser retains later header views from the same chunk after overflow destroys its socket', async t => {
  assert.equal(process.versions.node, '22.22.0');
  assert.equal(require('undici/package.json').version, '7.30.0');
  const headerLimit = 256, pairs = 192;
  const wire = 'HTTP/1.1 200 OK\r\n' + 'x: y\r\n'.repeat(pairs) + '\r\n';
  const frame = Buffer.allocUnsafeSlow(Buffer.byteLength(wire));
  frame.write(wire);
  const observations = [];
  let parser, requests = 0, connections = 0, closes = 0, responseQueued = false;
  class OriginalSocket extends Duplex {
    _read() {}
    _write(_chunk, _encoding, callback) {
      if (!responseQueued) {
        responseQueued = true;
        requests++;
        queueMicrotask(() => {
          parser = this[kParser];
          assert.ok(parser, 'the actual Client installed its real llhttp parser');
          for (const name of ['onHeaderField', 'onHeaderValue']) {
            const original = parser[name];
            parser[name] = function(buf) {
              const destroyedBefore = this.socket.destroyed;
              const result = Reflect.apply(original, this, [buf]);
              observations.push({name, bytes: buf.length, destroyedBefore,
                destroyedAfter: this.socket.destroyed, headersSize: this.headersSize,
                slots: this.headers.length, sameBacking: buf.buffer === frame.buffer});
              return result;
            };
          }
          this.push(frame);
          this.push(null);
        });
      }
      callback();
    }
    _destroy(error, callback) { callback(error); }
    setNoDelay() { return this; }
    setKeepAlive() { return this; }
    setTimeout() { return this; }
    ref() { return this; }
    unref() { return this; }
  }
  const socket = new OriginalSocket();
  socket.once('close', () => { closes++; });
  const client = new Client('http://original.fixture', {
    allowH2: false, pipelining: 0, maxHeaderSize: headerLimit, maxResponseSize: 8192,
    connect(_options, callback) {
      connections++;
      queueMicrotask(() => callback(null, socket));
    },
  });
  t.after(async () => { await client.destroy(); });
  await assert.rejects(client.request({path: '/chat/completions', method: 'POST', body: '{}'}),
    {code: 'UND_ERR_HEADERS_OVERFLOW'});
  await client.destroy();
  assert.equal(connections, 1);
  assert.equal(requests, 1);
  assert.equal(closes, 1);
  assert.equal(observations.length, pairs * 2);
  const firstOverflow = observations.findIndex(item => item.destroyedAfter);
  assert.equal(firstOverflow, headerLimit - 1);
  const later = observations.slice(firstOverflow + 1);
  assert.equal(later.length, 128);
  assert.ok(later.every(item => item.destroyedBefore && item.destroyedAfter));
  assert.ok(observations.every(item => item.sameBacking));
  assert.equal(parser.headers.length, pairs * 2);
  assert.equal(parser.headersSize, pairs * 2);
  assert.ok(parser.headersSize > headerLimit);
  t.diagnostic(JSON.stringify({headerLimit, wireBytes: frame.byteLength, pairs,
    callbacks: observations.length, callbacksAfterDestroyed: later.length,
    finalHeaderBytes: parser.headersSize, finalHeaderSlots: parser.headers.length,
    distinctInputBackings: 1, connections, requests, closes, tcpConnections: 0,
    qualification: 'Actual Undici7.30 Client/llhttp with controlled Duplex only. Diagnostic retains parser/events intentionally; no native socket/TLS/Provider/Core admission, numerical profile, or escaped-view retirement proof.',
    normalNumericProfile: null, publicE2E: 0}));
});
