import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';

// Test-process guards, not a Provider or an execution implementation. The
// caller installs no Source profiles. Only this fixture's HTTPS ingress may
// use fetch; process-backed or other fetch-backed Provider attempts fail.
export function guardReleaseSourcefreeIo({transportOrigin} = {}) {
  if (transportOrigin !== undefined) {
    assert.equal(new URL(transportOrigin).protocol, 'https:');
    assert.equal(new URL(transportOrigin).hostname, '127.0.0.1');
  }
  let sourceSecrets = 0, forbiddenFetches = 0, forbiddenProcesses = 0;
  const originalFetch = globalThis.fetch;
  const methods = ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork'];
  const originalMethods = new Map(methods.map(name => [name, childProcess[name]]));
  for (const name of methods) childProcess[name] = () => {
    forbiddenProcesses++;
    throw new Error('UnexpectedSourcefreeProviderProcess');
  };
  syncBuiltinESMExports();
  globalThis.fetch = (...args) => {
    const url = new URL(args[0] instanceof Request ? args[0].url : args[0]);
    if (transportOrigin === undefined || url.origin !== transportOrigin) {
      forbiddenFetches++;
      throw new Error('UnexpectedSourcefreeProviderFetch');
    }
    return Reflect.apply(originalFetch, globalThis, args);
  };
  return {
    allowTransportOrigin(origin) {
      assert.equal(transportOrigin, undefined);
      assert.equal(new URL(origin).protocol, 'https:');
      assert.equal(new URL(origin).hostname, '127.0.0.1');
      assert.equal(new URL(origin).origin, origin);
      transportOrigin = origin;
    },
    resolveSourceSecret() {
      sourceSecrets++;
      throw new Error('UnexpectedSourcefreeSecretResolution');
    },
    snapshot: () => ({sourceSecrets, forbiddenFetches, forbiddenProcesses}),
    attemptedProviderIo: () => sourceSecrets + forbiddenFetches + forbiddenProcesses,
    assertQuiet() {
      assert.deepEqual(this.snapshot(), {sourceSecrets: 0, forbiddenFetches: 0, forbiddenProcesses: 0});
    },
    close() {
      globalThis.fetch = originalFetch;
      for (const [name, method] of originalMethods) childProcess[name] = method;
      syncBuiltinESMExports();
    },
  };
}
