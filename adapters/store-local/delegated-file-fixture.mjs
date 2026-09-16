import { serveManagedExecution } from '../host-node/worker-channel.mjs';
import { openDelegatedFile } from './delegated-file.mjs';
import { consumeDelegatedFile } from './delegated-reader.mjs';

serveManagedExecution(async (request, signal, context) => {
  if (request.command === 'exit') process.exit(7);
  if (request.command === 'read') {
    if (request.lease.session !== context.session) throw Error('Foreign reader session');
    return consumeDelegatedFile(request.lease, () => {}, signal);
  }
  if (!['write', 'write-binary', 'crash-writing'].includes(request.command)) throw Error('Unknown fixture command');
  if (request.lease.session !== context.session) throw Error('Foreign writer session');
  const writer = await openDelegatedFile(request.lease, signal);
  try {
    if (request.command === 'write-binary') {
      await writer.appendBytes(new Uint8Array([0, 255, 128, 1]));
      await writer.appendBytes(new Uint8Array([2, 3]));
      return await writer.seal();
    }
    await writer.append('[0,');
    if (request.command === 'crash-writing') process.exit(9);
    await writer.append('1]');
    return await writer.seal();
  } finally { await writer.close(); }
}, { maxBytes: 4096, maxNodes: 100, maxDepth: 10 });
