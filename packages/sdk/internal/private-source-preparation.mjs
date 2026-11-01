// Reuse the SDK's exact snapshot freeze through this existing private bridge.
export {freezeInput} from './data.mjs';
// Read-only custody predicate on the existing private Host bridge; no issuer.
export {matchesPublishedSubmissionSnapshot} from './submission-observation.mjs';
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
    'bindSourceRequest', 'finishSourceProducer', 'intentCid',
    'captureSourceSnapshot', 'assertSourceSnapshotCurrent',
    'publishSourceSnapshot'].map(name => {
      const field = descriptor(receiver, name);
      if (field === undefined || !hasOwn(field, 'value') ||
          typeof field.value !== 'function') throw unavailable();
      return field.value;
    });
  const [before, snapshot, request, finish, intent, capture, snapshotCurrent, publication] = methods;
  const queryField = descriptor(receiver, 'beforeSourceQuery');
  const beforeQuery = queryField !== undefined && hasOwn(queryField, 'value') &&
    typeof queryField.value === 'function' ? queryField.value : undefined;
  // A selected Source owns this complete synchronous protocol. Capture once
  // at initialization; no request may select legacy capture or skip a fence.
  // Result support is separately selected by this same installation. Its
  // absence cannot break connect or Source submission, but cannot fund a read.
  const resultField = descriptor(receiver, 'beforeResultRead');
  const beforeResult = resultField !== undefined && hasOwn(resultField, 'value') &&
    typeof resultField.value === 'function' ? resultField.value : undefined;
  const currentField = descriptor(receiver, 'assertResultReadCurrent');
  const resultCurrent = currentField !== undefined && hasOwn(currentField, 'value') &&
    typeof currentField.value === 'function' ? currentField.value : undefined;
  const resultVoid = (method, args) => {
    if (beforeResult === undefined || resultCurrent === undefined) throw unavailable();
    const value = apply(method, receiver, args);
    if (value !== undefined) {
      if (value instanceof originalPromise) apply(promiseThen, value, [undefined, () => {}]);
      throw unavailable();
    }
  };
  return Object.freeze({
    beforeSourceQuery(format, text, parameters, options, originalConnection) {
      if (beforeQuery === undefined) throw unavailable();
      const receipt = apply(beforeQuery, receiver, [format, text, parameters, options, originalConnection]);
      if (receipt instanceof originalPromise) {
        apply(promiseThen, receipt, [undefined, () => {}]);
        throw unavailable();
      }
      return receipt;
    },
    beforeResultRead(schemaOrOptions, options) {
      resultVoid(beforeResult, [schemaOrOptions, options]);
    },
    assertResultReadCurrent() {
      resultVoid(resultCurrent, []);
    },
    beforeSourceSnapshot(kind, input, options, originalConnection) {
      const receipt = apply(before, receiver, [kind, input, options, originalConnection]);
      if (receipt instanceof originalPromise) {
        // Do not defer the original synchronous SDK capture until an await.
        // The original Host still owns any partial asynchronous preparation;
        // observing its rejection neither cancels it nor acknowledges cleanup.
        apply(promiseThen, receipt, [undefined, () => {}]);
        throw unavailable();
      }
      return receipt;
    },
    assertSourceSnapshotCurrent(receipt) {
      const value = apply(snapshotCurrent, receiver, [receipt]);
      if (value !== undefined) {
        if (value instanceof originalPromise) apply(promiseThen, value, [undefined, () => {}]);
        throw unavailable();
      }
    },
    captureSourceSnapshot(receipt, value, snapshot) {
      const result = apply(capture, receiver, [receipt, value, snapshot]);
      if (result instanceof originalPromise) {
        apply(promiseThen, result, [undefined, () => {}]);
        throw unavailable();
      }
      return result;
    },
    bindSourceSnapshot(receipt, originalFrozenBody) {
      return apply(snapshot, receiver, [receipt, originalFrozenBody]);
    },
    publishSourceSnapshot(receipt, originalBody, publicationReceipt) {
      return apply(publication, receiver,
        [receipt, originalBody, publicationReceipt]);
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
