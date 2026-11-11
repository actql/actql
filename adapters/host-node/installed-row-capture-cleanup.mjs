import {releasePreparedResults} from '../host-common/completed-run-publication.mjs';

// The existing capture retains this original child before any fallible current
// check or asynchronous preparation. A fulfilled request is not retirement of
// its reader, backing, borrowed Content or pending physical cleanup.
export async function prepareInstalledRowCaptureChild(options) {
  return retainInstalledRowCaptureChild(options).prepare();
}

// The SAME retainer can hold an original constructor before its actual data
// exists. Preparation is still the captured original method, never a new child,
// callback producer or cleanup owner. Immediate callers use the wrapper above.
export function retainInstalledRowCaptureChild({children, create,
  assertCurrent, signal}) {
  signal?.throwIfAborted();
  assertCurrent?.();
  let child = create();
  create = undefined;
  let methods;
  let preparing = false;
  let retired = false;
  let flight;
  let openingFlight = false;
  const invalid = () => Object.assign(new TypeError('InvalidInstalledRowRequestChild'),
    {code: 'InvalidInstalledRowRequestChild'});
  const drain = retry => {
    if (retired) return;
    // The async executor calls the original method synchronously, before its
    // returned Promise can be assigned. Fence that exact opening interval.
    if (openingFlight) return false;
    if (flight === undefined) {
      openingFlight = true;
      try {
        flight = (async () => {
          const method = retry ? methods?.retry : methods?.release;
          if (typeof method !== 'function') throw invalid();
          const result = await Reflect.apply(method, child, []);
          if (result !== false && !preparing &&
              Reflect.apply(methods.status, child, [])?.pending === false) {
            retired = true;
            child = undefined;
            methods = undefined;
            assertCurrent = undefined;
            signal = undefined;
          }
        })().finally(() => { flight = undefined; });
      } finally {openingFlight = false;}
    }
    return flight;
  };
  children.push({prepared: Object.freeze({release: () => drain(false),
    retry: () => drain(true), status: () => Object.freeze({pending: !retired})})});
  // Retention precedes even property callbacks. Capture each original method
  // once with its original receiver; a later property read cannot swap it.
  if (!child) throw invalid();
  methods = {release: child.release, retry: child.retry,
    status: child.status, prepare: child.prepare};
  if (Object.values(methods).some(method => typeof method !== 'function') ||
      typeof Reflect.apply(methods.status, child, [])?.pending !== 'boolean') throw invalid();
  return Object.freeze({async prepare() {
    if (retired || preparing) throw invalid();
    // The original current callback may synchronously invoke this same
    // retained method. Latch before it, without another current observation.
    preparing = true;
    try {
      assertCurrent?.();
      signal?.throwIfAborted();
      const prepared = await Reflect.apply(methods.prepare, child, []);
      assertCurrent?.();
      signal?.throwIfAborted();
      return prepared;
    } finally { preparing = false; }
  }});
}

// Adapt the original capture's existing Result and input-release owners into
// the common prepared cleanup owner. Every sibling is attempted independently;
// an unsuccessful release remains pending in that owner's retained retry handle.
export async function releaseInstalledRowCapture({payloads = [], children = [], releaseResults,
  releaseInputs, control}, primary) {
  // Capture children are append-only original handles; their retained wrapper
  // retires monotonically and cannot reopen. Advance only after that actual
  // retirement report. Each dependent need not rescan the same retired prefix.
  let retiredChildren = 0;
  const childPending = () => {
    while (retiredChildren < children.length) {
      const index = retiredChildren, value = children[index];
      if (typeof value?.prepared?.status !== 'function' ||
          value.prepared.status()?.pending !== false) return true;
      if (children[index] !== value) return true;
      // A status callback may reenter this same drain. Never skip the next
      // original child by advancing an index already consumed by that call.
      if (retiredChildren === index) retiredChildren++;
    }
    return false;
  };
  const retain = release => {
    let pending = typeof release === 'function';
    let flight;
    let openingFlight = false;
    const drain = () => {
      if (!pending) return;
      if (openingFlight) return false;
      if (childPending()) return false;
      if (flight === undefined) {
        openingFlight = true;
        try {
          flight = (async () => {
            if (await release() !== false) { pending = false; release = undefined; }
          })().finally(() => { flight = undefined; });
        } finally {openingFlight = false;}
      }
      return flight;
    };
    return Object.freeze({prepared: Object.freeze({
      release: drain, retry: drain,
      status: () => Object.freeze({pending}),
    })});
  };
  const dependent = value => {
    let original = value.prepared;
    let flight;
    let openingFlight = false;
    let attempted = false;
    const drain = retry => {
      if (original === undefined) return;
      if (openingFlight) return false;
      if (childPending()) return false;
      if (flight === undefined) {
        openingFlight = true;
        try {
          flight = (async () => {
            if (original.status()?.pending !== false) {
              const operation = retry && attempted ? original.retry : original.release;
              attempted = true;
              await Reflect.apply(operation, original, []);
            }
            if (original.status()?.pending === false) original = undefined;
          })().finally(() => { flight = undefined; });
        } finally {openingFlight = false;}
      }
      return flight;
    };
    return Object.freeze({prepared: Object.freeze({
      release: () => drain(false), retry: () => drain(true),
      status: () => Object.freeze({pending: original !== undefined &&
        (childPending() || original.status()?.pending !== false)}),
    })});
  };
  // The common owner drains in reverse. Preserve the original source/Result/
  // input order. Child siblings progress independently, but no still-borrowed
  // parent may retire while any of these original children remains pending.
  try {
    // Child handles come first in the retained retry inventory. The initial
    // reverse drain attempts gated parents without releasing them, then every
    // child; a later retry can retire children BEFORE any parent in one pass.
    await releasePreparedResults([...children.slice().reverse(),
      retain(releaseInputs), retain(releaseResults),
      ...payloads.slice().reverse().map(value => children.length ? dependent(value) : value)],
    primary, control);
  } catch (error) {
    if (children.length && !childPending() && error?.primaryFailure === primary &&
        error.cleanupPending === true) {
      // Only advance the same finite parent inventory after all original child
      // ACKs. This is not another preparation/read/send or a physical retry.
      if ((await error.cleanupHandle.retry()).pending === false) throw primary;
    }
    throw error;
  }
}
