// Salesforce's Effect installation entries for the Host's installed connector
// table (`src/connectors/salesforce/host-bundle.json`, `effect`). They adapt
// the Salesforce Effect factory to the table's shape: the Host supplies the
// provider bundle, the runtime identity and its own Effect Ledger root.
import {checkInstalledSalesforceEffectProfile, loadInstalledSalesforceEffect,
  publishInstalledSalesforceEffect} from './installed-salesforce-effect.mjs';
import {retainInstalledRowEffectAdapter} from
  '../../../host-node/installed-row-effect.mjs';
import {readPublicationFile} from './salesforce-publication.mjs';
import {captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';

type Profile = Parameters<typeof checkInstalledSalesforceEffectProfile>[0];
type Read = (path: string, options: Readonly<{maxBytes: number}>) => unknown;
type Readers = Readonly<{readText: NonNullable<Parameters<typeof readPublicationFile>[1]>;
  parseJsonText?: (text: string) => unknown}>;
type ProviderOptions<Options extends {salesforceMoon: unknown}> = Omit<Options, 'salesforceMoon'> &
  Readonly<{providerMoon: Options['salesforceMoon']}>;
type Publication = ProviderOptions<Parameters<typeof publishInstalledSalesforceEffect>[1]>;
type Install = ProviderOptions<Parameters<typeof loadInstalledSalesforceEffect>[1]>;

export function checkInstalledSalesforceEffectInstallation(profile: Profile) {
  return checkInstalledSalesforceEffectProfile(profile);
}

// The parts of this installation's identity: the Host profile with its
// account configuration as a document, the installed Site profile and the
// published generation, exactly as before the table existed.
export async function installedSalesforceEffectIdentityParts(profile: Profile & Readonly<{accountConfigurationWire: string}>,
  read: Read, _entry: unknown, {configurationReader}: Readonly<{configurationReader?: unknown}> = {}) {
  const checked = checkInstalledSalesforceEffectProfile(profile);
  const readers = captureConfigurationReaders(configurationReader, read,
    () => {throw new TypeError('InstalledConfigurationReaderUnavailable');}) as Readers;
  const publication = await readPublicationFile(checked.publicationPath, readers.readText);
  return [
    {...profile, accountConfigurationWire: JSON.parse(
      profile.accountConfigurationWire)},
    await read(checked.siteProfilePath, {maxBytes: 8 * 1024 * 1024}),
    (readers.parseJsonText ?? JSON.parse)(publication.body),
  ];
}

export function publishInstalledSalesforceEffectInstallation(checked: Profile,
  {providerMoon, ...options}: Publication) {
  return publishInstalledSalesforceEffect(checked,
    {...options, salesforceMoon: providerMoon});
}

export async function loadInstalledSalesforceEffectInstallation(checked: Profile,
  {providerMoon, ...options}: Install) {
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
      close: effect.close}));
}
