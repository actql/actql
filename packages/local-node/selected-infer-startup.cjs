'use strict';

// Keep the existing private startup/Host Owner. Importing this application-time
// does not manufacture early process responsibility or numerical coverage.
// The original Root can capture this SAME ancestor table while its namespace
// initializes. Do not replace it after the Root's pre-entry Module handoff.
// Null prototype avoids Node's circular-require warning prototype mutation.
const NodeModule = require('node:module');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const args = process.execArgv;
const offset = args.length === 3 && args[0] === '--no-lazy' ? 1 : 0;
const selected = typeof preloading === 'function' && apply(preloading, module, []) === true &&
  process.env.NODE_OPTIONS === undefined && args.length === offset + 2 &&
  args[offset] === '--require' &&
  (args[offset + 1] === '@actql/node/selected-infer-startup' ||
   args[offset + 1] === '@actql/local-node/selected-infer-startup');
let originalReceiver, originalConnect;
function connectInitialControlHostPreparation(kind, rawInput) {
  if (originalConnect === undefined) {
    throw Object.assign(new TypeError('NodeInitialControlAdmissionUnavailable'),
      {code: 'NodeInitialControlAdmissionUnavailable'});
  }
  return apply(originalConnect, originalReceiver, [kind, rawInput]);
}
module.exports = {selectedInitialControlHostPreparation:
  selected ? connectInitialControlHostPreparation : undefined};
Object.setPrototypeOf(module.exports, null);
Object.freeze(module.exports);
require('./initial-control-public-dispatch.cjs');
const child = require('./adapters/host-node/infer-trusted-node-preload.cjs');
const connect = descriptor(child, 'connectInitialControlHostPreparation');
if (selected && connect !== undefined && Object.hasOwn(connect, 'value') &&
    typeof connect.value === 'function') {
  originalReceiver = child;
  originalConnect = connect.value;
}
