// Private standard Host assembly for finite provider-page Sources. Provider
// meaning stays in preparePageReader; this is the existing Site/reader/source
// lifetime, not a second reader, resource Owner or public author callback.
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import type {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';

type SiteInput = Readonly<{installation: unknown; sourceInitialization?: unknown} & Record<string, unknown>>;
type Site = NonNullable<Parameters<typeof retainInstalledHostInitializationFailure>[1]['sourceProfile']>;
type OpenedSite = Readonly<{site: Site}>;
type Implementation = Readonly<{capacity: unknown}>;
type Reader = ReturnType<typeof createInstalledCredentialSourceReader>;
type PreparePageReader = (...args: never[]) => Extract<SynchronousRuntimeData, object>;
type Services<Opened extends OpenedSite, PageReader extends PreparePageReader> = {
  (name: 'openRowSite', input: SiteInput): Opened | Promise<Opened>;
  (name: 'createSourceReader', input: Readonly<{installation: unknown; sourceInitialization: unknown;
    implementation: Implementation; site: Opened['site']; operation: string; preparePageReader: PageReader}>): Reader;
};

export async function installFinitePageSource<Opened extends OpenedSite, PageReader extends PreparePageReader, Result>(
  services: Services<Opened, PageReader>, siteInput: SiteInput, implementation: Implementation,
  operation: string, preparePageReader: PageReader, implementationMismatch: string,
  publish: (opened: Opened, reader: Reader) => Result | Promise<Result>) {
  const {installation, sourceInitialization} = siteInput;
  let opened: Opened | undefined, providerReader: Reader | undefined;
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
