import test from 'node:test';
import assert from 'node:assert/strict';
import {issueInferTrustedRuntimeView, checkInferTrustedRuntimeView,
  forgetInferTrustedRuntimeView} from './infer-trusted-runtime-view.mjs';

// Nominal-reference doubles only. No real Host/bootstrap, Resource admission,
// runtime coverage, physical cleanup or normal numeric profile is exercised.
const original = () => Object.freeze({host: Object.freeze({}),
  supplier: Object.freeze({}), installation: Object.freeze({}),
  generation: Object.freeze({}), runtime: Object.freeze({}),
  moduleLifetime: Object.freeze({}), transport: () => {},
  target: 'https://example.invalid/v1/chat/completions'});
const rejects = (run, code) => assert.throws(run, error => error.code === code);

test('runtime view retains exact originals without exposing bindings or a grant', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  assert.equal(checkInferTrustedRuntimeView(view, actual), undefined);
  assert.deepEqual(Reflect.ownKeys(view), []);
  assert.equal(Object.isFrozen(view), true);
  assert.equal(view.constructor.binding, undefined);
  // An independent shell retaining the SAME actual originals is equivalent;
  // cloning the original handles is not. The shell itself is not authority.
  assert.equal(checkInferTrustedRuntimeView(view, {...actual}), undefined);
});

test('missing copied and prototype-forged runtime views are rejected', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  for (const copied of [undefined, null, {}, {...view},
    Object.create(Object.getPrototypeOf(view))]) {
    rejects(() => checkInferTrustedRuntimeView(copied, actual),
      'InferTrustedRuntimeViewUnavailable');
  }
  rejects(() => new view.constructor(Symbol(), actual),
    'InferTrustedRuntimeViewUnavailable');
});

test('every original and the exact target are checked independently', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  for (const name of Object.keys(actual)) {
    const foreign = name === 'target' ? `${actual.target}/other` : Object.freeze({});
    rejects(() => checkInferTrustedRuntimeView(view, {...actual, [name]: foreign}),
      'InferTrustedRuntimeOriginalChanged');
    assert.equal(checkInferTrustedRuntimeView(view, actual), undefined);
  }
});

test('original descriptor getters are not invoked during issue or recheck', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  let gets = 0;
  const changed = {...actual};
  Object.defineProperty(changed, 'supplier', {enumerable: true,
    get() { gets++; return actual.supplier; }});
  rejects(() => issueInferTrustedRuntimeView(changed),
    'InferTrustedRuntimeOriginalUnavailable');
  rejects(() => checkInferTrustedRuntimeView(view, changed),
    'InferTrustedRuntimeOriginalUnavailable');
  assert.equal(gets, 0);
  assert.equal(checkInferTrustedRuntimeView(view, actual), undefined);
});

test('declaration flags CIDs and malformed bindings do not replace originals', () => {
  const actual = original();
  for (const changed of [{...actual, supplier: true},
    {...actual, generation: 1}, {...actual, runtime: 'sha256:original'},
    {...actual, target: ''}, {...actual, covered: true},
    Object.fromEntries(Object.entries(actual).filter(([name]) => name !== 'host'))]) {
    rejects(() => issueInferTrustedRuntimeView(changed),
      'InferTrustedRuntimeOriginalUnavailable');
  }
});

test('foreign retirement keeps the same view for original cleanup', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  rejects(() => forgetInferTrustedRuntimeView(view, {}, actual.generation),
    'InferTrustedRuntimeOriginalChanged');
  rejects(() => forgetInferTrustedRuntimeView(view, actual.host, {}),
    'InferTrustedRuntimeOriginalChanged');
  assert.equal(checkInferTrustedRuntimeView(view, actual), undefined);
});

test('existing owner retains the view while cleanup is pending and forgets after settlement', () => {
  const actual = original();
  const view = issueInferTrustedRuntimeView(actual);
  // Simulate the existing owner's call order, not an ACK issuer in this helper.
  const pendingFailure = new Error('original cleanup pending');
  const cleanup = () => { throw pendingFailure; };
  assert.throws(cleanup, error => error === pendingFailure);
  assert.equal(checkInferTrustedRuntimeView(view, actual), undefined);
  assert.equal(forgetInferTrustedRuntimeView(view, actual.host, actual.generation), undefined);
  rejects(() => checkInferTrustedRuntimeView(view, actual),
    'InferTrustedRuntimeViewRetired');
  rejects(() => forgetInferTrustedRuntimeView(view, actual.host, actual.generation),
    'InferTrustedRuntimeViewRetired');
});

test('forgetting the view does not close native or module originals', () => {
  let closes = 0;
  const source = original();
  const actual = {...source, moduleLifetime: Object.freeze({close() { closes++; }}),
    supplier: Object.freeze({close() { closes++; }})};
  const view = issueInferTrustedRuntimeView(actual);
  forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
  assert.equal(closes, 0);
});
