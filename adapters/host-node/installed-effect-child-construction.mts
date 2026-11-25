import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {rejectInstalledEffectPlan as fail} from './installed-effect-recipe.mjs';

const NativePromise = Promise;
const nativePromiseThen = Promise.prototype.then;
export {NativePromise, nativePromiseThen};

type CoreResult = Extract<SynchronousRuntimeData, object>;
type Runtime = Readonly<{
  clientProgramInstalledEffectOperationConstructionRetain(parent: unknown, prepared: unknown,
    request: unknown, plan: unknown, memberIndex: number, perRow: boolean, operationIndex: number,
    rowIndex: number, operation: string): CoreResult;
  clientProgramInstalledEffectOperationConstructionBegin(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationConstructionComplete(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationConstructionCompleteOutput?(token: unknown, wire: string): CoreResult;
  clientProgramInstalledEffectOperationInputBegin?(token: unknown, extent: unknown): CoreResult;
  clientProgramInstalledEffectOperationInputGrow?(token: unknown, extent: unknown): CoreResult;
  clientProgramInstalledEffectOperationRetire(token: unknown, cleanupConfirmed: boolean): CoreResult;
}>;
type Run = Readonly<{
  runtime: Runtime;
  value: unknown;
  prepared: unknown;
  request: unknown;
  operationPlan: unknown;
  readPlan(parent: unknown, prepared: unknown, request: unknown): CoreResult;
  closed?: boolean;
  failure?: unknown;
}>;
type Grow = (extent: unknown) => undefined;
type ConstructorLocation = Readonly<{
  run: Run;
  memberIndex: number;
  rowIndex: number;
  operationIndex: number;
  operation: string;
  perRow?: boolean;
  inputExtent?: () => unknown;
  requestsRetired(): boolean;
}>;
type ConstructorOptions<Value> = ConstructorLocation & Readonly<{
  construct(grow: Grow): Value | Promise<Value>;
}>;
type State = 'fresh' | 'preparing' | 'prepared' | 'failed' | 'retired';
type Status = Readonly<{pending: boolean}>;
type ChildPorts<Value> = {
  prepare(): Value | Promise<Value>;
  release(): unknown;
  retry(): unknown;
  status(): Status;
  retainedOutputWire?(value: Awaited<Value>): string;
};
type OwnedRequestOptions<Value> = ConstructorLocation & Readonly<{
  construct?: never;
  constructChild(): Readonly<ChildPorts<Value>>;
}>;
type ConstructorChild<Value> = Readonly<{
  prepare(): Value;
  checkOriginal(): undefined;
  release(): boolean;
  retry(): boolean;
  status(): Status;
}>;

// An internal child of the EXISTING capture retainer, not a cleanup/permission
// Owner. The selected implementation's native occurrence is debited before the
// constructor. Its output stays charged until the enclosing original route and
// request aliases have actually retired, including failed constructor prefixes.
// A driver may already own a Content-borrowing request child. Retain that
// SAME child under the existing constructor token; do not replace its prepare
// or physical cleanup with a second request or a successful-looking snapshot.
export function prepareInstalledEffectOwnedRequestChild<Value>(options: OwnedRequestOptions<Value>): Readonly<{
  prepare(): Value | Promise<Awaited<Value>>;
  checkOriginal(): undefined;
  release(): false | Promise<boolean>;
  retry(): false | Promise<boolean>;
  status(): Status;
}>;
export function prepareInstalledEffectOwnedRequestChild<Value>({constructChild, ...options}:
  Omit<OwnedRequestOptions<Value>, 'constructChild'> & Readonly<{constructChild?: OwnedRequestOptions<Value>['constructChild']}>) {
  if (typeof constructChild !== 'function' || options.construct !== undefined) {
    fail('InstalledEffectConstructorUnavailable');
  }
  let child: Readonly<ChildPorts<Value>> | undefined, methods: Partial<ChildPorts<Value>> | undefined,
    retainedWire: string | undefined, retired = false, opening = false, invoking = false, stopping = false,
    flight: Promise<boolean> | undefined;
  const requestsRetired = options.requestsRetired;
  if (typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const captureMethods = <Name extends keyof ChildPorts<Value>,>(names: readonly Name[]) => {
    for (const name of names) {
      if (!Object.hasOwn(methods!, name)) methods![name] = child![name];
      if (typeof methods![name] !== 'function') fail('InvalidInstalledRowRequestChild');
    }
  };
  const managed = prepareInstalledEffectConstructorChild({...options,
    requestsRetired: () => retired && requestsRetired() === true,
    construct() {
      child = constructChild!(); // Retain before even a fallible method getter.
      constructChild = undefined;
      if (child === null || !['object', 'function'].includes(typeof child)) {
        fail('InvalidInstalledRowRequestChild');
      }
      methods = {};
      captureMethods(['release', 'retry', 'status', 'prepare']);
      if (typeof Reflect.apply(methods!.status!, child, [])?.pending !== 'boolean') {
        fail('InvalidInstalledRowRequestChild');
      }
      const outputWire = child.retainedOutputWire;
      if (outputWire !== undefined) {
        if (typeof outputWire !== 'function') fail('InvalidInstalledRowRequestChild');
        methods.retainedOutputWire = outputWire;
        if (typeof options.run?.runtime?.clientProgramInstalledEffectOperationConstructionCompleteOutput !== 'function') {
          fail('InstalledEffectOperationRuntimeUnavailable');
        }
      }
      if (stopping) fail('InstalledEffectRequestChildRetired');
      const result = Reflect.apply(methods.prepare!, child, []);
      if (stopping) fail('InstalledEffectRequestChildRetired');
      if (outputWire === undefined) return result;
      const finish = async (value: Awaited<Value>) => {
        managed.checkOriginal();
        if (stopping) fail('InstalledEffectRequestChildRetired');
        // SAME captured physical method, real close, then its original status.
        // Neither a fulfilled prepare nor a measured wire acknowledges close.
        const released = await Reflect.apply(methods!.release!, child, []);
        if (released === false || Reflect.apply(methods!.status!, child, [])?.pending !== false) {
          fail('InstalledEffectRequestChildCleanupPending');
        }
        managed.checkOriginal();
        if (stopping) fail('InstalledEffectRequestChildRetired');
        const wire = Reflect.apply(methods!.retainedOutputWire!, child, [value]);
        if (typeof wire !== 'string') fail('InvalidInstalledRowRequestChild');
        retainedWire = wire;
        return value;
      };
      if (nodeTypes.isPromise(result)) {
        return new NativePromise<Awaited<Value>>((resolve, reject) => {
          Reflect.apply(nativePromiseThen, result, [(value: Awaited<Value>) => {
            const closed = finish(value);
            Reflect.apply(nativePromiseThen, closed, [resolve, reject]);
          }, reject]);
        });
      }
      if (result !== null && (typeof result === 'object' || typeof result === 'function') &&
          typeof (result as Readonly<{then?: unknown}>).then === 'function') fail('InstalledEffectConstructorNotSynchronous');
      return finish(result as Awaited<Value>);
    }}, true, () => retainedWire);
  const drain = (retry: boolean) => {
    stopping = true;
    if (opening || invoking) return false;
    if (flight !== undefined) return flight;
    opening = true;
    try {
      flight = (async () => {
        if (!retired) {
          if (child !== undefined) {
            // Retry only still-unobserved methods on this same retained child;
            // successfully captured cleanup methods can never be replaced.
            if (methods === undefined) fail('InvalidInstalledRowRequestChild');
            captureMethods([retry ? 'retry' : 'release', 'status']);
            const release = retry ? methods.retry : methods.release;
            const result = await Reflect.apply(release!, child, []);
            if (result === false || Reflect.apply(methods!.status!, child, [])?.pending !== false) return false;
          }
          child = methods = constructChild = retainedWire = undefined;
          retired = true;
        }
        return managed.release();
      })().finally(() => {flight = undefined;});
    } finally {opening = false;}
    return flight;
  };
  return Object.freeze({prepare() {
    if (stopping) fail('InstalledEffectRequestChildRetired');
    if (invoking) fail('InstalledEffectRequestChildReentrantPrepare');
    invoking = true;
    try {return managed.prepare();} finally {invoking = false;}
  }, checkOriginal: managed.checkOriginal,
    release: () => drain(false), retry: () => drain(true), status: managed.status});
}

export function prepareInstalledEffectRequestChild<Value extends SynchronousRuntimeData>(
  options: ConstructorLocation & Readonly<{construct(grow: Grow): Value}>) {
  return prepareInstalledEffectConstructorChild(options);
}

// This installing-code capture constructor joins its actual original task.
// The enclosing capture retainer already owns every nested request child and
// retires their aliases before this same operation backing can be returned.
export function prepareInstalledEffectCaptureChild<Value>(options: ConstructorOptions<Value>) {
  return prepareInstalledEffectConstructorChild(options, true);
}

// Only the two closed retained wrappers can join an original native Promise.
// An arbitrary constructor Promise keeps the strict refusal below.
function prepareInstalledEffectConstructorChild<Value>(options: ConstructorOptions<Value>, ownedChild?: false):
  ConstructorChild<Value | Promise<never>>;
function prepareInstalledEffectConstructorChild<Value>(options: ConstructorOptions<Value>, ownedChild: true,
  ownedOutputWire?: () => string | undefined): ConstructorChild<Value | Promise<Awaited<Value>>>;
function prepareInstalledEffectConstructorChild<Value>({run, memberIndex, rowIndex,
  operationIndex, operation, perRow = true, construct: originalConstruct, inputExtent: originalInputExtent, requestsRetired}:
  ConstructorLocation & Readonly<{construct?: ConstructorOptions<Value>['construct']}>,
  ownedChild = false, ownedOutputWire?: () => string | undefined): ConstructorChild<Value | Promise<Awaited<Value>>> {
  if (run === undefined || typeof perRow !== 'boolean' || typeof originalConstruct !== 'function' ||
      typeof requestsRetired !== 'function') fail('InstalledEffectConstructorUnavailable');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const retain = runtime?.clientProgramInstalledEffectOperationConstructionRetain;
  const begin = runtime?.clientProgramInstalledEffectOperationConstructionBegin;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  const complete = runtime?.clientProgramInstalledEffectOperationConstructionComplete;
  const completeOutput = runtime?.clientProgramInstalledEffectOperationConstructionCompleteOutput;
  const beginInput = runtime?.clientProgramInstalledEffectOperationInputBegin;
  const growInput = runtime?.clientProgramInstalledEffectOperationInputGrow;
  if (originalInputExtent !== undefined && (typeof originalInputExtent !== 'function' || typeof beginInput !== 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  if (![retain, begin, complete, retire, readPlan].every(method => typeof method === 'function')) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const originalRecord = (): undefined => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
  };
  // Retained input/output backing precedes Source/Preview and its callbacks.
  // Temporary workspace is not reserved while this constructor is only held.
  originalRecord();
  let token = checked(Reflect.apply(retain, runtime,
    [parent, prepared, request, plan, memberIndex, perRow, operationIndex, rowIndex, operation]));
  let construct: ConstructorOptions<Value>['construct'] | undefined = originalConstruct, inputExtent = originalInputExtent;
  originalConstruct = originalInputExtent = undefined;
  let state: State = 'fresh';
  let preparing = false;
  let pendingConstructor: object | undefined;
  const drain = () => {
    if (state === 'retired') return true;
    if (preparing || requestsRetired() !== true) return false;
    // Clear this child's last input/callback references BEFORE the same native
    // body token may settle. The enclosing capture has already severed output.
    construct = inputExtent = ownedOutputWire = undefined;
    if (checked(Reflect.apply(retire, runtime, [token, true])) !== true) return false;
    token = undefined;
    state = 'retired';
    return true;
  };
  return Object.freeze({
    prepare() {
      if (state === 'retired') fail('InstalledEffectRequestChildRetired');
      if (state !== 'fresh') fail('InstalledEffectRequestChildAlreadyPrepared');
      state = 'preparing';
      preparing = true;
      try {
        originalRecord();
        // Atomic Core entry grows this SAME original backing to its captured
        // extent and observes current once, before any constructor allocation.
        if (inputExtent === undefined) checked(Reflect.apply(begin, runtime, [token]));
        else {
          const extent = inputExtent();
          originalRecord();
          checked(Reflect.apply(beginInput!, runtime, [token, extent]));
        }
        originalRecord();
        // The constructor may observe its actual nested input under this
        // first funded prelude. Only its SAME synchronous flight may grow the
        // original selected token before entering the complete nested codec.
        let constructing = true;
        const grow = (extent: unknown): undefined => {
          if (!constructing || !preparing || state !== 'preparing' || typeof growInput !== 'function') {
            fail('InstalledEffectOperationRuntimeUnavailable');
          }
          originalRecord();
          checked(Reflect.apply(growInput, runtime, [token, extent]));
          originalRecord();
        };
        let value: Value | Promise<Value>;
        try {value = construct!(grow);} finally {constructing = false;}
        if (nodeTypes.isPromise(value)) {
          pendingConstructor = value;
          if (ownedChild) {
            // The private wrapper already retained the actual child and all
            // cleanup methods BEFORE calling prepare. Keep construction live
            // until that same native task settles, then recheck its original.
            return new NativePromise<Awaited<Value>>((resolve, reject) => {
              const failed = (cause: unknown) => {
                pendingConstructor = undefined;
                preparing = false;
                state = 'failed';
                reject(cause);
              };
              Reflect.apply(nativePromiseThen, value, [(result: Awaited<Value>) => {
                pendingConstructor = undefined;
                try {
                  originalRecord();
                  const wire = ownedOutputWire?.();
                  if (wire === undefined) checked(Reflect.apply(complete, runtime, [token]));
                  else {
                    if (typeof wire !== 'string' || typeof completeOutput !== 'function') {
                      fail('InstalledEffectOperationRuntimeUnavailable');
                    }
                    checked(Reflect.apply(completeOutput, runtime, [token, wire]));
                  }
                  originalRecord();
                  preparing = false;
                  state = 'prepared';
                  resolve(result);
                } catch (cause) {failed(cause);}
              }, failed]);
            });
          }
          // Observe the native original before any replaceable public then.
          // Failed species/constructor observation rejects this wrapper, but
          // leaves the SAME unjoined task and its body in this child's custody.
          return new NativePromise<never>((resolve, reject) => {
            const settled = () => {
              pendingConstructor = undefined;
              preparing = false;
              state = 'failed';
              reject(Object.assign(new Error('InstalledEffectConstructorNotSynchronous'),
                {code: 'InstalledEffectConstructorNotSynchronous'}));
            };
            Reflect.apply(nativePromiseThen, value, [settled, settled]);
          });
        }
        if (value !== null && (typeof value === 'object' || typeof value === 'function')) {
          pendingConstructor = value;
          // A foreign thenable or throwing accessor cannot certify settlement.
          // Do not start it merely to manufacture an asynchronous cleanup ACK.
          if (typeof (value as Readonly<{then?: unknown}>).then === 'function') fail('InstalledEffectConstructorNotSynchronous');
          pendingConstructor = undefined;
        }
        // Every call now executes its actual constructor. Member capture is
        // retained earlier and prepares only at its real recovery-entry work;
        // no placeholder may return that workspace before Source/Preview.
        originalRecord();
        checked(Reflect.apply(complete, runtime, [token]));
        originalRecord();
        state = 'prepared';
        preparing = false;
        return value;
      } catch (error) {
        if (pendingConstructor === undefined) preparing = false;
        state = 'failed';
        throw error;
      }
    },
    // Callback-free original-record fence after this child was retained.
    // This is not a current observation or an admission proof.
    checkOriginal: originalRecord,
    release: drain, retry: drain,
    status: () => Object.freeze({pending: state !== 'retired'}),
  });
}
