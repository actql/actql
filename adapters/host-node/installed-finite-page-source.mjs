// Private standard Host assembly for finite provider-page Sources. Provider
// meaning stays in preparePageReader; this is the existing Site/reader/source
// lifetime, not a second reader, resource Owner or public author callback.
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';

export async function installFinitePageSource(services, siteInput, implementation,
  operation, preparePageReader, implementationMismatch, publish) {
  const {installation, sourceInitialization} = siteInput;
  let opened, providerReader;
  try {
    // Reuse the original call record; do not copy the profile/credential DATA
    // into a second retained assembly record or construct another capacity.
    opened = await services('openRowSite', siteInput);
    providerReader = services('createSourceReader', {installation, sourceInitialization,
      implementation, site: opened.site, operation, preparePageReader});
    if (providerReader.capacity !== implementation.capacity) {
      throw Object.assign(new Error(implementationMismatch), {code: implementationMismatch});
    }
    // Only the trusted installed Host supplies this continuation. It binds
    // the original declaration/target/context to createInstalledRowSource;
    // the provider's pure page ports never receive these physical originals.
    return await publish(opened, providerReader);
  } catch (cause) {
    // Retain the returned reader before its capacity getter or publication can
    // fail. An openRowSite failure retains its own partial child in cause.
    throw await retainInstalledHostInitializationFailure(cause,
      {sourceReader: providerReader, sourceProfile: opened?.site});
  }
}
