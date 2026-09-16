// Installed test worker using the real common ledger, not diagnostic usage as
// a product completion claim. Each process constructs its own exact subledger.
import * as runtime from '../../_build/js/release/build/process_host_bridge/process_host_bridge.js';
import {checked} from '../host-common/runtime-result.mjs';
import {serveManagedExecution} from './worker-channel.mjs';
import {emptyProcessUsage} from './process-accounting.mjs';

let ledger, reportTransform = value => value;
const reservations = [];
serveManagedExecution(async (request, signal, context) => {
  if (!context.resourceLimits) throw Error('MissingResourceLimits');
  ledger ??= checked(runtime.processLedgerCreate(context.resourceLimits));
  if (request.command === 'allocate') {
    reservations.push(checked(runtime.processReserve(ledger, 0n, 1n)));
    return {allocated: true};
  }
  if (request.command === 'crash') process.exit(9);
  if (request.command === 'invalid-report') {
    reportTransform = value => ({...value, attempts: context.resourceLimits.attempts + 1});
    return null;
  }
  if (request.command === 'wait') {
    await new Promise(resolve => signal.addEventListener('abort', resolve, {once: true}));
    signal.throwIfAborted();
  }
  return {limits: Object.fromEntries(Object.entries(context.resourceLimits)
    .map(([key, value]) => [key, typeof value === 'bigint' ? value.toString() : value]))};
}, {maxBytes: 4096, maxNodes: 100, maxDepth: 10}, {
  accounting: () => reportTransform(ledger ? runtime.processLedgerUsage(ledger) : emptyProcessUsage()),
  finish: async () => {
    for (const reservation of reservations) checked(runtime.processStopped(ledger, reservation));
  },
});
