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
