import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as storeModule from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {issueInferTrustedRuntimeView, bindInferTrustedStore,
  checkInferTrustedStore, forgetInferTrustedRuntimeView} from './infer-trusted-runtime-view.mjs';

// Real Store/writer/filesystem and existing shutdown Owner. The runtime and
// contract control are nominal doubles: no selected startup, Resource grant,
// numeric profile, real Core authorization or public INFER is established.
test('original Store binding survives pending shutdown and retires only after same Store cleanup',
  async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-c-trusted-store-'));
    const store = await storeModule.openLocalPublicationStore({directory,
      storeAuthorityCid: 'sha256:' + 'a'.repeat(64), capacityBytes: 1024,
      maxObjectBytes: 1024, maxObjects: 4, maxContractNodes: 64,
      maxContractDepth: 8}, createPublicationContractControlFixture());
    t.after(async () => {
      // Never erase a live Store or its unresolved physical responsibility.
      await store.close();
      await rm(directory, {recursive: true});
    });
    const host = {};
    const actual = {host, supplier: storeModule.openLocalPublicationStore,
      installation: {}, generation: host, runtime: process,
      moduleLifetime: import.meta, transport: {}, target: 'nominal-test-only'};
    const view = issueInferTrustedRuntimeView(actual);
    bindInferTrustedStore(view, actual, store, storeModule);
    let retired = 0;
    Object.assign(host, {store, dispatchOwner: {drain() {}},
      journal: {close() {}}, retireTerminalEffects() {},
      retireModelRuntime() {
        assert.equal(store.status().closed, true);
        forgetInferTrustedRuntimeView(view, host, host);
        retired++;
      }});
    const shutdown = installedHostShutdown(host);
    const writer = store.createObjectWriter(4);
    await writer.append('held');
    await assert.rejects(shutdown.close(), error =>
      error.code === 'InstalledHostCleanupPending' && error.storeCleanupPending === true &&
      error.cleanupErrors.some(item => item.owner === 'store' &&
        item.error.code === 'PublicationStoreCleanupPending'));
    assert.equal(retired, 0);
    assert.equal(store.status().reservedBytes, 4);
    assert.equal(store.status().closed, false);
    checkInferTrustedStore(view, actual, store, storeModule);
    await writer.cancel();
    await shutdown.close();
    assert.equal(retired, 1);
    assert.equal(store.status().closed, true);
    assert.throws(() => checkInferTrustedStore(view, actual, store, storeModule),
      error => error.code === 'InferTrustedRuntimeViewRetired');
    await shutdown.close();
    assert.equal(retired, 1);
  });
