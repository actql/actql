import { serveManagedExecution } from '../host-node/worker-channel.mjs';
import { openDelegatedFile } from './delegated-file.mjs';
import { consumeDelegatedFile } from './delegated-reader.mjs';

serveManagedExecution(async (request, signal, context) => {
  if (request.command === 'exit') process.exit(7);
  if (request.command === 'read') {
    if (request.lease.session !== context.session) throw Error('Foreign reader session');
    return consumeDelegatedFile(request.lease, () => {}, signal);
  }
  if (!['write', 'crash-writing'].includes(request.command)) throw Error('Unknown fixture command');
  if (request.lease.session !== context.session) throw Error('Foreign writer session');
  const writer = await openDelegatedFile(request.lease, signal);
  try {
    await writer.append('[0,');
    if (request.command === 'crash-writing') process.exit(9);
    await writer.append('1]');
    return await writer.seal();
  } finally { await writer.close(); }
}, { maxBytes: 4096, maxNodes: 100, maxDepth: 10 });
