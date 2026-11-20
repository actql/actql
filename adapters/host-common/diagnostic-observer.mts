// Best-effort diagnostics have no authority over execution. One bounded queue
// owns callback delivery; a hung observer occupies its slot until it settles.
// Saturation drops new diagnostics, never starts another unbounded Promise.
const sinks = new WeakSet();
export function createDiagnosticObserver(observe, {maxQueued = 32} = {}) {
  if (observe !== undefined && typeof observe !== 'function' ||
      !Number.isSafeInteger(maxQueued) || maxQueued < 0) {
    throw new TypeError('InvalidDiagnosticObserver');
  }
  const queue = [];
  let active;
  let closed = false;
  let dropped = 0;
  let failures = 0;
  const pump = () => {
    if (closed || active !== undefined || queue.length === 0) return;
    const item = queue.shift();
    const controller = new AbortController();
    active = controller;
    // The callback is outside the caller's awaited operation. Rejections
    // are consumed, and the physical delivery slot is not released early.
    Promise.resolve().then(() => {
      if (!controller.signal.aborted) {
        return observe(item.name, item.detail,
          {signal: controller.signal});
      }
    }).catch(() => { failures++; }).finally(() => {
      active = undefined;
      pump();
    });
  };
  const emit = (name, detail) => {
    if (observe === undefined) return;
    if (closed || active !== undefined && queue.length >= maxQueued) {
      dropped++;
      return;
    }
    queue.push({name, detail});
    pump();
  };
  const sink = Object.freeze(Object.assign(emit, {
    status: () => Object.freeze({queued: queue.length,
      active: active === undefined ? 0 : 1, dropped, failures, closed}),
    close() {
      closed = true;
      dropped += queue.length;
      queue.length = 0;
      active?.abort();
    },
  }));
  sinks.add(sink);
  return sink;
}

// Ingress can share a configured callback without building one queue per
// request. Weak ownership does not keep discarded Host installations alive.
const installed = new WeakMap();
export function diagnosticObserver(observe) {
  if (observe === undefined) return createDiagnosticObserver();
  if (typeof observe !== 'function') throw new TypeError('InvalidDiagnosticObserver');
  if (sinks.has(observe)) return observe;
  let sink = installed.get(observe);
  if (sink === undefined || sink.status().closed) {
    sink = createDiagnosticObserver(observe);
    installed.set(observe, sink);
  }
  return sink;
}
