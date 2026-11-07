// Real initial Resource and Host services for public installed-loader tests.
// This owner is retained before open(); no scope, constructor or ACK is mocked.
import assert from 'node:assert/strict';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../../local-node/request-preparation-adapter.mjs';
import {createInstalledHostServices, retireInstalledSourceInitialization}
  from '../installed-host-services.mjs';

export function createInstalledLoaderParent({root, principalId = 'operator', moon}) {
  const state = {}, sources = new Set(), failures = new Set();
  let services, active = true, childrenPending = false, opened = false, closed = false;
  const current = () => assert.equal(active, true, 'original installation parent remains current');
  return Object.freeze({
    get services() {return services;},
    open() {
      assert.equal(opened, false);
      opened = true;
      const input = Object.freeze({root, purpose: 'public installed-loader regression'});
      const initialPreparation = openHostInitializationPreparation(state, moon, input,
        current, () => childrenPending);
      services = createInstalledHostServices({root, principalId, moon,
        initialPreparation, assertCurrent: current});
      childrenPending = true;
    },
    async load(factory, path, options) {
      assert.ok(services);
      assert.equal(closed, false);
      try {
        const adapter = await factory(path, {...options, installationServices: services});
        if (adapter !== undefined) sources.add(adapter);
        return adapter;
      } catch (failure) {
        failures.add(failure);
        throw failure;
      }
    },
    retain(adapter) {sources.add(adapter); return adapter;},
    async close() {
      if (closed) return;
      const errors = [];
      for (const failure of failures) {
        try {
          if (failure.cleanupHandle?.status().pending === true) {
            const observed = await failure.cleanupHandle.retry();
            assert.equal(observed.pending, false);
          }
        } catch (error) {errors.push(error);}
      }
      for (const source of sources) {
        try {await source.close();} catch (error) {errors.push(error);}
      }
      if (errors.length) throw new AggregateError(errors, 'InstalledLoaderChildrenCleanupPending');
      if (services !== undefined) assert.equal(retireInstalledSourceInitialization(services), true);
      childrenPending = false;
      if (opened) closeHostInitializationPreparation(state);
      active = false; closed = true;
    },
  });
}

// A common failure wrapper must preserve, not replace, the specific original
// refusal. Inspect only error identities/codes, never retained input or secrets.
export function installedFailureCode(code) {
  return failure => {
    const pending = [failure], seen = new Set();
    while (pending.length && seen.size < 12) {
      const value = pending.shift();
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      if (value.code === code) return true;
      pending.push(value.primaryFailure, value.cause);
    }
    return false;
  };
}
