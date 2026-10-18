'use strict';

// Preload-only public delivery. No runtime issuer, original, grant or handle
// escapes this entry; the existing Local startup authenticates its loader.
// Keep this original ancestor table through synchronous namespace reentry.
const NodeModule = require('node:module');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const args = process.execArgv;
const offset = args.length === 3 && args[0] === '--no-lazy' ? 1 : 0;
const selected = typeof preloading === 'function' && apply(preloading, module, []) === true &&
  process.env.NODE_OPTIONS === undefined && args.length === offset + 2 &&
  args[offset] === '--require' && args[offset + 1] === '@actql/node/selected-infer-startup';
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
// Capture only during this actual wrapper's preload, before child namespace
// initialization can reenter the public facade. No setter or issuer escapes.
require('./initial-control-public-dispatch.cjs');
const child = require('@actql/local-node/selected-infer-startup');
const connect = descriptor(child, 'selectedInitialControlHostPreparation');
if (selected && connect !== undefined && Object.hasOwn(connect, 'value') &&
    typeof connect.value === 'function') {
  originalReceiver = child;
  originalConnect = connect.value;
}
