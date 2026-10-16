import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {request} from 'node:https';
import {readFile, readdir, stat} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {openHttpsExchangeFixture} from './https-exchange-fixture.mjs';

async function openWithPreservation(value) {
  const previous = process.env.ACTQL_TEST_PRESERVE_SCRATCH;
  try {
    if (value === undefined) delete process.env.ACTQL_TEST_PRESERVE_SCRATCH;
    else process.env.ACTQL_TEST_PRESERVE_SCRATCH = value;
    return await openHttpsExchangeFixture(undefined, {
      routes: [{pathname: '/original', handle: () => ({body: {original: true}})}],
    });
  } finally {
    if (previous === undefined) delete process.env.ACTQL_TEST_PRESERVE_SCRATCH;
    else process.env.ACTQL_TEST_PRESERVE_SCRATCH = previous;
  }
}

function fetch(fixture) {
  return new Promise((resolve, reject) => {
    const call = request(`${fixture.origin}/original`, {ca: fixture.ca, agent: false}, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.once('end', () => resolve(JSON.parse(Buffer.concat(chunks))));
      response.once('error', reject);
    });
    call.once('error', reject);
    call.end();
  });
}

async function inventory(root) {
  return Promise.all((await readdir(root)).sort().map(async name => {
    const path = join(root, name);
    const entry = await stat(path);
    assert(entry.isFile());
    return {name, bytes: entry.size, mode: entry.mode & 0o777,
      sha256: createHash('sha256').update(await readFile(path)).digest('hex')};
  }));
}

test('the HTTPS fixture closes its server but preserves the original TLS files when requested', async t => {
  // Capture the caller's flag at creation; restoring its environment must not
  // erase the original certificates when the asynchronous closer runs later.
  const fixture = await openWithPreservation('1');
  const root = dirname(fixture.caPath);
  t.diagnostic(`Original disposable HTTPS fixture custody: ${root}`);
  const original = await inventory(root);
  assert(original.some(entry => entry.name === 'ca.key'));
  assert(original.some(entry => entry.name === 'resource.key'));
  try {
    assert.deepEqual(await fetch(fixture), {original: true});
  } finally {
    await fixture.close();
  }
  await assert.rejects(fetch(fixture), {code: 'ECONNREFUSED'});
  assert.deepEqual(await inventory(root), original);
  assert.deepEqual(fixture.seen().map(entry => entry.pathname), ['/original']);
});

test('the default disposable HTTPS fixture still closes and removes its TLS files', async t => {
  const fixture = await openWithPreservation(undefined);
  const root = dirname(fixture.caPath);
  t.diagnostic(`Explicit default-disposable HTTPS fixture custody: ${root}`);
  try {
    assert.deepEqual(await fetch(fixture), {original: true});
  } finally {
    await fixture.close();
  }
  await assert.rejects(fetch(fixture), {code: 'ECONNREFUSED'});
  await assert.rejects(stat(root), {code: 'ENOENT'});
  assert.deepEqual(fixture.seen().map(entry => entry.pathname), ['/original']);
});
