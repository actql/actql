// The installing Source owner already owns these three inventories. Keep
// the same initialization borrow until its original synchronous return.
import {types} from 'node:util';

type Callback = () => unknown;
type Then = (resolve: (value: unknown) => void, reject: (cause: unknown) => void) => unknown;
type Thenable = Readonly<{then?: unknown}> | null | undefined;
type Material = {
  view: unknown; environment?: Callback; release?: Callback; originalEnvironment?: unknown;
  computation?: unknown; pending: boolean; failure?: unknown;
};
export type SourceProducerCustody = {
  receipt: object; request?: object; finished: boolean; liveRuns: number;
  preparation?: unknown; sourceInitialization?: Material; snapshotPublication?: unknown;
};
type Ports<Original, Producer extends SourceProducerCustody> = Readonly<{
  originals: Original; callbacks: object; borrowSourceInitialization?: (originals: Original) => unknown;
  receipts: Pick<WeakMap<object, Producer>, 'get'>; producers: Set<Producer>;
  requestProducers: Pick<WeakMap<object, WeakRef<Producer>>, 'get'>;
  closing: boolean; closed: boolean; fail(code: string): never;
}>;

export function createOrdinarySourceProducerCustody<Original, Producer extends SourceProducerCustody>(ports: Ports<Original, Producer>) {
  const {originals, callbacks, borrowSourceInitialization, receipts, producers, requestProducers, fail} = ports;
  function captureSourceMaterialMethod(record: Material, name: 'release' | 'environment'): Callback {
    const field = Object.getOwnPropertyDescriptor(record.view!, name);
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
      fail('InstalledSourceInitializationMethodUnavailable');
    }
    return field!.value;
  }
  function joinSourceMaterialComputation(record: Material, value: unknown) {
    // Unexpected async protocol results remain in this SAME producer inventory.
    // Their settlement permits another original return, never acknowledges it.
    record.computation = value;
    const native = types.isPromise(value), then = native ? undefined : (value as Thenable)?.then;
    if (!native && typeof then !== 'function') return;
    record.pending = true;
    const settled = () => {record.pending = false;record.computation = undefined;};
    const rejected = (cause: unknown) => {record.failure ??= cause;settled();};
    if (native) {
      Reflect.apply(Promise.prototype.then,value,[settled,rejected]);
      void value.then;
    } else {
      const pending = new Promise((resolve,reject) => Reflect.apply(then as Then,value,[resolve,reject]));
      void pending.then(settled,rejected);
    }
  }
  function retainSourceInitializationMaterial(producer: Producer) {
    if (ports.closing || ports.closed || producer.finished || receipts.get(producer.receipt) !== producer ||
        producer.sourceInitialization !== undefined) fail('ForeignInstalledSourceProducer');
    if (borrowSourceInitialization === undefined) return undefined;
    try {
      if (typeof borrowSourceInitialization !== 'function') fail('InstalledSourceInitializationUnavailable');
      const view = Reflect.apply(borrowSourceInitialization,callbacks,[originals]);
      if (view === undefined) return undefined; // This original Host has no Source material.
      const record: Material = {view, environment:undefined, release:undefined, originalEnvironment:undefined,
        computation:undefined, pending:false, failure:undefined};
      producer.sourceInitialization = record; // Retain before any fallible observation.
      record.release = captureSourceMaterialMethod(record,'release');
      record.environment = captureSourceMaterialMethod(record,'environment');
      const environment = Reflect.apply(record.environment,record.view,[]);
      if (types.isPromise(environment) || typeof (environment as Thenable)?.then === 'function') {
        joinSourceMaterialComputation(record,environment);
        fail('InstalledSourceInitializationNotSynchronous');
      }
      if (environment === undefined) fail('InstalledSourceInitializationUnavailable');
      if (ports.closing || ports.closed || producer.finished || receipts.get(producer.receipt) !== producer) {
        fail('ForeignInstalledSourceProducer');
      }
      record.originalEnvironment = environment;
      return environment;
    } catch (cause) {
      // The SDK may never receive its receipt. Existing close still owns this
      // same unreturned producer and its original Source material borrow.
      producer.finished = true;
      throw cause;
    }
  }
  function returnSourceInitializationMaterial(producer: Producer) {
    const record = producer.sourceInitialization;
    if (record === undefined) return true;
    if (record.pending) return false;
    record.release ??= captureSourceMaterialMethod(record,'release');
    const returned = Reflect.apply(record.release,record.view,[]);
    // Both Bool values acknowledge this borrow's return. False only says the
    // parent itself is still live; neither value is a Source/Run/physical ACK.
    if (typeof returned !== 'boolean') {
      joinSourceMaterialComputation(record,returned);
      fail('InstalledSourceInitializationNotSynchronous');
    }
    record.view = record.release = record.environment = record.originalEnvironment = record.computation = undefined;
    producer.sourceInitialization = undefined;
    return true;
  }
  const releaseFinishedProducer = (producer: Producer) => {
    if (producer.finished && producer.liveRuns === 0) {
      // Retain a failed return even after its last original Run left liveRuns.
      producers.add(producer);
      if (producer.preparation !== undefined || !returnSourceInitializationMaterial(producer)) return false;
      producer.request = undefined;
      producer.snapshotPublication = undefined;
      producers.delete(producer);
      return true;
    }
    return false;
  };
  const producerForRequest = (request: object) => {
    const producer = requestProducers.get(request)?.deref();
    return !ports.closing && !ports.closed && producer !== undefined && producers.has(producer) &&
      receipts.get(producer.receipt) === producer && producer.request === request &&
      !producer.finished ? producer : undefined;
  };
  return {retainSourceInitializationMaterial, releaseFinishedProducer, producerForRequest};
}
