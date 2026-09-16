import {serveManagedExecution} from '../host-node/worker-channel.mjs';
import {openDelegatedFile} from './delegated-file.mjs';
import {consumeDelegatedFile} from './delegated-reader.mjs';

const reads = [];

serveManagedExecution(async (request, signal, context) => {
  if (request.command === 'open-read-pair') {
    for (let i = 0; i < 2; i++) reads.push(await context.callHost({command: 'read', output: request.output}));
    return {tokens: reads.map(read => read.token)};
  }
  if (request.command === 'finish-one-read') {
    const descriptor = reads.shift();
    const report = await consumeDelegatedFile(descriptor, () => {}, signal);
    return context.callHost({command: 'read-finish', output: request.output, report});
  }
  if (request.command === 'crash-reader') process.exit(9);
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
