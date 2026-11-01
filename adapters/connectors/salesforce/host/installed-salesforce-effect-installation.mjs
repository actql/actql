// Salesforce's Effect installation entries for the Host's installed connector
// table (`src/connectors/salesforce/host-bundle.json`, `effect`). They adapt
// the Salesforce Effect factory to the table's shape: the Host supplies the
// provider bundle, the runtime identity and its own Effect Ledger root.
import {checkInstalledSalesforceEffectProfile, loadInstalledSalesforceEffect,
  publishInstalledSalesforceEffect} from './installed-salesforce-effect.mjs';
import {retainInstalledRowEffectAdapter} from
  '../../../host-node/installed-row-effect.mjs';
import {readPublicationFile} from './salesforce-publication.mjs';

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
    await read(checked.siteProfilePath, {maxBytes: 8 * 1024 * 1024}),
    JSON.parse((await readPublicationFile(checked.publicationPath)).body),
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
  // The row owner accepts the Host's capture and recovery facts directly.
  // Preserve its original ports through this table projection so an installed
  // UPDATE target can bind the same private owner as the loaded factory.
  return retainInstalledRowEffectAdapter(effect,
    Object.freeze({environmentWire: effect.environmentWire,
      connectorBindings: effect.connectorBindings,
      effectSelectors: effect.effectSelectors,
      mappings: effect.mappings,
      connectorRegistration: effect.connectorRegistration,
      connectorRevision: effect.connectorRevision,
      targetReadInventory: effect.targetReadInventory,
      targetReadAuthorization: effect.targetReadAuthorization,
      prepareManagedPlan: effect.prepareManagedPlan,
      prepareCaptured: effect.prepareCaptured,
      prepareRecovered: effect.prepareRecovered,
      close: () => effect.close()}));
}
