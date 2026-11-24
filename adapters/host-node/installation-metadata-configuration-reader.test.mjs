import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installationMetadataSiteFixture} from './fixtures/installation-metadata-site.fixture.mjs';
import {createInstalledRowSourceCredentialSite} from './installed-row-source-credential-site.mjs';

function observeSite({beforeView = () => {}, beforeRetire = () => {}} = {}) {
  let views = 0, retires = 0;
  const {openRowSourceCredentialSite: openSite} = createInstalledRowSourceCredentialSite({
    runtimeCore(moon) {
      const original = runtimeCore(moon);
      return {...original, installationPreparationMetadata() {
        views++; beforeView();
        const view = original.installationPreparationMetadata();
        return Object.freeze({...view, retireMetadataView() {
          retires++; beforeRetire();
          return view.retireMetadataView();
        }});
      }};
    },
    text: value => typeof value === 'string' && value.length > 0,
    cidPattern: /^sha256:[0-9a-f]{64}$/u,
  });
  return {openSite, counts: () => ({views, retires})};
}

async function withKeyOpenCount(t, state, execute) {
  const original = fs.open;
  let opens = 0;
  const wrapped = t.mock.method(fs, 'open', function (path, ...args) {
    if (path === state.profile.credentialPrivateKeyPath) opens++;
    return Reflect.apply(original, this, [path, ...args]);
  });
  syncBuiltinESMExports();
  try {await execute(() => opens);}
  finally {wrapped.mock.restore(); syncBuiltinESMExports();}
}

function suppliedReader(state, pem = state.issuerPem) {
  const reader = {readText(path, bounds) {
    assert.strictEqual(this, reader);
    assert.equal(path, state.profile.credentialPrivateKeyPath);
    assert.deepEqual(bounds, {maxBytes: 4096});
    return pem;
  }};
  return reader;
}

test('metadata issuer uses the same configuration read and receiver captured before the metadata await', async t => {
  let reader, original, reads = 0;
  const selected = observeSite({beforeView() {
    reader.readText = () => assert.fail('A replacement method must not receive the original read');
  }});
  const f = await installationMetadataSiteFixture(t, async state => {
    await withKeyOpenCount(t, state, async opens => {
      const site = await state.open();
      assert.strictEqual(site, state.site);
      assert.equal(reads, 1);
      assert.equal(opens(), 0);
      assert.equal(state.counters().opens, 1);
      assert.notEqual(reader.readText, original);
    });
  }, {openSite: selected.openSite, configurationReader(state) {
    reader = suppliedReader(state);
    const supplied = reader.readText;
    original = function (...args) {reads++; return Reflect.apply(supplied, this, args);};
    reader.readText = original;
    return reader;
  }});
  await f.run();
});

test('metadata configuration refusal preserves the original pending cleanup and opens no custody', async t => {
  let pending = true;
  const cleanupHandle = Object.freeze({status: () => ({pending}), async retry() {return {pending};}});
  const original = Object.assign(new Error('OriginalConfigurationPending'), {cleanupHandle});
  const reader = {readText() {assert.strictEqual(this, reader); throw original;}};
  const selected = observeSite();
  const f = await installationMetadataSiteFixture(t, async state => {
    let failure;
    await withKeyOpenCount(t, state, async opens => {
      await assert.rejects(state.open(), error => {failure = error; return error.primaryFailure === original;});
      assert.equal(opens(), 0);
      assert.equal(state.counters().opens, 0);
    });
    assert.strictEqual(failure.primaryFailure.cleanupHandle, cleanupHandle);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(selected.counts(), {views: 1, retires: 0});
    pending = false;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(selected.counts(), {views: 1, retires: 1});
  }, {openSite: selected.openSite, configurationReader: () => reader});
  await f.run();
});

test('metadata refuses a supplied invalid reader before its await and retains the absent-reader path', async t => {
  for (const reader of [{}, Object.create({readText() {}}), {get readText() {
    assert.fail('Reader accessor must not run');
  }}, {readText: 1}, new Proxy({}, {getOwnPropertyDescriptor() {
    assert.fail('Proxy inspection must not run');
  }})]) {
    const selected = observeSite();
    const f = await installationMetadataSiteFixture(t, async state => {
      await withKeyOpenCount(t, state, async opens => {
        await assert.rejects(state.open(), {code: 'InvalidRowSourceCredentialSite'});
        assert.deepEqual(selected.counts(), {views: 0, retires: 0});
        assert.equal(opens(), 0);
        assert.equal(state.counters().opens, 0);
      });
    }, {openSite: selected.openSite, configurationReader: () => reader});
    await f.run();
  }
  const f = await installationMetadataSiteFixture(t, async state => {
    await withKeyOpenCount(t, state, async opens => {
      assert.strictEqual(await state.open(), state.site);
      assert.equal(opens(), 1);
      assert.equal(state.counters().opens, 1);
    });
  });
  await f.run();
});

test('metadata wrong issuer type retires its same original view through existing initialization cleanup', async t => {
  const pem = generateKeyPairSync('ec', {namedCurve: 'P-256'}).privateKey
    .export({type: 'pkcs8', format: 'pem'});
  const selected = observeSite();
  const f = await installationMetadataSiteFixture(t, async state => {
    let failure;
    await assert.rejects(state.open(), cause => {failure = cause; return true;});
    assert.equal(state.counters().opens, 0);
    assert.deepEqual(selected.counts(), {views: 1, retires: 1});
    assert.equal(failure.primaryFailure.code, 'InvalidRowSourceCredentialSite');
    assert.equal(failure.cleanupHandle.status().pending, false);
  }, {openSite: selected.openSite, configurationReader: state => suppliedReader(state, pem)});
  await f.run();
});

test('metadata current failure retains the same view for its original pending cleanup retry', async t => {
  const original = new Error('OriginalMetadataCurrentRefused');
  const pending = new Error('OriginalViewCleanupPending');
  let ready = false;
  const selected = observeSite({beforeRetire() {if (!ready) throw pending;}});
  const f = await installationMetadataSiteFixture(t, async state => {
    let failure;
    await assert.rejects(state.open(), cause => {failure = cause; return true;});
    assert.strictEqual(failure.primaryFailure, original);
    assert.deepEqual(selected.counts(), {views: 1, retires: 1});
    assert.equal(state.counters().opens, 0);
    assert.equal(failure.cleanupHandle.status().pending, true);
    ready = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(selected.counts(), {views: 1, retires: 2});
    assert.strictEqual(failure.primaryFailure, original);
  }, {openSite: selected.openSite, configurationReader: state => suppliedReader(state),
    input(metadata) {metadata.siteCurrent.assertCurrent = () => {throw original;};}});
  await f.run();
});

test('metadata custody construction failure joins the original child before retiring its view', async t => {
  const original = new Error('OriginalCustodyConstructionFailed');
  let pending = true, retries = 0;
  original.cleanupHandle = Object.freeze({status: () => ({pending}), async retry() {retries++; return {pending};}});
  const selected = observeSite();
  const f = await installationMetadataSiteFixture(t, async state => {
    let failure;
    await assert.rejects(state.open(), cause => {failure = cause; return true;});
    assert.strictEqual(failure.primaryFailure, original);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(selected.counts(), {views: 1, retires: 0});
    assert.equal(state.counters().opens, 1);
    pending = false;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(selected.counts(), {views: 1, retires: 1});
    assert.equal(state.counters().opens, 1);
    assert.equal(retries, 2);
    assert.strictEqual(failure.primaryFailure, original);
  }, {openSite: selected.openSite, configurationReader: state => suppliedReader(state),
    beforeJournal() {throw original;}});
  await f.run();
});
