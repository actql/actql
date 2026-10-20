// The approved Effect caller retains this child before execution. Content is
// borrowed from the same Run owner, never reconstructed from its wire or CID.
import {prepareLocalFileWrite} from './root-file-writer.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};

export function prepareLocalStoredContentWrite({contentOwner, content, assertCurrent,
  ...options}) {
  const consume = contentOwner?.consumeContent;
  const select = contentOwner?.storageForContent;
  const selectedCurrent = contentOwner?.storageCurrentForContent;
  const contentCurrent = content?.current;
  if (typeof consume !== 'function' || typeof select !== 'function' ||
      typeof selectedCurrent !== 'function' || typeof contentCurrent !== 'function' ||
      typeof assertCurrent !== 'function') fail('OriginalEffectContentUnavailable');
  const binding = content.binding;
  const original = Reflect.apply(select, contentOwner, [binding]);
  let attempted = false, stopping = false, flight, cleanupFlight, reader;
  const current = () => {
    if (stopping) fail('LocalFileWriteClosing');
    const result = assertCurrent();
    if (result !== undefined) {
      if (result instanceof Promise) void result.catch(() => {});
      fail('InvalidLocalFileCurrentFence');
    }
    if (stopping || Reflect.apply(contentCurrent, content, []) !== true ||
        Reflect.apply(selectedCurrent, contentOwner, [original, binding]) !== true ||
        original === undefined) fail('OriginalEffectContentUnavailable');
    if (stopping) fail('LocalFileWriteClosing');
  };
  // The lower physical factory also performs no I/O. Its limits are the
  // installed file-write limits, not the declaration's JSON byte allowance.
  const writer = prepareLocalFileWrite({...options, assertCurrent: current});
  const status = () => Object.freeze({pending: flight !== undefined || reader !== undefined ||
    writer.status().pending});
  const close = () => {
    stopping = true;
    if (cleanupFlight !== undefined) return cleanupFlight;
    if (flight !== undefined) return Promise.resolve(status());
    cleanupFlight = (async () => {
      if (reader !== undefined) {
        if (reader.status().pending) await reader.retry();
        if (reader.status().pending) return status();
        reader = undefined;
      }
      writer.close();
      return status();
    })().finally(() => {cleanupFlight = undefined;});
    return cleanupFlight;
  };
  return Object.freeze({
    execute() {
      if (attempted) fail('LocalFileWriteAlreadyAttempted');
      attempted = true; // No resend after any partial write/publication outcome.
      let operation;
      operation = Promise.resolve().then(async () => {
        current();
        writer.start();
        await Reflect.apply(consume, contentOwner, [binding, bytes => {
          current();
          writer.write(bytes);
        }]);
        current();
        return writer.publish();
      }).catch(cause => {
        if (cause?.cleanupHandle !== undefined) reader = cause.cleanupHandle;
        throw cause;
      }).finally(() => {if (flight === operation) flight = undefined;});
      flight = operation;
      return operation;
    },
    close, retry: close, release: close, status,
  });
}
