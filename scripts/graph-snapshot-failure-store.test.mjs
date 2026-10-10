import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import test from 'node:test';
import {createLocalRetainedStore} from '../adapters/store-local/files.mjs';
import {graphSnapshotFailureStore} from './fixtures/graph-snapshot-failure-store.mjs';

for (const failure of ['append', 'seal']) {
  test(`Graph ${failure} fault retains real Store reservation until cleanup retry`, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-graph-store-fault-'));
    const fixture = graphSnapshotFailureStore({createStore:createLocalRetainedStore,
      targetKey:'task-3', failure});
    t.after(async () => {
      await fixture.reclaim();
      await rm(directory, {recursive:true, force:true});
    });
    const lease = await fixture.factory({key:'task-3',bytes:128,frame:64,parentDirectory:directory});
    const writer = lease.reserve(128);
    await writer.start();
    const bytes = '[]';
    if (failure === 'append') {
      await assert.rejects(writer.append(bytes), /InjectedGraphSnapshotAppendFailure/);
    } else {
      await writer.append(bytes);
      await assert.rejects(writer.seal({bytes:2,
        cid:'sha256:'+createHash('sha256').update(bytes).digest('hex')}),
      /InjectedGraphSnapshotSealAcknowledgementLost/);
      assert.equal(fixture.leases[0].sealed.length, 1);
      assert.equal(fixture.leases[0].sealed[0].available(), true);
    }
    lease.close();
    await assert.rejects(lease.cleanup(), /InjectedGraphSnapshotCleanupPending/);
    await assert.rejects(lease.cleanup(), /InjectedGraphSnapshotCleanupPending/);
    // Seal returns unused capacity; its real two-byte body still holds the
    // remaining reservation even when acknowledgement and cleanup fail.
    assert.equal(lease.status().reservedBytes, failure === 'append' ? 128 : 2);
    assert.equal(lease.status().cleanupPending, true);
    assert.equal(fixture.leases.length, 1);
    assert.deepEqual(fixture.counts(), {failedAppends:failure === 'append' ? 1 : 0,
      lostSeals:failure === 'seal' ? 1 : 0,refusedCleanups:2});
    fixture.permitCleanup();
    await lease.cleanup();
    await lease.cleanup();
    assert.equal(lease.status().reservedBytes, 0);
    assert.equal(lease.status().cleanupPending, false);
    assert.equal(fixture.leases.length, 1);
    assert.deepEqual(await readdir(directory), []);
  });
}

test('Graph Store faults do not affect an untargeted physical lease', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-graph-store-fault-scope-'));
  const fixture = graphSnapshotFailureStore({createStore:createLocalRetainedStore,
    targetKey:'task-3',failure:'append'});
  t.after(async () => { await fixture.reclaim(); await rm(directory,{recursive:true,force:true}); });
  const lease = await fixture.factory({key:'task-2',bytes:128,frame:64,parentDirectory:directory});
  const writer = lease.reserve(128);
  await writer.start();
  await writer.append('[]');
  const body = await writer.seal({bytes:2,
    cid:'sha256:'+createHash('sha256').update('[]').digest('hex')});
  assert.equal(body.available(), true);
  lease.close();
  await lease.cleanup();
  assert.equal(lease.status().reservedBytes, 0);
  assert.deepEqual(fixture.counts(),{failedAppends:0,lostSeals:0,refusedCleanups:0});
});
