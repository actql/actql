import {lstat} from 'node:fs/promises';
import {exactKeys, fail, retainStoreOpeningFailure, writeExclusive} from './publication-store-io.mjs';
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
