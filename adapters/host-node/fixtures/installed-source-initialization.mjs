// Actual initial Resource/service entrance for installed-provider components.
// This is not the public Host installation/current or Request-borrow route.
import assert from 'node:assert/strict';
// A retained external Common uses its own relative CJS resource issuer. The
// component must select that SAME original adapter, without copying a module
// or rebinding Common's FFI to a new namespace. Normal local execution uses
// the default adjacent adapter and runtime together.
const {openHostInitializationPreparation, closeHostInitializationPreparation} =
  await import(process.env.ACTQL_TEST_PREPARATION_ADAPTER_URL ??
    new URL('../../local-node/request-preparation-adapter.mjs', import.meta.url).href);
import {createInstalledHostServices, retainInstalledHostServiceInstallation,
  installedSourceConfigurationReader, beginInstalledSourceInitialization,
  finishInstalledSourceInitialization, retireInstalledSourceInitialization}
  from '../installed-host-services.mjs';

// Register one ordered after hook even though the underlying transport fixture
// is constructed first. A pending Source must not permit its parent to close.
export function installedSourceFixtureLifetime(t) {
  let dependentClose, initialization;
  const sources = [];
  const transportContext = {
    diagnostic: (...args) => t.diagnostic(...args),
    after(close) {assert.equal(dependentClose, undefined); dependentClose = close;},
  };
  t.after(async () => {
    const failures = [];
    try {
      for (const source of sources) await source.close();
      if (initialization !== undefined) {
        if (initialization.services !== undefined) {
          assert.equal(retireInstalledSourceInitialization(initialization.services), true);
        }
        initialization.childrenPending = false;
        closeHostInitializationPreparation(initialization.state);
        initialization.active = false;
      }
    } catch (cause) {failures.push(cause);}
    // This fixture's TLS listener/independent journal must still close when
    // original Source/parent cleanup refuses. Keep that refusal; do not clear
    // the original child duty or manufacture a parent retirement ACK.
    try {await dependentClose?.();} catch (cause) {failures.push(cause);}
    if (failures.length === 1) throw failures[0];
    if (failures.length > 1) throw new AggregateError(failures,
      'InstalledSourceFixtureCleanupUnconfirmed', {cause: failures[0]});
  });
  return {transportContext, sources,
    open({root, moon, installation, runtimeBundleCid, baseEnvironmentWire,principalId='operator'}) {
      assert.equal(initialization, undefined);
      // Retain before the actual fallible Resource/admission constructor.
      initialization = {state: {}, active: true, childrenPending: false};
      const current = () => {assert.equal(initialization.active, true);};
      const input = Object.freeze({root, original: 'installed Source component'});
      const parent = openHostInitializationPreparation(initialization.state, moon,
        input, current, () => initialization.childrenPending);
      const services = createInstalledHostServices({root, principalId, moon,
        assertCurrent: current, initialPreparation: parent});
      initialization.services = services;
      // The SAME service's acknowledged retirement, rather than an optional
      // provider status field, is what clears this original child duty.
      initialization.childrenPending = true;
      retainInstalledHostServiceInstallation(services, installation, runtimeBundleCid);
      const configurationReader = installedSourceConfigurationReader(services);
      return Object.freeze({installation, installationServices: services, configurationReader,
        async load(factory, profile, options) {
          const sourceInitialization = beginInstalledSourceInitialization(services,
            installation, profile.connectorId, baseEnvironmentWire);
          let source;
          try {
            source = await factory(profile, {...options, installation,
              installationServices: services, configurationReader, sourceInitialization});
            finishInstalledSourceInitialization(sourceInitialization, source);
            sources.push(source);
            return source;
          } catch (cause) {
            // Bounded fixture diagnostics select only error/stack coordinates;
            // never serialize a retained preparation, Credential or cleanup
            // carrier. This does not classify the failure or drive its retry.
            const pending = [cause], seen = new Set(), errors = [];
            while (pending.length && errors.length < 8) {
              const value = pending.shift();
              if (value === null || typeof value !== 'object' || seen.has(value)) continue;
              seen.add(value);
              errors.push({name: value.name, code: value.code,
                constructor: value.constructor?.name,
                tag: typeof value.$tag === 'number' ? value.$tag : undefined,
                stack: typeof value.stack === 'string' ? value.stack.split('\n').slice(0, 10) : undefined});
              pending.push(value.cause, value.primaryFailure);
            }
            t.diagnostic(JSON.stringify({fixtureInitializationErrors: errors}));
            finishInstalledSourceInitialization(sourceInitialization, source, cause, true);
            throw cause;
          }
        },
      });
    },
  };
}
