import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {registerRetainedInput} from '../store-local/representations.mjs';
import type {LocalRetainedStore} from '../store-local/files.mjs';

type WireLimits = Parameters<typeof registerRetainedInput>[3]['wire'] & Readonly<{max_bytes: number}>;
type StoreLease = Pick<LocalRetainedStore, 'status' | 'reserve' | 'close' | 'cleanup'>;
type OutputBody = Awaited<ReturnType<ReturnType<StoreLease['reserve']>['seal']>>;
type CreateLease = (key: string, maxBytes: number, maxBatchBytes: number, signal?: AbortSignal) => StoreLease | PromiseLike<StoreLease>;
type RetainedOutput = Readonly<{
  key: string;
  limits: Readonly<{wire: WireLimits; max_batch_bytes: number}>;
  install(released: () => boolean): unknown;
  begin(): unknown;
  prepare(quantum: number): unknown;
  advance(quantum: number): unknown;
  finish(): unknown;
  refresh(): unknown;
}>;
type AdvancePoll = Readonly<{steps: number; complete: boolean; batch?: string | null}>;
type OutputContent = Readonly<{
  tail: string;
  cid: string;
  bytes: number;
  rows: number;
  bind(available: () => boolean): unknown;
}>;
type BoundRepresentation = Readonly<{
  material: Parameters<typeof registerRetainedInput>[0];
  readable: Parameters<typeof registerRetainedInput>[1];
}>;
type OutputFault = (...event:
  [kind: 'local_retained_output_appended', facts: Readonly<{admittedWriteBytes: number; reservedBytes: number}>] |
  [kind: 'local_retained_output_sealed', facts: Readonly<{sealedBytes: number; reservedBytes: number}>]
) => unknown;

const yieldToHost = () => new Promise<void>(resolve => setTimeout(resolve, 0));

export function prepareLocalRetainedOutput(
  output: RetainedOutput, createLease: CreateLease | undefined, checked: (result: unknown) => unknown,
  signal?: AbortSignal, faultInjection?: OutputFault,
) {
  if (!createLease) throw new TypeError('LocalOutputStoreRequired');
  const {key, limits, install, begin, prepare, advance, finish, refresh} = output;
  if (typeof prepare !== 'function' || typeof advance !== 'function') {
    throw new TypeError('LocalOutputAdvanceRequired');
  }
  let store: StoreLease | undefined, body: OutputBody | undefined;
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
        if (poll == null || typeof runtimeField(poll, 0) !== 'boolean' ||
            !Number.isSafeInteger(runtimeField(poll, 1)) || (runtimeField(poll, 1) as number) < 0 || (runtimeField(poll, 1) as number) > 64 ||
            (!runtimeField(poll, 0) && runtimeField(poll, 1) === 0)) {
          throw new Error('InvalidLocalOutputPreparation');
        }
        signal?.throwIfAborted();
        if (runtimeField(poll, 0)) break;
        await yieldToHost();
      }
      store = await createLease(key, limits.wire.max_bytes, limits.max_batch_bytes, signal);
      signal?.throwIfAborted();
      const writer = store.reserve(limits.wire.max_bytes);
      await writer.start();
      signal?.throwIfAborted();
      for (;;) {
        signal?.throwIfAborted();
        const poll = checked(advance(64)) as AdvancePoll;
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
      const content = checked(finish()) as OutputContent;
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
      const representation = checked(content.bind(() => body!.available())) as BoundRepresentation;
      registerRetainedInput(representation.material, representation.readable, body,
        {wire: limits.wire, maxFrameBytes: limits.max_batch_bytes});
      return {outputRepresentation: 'retained-file', exportedRows: content.rows, exportedBytes: String(content.bytes)};
    },
    close() { body?.close(); store?.close(); },
  });
}
