import {serveManagedExecution} from '../host-node/worker-channel.mjs';
import {openDelegatedFile} from './delegated-file.mjs';

serveManagedExecution(async (request, signal, context) => {
  if (request.command === 'reserve-invalid') {
    try { await context.callHost({command: 'reserve', output: 'bad', bytes: -1}); }
    catch { return {rejected: true}; }
    return {rejected: false};
  }
  const descriptor = await context.callHost({command: 'reserve', output: request.output, bytes: 100});
  const writer = await openDelegatedFile(descriptor, signal);
  try {
    await writer.append('[{"id":3}]');
    if (request.command === 'crash') process.exit(9);
    const report = await writer.seal();
    return await context.callHost({command: 'seal', output: request.output, report});
  } finally { await writer.close(); }
}, {maxBytes: 4096, maxNodes: 100, maxDepth: 10});
