// Execution-side lease on a control-owned Store. Closing this lease releases
// only the process's writer/reader and local usage rights, never the independent
// parent holding. The parent confirms orphan cleanup from actual process exit.
import {processStoreContext} from './process-binding.mjs';
import {openDelegatedFile} from './delegated-file.mjs';
import {consumeDelegatedFile} from './delegated-reader.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';
import {RetainedFileError} from './files.mjs';

const origins = new WeakMap();

// An exact sealed lease, not a caller-supplied output key or matching digest.
// This is physical provenance; completion evidence is checked separately.
export function processRetainedBodyIdentity(body, binding) {
  processStoreContext(binding);
  const origin = origins.get(body);
  if (!origin || origin.binding !== binding || !body.available()) {
    throw new RetainedFileError('ForeignRetainedStoreBody');
  }
  return origin.identity;
}

export function createProcessStoreLease(binding, output, capacityBytes, maxFrameBytes, signal) {
  const context = processStoreContext(binding);
  if (typeof output !== 'string' || !output.length || output.length > 256 ||
      !Number.isSafeInteger(capacityBytes) || capacityBytes < 0 ||
      !Number.isSafeInteger(maxFrameBytes) || maxFrameBytes < 1 || maxFrameBytes > 16777216) throw new RetainedFileError('InvalidStoreLimits');
  let reserved = false, closed = false, writer, writerStopped = true, readers = 0, sealed = false, filePath;
  const active = () => {
    signal?.throwIfAborted();
    if (closed) throw new RetainedFileError('RetainedUnavailable');
  };
  return Object.freeze({
    status: () => ({reservedBytes: reserved && !(closed && writerStopped && !readers) ? capacityBytes : 0,
      cleanupPending: closed && (!writerStopped || readers > 0)}),
    reserve(bytes) {
      active();
      if (reserved || bytes !== capacityBytes) throw new RetainedFileError('StoreCapacity');
      reserved = true;
      return Object.freeze({
        async start() {
          active();
          if (writer) throw new RetainedFileError('StoreAlreadyStarted');
          const descriptor = await context.callHost({command: 'reserve', output, bytes});
          if (descriptor.session !== context.session || descriptor.maxBytes !== capacityBytes || descriptor.maxFrameBytes !== maxFrameBytes) {
            throw new RetainedFileError('ForeignStoreSession');
          }
          active();
          writer = await openDelegatedFile(descriptor, signal);
          filePath = descriptor.path;
          writerStopped = false;
        },
        async append(text) { active(); await writer.append(text); },
        async seal(identity) {
          active();
          const report = await writer.seal();
          writerStopped = true;
          if (report.bytes !== identity.bytes || report.cid !== identity.cid) throw new RetainedFileError('StoreIdentityMismatch');
          await context.callHost({command: 'seal', output, report});
          active(); sealed = true;
          const read = async (operation, readSignal) => {
            active(); readSignal?.throwIfAborted();
            const descriptor = await context.callHost({command: 'read', output});
            if (descriptor.session !== context.session || descriptor.bytes !== report.bytes || descriptor.cid !== report.cid ||
                descriptor.maxFrameBytes !== maxFrameBytes) {
              throw new RetainedFileError('ForeignStoreReadReport');
            }
            readers++;
            let readStopped = false;
            try {
              const result = await operation(descriptor);
              readStopped = true;
              await context.callHost({command: 'read-finish', output, report: result.report});
              active(); readSignal?.throwIfAborted();
              return result.value;
            } catch (error) {
              if (['ForeignStoreFile', 'RetainedBodyChanged', 'RetainedBodyTruncated'].includes(error?.code)) closed = true;
              throw error;
            } finally {
              // A rejection is not proof that descriptor close stopped a read.
              // Its conservative parent borrow lasts until confirmed exit.
              if (readStopped) readers--;
            }
          };
          const body = Object.freeze({
            available: () => sealed && !closed,
            nativeFilePath() { active(); return filePath; },
            close() { closed = true; },
            async consume(accept, readSignal) {
              return read(async descriptor => ({
                report: await consumeDelegatedFile(descriptor, accept, readSignal),
              }), readSignal);
            },
            async withVerifiedFile(use, readSignal, beforeRead) {
              return read(descriptor => withVerifiedDelegatedFile(descriptor, use, readSignal, beforeRead), readSignal);
            },
          });
          origins.set(body, Object.freeze({binding, identity: Object.freeze({
            session: context.session, run: context.run, output,
            bytes: report.bytes, cid: report.cid,
          })}));
          return body;
        },
      });
    },
    close() { closed = true; },
    async cleanup() {
      if (closed && writer && !writerStopped) {
        await writer.close(); writerStopped = true;
      }
    },
  });
}
