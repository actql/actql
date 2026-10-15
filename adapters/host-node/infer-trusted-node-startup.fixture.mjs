import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {Readable} from 'node:stream';
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
if (mode === 'absent') {
  assert.equal(associateInferTrustedStartupView(view, actual), undefined);
  rejects(() => requireInferTrustedStartupView(view, actual), 'InferTrustedStartupUnavailable');
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
