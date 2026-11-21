import type {storeCompletedResultPublicationPayload} from './durable-result-payload.mjs';
import type {publishEffectFreeRun} from './run-publication.mjs';

type Options = Parameters<typeof publishEffectFreeRun>[0];
type Publication = Awaited<ReturnType<typeof publishEffectFreeRun>>;
type Cleanup = NonNullable<Publication['cleanupHandle']>;
type ResolveConfirmed = NonNullable<Cleanup['resolveConfirmed']>;
type RetireCapture = NonNullable<Options['control']['retireCapturedComputation']>;
type Assert<Value extends true> = Value;
type Require<Expected, Actual extends Expected> = Actual;

export type PublicationPortCases = [
  Require<ResolveConfirmed, (entry: undefined) => Promise<Readonly<{pending: boolean}>>>,
  Require<RetireCapture, (capture: Parameters<RetireCapture>[0]) => undefined>,
  Assert<(() => Promise<undefined>) extends RetireCapture ? false : true>,
  Assert<(() => PromiseLike<undefined>) extends RetireCapture ? false : true>,
];

type PublicationStore = Parameters<typeof storeCompletedResultPublicationPayload>[0];
type PreparedWriter = ReturnType<PublicationStore['createPreparedObjectWriter']>;
type PreparedSeal = Awaited<ReturnType<PreparedWriter['seal']>>;
type StoredPayload = Awaited<ReturnType<typeof storeCompletedResultPublicationPayload>>;
type OwnerWithoutCid = Omit<PreparedSeal['prepared'], 'cid'>;
type SealWithoutOwnerCid = Omit<PreparedSeal, 'prepared'> & Readonly<{prepared: OwnerWithoutCid}>;
type WriterWithoutOwnerCid = Omit<PreparedWriter, 'seal'> & Readonly<{seal(cid: string): Promise<SealWithoutOwnerCid>}>;
type StoreWithoutOwnerCid = Omit<PublicationStore, 'createPreparedObjectWriter'> &
  Readonly<{createPreparedObjectWriter(maxBytes: number): WriterWithoutOwnerCid}>;

export type PublicationWriterCases = [
  Require<StoredPayload['physicalPrepared'], PreparedSeal['prepared']>,
  Require<string, StoredPayload['physicalPrepared']['cid']>,
  Assert<StoreWithoutOwnerCid extends PublicationStore ? false : true>,
  Assert<OwnerWithoutCid extends StoredPayload['physicalPrepared'] ? false : true>,
];
