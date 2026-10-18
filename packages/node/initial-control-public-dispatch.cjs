'use strict';

// Private Client-only delivery, never an application-time admission factory.
// The actual public wrapper retains this delivery once. Ordinary Local is
// selected before acquiring its bootstrap; an unselected import owns no loader.
const NodeModule = require('node:module');
const {join} = require('node:path');
const originalProcess = require('node:process');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const isProxy = require('node:util').types.isProxy, own = Object.hasOwn;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const args = originalProcess.execArgv;
const offset = args.length === 3 && args[0] === '--no-lazy' ? 1 : 0;
let selectedInitialControlHostPreparation, ordinaryReceiver, ordinaryConnect;
const ordinary = args.length === 0 && originalProcess.env.NODE_OPTIONS === undefined;
function forwardOrdinary(kind,raw) {
  // Selection is the same fixed own-DATA entrance as the Local prefix. No
  // packet copy, getters, provider discovery or operational issuance occurs.
  if (kind === 'connect') {
    if (raw === null || typeof raw !== 'object' || isProxy(raw)) return undefined;
    const mode = descriptor(raw,'mode'), endpoint = descriptor(raw,'endpoint');
    if (mode === undefined || !own(mode,'value') || mode.value !== 'local' ||
        endpoint !== undefined && own(endpoint,'value') && endpoint.value !== undefined) return undefined;
  } else if (kind !== 'open') return undefined;
  if (ordinaryConnect === undefined) {
    // Resolve only the actual installed Local package after Local selection.
    let receiver;
    try { receiver = require('@actql/local-node/_internal/initial-control-public-dispatch'); }
    catch(cause) { if (cause.code !== 'MODULE_NOT_FOUND') throw cause; }
    const connect = receiver === undefined ? undefined : descriptor(receiver,'selectedInitialControlHostPreparation');
    if (connect === undefined || !own(connect,'value') || typeof connect.value !== 'function') return undefined;
    ordinaryReceiver = receiver;
    ordinaryConnect = connect.value;
  }
  return apply(ordinaryConnect,ordinaryReceiver,[kind,raw]);
}
if (typeof preloading === 'function' && apply(preloading, module, []) === true &&
    originalProcess.env.NODE_OPTIONS === undefined && args.length === offset + 2 &&
    args[offset] === '--require' && args[offset + 1] === '@actql/node/selected-infer-startup') {
  const parent = module.parent;
  const filename = join(__dirname, 'selected-infer-startup.cjs');
  // Module/cache shape alone is not an original. Keep the actual fixed entry,
  // native preload ancestor and same consumer resolution together.
  const entry = parent;
  if (parent?.filename === filename && require.cache[filename] === parent &&
      entry.parent?.id === 'internal/preload' &&
      NodeModule.createRequire(originalProcess.argv[1]).resolve(args[offset + 1]) === entry.filename) {
    const receiver = parent.exports;
    const property = descriptor(receiver, 'selectedInitialControlHostPreparation');
    if (property !== undefined && Object.hasOwn(property, 'value') &&
        typeof property.value === 'function') {
      const connect = property.value;
      selectedInitialControlHostPreparation = function(kind, rawInput) {
        return apply(connect, receiver, [kind, rawInput]);
      };
    }
  }
}
module.exports = {selectedInitialControlHostPreparation:
  ordinary ? forwardOrdinary : selectedInitialControlHostPreparation};
Object.setPrototypeOf(module.exports, null);
Object.freeze(module.exports);
