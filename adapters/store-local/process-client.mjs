// Execution-side lease on a control-owned Store. Closing this lease releases
// only the process's writer/reader and local usage rights, never the independent
// parent holding. The parent confirms orphan cleanup from actual process exit.
// Explicit release of a sealed temporary body is separate: it requires the
// parent's exact typed reclamation report before cleanup responsibility ends.
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
  let sealedIdentity, releaseRequested = false, released = false, releasing;
  const active = () => {
    signal?.throwIfAborted();
    if (closed) throw new RetainedFileError('RetainedUnavailable');
  };
  const release = async () => {
    releaseRequested = true;
    closed = true;
    if (!reserved) released = true;
    if (released) return {pending: false};
    // A missing/unaccepted seal is not proof that an external writer stopped.
    // Its orphan responsibility remains with the existing process-stop owner.
    if (!sealedIdentity) return {pending: true};
    if (releasing) return releasing;
    releasing = (async () => {
      const report = await context.callHost({command: 'release-sealed', output,
        report: sealedIdentity});
      if (!report || typeof report !== 'object' || Array.isArray(report) ||
          Object.keys(report).sort().join(',') !== 'bytes,cid,output,reclaimed,version' ||
          report.version !== 'actql-local-file-release/0.1' || report.output !== output ||
          report.cid !== sealedIdentity.cid || report.bytes !== sealedIdentity.bytes ||
          typeof report.reclaimed !== 'boolean') {
        throw new RetainedFileError('ForeignStoreReleaseReport');
      }
      if (report.reclaimed) released = true;
      return {pending: !released};
    })();
    try { return await releasing; } finally { releasing = undefined; }
  };
  return Object.freeze({
    status: () => ({reservedBytes: reserved &&
        ((releaseRequested && !released) || !(closed && writerStopped && !readers)) ? capacityBytes : 0,
      cleanupPending: (releaseRequested && !released) || (closed && (!writerStopped || readers > 0))}),
    reserve(bytes) {
      active();
      if (reserved || bytes !== capacityBytes) throw new RetainedFileError('StoreCapacity');
      reserved = true;
      const operations = {
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
        async appendBytes(bytes) { active(); await writer.appendBytes(bytes); },
      };
      const seal = async (identity, physical = false) => {
        active();
        const report = await writer.seal();
        writerStopped = true;
        if (!physical && (report.bytes !== identity?.bytes || report.cid !== identity?.cid)) {
          throw new RetainedFileError('StoreIdentityMismatch');
        }
        // Preserve the original report even if parent seal acceptance loses its
        // response. Retrying release cannot create or re-seal another body.
        sealedIdentity = Object.freeze({bytes: report.bytes, cid: report.cid});
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
          bytes: report.bytes, cid: report.cid,
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
      };
      return Object.freeze({...operations, seal: identity => seal(identity),
        sealPhysical: () => seal(undefined, true)});
    },
    close() { closed = true; },
    release,
    async cleanup() {
      if (closed && writer && !writerStopped) {
        await writer.close(); writerStopped = true;
      }
      if (releaseRequested && !released) await release();
    },
  });
}
