import {lstat, mkdir, readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {cidPattern, exactKeys, fail, readBounded, retainStoreOpeningFailure} from './publication-store-io.mjs';
import {storeBootstrapAcquisition} from './publication-store-bootstrap.mjs';
import {acquireStoreOwnership} from './publication-store-ownership.mjs';

type StoreOwnership = Awaited<ReturnType<typeof acquireStoreOwnership>>;
type Observation = Readonly<{pending?: unknown}> | null | undefined;
type Observer = () => unknown;
type CleanupStatus = Readonly<{pending: boolean; adopted: boolean}>;
type PreparedOwnership = {
  root: string;
  fresh: boolean;
  ownership: StoreOwnership | undefined;
  phase: 'prepared' | 'adopting' | 'adopted' | 'closed';
  directoryBootstrap: ReturnType<typeof storeBootstrapAcquisition> | undefined;
  dependency: unknown;
  dependencyStatus: Observer | undefined;
  closing: boolean;
  releaseFlight: Promise<boolean> | undefined;
  cleanupFlight: Promise<CleanupStatus> | undefined;
  child: unknown;
  childStatus: Observer | undefined;
  childRetry: Observer | undefined;
  unknownChild: boolean;
  recoveryReady?: boolean;
};

// A prepared original is only the existing physical exclusion duty. It is
// neither a Store/capacity authority nor permission to initialize a format,
// create keys, publish, or repair an unknown prefix.
const preparedStoreOwnerships = new WeakMap<object, PreparedOwnership>();
export function originalPreparedStoreOwnership(original: unknown) {
  const entry = preparedStoreOwnerships.get(original as object);
  if (entry === undefined) fail('PublicationStoreOwnershipLost');
  return entry;
}
function preparedOwnershipStatus(entry: PreparedOwnership): CleanupStatus {
  return Object.freeze({pending: entry.ownership !== undefined || entry.child !== undefined,
    adopted: entry.phase === 'adopted'});
}
export async function releasePreparedOwnership(entry: PreparedOwnership) {
  if (entry.releaseFlight !== undefined) return entry.releaseFlight;
  if (entry.ownership === undefined) return true;
  entry.closing = true;
  entry.releaseFlight = Promise.resolve().then(async () => {
    // The selected Host may share this SAME exclusion with its Journal.
    // Payload cleanup must still run independently, but cannot release the
    // original owner while the retained Journal's physical close is pending.
    // This dependency only delays release; it issues no capacity/authority.
    if (entry.dependency !== undefined) {
      const observation = await Reflect.apply(entry.dependencyStatus!, entry.dependency, []);
      const pending = observation !== null && typeof observation === 'object'
        ? Object.getOwnPropertyDescriptor(observation, 'pending') : undefined;
      if (pending === undefined || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('PublicationStoreCleanupPending');
      }
      entry.dependency = entry.dependencyStatus = undefined;
    }
    if (await entry.ownership!.release() !== true) fail('PublicationStoreOwnershipLost');
    entry.ownership = undefined;
    entry.phase = 'closed';
    return true;
  }).finally(() => { entry.releaseFlight = undefined; });
  return entry.releaseFlight;
}
export function assertOriginalPreparedLocalPublicationStoreOwnership(original: unknown, directory: string) {
  const entry = originalPreparedStoreOwnership(original);
  if (entry.root !== resolve(directory) || entry.closing ||
      entry.ownership === undefined || !['prepared', 'adopting', 'adopted'].includes(entry.phase)) {
    fail('PublicationStoreOwnershipLost');
  }
}
// Private original custody only: no caller-provided owner or copied flag can
// issue a start receipt or turn a missing execution observation into a stop.
export function captureOriginalLocalExecutionOwner(original: unknown) {
  const entry = originalPreparedStoreOwnership(original);
  assertOriginalPreparedLocalPublicationStoreOwnership(original, entry.root);
  return entry.ownership!.executionReceipt();
}
export function originalLocalExecutionOwnerStopped(original: unknown, receipt: unknown) {
  const entry = originalPreparedStoreOwnership(original);
  assertOriginalPreparedLocalPublicationStoreOwnership(original, entry.root);
  return entry.recoveryReady === true && entry.ownership!.priorExecutionStopped(receipt as Parameters<StoreOwnership['priorExecutionStopped']>[0]);
}
// Only this actual prepared Owner can select first private-key setup. An
// absent key/path or caller flag cannot make an existing Store never-adopted.
export async function assertOriginalPreparedLocalPublicationStoreFirstInitialization(original: unknown, directory: string) {
  assertOriginalPreparedLocalPublicationStoreOwnership(original, directory);
  const entry = originalPreparedStoreOwnership(original);
  await entry.ownership!.assertCurrent();
  assertOriginalPreparedLocalPublicationStoreOwnership(original, directory);
  if (!entry.fresh || entry.phase !== 'prepared') {
    fail('PublicationStoreFirstInitializationUnavailable');
  }
}
export async function prepareLocalPublicationStoreOwnership(directory: unknown, bounds?: unknown,
  dependency?: unknown, directoryInspection?: unknown) {
  if (typeof directory !== 'string' || directory.length === 0) fail('InvalidPublicationStoreConfiguration');
  // Capture before any acquisition/callback. The actual Root supplies its
  // original close-only observation, never a replacement DB or public flag.
  const dependencyProperty = dependency !== null && typeof dependency === 'object'
    ? Object.getOwnPropertyDescriptor(dependency, 'status') : undefined;
  if (dependency !== undefined && (dependencyProperty === undefined ||
      !Object.hasOwn(dependencyProperty, 'value') || typeof dependencyProperty.value !== 'function')) {
    fail('InvalidPublicationStoreConfiguration');
  }
  const dependencyStatus: Observer | undefined = dependencyProperty?.value;
  const root = resolve(directory);
  if (bounds === undefined && directoryInspection !== undefined) {
    fail('InvalidPublicationStoreBootstrapBounds');
  }
  // Ordinary installed Hosts move this same exclusion before their Journal
  // without selecting a resource recipe or changing their existing intake.
  // Selected operational callers still supply their explicit finite bounds.
  const bootstrap = bounds === undefined ? Object.freeze({
    readDirectory: readdir, readMetadata: (path: string) => readBounded(path, 4096),
  }) : storeBootstrapAcquisition(bounds, 4096, directoryInspection);
  let names: readonly string[];
  try {
    const state = await lstat(root);
    if (!state.isDirectory() || state.isSymbolicLink()) fail('UnknownPublicationStoreFormat');
    names = await bootstrap.readDirectory(root);
  } catch (cause) {
    if ((cause as {code?: unknown} | null | undefined)?.code !== 'ENOENT') throw cause;
    await mkdir(root, {recursive: true, mode: 0o700});
    names = await bootstrap.readDirectory(root);
  }
  const fresh = names.length === 0;
  if (!fresh) {
    if (!names.includes('store.json')) fail('UnknownPublicationStoreFormat');
    const contract = JSON.parse(await bootstrap.readMetadata(resolve(root, 'store.json')) as unknown as string) as unknown;
    if (!exactKeys(contract, ['version', 'isolation', 'store_authority_cid']) ||
        contract.version !== 'actql-local-publication-store/0.1' ||
        contract.isolation !== 'execution-namespace' || !cidPattern.test(contract.store_authority_cid as string)) {
      fail('UnknownPublicationStoreFormat');
    }
  }
  const original: object = Object.freeze(Object.create(null));
  const entry: PreparedOwnership = {root, fresh, ownership: undefined, phase: 'prepared',
    directoryBootstrap: directoryInspection === undefined ? undefined : bootstrap,
    dependency, dependencyStatus,
    closing: false, releaseFlight: undefined, cleanupFlight: undefined,
    child: undefined, childStatus: undefined, childRetry: undefined, unknownChild: false};
  preparedStoreOwnerships.set(original, entry);
  entry.ownership = await acquireStoreOwnership(root, bootstrap, undefined, fresh, directoryInspection);
  try { await entry.ownership.assertCurrent(); }
  catch (cause) {
    entry.closing = true;
    throw await retainStoreOpeningFailure(cause,
      Object.freeze({release: () => releasePreparedOwnership(entry)}), undefined);
  }
  return original;
}
export function closePreparedLocalPublicationStoreOwnership(original: unknown) {
  const entry = originalPreparedStoreOwnership(original);
  entry.closing = true;
  if (entry.cleanupFlight !== undefined) return entry.cleanupFlight;
  entry.cleanupFlight = Promise.resolve().then(async () => {
    if (entry.unknownChild) return preparedOwnershipStatus(entry);
    if (entry.child !== undefined) {
      let state = await Reflect.apply(entry.childStatus!, entry.child, []) as Observation;
      if (state?.pending !== false) state = await Reflect.apply(entry.childRetry!, entry.child, []) as Observation;
      if (state?.pending !== false) return preparedOwnershipStatus(entry);
      entry.child = entry.childStatus = entry.childRetry = undefined;
    }
    // A live/adopting Store owns its children and the same original release.
    // Parent close cannot certify or interrupt that Store's physical work.
    if (entry.phase !== 'adopted' && entry.phase !== 'adopting') {
      await releasePreparedOwnership(entry);
    }
    return preparedOwnershipStatus(entry);
  }).finally(() => { entry.cleanupFlight = undefined; });
  return entry.cleanupFlight;
}
