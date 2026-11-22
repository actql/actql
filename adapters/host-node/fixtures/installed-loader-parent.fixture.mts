// Real initial Resource and Host services for public installed-loader tests.
// This owner is retained before open(); no scope, constructor or ACK is mocked.
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {createInstalledHostServices, retireInstalledSourceInitialization, closeInstalledAccountConstruction}
  from '../installed-host-services.mjs';

type Preparation = Pick<typeof import('../../local-node/request-preparation-adapter.mjs'),
  'openHostInitializationPreparation' | 'closeHostInitializationPreparation'>;
type Services = ReturnType<typeof createInstalledHostServices>;
type Runtime = Parameters<typeof createInstalledHostServices>[0]['moon'] &
  Parameters<Preparation['openHostInitializationPreparation']>[1];
type InitializationState = Parameters<Preparation['openHostInitializationPreparation']>[0];
type ParentInput = Readonly<{root: string; principalId?: string; moon: Runtime; assertCurrent?: () => unknown}>;
type Adapter = Readonly<{close(): unknown}>;
type CleanupFailure = Readonly<{cleanupHandle?: {
  status(): Readonly<{pending?: boolean}>;
  retry(): Promise<Readonly<{pending: boolean}>> | Readonly<{pending: boolean}>;
}}>;
type FailureData = Readonly<{code?: unknown; primaryFailure?: unknown; cause?: unknown}>;

// A retained normal runtime has its own physical Resource module instance.
// Equal source-side bytes cannot open that runtime's original parent ports.
const preparationUrl = process.env.ACTQL_TEST_BOUND_CONSTRUCTION_RUNTIME === undefined
  ? new URL('../../local-node/request-preparation-adapter.mjs', import.meta.url)
  : new URL('../../../../../adapters/local-node/request-preparation-adapter.mjs',
    pathToFileURL(realpathSync(process.env.ACTQL_TEST_BOUND_CONSTRUCTION_RUNTIME)));
const {openHostInitializationPreparation, closeHostInitializationPreparation}: Preparation = await import(preparationUrl.href);

export function createInstalledLoaderParent({root, principalId = 'operator', moon, assertCurrent}: ParentInput) {
  const state: InitializationState = {}, sources = new Set<Adapter>(), failures = new Set<CleanupFailure>();
  let services: Services | undefined, active = true, childrenPending = false, opened = false, closed = false;
  const current = (): undefined => {
    assert.equal(active, true, 'original installation parent remains current');
    assertCurrent?.();
  };
  return Object.freeze({
    get services() {return services;},
    open() {
      assert.equal(opened, false);
      opened = true;
      const input = Object.freeze({root, purpose: 'public installed-loader regression'});
      const initialPreparation = openHostInitializationPreparation(state, moon, input,
        current, () => childrenPending);
      services = createInstalledHostServices({root, principalId, moon,
        initialPreparation, assertCurrent: current, accountCurrent: current});
      childrenPending = true;
    },
    async load<Path, Options extends object, Loaded extends Adapter>(
      factory: (path: Path, options: Options & {installationServices: Services}) => Loaded | undefined | PromiseLike<Loaded | undefined>,
      path: Path, options: Options,
    ) {
      assert.ok(services);
      assert.equal(closed, false);
      try {
        const adapter = await factory(path, {...options, installationServices: services});
        if (adapter !== undefined) sources.add(adapter);
        return adapter;
      } catch (failure) {
        failures.add(failure as CleanupFailure);
        throw failure;
      }
    },
    retain<Loaded extends Adapter>(adapter: Loaded) {sources.add(adapter); return adapter;},
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
      if (services !== undefined) {
        assert.equal(await closeInstalledAccountConstruction(services), true);
        assert.equal(retireInstalledSourceInitialization(services), true);
      }
      childrenPending = false;
      if (opened) closeHostInitializationPreparation(state);
      active = false; closed = true;
    },
  });
}

// A common failure wrapper must preserve, not replace, the specific original
// refusal. Inspect only error identities/codes, never retained input or secrets.
export function installedFailureCode(code: string) {
  return (failure: unknown) => {
    const pending = [failure], seen = new Set<object>();
    while (pending.length && seen.size < 12) {
      const value = pending.shift();
      if (!value || typeof value !== 'object' || seen.has(value)) continue;
      seen.add(value);
      if ((value as FailureData).code === code) return true;
      pending.push((value as FailureData).primaryFailure, (value as FailureData).cause);
    }
    return false;
  };
}
