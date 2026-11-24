import {createHash} from 'node:crypto';
import {lstat} from 'node:fs/promises';
import {exactKeys, fail, readBounded, retainStoreOpeningFailure, writeExclusive} from './publication-store-io.mjs';
import type {originalPreparedStoreOwnership} from './prepared-publication-store-ownership.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';

type PreparedOwnership = ReturnType<typeof originalPreparedStoreOwnership>;
type OpeningDirectory = (path: string) => Promise<readonly string[]>;
type OpeningMetadata = (path: string) => Promise<Buffer>;
type OpeningStoreFormat = Readonly<{version: string; isolation: string}>;
type KeyConfiguration = Pick<ReturnType<typeof validateConfiguration>, 'privateEvidenceKey'>;
type OpeningFailureFields = {
  code?: unknown;
  cleanupHandle?: unknown;
  cleanupPending?: boolean;
  cleanupError?: unknown;
  primaryFailure?: unknown;
};
type OpeningCause = Readonly<OpeningFailureFields> | null | undefined;

export async function admitExistingStoreFormat(root: string, storeContractPath: string,
  storeContract: OpeningStoreFormat, storeContractBytes: Buffer, prepared: PreparedOwnership | undefined,
  readOpeningDirectory: OpeningDirectory, readOpeningMetadata: OpeningMetadata) {
  let existingNames: readonly string[] | undefined;
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) {
      fail('UnknownPublicationStoreFormat');
    }
    existingNames = await readOpeningDirectory(root);
  } catch (error) {
    if ((error as OpeningCause)?.code !== 'ENOENT') throw error;
  }
  // Only the same still-held original may explain this exact fresh prefix.
  // Ordinary opens and cold owner-only directories retain their old refusal.
  const preparedFreshPrefix = prepared !== undefined && prepared.fresh &&
    prepared.phase === 'adopting' && prepared.ownership !== undefined &&
    existingNames?.length === 1 && existingNames[0] === 'owner';
  if ((existingNames?.length as number) > 0 && !preparedFreshPrefix) {
    if (!existingNames!.includes('store.json')) {
      const legacy = existingNames!.some(name => [
        'objects', 'contracts', 'indexes', 'staging', 'owner',
      ].includes(name));
      throw Object.assign(new Error(legacy ?
        'LegacyPublicationStoreFormat' : 'UnknownPublicationStoreFormat'), {
        code: legacy ? 'LegacyPublicationStoreFormat' :
          'UnknownPublicationStoreFormat', target: root,
      });
    }
    let previous: Readonly<{
      version?: unknown; isolation?: unknown; store_authority_cid?: unknown;
    }> | null;
    try {
      previous = JSON.parse(await readOpeningMetadata(storeContractPath) as unknown as string);
    } catch (cause) {
      const failure: Error & OpeningFailureFields = Object.assign(new Error('UnknownPublicationStoreFormat',
        {cause}), {code: 'UnknownPublicationStoreFormat', target: root});
      // This reader precedes Store ownership. The same original failed FD
      // must remain visible to installed initialization cleanup; wrapping a
      // format refusal must not make that cleanup appear complete.
      if ((cause as OpeningCause)?.cleanupHandle !== undefined) {
        failure.cleanupHandle = (cause as OpeningCause)!.cleanupHandle;
        failure.cleanupPending = true;
        failure.cleanupError = (cause as OpeningCause)!.cleanupError;
        failure.primaryFailure = (cause as OpeningCause)!.primaryFailure ?? cause;
      }
      throw failure;
    }
    if (previous?.version === storeContract.version &&
        previous?.isolation === undefined &&
        typeof previous?.store_authority_cid === 'string') {
      throw Object.assign(new Error('LegacyPublicationStoreFormat'), {
        code: 'LegacyPublicationStoreFormat', target: root});
    }
    if (!exactKeys(previous, ['version', 'isolation',
      'store_authority_cid'] as const) ||
        previous.version !== storeContract.version ||
        previous.isolation !== storeContract.isolation) {
      throw Object.assign(new Error('UnknownPublicationStoreFormat'), {
        code: 'UnknownPublicationStoreFormat', target: root});
    }
    if (!Buffer.from(JSON.stringify(previous), 'utf8')
      .equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
  }
}

export async function createStoreContract(root: string, storeContractPath: string, storeContractBytes: Buffer,
  configuration: KeyConfiguration, readOpeningMetadata: OpeningMetadata, syncDirectory: (path: string) => unknown) {
  let createdStore = false;
  try {
    await writeExclusive(storeContractPath, storeContractBytes);
    await syncDirectory(root);
    createdStore = true;
  } catch (error) {
    if ((error as OpeningCause)?.cleanupHandle !== undefined) {
      throw await retainStoreOpeningFailure(error, undefined, configuration.privateEvidenceKey);
    }
    if ((error as OpeningCause)?.code !== 'EEXIST') throw error;
    const existing = await readOpeningMetadata(storeContractPath);
    if (!existing.equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
  }
  return createdStore;
}

type ModelEvidenceFields = Readonly<{identity: string; wire: string}>;
type ModelStorageBindingHandle<Evidence extends ModelEvidenceFields> = Readonly<{
  kind: 'model-original-storage-binding'; identity: Evidence['identity']; wire: Evidence['wire'];
}>;
type InstallationStorageBinding = Readonly<{
  handle: Readonly<{kind: 'installation-publication-storage-binding'}>;
  evidence: Readonly<{storeContractWire: string; storeAuthorityCid: string; keyGenerationCid: string;
    privateNamespace: 'publication-private'}>;
}>;
type ModelEvidenceIssuer<Evidence extends ModelEvidenceFields> = Readonly<{
  sealRunEvidence(name: 'model_original_storage_binding', wire: string,
    limits: Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>): Evidence;
}>;

export function createOriginalStoreStorageBindings<Evidence extends ModelEvidenceFields>(
  configuration: Readonly<{storeAuthorityCid: string; directory: string}>,
  storeContractPath: string, storeContractBytes: Buffer, contractControl: ModelEvidenceIssuer<Evidence>,
  active: () => unknown, privateEvidenceKey: () => Uint8Array,
) {
  // One bounded semantic view per actual Store admission. The escaped handle
  // carries no key/path and must be presented to this same live Store owner.
  let originalModelStorageBinding: Readonly<{evidence: Evidence; handle: ModelStorageBindingHandle<Evidence>}> | undefined;
  // This existing Store's original binding readers stay owned during read and
  // failed-close cleanup. Count/callback/error/control holding is not a new
  // physical byte allowance, and must be included in the installed envelope.
  let originalModelStorageBindingReaders = 0;
  const observeOriginalModelStorageBinding = async () => {
    active();
    if (originalModelStorageBindingReaders !== 0) {
      fail('PublicationStoreCleanupPending');
    }
    originalModelStorageBindingReaders++;
    const bytes = await readBounded(storeContractPath, 256, () => {
      originalModelStorageBindingReaders--;
    });
    const current: unknown = JSON.parse(bytes as unknown as string);
    active();
    if (!exactKeys(current, ['version', 'isolation', 'store_authority_cid']) ||
        !Buffer.from(JSON.stringify(current), 'utf8').equals(storeContractBytes)) {
      fail('PublicationStoreAuthorityMismatch');
    }
    if (originalModelStorageBinding === undefined) {
      const evidence = contractControl.sealRunEvidence('model_original_storage_binding',
        JSON.stringify({version: 'actql-model-original-storage-binding/0.1',
          store_contract_wire: storeContractBytes.toString('utf8'),
          store_contract_cid: `sha256:${createHash('sha256').update(storeContractBytes).digest('hex')}`,
          store_authority_cid: configuration.storeAuthorityCid,
          key_generation_cid: `sha256:${createHash('sha256').update(privateEvidenceKey()).digest('hex')}`,
          private_namespace: 'local-continuation-private'}),
        {maxWireBytes: 2048, maxNodes: 32, maxDepth: 2});
      originalModelStorageBinding = {evidence, handle: Object.freeze({
        kind: 'model-original-storage-binding', identity: evidence.identity,
        wire: evidence.wire})};
    }
    return originalModelStorageBinding.handle;
  };

  // Read-only original Store observation for the separate installation
  // publication Owner. This is not Model RunEvidence or a semantic issuer.
  // A caller must fund the read/hash/control overlap and independently admit
  // its publication, installation and generation before using these DATA.
  let originalInstallationPublicationStorageBinding: InstallationStorageBinding | undefined;
  let originalInstallationPublicationStorageBindingReaders = 0;
  const observeOriginalInstallationPublicationStorageBinding = async () => {
    active();
    if (originalInstallationPublicationStorageBindingReaders !== 0) {
      fail('PublicationStoreCleanupPending');
    }
    originalInstallationPublicationStorageBindingReaders++;
    const bytes = await readBounded(storeContractPath, 256, () => {
      originalInstallationPublicationStorageBindingReaders--;
    });
    active();
    // Preserve the exact immutable original contract wire, not a parsed and
    // reserialized replacement. readBounded retains its same FD on failed close.
    if (!bytes.equals(storeContractBytes)) fail('PublicationStoreAuthorityMismatch');
    if (originalInstallationPublicationStorageBinding === undefined) {
      const evidence = Object.freeze({
        storeContractWire: storeContractBytes.toString('utf8'),
        storeAuthorityCid: configuration.storeAuthorityCid,
        keyGenerationCid: `sha256:${createHash('sha256').update(privateEvidenceKey()).digest('hex')}`,
        privateNamespace: 'publication-private',
      });
      originalInstallationPublicationStorageBinding = {evidence,
        handle: Object.freeze({kind: 'installation-publication-storage-binding'})};
    }
    return originalInstallationPublicationStorageBinding.handle;
  };

  return {
    observeOriginalInstallationPublicationStorageBinding,
    originalInstallationPublicationStorageBindingEvidence(handle: unknown) {
      active();
      if (originalInstallationPublicationStorageBinding === undefined ||
          handle !== originalInstallationPublicationStorageBinding.handle) {
        fail('ForeignOriginalInstallationPublicationStorageBinding');
      }
      return originalInstallationPublicationStorageBinding.evidence;
    },
    observeOriginalModelStorageBinding,
    originalModelStorageBindingEvidence(handle: unknown) {
      active();
      if (originalModelStorageBinding === undefined ||
          handle !== originalModelStorageBinding.handle) {
        fail('ForeignOriginalModelStorageBinding');
      }
      return originalModelStorageBinding.evidence;
    },
    // Private Host DATA from this exact Store, not caller-supplied profile
    // dimensions or authenticated storage evidence. The original installation
    // must bind the receiver and fund this record, UTF-8 scan workspace and
    // all derived paths/encodings before using it in an envelope. No path or
    // key bytes escape, and no I/O, reservation, ACK or permission is issued.
    originalModelStorageDimensions() {
      active();
      const key = privateEvidenceKey();
      const namespace = 'local-continuation-private';
      return Object.freeze({
        directoryCodeUnits: configuration.directory.length,
        directoryUtf8Bytes: Buffer.byteLength(configuration.directory, 'utf8'),
        privateNamespaceCodeUnits: namespace.length,
        privateNamespaceUtf8Bytes: Buffer.byteLength(namespace, 'utf8'),
        privateKeyBytes: key.byteLength,
      });
    },
    get modelStorageBindingReaders() { return originalModelStorageBindingReaders; },
    get installationPublicationStorageBindingReaders() { return originalInstallationPublicationStorageBindingReaders; },
    clearInstallationPublicationStorageBinding() { originalInstallationPublicationStorageBinding = undefined; },
  };
}
