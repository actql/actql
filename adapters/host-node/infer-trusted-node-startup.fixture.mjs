import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {Readable} from 'node:stream';
import {TextDecoder as NodeTextDecoder} from 'node:util';
import tls from 'node:tls';
import {issueInferTrustedRuntimeView, requireInferTrustedStartupView,
  associateInferTrustedStartupView, borrowInferTrustedStartupView,
  forgetInferTrustedStartupView, forgetInferTrustedRuntimeView} from './infer-trusted-runtime-view.mjs';

// Actual Node startup/allocator, nominal Host/Scope reference doubles. No Core
// scope, Ledger, byte quote, physical ACK, Provider or publication is issued.
const source = () => ({host: {}, supplier() {}, installation: {}, generation: {},
  runtime: process, moduleLifetime: import.meta, transport() {}, target: 'selected-node'});
const actual = source();
const view = issueInferTrustedRuntimeView(actual);
const mode = process.argv[2];
const rejects = (run, code) => assert.throws(run, error => error.code === code);
if (mode === 'absent' || mode === 'promise-unselected') {
  assert.equal(associateInferTrustedStartupView(view, actual), undefined);
  rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedStartupUnavailable');
  if (mode === 'promise-unselected') {
    const descriptor = Object.getOwnPropertyDescriptor(Promise.prototype, 'then');
    assert.equal(descriptor.writable, true);
    assert.equal(descriptor.configurable, true);
    const original = Promise.prototype.then;
    try { Promise.prototype.then = () => undefined; }
    finally { Promise.prototype.then = original; }
  }
} else {
  assert.equal(associateInferTrustedStartupView(view, actual), view);
  requireInferTrustedStartupView(view, actual);
  if (mode === 'selected') {
    for (const field of ['host', 'supplier', 'generation', 'installation']) {
      rejects(() => requireInferTrustedStartupView(view, {...actual, [field]: {}}),
        'InferTrustedRuntimeOriginalChanged');
    }
    rejects(() => requireInferTrustedStartupView({...view}, actual),
      'InferTrustedRuntimeViewUnavailable');
    rejects(() => associateInferTrustedStartupView(issueInferTrustedRuntimeView(source()), source()),
      'InferTrustedRuntimeOriginalChanged');
    const foreign = source();
    rejects(() => associateInferTrustedStartupView(issueInferTrustedRuntimeView(foreign), foreign),
      'InferTrustedStartupChanged');
    const scoped = {...actual, installation: {}, transport() {}};
    const borrow = issueInferTrustedRuntimeView(scoped);
    borrowInferTrustedStartupView(view, borrow, actual, scoped);
    requireInferTrustedStartupView(borrow, scoped);
    rejects(() => forgetInferTrustedStartupView(borrow, {}, actual.generation),
      'InferTrustedStartupUnavailable');
    requireInferTrustedStartupView(borrow, scoped);
    forgetInferTrustedStartupView(borrow, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(borrow, actual.host, actual.generation);
    rejects(() => requireInferTrustedStartupView(borrow, scoped),
      'InferTrustedRuntimeViewRetired');
    // Process/module responsibility is still present: no close or ACK occurs.
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedRuntimeViewRetired');
    rejects(() => associateInferTrustedStartupView(issueInferTrustedRuntimeView(actual), actual),
      'InferTrustedStartupUnavailable');
    // The same managed process/module responsibility can cover a NEW actual
    // Host generation. Forgetting an old view does not retire that baseline.
    const next = {...actual, host: {}, generation: {}, installation: {}};
    const nextView = issueInferTrustedRuntimeView(next);
    associateInferTrustedStartupView(nextView, next);
    requireInferTrustedStartupView(nextView, next);
    forgetInferTrustedStartupView(nextView, next.host, next.generation);
    forgetInferTrustedRuntimeView(nextView, next.host, next.generation);
  } else if (mode === 'identity-index-lifetime') {
    // Actual selected startup/index implementation, nominal Host/Scope refs.
    // This observes membership and retirement, never backing size/shrink/ACK.
    const other = {...actual, host: {}, generation: {}, installation: {}};
    const otherView = issueInferTrustedRuntimeView(other);
    assert.equal(associateInferTrustedStartupView(otherView, other), otherView);
    const escaped = {...actual, installation: {}, transport() {}};
    const escapedView = issueInferTrustedRuntimeView(escaped);
    borrowInferTrustedStartupView(view, escapedView, actual, escaped);
    requireInferTrustedStartupView(escapedView, escaped);
    // Repeated Runs on the SAME Host do not invent new Host generations.
    for (let index = 0; index < 3; index++) {
      const scoped = {...actual, installation: {}, transport() {}};
      const scopedView = issueInferTrustedRuntimeView(scoped);
      borrowInferTrustedStartupView(view, scopedView, actual, scoped);
      requireInferTrustedStartupView(scopedView, scoped);
      requireInferTrustedStartupView(otherView, other);
      rejects(() => requireInferTrustedStartupView(scopedView,
        {...scoped, generation: other.generation}), 'InferTrustedRuntimeOriginalChanged');
      forgetInferTrustedStartupView(scopedView, actual.host, actual.generation);
      forgetInferTrustedRuntimeView(scopedView, actual.host, actual.generation);
      rejects(() => requireInferTrustedStartupView(scopedView, scoped),
        'InferTrustedRuntimeViewRetired');
    }
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    rejects(() => requireInferTrustedStartupView(escapedView, escaped),
      'InferTrustedStartupUnavailable');
    // Retaining the original Host key does not permit generation reuse after
    // association deletion. Another live Host keeps its independent duty.
    rejects(() => associateInferTrustedStartupView(issueInferTrustedRuntimeView(actual), actual),
      'InferTrustedStartupUnavailable');
    requireInferTrustedStartupView(otherView, other);
    rejects(() => requireInferTrustedStartupView({...otherView}, other),
      'InferTrustedRuntimeViewUnavailable');
    forgetInferTrustedStartupView(escapedView, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(escapedView, actual.host, actual.generation);
    forgetInferTrustedStartupView(otherView, other.host, other.generation);
    forgetInferTrustedRuntimeView(otherView, other.host, other.generation);
  } else if (mode === 'tls-peer-originals') {
    // Selected builtin JS only, not a handshake or certificate-size bound.
    // The TLS adapter's original error retains this SAME peer graph. ActQL
    // aliases, copied diagnostics and pending controls still require funding.
    const cert = {subject: {CN: 'other.invalid'},
      subjectaltname: 'DNS:other.invalid', issuerCertificate: {subject: {CN: 'issuer'}}};
    const error = tls.checkServerIdentity('expected.invalid', cert);
    assert.equal(error.code, 'ERR_TLS_CERT_ALTNAME_INVALID');
    assert.equal(error.cert, cert);
    assert.equal(error.cert.issuerCertificate, cert.issuerCertificate);
    assert.equal(error.host, 'expected.invalid');
    for (const [owner, name] of [[tls, 'connect'], [tls, 'checkServerIdentity'],
      [tls.TLSSocket.prototype, 'getPeerCertificate']]) {
      const descriptor = Object.getOwnPropertyDescriptor(owner, name);
      assert.equal(descriptor.writable, false, name);
      assert.equal(descriptor.configurable, false, name);
      assert.throws(() => { owner[name] = () => undefined; }, TypeError);
    }
    requireInferTrustedStartupView(view, actual);
    rejects(() => requireInferTrustedStartupView(view, {...actual, transport() {}}),
      'InferTrustedRuntimeOriginalChanged');
    // Rechecking or retiring the view never acknowledges a TLS/socket close
    // and cannot clear a still-borrowed original error or certificate graph.
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    assert.equal(error.cert, cert);
    rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedRuntimeViewRetired');
  } else if (mode === 'promise-originals') {
    const original = Promise;
    for (const [owner, name] of [[globalThis, 'Promise'], [original, 'resolve'],
      [original, 'reject'], [original.prototype, 'then'],
      [original.prototype, 'catch'], [original.prototype, 'finally'],
      [original.prototype, 'constructor']]) {
      const descriptor = Object.getOwnPropertyDescriptor(owner, name);
      assert.equal(descriptor.writable, false, name);
      assert.equal(descriptor.configurable, false, name);
      assert.throws(() => { owner[name] = () => undefined; }, TypeError);
    }
    const species = Object.getOwnPropertyDescriptor(original, Symbol.species);
    assert.equal(typeof species.get, 'function');
    assert.equal(species.set, undefined);
    assert.equal(species.configurable, false);
    assert.strictEqual(species.get.call(original), original);
    assert.throws(() => Object.defineProperty(original, Symbol.species,
      {get: () => class ForeignPromise extends original {}}), TypeError);
    const value = Object.freeze({synthetic: 'same-original'});
    const pending = original.resolve(value).then(result => result).finally(() => {});
    assert.strictEqual(await pending, value);
    requireInferTrustedStartupView(view, actual);
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    // Host retirement is not retirement of the process/module originals.
    assert.equal(Object.getOwnPropertyDescriptor(original.prototype, 'then').writable, false);
  } else if (['read-decoder-global', 'read-decoder-decode', 'read-buffer-subarray'].includes(mode)) {
    assert.equal(globalThis.TextDecoder, NodeTextDecoder);
    if (mode === 'read-decoder-global') {
      assert.throws(() => Object.defineProperty(globalThis, 'TextDecoder', {
        value: class ReplacementDecoder {},
      }), TypeError);
    } else if (mode === 'read-decoder-decode') {
      assert.throws(() => {NodeTextDecoder.prototype.decode = () => '';}, TypeError);
    } else {
      assert.throws(() => {Buffer.prototype.subarray = () => Buffer.alloc(0);}, TypeError);
    }
    // The selected READ uses Buffer receivers and two distinct strict decoders.
    // Views retain the same dedicated backing, not another byte allocation.
    const bytes = Buffer.allocUnsafeSlow(7);
    bytes.set([0xef, 0xbb, 0xbf, 0x61, 0xc3, 0xa9, 0x0a]);
    const slice = bytes.subarray(3);
    assert.equal(Object.getPrototypeOf(slice), Buffer.prototype);
    assert.equal(slice.buffer, bytes.buffer);
    const first = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
    const second = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
    assert.notEqual(first, second);
    assert.equal(first.decode(bytes), '\ufeffa\u00e9\n');
    assert.equal(second.decode(slice), 'a\u00e9\n');
    assert.throws(() => first.decode(Buffer.from([0xff])), TypeError);
    requireInferTrustedStartupView(view, actual);
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
  } else if (mode === 'mutation') {
    assert.throws(() => {Buffer.poolSize = 16384;}, TypeError);
    assert.throws(() => {Buffer.concat = () => Buffer.alloc(1);}, TypeError);
    assert.throws(() => {Readable.prototype.read = () => null;}, TypeError);
    requireInferTrustedStartupView(view, actual);
    const original = globalThis.Buffer;
    globalThis.Buffer = {};
    rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedStartupChanged');
    globalThis.Buffer = original;
    rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedStartupChanged');
    // Invalidated currentness must not prevent the existing cleanup cut.
    forgetInferTrustedStartupView(view, actual.host, actual.generation);
    forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
  } else throw new Error('Explicit startup fixture mode required');
}
console.log(JSON.stringify({mode, checked: true, providerCalls: 0, physicalAcks: 0,
  coreScopes: 0, normalNumericProfile: null, publicE2E: 0}));
