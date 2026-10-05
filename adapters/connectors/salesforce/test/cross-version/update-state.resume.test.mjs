// Resume Salesforce record-update Host state that generate-update-state.mjs
// saved with an earlier checkout, using this checkout's code. Run with
//   ACTQL_UPDATE_CROSS_VERSION_STATE=<output> node --test <this file>
// A Host's authority is bound to its absolute root and principal, so each
// case restores the saved phase into its original root, on the machine and
// as the user that generated it; the saved copy is never changed, and every
// restored file must match its saved digest. A Run captured by another
// standard runtime is refused by design, so a state whose runtime differs
// from this checkout's is reported, never resumed.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {approve, digests, localStep, openHost, openOrg, runtimeBundleCid,
  terminal, waitFor} from './update-state.mjs';

// Run by run-cross-version.mjs, which generates the state. Without it the
// acceptance fails: an unproduced state is incomplete, never skipped.
const saved = process.env.ACTQL_UPDATE_CROSS_VERSION_STATE;
const skip = undefined;
test('the cross-version state was generated', () => {
  assert.ok(saved !== undefined,
    'run adapters/connectors/salesforce/test/cross-version/' +
    'run-cross-version.mjs, which generates the state this test resumes');
});

// Restore one saved phase into its original root and check it.
async function restore(t, phase, {alter} = {}) {
  const source = join(saved, 'saved', phase);
  const manifest = JSON.parse(await readFile(join(source, 'manifest.json'),
    'utf8'));
  const root = manifest.root;
  await rm(root, {recursive: true, force: true});
  t.after(() => rm(root, {recursive: true, force: true}));
  await mkdir(root, {recursive: true});
  // The archive keeps the Store's hard links; the saved archive is only read.
  execFileSync('tar', ['-xf', join(source, 'state.tar'), '-C', root]);
  assert.deepEqual(await digests(root), manifest.digests,
    `${phase}: saved digests`);
  await alter?.(root);
  const keys = JSON.parse(await readFile(join(root, 'keys.json'), 'utf8'));
  const org = await openOrg(t, {port: Number(manifest.org.port),
    certificateDirectory: join(root, 'org-tls'),
    records: manifest.expected.records_after_generation,
    writeOperation: manifest.org.write_operation});
  const installation = {directory: join(root, 'state'),
    sourceProfilePath: join(root, 'source-profile.json'),
    effectProfilePath: join(root, 'effect-profile.json')};
  const context = {installation, orgId: org.orgId, keys,
    tlsRoot: root};
  // Record writes: an update's record Id, or for a create or an upsert
  // phase the method and the last two path segments.
  const writes = () => org.seen.filter(item => item.method === 'PATCH' ||
    item.method === 'POST').map(item => /^(create|upsert)-/u.test(
    manifest.phase)
    ? `${item.method} ${decodeURIComponent(item.path.split('/').slice(-2)
      .join('/'))}`
    : decodeURIComponent(item.path.split('/').at(-1)));
  return {manifest, org, context, writes, ref: manifest.request.ref};
}

// A Host killed while it held the Set's claim keeps its Checkpoint lease
// until the lease expires; the next Host then continues the Run.
async function settled(t, context, ref) {
  const host = await openHost(context);
  t.after(() => host.close().catch(() => {}));
  const attached = await (await host.as('owner-token')).attach(ref);
  const state = await waitFor(async () => {
    const current = await attached.status();
    return terminal.includes(current.status) ? current : undefined;
  }, {attempts: 2400});
  return {host, attached, state};
}

test('saved state is from the same standard runtime', {skip}, async () => {
  for (const phase of await readdir(join(saved, 'saved'))) {
    const manifest = JSON.parse(await readFile(join(saved, 'saved', phase,
      'manifest.json'), 'utf8'));
    assert.equal(manifest.runtime_bundle_cid, await runtimeBundleCid(),
      `${phase}: a Run captured by another runtime is refused by design`);
  }
});

test('held for approval: nothing is sent until approval, then exactly once',
  {skip}, async t => {
    const {context, writes, ref} = await restore(t, 'held-for-approval');
    const first = await openHost(context);
    const attached = await (await first.as('owner-token')).attach(ref);
    assert.equal((await attached.status()).status, 'waiting_checkpoint');
    await new Promise(resolve => setTimeout(resolve, 1000));
    assert.deepEqual(writes(), []);
    await approve(first, {ref}, context.keys);
    await first.close();
    assert.deepEqual(writes(), []);
    const {host, state} = await settled(t, context, ref);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(writes(), ['a00000000000001']);
    await host.close();
  });

test('approval saved: the approved Set is sent exactly once', {skip},
  async t => {
    const {context, org, writes, ref} = await restore(t, 'approval-saved');
    const {host, state} = await settled(t, context, ref);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(writes(), ['a00000000000001']);
    assert.equal(org.records()[0].Name, 'a00000000000001');
    await host.close();
    const again = await settled(t, context, ref);
    assert.equal(again.state.status, 'succeeded');
    assert.deepEqual(writes(), ['a00000000000001']);
    await again.host.close();
  });

test('unknown after the send started: never resent', {skip}, async t => {
  const {context, writes, ref} = await restore(t, 'unknown-after-send');
  const {host, state} = await settled(t, context, ref);
  assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
  assert.deepEqual(writes(), []);
  await host.close();
});

test('response saved: continues from the saved response, never resends',
  {skip}, async t => {
    const {manifest, context, org, writes, ref} =
      await restore(t, 'response-saved');
    const {host, state} = await settled(t, context, ref);
    // The first row's saved reply stands; the held second row is unknown.
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    assert.deepEqual(writes(), []);
    assert.deepEqual(org.records(),
      manifest.expected.records_after_generation);
    await host.close();
  });

// A state whose Site binding or durable Effect input was changed after
// approval is refused before any send.
const alterations = {
  'a changed Site binding': async root => {
    const path = join(root, 'salesforce-site.json');
    const site = JSON.parse(await readFile(path, 'utf8'));
    await writeFile(path, JSON.stringify({...site, siteKey: 'another-site'}));
  },
  'an altered Effect input': async root => {
    const holdings = [];
    const walk = async directory => {
      for (const entry of await readdir(directory, {withFileTypes: true})) {
        const path = join(directory, entry.name);
        if (entry.isDirectory()) await walk(path);
        else if (entry.name.endsWith('.json') &&
            directory.includes('physical-holdings')) {
          const holding = JSON.parse(await readFile(path, 'utf8'));
          if (holding.namespace === 'effect-source') {
            const store = directory.slice(0,
              directory.indexOf('physical-holdings'));
            holdings.push(...holding.objects.map(object =>
              join(store, 'objects', object.cid.slice(7))));
          }
        }
      }
    };
    await walk(join(root, 'state'));
    assert.equal(holdings.length, 1);
    const bytes = await readFile(holdings[0]);
    bytes[bytes.length - 1] ^= 0x01;
    await writeFile(holdings[0], bytes);
  },
};
for (const [label, alter] of Object.entries(alterations)) {
  test(`${label} after approval is refused before any send`, {skip},
    async t => {
      const {context, writes, ref} = await restore(t, 'approval-saved',
        {alter});
      const opened = await settled(t, context, ref).then(value => value,
        error => ({error}));
      if (opened.error === undefined) {
        assert.equal(opened.state.status, 'failed',
          JSON.stringify(opened.state));
        await opened.host.close();
      }
      assert.deepEqual(writes(), []);
    });
}

// Sets of the other installed kinds, captured before the move.
const kindWrites = {create: 'POST Test_Record__c/',
  upsert: 'PATCH External_Key__c/a00000000000001'};
for (const [kind, write] of Object.entries(kindWrites)) {
  test(`${kind} held for approval: nothing is sent until approval, then once`,
    {skip}, async t => {
      const {context, writes, ref} = await restore(t,
        `${kind}-held-for-approval`);
      const first = await openHost(context);
      const attached = await (await first.as('owner-token')).attach(ref);
      assert.equal((await attached.status()).status, 'waiting_checkpoint');
      await new Promise(resolve => setTimeout(resolve, 1000));
      assert.deepEqual(writes(), []);
      await approve(first, {ref}, context.keys);
      await first.close();
      const {host, state} = await settled(t, context, ref);
      assert.equal(state.status, 'succeeded', JSON.stringify(state));
      assert.deepEqual(writes(), [write]);
      await host.close();
    });

  test(`${kind} with approval saved: sent exactly once`, {skip}, async t => {
    const {context, writes, ref} = await restore(t, `${kind}-approval-saved`);
    const {host, state} = await settled(t, context, ref);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(writes(), [write]);
    await host.close();
    const again = await settled(t, context, ref);
    assert.equal(again.state.status, 'succeeded');
    assert.deepEqual(writes(), [write]);
  });

  test(`${kind} unknown after the send started: never resent`, {skip},
    async t => {
      const {context, writes, ref} = await restore(t,
        `${kind}-unknown-after-send`);
      const {host, state} = await settled(t, context, ref);
      assert.equal(state.status, 'needs_reconciliation',
        JSON.stringify(state));
      assert.deepEqual(writes(), []);
      await host.close();
    });
}

// --- Embedded Local resumes the same saved state ---------------------------
// Each resume is its own process: the Embedded Local Host lives as long as
// its process, so the step settles the Run and exits before the root is
// removed.
async function settledLocal(context, ref) {
  const refPath = join(context.installation.directory, '..',
    'local-ref.json');
  await writeFile(refPath, JSON.stringify(ref));
  const printed = await localStep('settle', {installation:
    context.installation, orgId: context.orgId, keys: context.keys,
  refPath});
  return JSON.parse(printed.trim().split('\n').at(-1));
}

test('Local: approval saved: the approved Set is sent exactly once', {skip},
  async t => {
    const {context, writes, ref} = await restore(t, 'local-approval-saved');
    const state = await settledLocal(context, ref);
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(writes(), ['a00000000000001']);
    // A further restart sends nothing more.
    assert.equal((await settledLocal(context, ref)).status, 'succeeded');
    assert.deepEqual(writes(), ['a00000000000001']);
  });

test('Local: unknown after the send started: never resent', {skip},
  async t => {
    const {context, writes, ref} = await restore(t,
      'local-unknown-after-send');
    const state = await settledLocal(context, ref);
    assert.equal(state.status, 'needs_reconciliation', JSON.stringify(state));
    assert.deepEqual(writes(), []);
  });
