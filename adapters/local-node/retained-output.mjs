import {registerRetainedInput} from '../store-local/representations.mjs';

const yieldToHost = () => new Promise(resolve => setTimeout(resolve, 0));

export function prepareLocalRetainedOutput(
  output, createLease, checked, signal, faultInjection,
) {
  if (!createLease) throw new TypeError('LocalOutputStoreRequired');
  const {key, limits, install, begin, prepare, advance, finish, refresh} = output;
  if (typeof prepare !== 'function' || typeof advance !== 'function') {
    throw new TypeError('LocalOutputAdvanceRequired');
  }
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
      for (;;) {
        signal?.throwIfAborted();
        const poll = checked(prepare(64));
        if (!Array.isArray(poll) || poll.length !== 2 || typeof poll[0] !== 'boolean' ||
            !Number.isSafeInteger(poll[1]) || poll[1] < 0 || poll[1] > 64 ||
            (!poll[0] && poll[1] === 0)) {
          throw new Error('InvalidLocalOutputPreparation');
        }
        signal?.throwIfAborted();
        if (poll[0]) break;
        await yieldToHost();
      }
      store = await createLease(key, limits.wire.max_bytes, limits.max_batch_bytes, signal);
      signal?.throwIfAborted();
      const writer = store.reserve(limits.wire.max_bytes);
      await writer.start();
      signal?.throwIfAborted();
      for (;;) {
        signal?.throwIfAborted();
        const poll = checked(advance(64));
        if (!Number.isSafeInteger(poll.steps) || poll.steps < 0 || poll.steps > 64 ||
            typeof poll.complete !== 'boolean' ||
            (poll.batch != null && typeof poll.batch !== 'string') ||
            (poll.complete && poll.batch != null) ||
            (!poll.complete && poll.steps === 0)) {
          throw new Error('InvalidLocalOutputAdvance');
        }
        signal?.throwIfAborted();
        if (poll.complete) break;
        if (poll.batch == null) {
          await yieldToHost();
          signal?.throwIfAborted();
          continue;
        }
        const part = poll.batch;
        await writer.append(part);
        if (faultInjection !== undefined) {
          // A trusted test hook after physical acceptance, not completion.
          const status = store.status();
          await faultInjection('local_retained_output_appended', {
            admittedWriteBytes: status.admittedWriteBytes,
            reservedBytes: status.reservedBytes,
          });
        }
        signal?.throwIfAborted();
        await yieldToHost();
      }
      const content = checked(finish());
      await writer.append(content.tail);
      signal?.throwIfAborted();
      body = await writer.seal({cid: content.cid, bytes: content.bytes});
      if (faultInjection !== undefined) {
        // The sealed body stays owned when its acknowledgement is lost.
        await faultInjection('local_retained_output_sealed', {
          sealedBytes: body.bytes,
          reservedBytes: store.status().reservedBytes,
        });
      }
      signal?.throwIfAborted();
      const representation = checked(content.bind(() => body.available()));
      registerRetainedInput(representation.material, representation.readable, body,
        {wire: limits.wire, maxFrameBytes: limits.max_batch_bytes});
      return {outputRepresentation: 'retained-file', exportedRows: content.rows, exportedBytes: String(content.bytes)};
    },
    close() { body?.close(); store?.close(); },
  });
}
