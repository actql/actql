import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {bindProcessStore} from './process-binding.mjs';
import {createProcessStoreLease, processRetainedBodyIdentity} from './process-client.mjs';
import {createProcessRetainedStore} from './process-service.mjs';
import {registerRetainedInput, retainedStorageBody} from './representations.mjs';

test('completion storage lookup keeps exact material, lease and process binding with real sealed bytes', async () => {
  const parentDirectory = await mkdtemp(join(tmpdir(), 'actql-completion-lease-'));
  const store = createProcessRetainedStore({parentDirectory, capacityBytes: 100, maxFrameBytes: 100, maxEntries: 1});
  const identity = {session: 'installed-session', run: 'same-run'};
  let stop;
  const stopped = new Promise(resolve => { stop = resolve; });
  store.observe({identity: () => identity, cleanupHandle: {whenStopped: () => stopped}});
  const controller = new AbortController();
  let calls = 0;
  const context = {...identity, callHost: request => store.service.invoke(request,
    controller.signal, {...identity, sequence: 1, call: ++calls})};
  const binding = bindProcessStore(context);
  const lease = createProcessStoreLease(binding, 'task-1', 100, 100, controller.signal);
  try {
    const writer = lease.reserve(100);
    await writer.start();
    await writer.append('[]');
    const cid = `sha256:${createHash('sha256').update('[]').digest('hex')}`;
    const body = await writer.seal({bytes: 2, cid});
    const material = {}, input = {};
    registerRetainedInput(material, read => read === input, body,
      {maxFrameBytes: 100, wire: {max_bytes: 100}});
    assert.equal(retainedStorageBody(material), body);
    assert.throws(() => retainedStorageBody({...material}), /ForeignRetainedStorage/);
    assert.deepEqual(processRetainedBodyIdentity(body, binding), {...identity, output: 'task-1', bytes: 2, cid});
    assert.throws(() => processRetainedBodyIdentity({...body}, binding), {code: 'ForeignRetainedStoreBody'});
    // Even a second installed binding with equal session strings is not the
    // binding that created this lease. Wire/copied settings grant nothing.
    assert.throws(() => processRetainedBodyIdentity(body, bindProcessStore(context)), {code: 'ForeignRetainedStoreBody'});
    assert.throws(() => processRetainedBodyIdentity(body, {...binding}), /ForeignProcessStoreBinding/);
    assert.equal(await body.withVerifiedFile(async file => {
      assert.equal(await readFile(file.path, 'utf8'), '[]');
      return 'native-result';
    }), 'native-result');
    assert.equal(body.available(), true);
    body.close();
    assert.throws(() => processRetainedBodyIdentity(body, binding), {code: 'ForeignRetainedStoreBody'});
    assert.equal(store.body('task-1').available(), true);
    assert.equal(store.status().admittedWriteBytes, 2);
  } finally {
    lease.close(); await lease.cleanup(); stop(); await stopped;
    await store.close(); await store.cleanupHandle.retry(); await rmdir(parentDirectory);
  }
});
