// The SAME adopted Effect Run owns Result preparation and later dependency
// publication work. This adapter creates no Ledger, grant or cleanup owner.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

type Runtime = Readonly<{
  clientProgramInstalledEffectResultWorkPrepare(owner: unknown, prepared: unknown, request: unknown,
    plan: unknown, source: unknown): unknown;
  clientProgramInstalledEffectResultAdvance(owner: unknown, prepared: unknown, request: unknown,
    plan: unknown, source: unknown, transformation: unknown, quantum: number): unknown;
}>;
type ManagedRun = {
  runtime: Runtime; value: unknown; prepared: unknown; request: unknown; operationPlan: unknown;
  readPlan: (...args: never[]) => unknown; closed?: boolean; selecting?: boolean; failure?: unknown;
};

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectResultProgress(run: ManagedRun, source: unknown) {
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run ?? {};
  const prepare = runtime?.clientProgramInstalledEffectResultWorkPrepare;
  const advance = runtime?.clientProgramInstalledEffectResultAdvance;
  if (![prepare, advance, readPlan].every(value => typeof value === 'function') ||
      parent === undefined || prepared === undefined || request === undefined ||
      plan === undefined || source === undefined || run.closed || run.selecting) {
    fail('InstalledEffectResultWorkUnavailable');
  }
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  // Core funds this fixed adapter packet before its closure is retained. Its
  // current/Plan/Run checks are authoritative; the JavaScript tuple fence also
  // rejects replacement of the installing record during a synchronous call.
  run.selecting = true;
  try {
    checked(Reflect.apply(prepare, runtime, [parent, prepared, request, plan, source]));
  } finally {run.selecting = false;}
  if (Object.hasOwn(run, 'failure')) throw run.failure;
  if (run.closed || run.runtime !== runtime || run.value !== parent ||
      run.prepared !== prepared || run.request !== request ||
      run.operationPlan !== plan || run.readPlan !== readPlan ||
      runtime.clientProgramInstalledEffectResultWorkPrepare !== prepare ||
      runtime.clientProgramInstalledEffectResultAdvance !== advance) {
    fail('ForeignInstalledEffectManagedRun');
  }
  let busy = false, failed = false;
  let primary: unknown;
  return function advanceResult(transformation: unknown, quantum: number) {
    if (failed) throw primary;
    if (busy || run.selecting) fail('InstalledEffectResultWorkPending');
    if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 256) {
      fail('InvalidInstalledEffectResultQuantum');
    }
    busy = true;
    run.selecting = true;
    try {
      if (Object.hasOwn(run, 'failure')) throw run.failure;
      if (run.closed || run.runtime !== runtime || run.value !== parent ||
          run.prepared !== prepared || run.request !== request ||
          run.operationPlan !== plan || run.readPlan !== readPlan ||
          runtime.clientProgramInstalledEffectResultWorkPrepare !== prepare ||
          runtime.clientProgramInstalledEffectResultAdvance !== advance) {
        fail('ForeignInstalledEffectManagedRun');
      }
      const progress = checked(Reflect.apply(advance, runtime,
        [parent, prepared, request, plan, source, transformation, quantum]));
      // Core has already charged actual progress, including a failed prefix.
      // An invalid result never falls back to the unmetered generic advance.
      if (progress === null || typeof progress !== 'object') {
        fail('InvalidInstalledEffectResultProgress');
      }
      const ready = runtimeField(progress, 0), work = runtimeField(progress, 1) as number;
      if (typeof ready !== 'boolean' || !Number.isSafeInteger(work) ||
          work < 0 || work > quantum) fail('InvalidInstalledEffectResultProgress');
      if (Object.hasOwn(run, 'failure')) throw run.failure;
      if (run.closed || run.runtime !== runtime || run.value !== parent ||
          run.prepared !== prepared || run.request !== request ||
          run.operationPlan !== plan || run.readPlan !== readPlan ||
          runtime.clientProgramInstalledEffectResultWorkPrepare !== prepare ||
          runtime.clientProgramInstalledEffectResultAdvance !== advance) {
        fail('ForeignInstalledEffectManagedRun');
      }
      return ready;
    } catch (cause) {
      failed = true;
      primary = cause;
      throw cause;
    } finally {
      busy = false;
      run.selecting = false;
    }
  };
}
