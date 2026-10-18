// Private in-process transport connection, not a wire field, receipt issuer
// or proof of capacity. Only the selected Host/Resource owner authenticates
// its receiver, original installation and every returned opaque receipt.
export const sourcePreparationPort = Symbol('actql.privateSourcePreparation');

const descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn;
const apply = Reflect.apply;
const originalPromise = Promise;
const promiseThen = Promise.prototype.then;

const unavailable = () => Object.assign(new Error('NodeSourceManagedAdmissionUnavailable'),
  {code: 'NodeSourceManagedAdmissionUnavailable'});

// Capture the actual receiver and its methods once, while the installation
// still owns preparation. Later property replacement cannot redirect this
// connection. A generic Host port implementing these methods gains no grant.
export function captureSourcePreparation(port) {
  if (port === undefined) return undefined;
  const entry = descriptor(port, sourcePreparationPort);
  if (entry === undefined) return undefined;
  if (!hasOwn(entry, 'value') || entry.value === null ||
      typeof entry.value !== 'object') throw unavailable();
  const receiver = entry.value;
  const methods = ['beforeSourceSnapshot', 'bindSourceSnapshot',
    'bindSourceRequest', 'finishSourceProducer', 'intentCid'].map(name => {
      const field = descriptor(receiver, name);
      if (field === undefined || !hasOwn(field, 'value') ||
          typeof field.value !== 'function') throw unavailable();
      return field.value;
    });
  const [before, snapshot, request, finish, intent] = methods;
  return Object.freeze({
    beforeSourceSnapshot(kind, input, options) {
      const receipt = apply(before, receiver, [kind, input, options]);
      if (receipt instanceof originalPromise) {
        // Do not defer the original synchronous SDK capture until an await.
        // The original Host still owns any partial asynchronous preparation;
        // observing its rejection neither cancels it nor acknowledges cleanup.
        apply(promiseThen, receipt, [undefined, () => {}]);
        throw unavailable();
      }
      return receipt;
    },
    bindSourceSnapshot(receipt, originalFrozenBody) {
      return apply(snapshot, receiver, [receipt, originalFrozenBody]);
    },
    bindSourceRequest(receipt, originalBody, actualClonedRequest) {
      return apply(request, receiver, [receipt, originalBody, actualClonedRequest]);
    },
    intentCid(receipt, originalBody) {
      const value = apply(intent, receiver, [receipt, originalBody]);
      if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(value)) {
        // No Promise/thenable or native-hash fallback can escape this original
        // synchronous Source operation. This CID remains metadata, not a grant.
        if (value instanceof originalPromise) apply(promiseThen, value, [undefined, () => {}]);
        throw unavailable();
      }
      return value;
    },
    finishSourceProducer(receipt, terminal) {
      return apply(finish, receiver, [receipt, terminal]);
    },
  });
}
