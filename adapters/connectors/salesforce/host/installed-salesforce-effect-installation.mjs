// Salesforce's Effect installation entries for the Host's installed connector
// table (`src/connectors/salesforce/host-bundle.json`, `effect`). They adapt
// the Salesforce Effect factory to the table's shape: the Host supplies the
// provider bundle, the runtime identity and its own Effect Ledger root.
import {checkInstalledSalesforceEffectProfile, loadInstalledSalesforceEffect,
  publishInstalledSalesforceEffect} from './installed-salesforce-effect.mjs';
import {salesforceEffectSiteHooks} from './installed-salesforce-effect-hooks.mjs';

export function checkInstalledSalesforceEffectInstallation(profile) {
  return checkInstalledSalesforceEffectProfile(profile);
}

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the installed Site profile and the
// published generation, exactly as before the table existed.
export async function installedSalesforceEffectIdentityParts(profile, read) {
  const checked = checkInstalledSalesforceEffectProfile(profile);
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await read(checked.siteProfilePath),
    await read(checked.publicationPath),
  ];
}

export function publishInstalledSalesforceEffectInstallation(checked,
  {providerMoon, ...options}) {
  return publishInstalledSalesforceEffect(checked,
    {...options, salesforceMoon: providerMoon});
}

export async function loadInstalledSalesforceEffectInstallation(checked,
  {providerMoon, ...options}) {
  const effect = await loadInstalledSalesforceEffect(checked,
    {...options, salesforceMoon: providerMoon});
  const hooks = salesforceEffectSiteHooks(effect);
  return Object.freeze({environmentWire: effect.environmentWire,
    connectorBindings: effect.connectorBindings,
    connectorRegistration: effect.connectorRegistration,
    connectorRevision: effect.connectorRevision,
    prepareCaptured: hooks.prepareCaptured,
    prepareRecovered: hooks.prepareRecovered,
    close: () => effect.close()});
}
