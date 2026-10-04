import {registerRetainedInput} from '../store-local/representations.mjs';

export function prepareLocalRetainedOutput(output, createLease, checked, signal) {
  if (!createLease) throw new TypeError('LocalOutputStoreRequired');
  const {key, limits, install, begin, next, finish, refresh} = output;
  let store, body;
  checked(install(() => !store || store.status().reservedBytes === 0));
  const cleanupHandle = Object.freeze({
    status: () => ({pending: store?.status().cleanupPending ?? false}),
    async retry() {
      if (store) await store.cleanup();
      checked(refresh());
      return cleanupHandle.status();
    },
  });
  return Object.freeze({
    cleanupHandle,
    async write() {
      signal?.throwIfAborted();
      checked(begin());
      store = await createLease(key, limits.wire.max_bytes, limits.max_batch_bytes, signal);
      signal?.throwIfAborted();
      const writer = store.reserve(limits.wire.max_bytes);
      await writer.start();
      signal?.throwIfAborted();
      for (;;) {
        const part = checked(next());
        if (part == null) break;
        await writer.append(part);
        signal?.throwIfAborted();
      }
      const content = checked(finish());
      await writer.append(content.tail);
      signal?.throwIfAborted();
      body = await writer.seal({cid: content.cid, bytes: content.bytes});
      signal?.throwIfAborted();
      const representation = checked(content.bind(() => body.available()));
      registerRetainedInput(representation.material, representation.readable, body,
        {wire: limits.wire, maxFrameBytes: limits.max_batch_bytes});
      return {outputRepresentation: 'retained-file', exportedRows: content.rows, exportedBytes: String(content.bytes)};
    },
    close() { body?.close(); store?.close(); },
  });
}
