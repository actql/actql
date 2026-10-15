import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as storeModule from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {issueInferTrustedRuntimeView, bindInferTrustedStore,
  selectedInferTrustedStoreDimensions, forgetInferTrustedRuntimeView} from './infer-trusted-runtime-view.mjs';

const originals = () => Object.freeze({host: {}, supplier: {}, installation: {},
  generation: {}, runtime: process, moduleLifetime: import.meta, transport: {},
  target: 'nominal-test-only'});
const rejects = (fn, code) => assert.throws(fn, {code});
const dimensions = () => Object.freeze({directoryCodeUnits: 1, directoryUtf8Bytes: 1,
  privateNamespaceCodeUnits: 26, privateNamespaceUtf8Bytes: 26, privateKeyBytes: 32});

// Actual Store/filesystem, explicit protocol-control and runtime-original
// doubles. This is not an installed Host, Resource grant or numeric profile.
test('same Host borrows the actual original Store dimensions without another projection', async t => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-a-store-dimensions-'));
  const directory = join(parent, 'e\u0301\u{1f600}');
  const store = await storeModule.openLocalPublicationStore({directory,
    storeAuthorityCid: 'sha256:' + 'a'.repeat(64), privateEvidenceKey: Buffer.alloc(32, 7),
    capacityBytes: 65536, maxObjectBytes: 16384, maxObjects: 8,
    maxContractNodes: 128, maxContractDepth: 16}, createPublicationContractControlFixture());
  t.after(async () => {
    assert.equal(await store.close(), true);
    await rm(parent, {recursive: true});
  });
  const actual = originals(), view = issueInferTrustedRuntimeView(actual);
  bindInferTrustedStore(view, actual, store, storeModule);
  const value = selectedInferTrustedStoreDimensions(view, actual, store, storeModule);
  assert.deepEqual(value, {directoryCodeUnits: parent.length + 1 + 4,
    directoryUtf8Bytes: Buffer.byteLength(parent) + 1 + 7,
    privateNamespaceCodeUnits: 26, privateNamespaceUtf8Bytes: 26, privateKeyBytes: 32});
  assert.equal(Object.isFrozen(value), true);
  const before = store.status();
  for (let index = 0; index < 5; index++) {
    assert.equal(selectedInferTrustedStoreDimensions(view, actual, store, storeModule), value);
  }
  assert.deepEqual(store.status(), before, 'observations do not reserve, write or release');
  assert.deepEqual(Reflect.ownKeys(view), [], 'no Store, pathname or key getter');
  forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
  rejects(() => selectedInferTrustedStoreDimensions(view, actual, store, storeModule),
    'InferTrustedRuntimeViewRetired');
});

test('dimension projection captures the original method receiver and immutable result once', () => {
  const actual = originals(), view = issueInferTrustedRuntimeView(actual);
  const value = dimensions();
  let calls = 0;
  const store = {originalModelStorageDimensions() {
    assert.equal(this, store);
    calls++;
    return value;
  }};
  bindInferTrustedStore(view, actual, store, storeModule);
  assert.equal(calls, 0, 'legacy association does not acquire this new role');
  assert.equal(selectedInferTrustedStoreDimensions(view, actual, store, storeModule), value);
  assert.equal(calls, 1);
  store.originalModelStorageDimensions = () => { throw new Error('ReconstructedProjection'); };
  for (let index = 0; index < 5; index++) {
    assert.equal(selectedInferTrustedStoreDimensions(view, actual, store, storeModule), value);
  }
  assert.equal(calls, 1);
  rejects(() => bindInferTrustedStore(view, actual, store, storeModule),
    'InferTrustedStoreAlreadyBound');
});

test('equal dimension packets cannot replace the original Host Store module or generation', () => {
  const actual = originals(), view = issueInferTrustedRuntimeView(actual);
  const store = {originalModelStorageDimensions: dimensions};
  bindInferTrustedStore(view, actual, store, storeModule);
  for (const [selected, receiver, module, code] of [
    [actual, {originalModelStorageDimensions: dimensions}, storeModule, 'InferTrustedStoreChanged'],
    [actual, dimensions(), storeModule, 'InferTrustedStoreChanged'],
    [actual, store, {...storeModule}, 'InferTrustedStoreChanged'],
    [{...actual, host: {}}, store, storeModule, 'InferTrustedRuntimeOriginalChanged'],
    [{...actual, generation: {}}, store, storeModule, 'InferTrustedRuntimeOriginalChanged'],
  ]) {
    rejects(() => selectedInferTrustedStoreDimensions(view, selected, receiver, module), code);
  }
});

test('missing malformed and accessor dimensions refuse without guessing zero or caps', () => {
  const actual = originals();
  const missing = {}, view = issueInferTrustedRuntimeView(actual);
  bindInferTrustedStore(view, actual, missing, storeModule);
  rejects(() => selectedInferTrustedStoreDimensions(view, actual, missing, storeModule),
    'InferTrustedStoreDimensionsUnavailable');
  let gets = 0;
  const accessor = Object.freeze({...dimensions(),
    get directoryCodeUnits() { gets++; return 1; }});
  for (const value of [undefined, null, {}, {...dimensions()},
    Object.freeze({...dimensions(), directoryCodeUnits: 0}),
    Object.freeze({...dimensions(), directoryUtf8Bytes: Number.MAX_SAFE_INTEGER + 1}),
    Object.freeze({...dimensions(), extra: 1}), accessor]) {
    const selected = issueInferTrustedRuntimeView(actual);
    const store = {originalModelStorageDimensions: () => value};
    bindInferTrustedStore(selected, actual, store, storeModule);
    rejects(() => selectedInferTrustedStoreDimensions(selected, actual, store, storeModule),
      'InferTrustedStoreDimensionsUnavailable');
  }
  assert.equal(gets, 0);
});
