// Actual initial Resource/service entrance for installed-provider components.
// This is not the public Host installation/current or Request-borrow route.
import assert from 'node:assert/strict';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../../local-node/request-preparation-adapter.mjs';
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
    for (const source of sources) await source.close();
    if (initialization !== undefined) {
      if (initialization.services !== undefined) {
        assert.equal(retireInstalledSourceInitialization(initialization.services), true);
      }
      initialization.childrenPending = false;
      closeHostInitializationPreparation(initialization.state);
      initialization.active = false;
    }
    await dependentClose?.();
  });
  return {transportContext, sources,
    open({root, moon, installation, runtimeBundleCid, baseEnvironmentWire}) {
      assert.equal(initialization, undefined);
      // Retain before the actual fallible Resource/admission constructor.
      initialization = {state: {}, active: true, childrenPending: false};
      const current = () => {assert.equal(initialization.active, true);};
      const input = Object.freeze({root, original: 'installed Source component'});
      const parent = openHostInitializationPreparation(initialization.state, moon,
        input, current, () => initialization.childrenPending);
      const services = createInstalledHostServices({root, principalId: 'operator', moon,
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
            finishInstalledSourceInitialization(sourceInitialization, source, cause, true);
            throw cause;
          }
        },
      });
    },
  };
}
