// Installed Store wiring, separate from operator settings or completion evidence.
// Pure factories construct a lease; I/O starts only through that lease after the
// exact Local attempt has installed its retention-release predicate.
import type {LocalRetainedStore} from '../store-local/files.mjs';
import type {SynchronousMemoryAction} from '../store-local/managed-memory-representations.mjs';
import type {registerRetainedInput} from '../store-local/representations.mjs';

type FileWriter = ReturnType<LocalRetainedStore['reserve']>;
type StoreStatus = Pick<ReturnType<LocalRetainedStore['status']>, 'reservedBytes' | 'cleanupPending'> &
  Partial<Pick<ReturnType<LocalRetainedStore['status']>, 'admittedWriteBytes'>>;
export type LeasedOutputBody = Parameters<typeof registerRetainedInput>[2] &
  Readonly<{cid: string; bytes: number; available(): boolean; close: SynchronousMemoryAction}>;
type StoreWriter = Pick<FileWriter, 'start' | 'append'> &
  Readonly<{seal(identity: Parameters<FileWriter['seal']>[0]): PromiseLike<LeasedOutputBody>}>;
export type LocalStoreLease = Readonly<{
  status(): StoreStatus;
  reserve(bytes: number): StoreWriter;
  close: SynchronousMemoryAction;
  cleanup(): unknown;
  release?(): PromiseLike<{pending: boolean}>;
}>;
export type LocalStoreLeaseFactory = (key: string, capacityBytes: number, maxFrameBytes: number,
  signal?: AbortSignal) => LocalStoreLease | PromiseLike<LocalStoreLease>;
type OutputFaultEvent =
  [kind: 'local_retained_output_appended', facts: Readonly<{admittedWriteBytes: number | undefined; reservedBytes: number}>] |
  [kind: 'local_retained_output_sealed', facts: Readonly<{sealedBytes: number; reservedBytes: number}>];
export type LocalOutputFault = (...event: OutputFaultEvent) => unknown;
type LocalFaultInjection = (...event: OutputFaultEvent |
  [kind: 'local_compute_advanced', facts: Readonly<{task: number | undefined; progress: string; work: string}>]) => unknown;
type PauseBoundary = Readonly<{task: number | undefined; status: 'waiting' | 'settling'; slot?: number; signal: AbortSignal | undefined}>;
type PauseHandler = (boundary: PauseBoundary) => unknown;
type BeforePrepare = (task: number, physicalSource: unknown) => unknown;
type InstalledConfiguration = Readonly<{
  retained?: LocalStoreLeaseFactory;
  snapshot?: LocalStoreLeaseFactory;
  faultInjection?: LocalFaultInjection;
  handlePause?: PauseHandler;
  beforePrepare?: BeforePrepare;
}>;

const configurations = new WeakMap<object, InstalledConfiguration>();
export function installLocalRetainedStore(createLease: LocalStoreLeaseFactory, faultInjection?: LocalFaultInjection) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  if (faultInjection !== undefined && typeof faultInjection !== 'function') {
    throw new TypeError('InvalidLocalFaultInjection');
  }
  const configuration = Object.freeze({});
  configurations.set(configuration, {retained:createLease,snapshot:createLease,
    faultInjection});
  return configuration;
}
// An installed Host can persist a Carrier without switching its Relation
// tasks to file output. Both routes still use the existing physical Store.
export function installLocalSnapshotStore(createLease: LocalStoreLeaseFactory, faultInjection?: LocalFaultInjection) {
  if (typeof createLease !== 'function') throw new TypeError('MissingLocalStore');
  if (faultInjection !== undefined && typeof faultInjection !== 'function') {
    throw new TypeError('InvalidLocalFaultInjection');
  }
  const configuration = Object.freeze({});
  configurations.set(configuration, {snapshot:createLease,faultInjection});
  return configuration;
}
export function localRetainedStore(configuration: object | undefined) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.retained;
}
export function localSnapshotStore(configuration: object | undefined) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.snapshot;
}
export function localComputeFaultInjection(configuration: object | undefined) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (!installed) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.faultInjection;
}

// A per-invocation Host callback resumes the SAME Local driver only after
// current authority or Store custody is ready. Existing Store configuration
// remains immutable and can be shared by other runs.
export function withLocalExecutionPauseHandler(configuration: object | undefined, handlePause: PauseHandler,
  beforePrepare?: BeforePrepare) {
  if (typeof handlePause !== 'function') {
    throw new TypeError('InvalidLocalExecutionPauseHandler');
  }
  if (beforePrepare !== undefined && typeof beforePrepare !== 'function') throw new TypeError('InvalidLocalBeforePrepare');
  const installed = configuration === undefined ? {} : configurations.get(configuration);
  if (installed === undefined) throw new TypeError('InvalidLocalStoreConfiguration');
  const derived = Object.freeze({});
  configurations.set(derived, {...installed, handlePause, beforePrepare});
  return derived;
}
export function localExecutionPauseHandler(configuration: object | undefined) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (installed === undefined) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.handlePause;
}

// Same per-invocation Local configuration; no public task or authority issuer.
export function localExecutionBeforePrepare(configuration: object | undefined) {
  if (configuration === undefined) return undefined;
  const installed = configurations.get(configuration);
  if (installed === undefined) throw new TypeError('InvalidLocalStoreConfiguration');
  return installed.beforePrepare;
}
