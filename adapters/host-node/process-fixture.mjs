import { serveManagedExecution } from './worker-channel.mjs';
serveManagedExecution(async (request, signal, context) => {
  switch (request.command) {
    case 'echo': return { value: request.value, pid: process.pid };
    case 'host-call': return {value: await context.callHost(request.value), pid: process.pid};
    case 'host-caught':
      try { await context.callHost(request.value); return {failed: false}; }
      catch { return {failed: true}; }
    case 'undefined-failure': return Promise.reject();
    case 'crash': process.exit(9); break;
    case 'hang': return new Promise(() => { setInterval(() => {}, 1000); });
    case 'wait': return new Promise((resolve, reject) => {
      const timer = setTimeout(() => resolve({ finished: true }), 10000);
      signal.addEventListener('abort', () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
    });
    default: throw Error('Unsupported test command');
  }
}, { maxBytes: 4096, maxNodes: 100, maxDepth: 10 });
