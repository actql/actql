import assert from 'node:assert/strict';
import {mkdir, mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {retainInstalledCredentialSiteCleanup} from './installed-host-cleanup.mjs';

function siteOwner() {
  let closes = 0;
  return {close() { closes++; }, cleanupPending: () => closes === 0,
    closes: () => closes};
}

test('a replacement status during the original retry cannot acknowledge the held original child', async () => {
  const site = siteOwner();
  let held = true, retries = 0;
  const child = {
    status() { assert.equal(this, child); return {pending: held, errors: []}; },
    async retry() {
      assert.equal(this, child);
      retries++;
      child.status = () => ({pending: false, errors: []});
    },
  };
  const primary = Object.assign(new Error('OriginalOpeningFailure'), {
    cleanupHandle: child, cleanupPending: true,
  });
  const failure = retainInstalledCredentialSiteCleanup(site, primary);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(held, true);
  assert.equal(retries, 1);
  held = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(retries, 1);
  assert.equal(site.closes(), 1);
});

test('the original Reader and methods stay owned across replacement handles and retry properties', async t => {
  const parent = fileURLToPath(new URL('../../_build/credential-site-original-methods/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'owned-'));
  await writeFile(join(root, 'reader'), 'original reader remains held');
  const reader = await open(join(root, 'reader'), 'r');
  let closed = false, permit = false, retries = 0, replaced = 0;
  t.after(async () => {
    if (!closed) await reader.close();
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      console.error(`Original Reader cleanup scratch retained: ${root}`);
    } else await rm(root, {recursive: true, force: true});
  });
  const child = {
    status() { assert.equal(this, child); return {pending: !closed, errors: []}; },
    async retry() {
      assert.equal(this, child);
      retries++;
      child.retry = async () => { replaced++; };
      child.status = () => ({pending: false, errors: []});
      if (permit && !closed) { await reader.close(); closed = true; }
    },
  };
  const primary = Object.assign(new Error('OriginalReaderFailure'), {
    cleanupHandle: child, cleanupPending: true,
  });
  const site = siteOwner();
  const failure = retainInstalledCredentialSiteCleanup(site, primary);
  const handle = failure.cleanupHandle;
  assert.equal((await handle.retry()).pending, true);
  assert.ok((await reader.stat()).size > 0);
  primary.cleanupHandle = {status: () => ({pending: false}), retry: async () => { replaced++; }};
  assert.equal((await handle.retry()).pending, true);
  assert.equal(retries, 2);
  permit = true;
  assert.equal((await handle.retry()).pending, false);
  await assert.rejects(reader.stat(), {code: 'EBADF'});
  assert.equal((await handle.retry()).pending, false);
  assert.equal(retries, 3);
  assert.equal(replaced, 0);
  assert.equal(site.closes(), 1);
});

for (const property of ['retry', 'status']) {
  test(`a throwing original ${property} getter retains the same child and independent Site`, async () => {
    const site = siteOwner();
    let available = false, held = true, retries = 0;
    const observation = new Error('OriginalMethodCaptureUnavailable');
    const child = {};
    const methods = {
      status() { assert.equal(this, child); return {pending: held, errors: []}; },
      async retry() { assert.equal(this, child); retries++; },
    };
    for (const name of ['retry', 'status']) {
      Object.defineProperty(child, name, {get() {
        if (name === property && !available) throw observation;
        return methods[name];
      }});
    }
    const primary = Object.assign(new Error('OriginalOpeningFailure'), {
      cleanupHandle: child, cleanupPending: true,
    });
    const failure = retainInstalledCredentialSiteCleanup(site, primary);
    const handle = failure.cleanupHandle;
    assert.equal(handle.status().pending, true);
    assert.ok(handle.status().errors.includes(observation));
    assert.equal((await handle.retry()).pending, true);
    assert.equal(site.closes(), 1);
    available = true;
    assert.equal((await handle.retry()).pending, true);
    assert.equal(retries, 1);
    held = false;
    assert.equal((await handle.retry()).pending, false);
    assert.equal(retries, 1);
  });
}
