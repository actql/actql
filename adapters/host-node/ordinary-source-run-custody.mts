// One retained ordinary Source Run belongs to its exact Request producer.
// The existing Resource runtime owns capacity, currentness and physical stop.
import resourceRuntime from './ordinary-node-resource-runtime.cjs';

import type {SourceReaderChild} from './ordinary-source-reader.mjs';
import type {SourceProducerCustody} from './ordinary-source-producer-custody.mjs';

type Requirements = Parameters<typeof resourceRuntime.retainOrdinaryManagedRun>[1];
type Purpose = NonNullable<Parameters<typeof resourceRuntime.retainOrdinaryManagedRun>[4]>;
type Preparation = Readonly<{adopting?: boolean; prepared?: unknown; original?: unknown}>;
type Producer = SourceProducerCustody & {preparation?: Preparation};
export type OrdinarySourceRun = {
  prepared?: object; request?: object; producer?: Producer; purpose: Purpose;
  original?: object; operationPlan?: object; value?: unknown;
  required?: Requirements; effectful: boolean; model?: unknown; content?: unknown;
  children: SourceReaderChild[]; fileIdentity?: readonly bigint[];
};
type Run = OrdinarySourceRun;
type RetainedRun = Run & {prepared: object; producer: Producer};
type Ports = Readonly<{
  originals: unknown;
  callbacks: Readonly<{retainedValidator(originals: unknown): void; request(originals: unknown, prepared: object): object;
    requirements(originals: unknown, prepared: object): Requirements}>;
  runs: WeakMap<object, Run>; liveRuns: Set<Run>; receipts: Pick<WeakMap<object, Producer>, 'get'>;
  retiredRuns: Pick<WeakMap<object, object>, 'has'>; pendingRunRegistrations: Set<object>;
  producerForRequest(request: object): Producer | undefined;
  current(): void; fail(code: string): never; closed: boolean;
}>;

export function createOrdinarySourceRunCustody(ports: Ports) {
  const {originals, callbacks, runs, liveRuns, receipts, retiredRuns, pendingRunRegistrations,
    producerForRequest, current, fail} = ports;
  function retainedRunCurrent(run: Run | undefined): asserts run is RetainedRun {
    const producer = run?.producer, state = producer?.preparation;
    if (ports.closed || run === undefined || runs.get(run.prepared!) !== run ||
        !liveRuns.has(run) || state === undefined || !state.adopting ||
        state.prepared !== run.prepared || state.original !== run.original ||
        receipts.get(producer!.receipt) !== producer || run.value === undefined) {
      fail('ForeignInstalledSourceProducer');
    }
    callbacks.retainedValidator(originals);
    // Keep exact custody across the currentness callback's possible reentry.
    if (ports.closed || runs.get(run!.prepared!) !== run || !liveRuns.has(run!) ||
        producer!.preparation !== state || state!.original !== run!.original) {
      fail('ForeignInstalledSourceProducer');
    }
  }
  function publicationRunFor(prepared: object) {
    const run = runs.get(prepared);
    retainedRunCurrent(run);
    resourceRuntime.assertOrdinaryManagedRunCurrent(run.original!, run.producer.receipt);
    return run;
  }
  function runFor(prepared: object) {
    current();
    const run = runs.get(prepared);
    if (run === undefined) fail('NodeManagedRunAdmissionUnavailable');
    resourceRuntime.assertOrdinaryManagedRunCurrent(run!.original!, (run!.producer!.preparation === undefined ? run!.operationPlan ?? prepared : run!.producer!.receipt));
    return run;
  }
  function prepareRun(prepared: object, purpose: Purpose, model: unknown, content: unknown) {
    current();
    if (retiredRuns.has(prepared)) fail('ForeignInstalledModelPreparation');
    const old = runs.get(prepared);
    if (old !== undefined) {
      if (old.purpose !== purpose || old.model !== model || old.effectful !== false || old.content !== content || old.operationPlan !== undefined) {
        fail('ForeignInstalledModelPreparation');
      }
      return runFor(prepared)!.original;
    }
    const request = callbacks.request(originals, prepared);
    const producer = producerForRequest(request);
    if (producer === undefined || pendingRunRegistrations.has(prepared) ||
        liveRuns.size + pendingRunRegistrations.size >= 4096) fail('ForeignInstalledSourceProducer');
    const run: Run = {prepared, request, producer, purpose, model, effectful: false, content, operationPlan: undefined, original: undefined,
      children: [], fileIdentity: undefined};
    if (producer!.liveRuns === Number.MAX_SAFE_INTEGER) fail('InstalledSourceProducerLimit');
    producer!.liveRuns++;
    runs.set(prepared, run);
    liveRuns.add(run);
    // A failed quote remains attached to this one preparation. It cannot be
    // retried under a different purpose or replaced by another original.
    const required = callbacks.requirements(originals, prepared);
    run.required = required;
    const producerReceipt = producer!.receipt;
    const requestOriginals = new WeakSet<object>();
    requestOriginals.add(request);
    run.original = resourceRuntime.retainOrdinaryManagedRun(prepared, required,
      () => {
        current();
        if (run.producer!.receipt !== producerReceipt ||
            !requestOriginals.has(run.producer!.request!)) fail('ForeignInstalledSourceProducer');
      },
      () => run.children.some(child => child.flight !== undefined || !child.closed), purpose);
    return run.original;
  }
  return {retainedRunCurrent, publicationRunFor, runFor, prepareRun};
}
