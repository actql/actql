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
let selectedInitialControlHostPreparation, ordinaryReceiver, ordinaryConnect, ordinaryFailure;
const ordinary = args.length === 0 && originalProcess.env.NODE_OPTIONS === undefined;
function forwardOrdinary(kind,raw) {
  // Fixed own-DATA selection only, not packet admission or a caller copy.
  // Do not invoke getters/Proxy traps or load Local for connected Host routes.
  if (kind === 'connect') {
    if (raw === null || typeof raw !== 'object' || isProxy(raw)) return undefined;
    const mode = descriptor(raw,'mode'), endpoint = descriptor(raw,'endpoint');
    if (mode === undefined || !own(mode,'value') || mode.value !== 'local' ||
        endpoint !== undefined && own(endpoint,'value') && endpoint.value !== undefined) return undefined;
  } else if (kind !== 'open') return undefined;
  if (ordinaryFailure !== undefined) throw ordinaryFailure.cause;
  if (ordinaryConnect === undefined) {
    try {
      const receiver = require('./adapters/host-node/node-public-initial-control-bootstrap.cjs');
      const connect = descriptor(receiver,'selectedInitialControlHostPreparation');
      if (connect === undefined || !own(connect,'value') || typeof connect.value !== 'function') {
        throw Object.assign(new Error('NodeInitialControlAdmissionUnavailable'),
          {code:'NodeInitialControlAdmissionUnavailable'});
      }
      ordinaryReceiver = receiver;
      ordinaryConnect = connect.value;
    } catch(cause) {
      // A failed module can disappear from Node's cache. Retain its original
      // failure instead of reexecuting a partial bootstrap on the next call.
      ordinaryFailure = Object.freeze({cause});
      throw cause;
    }
  }
  return apply(ordinaryConnect,ordinaryReceiver,[kind,raw]);
}
if (typeof preloading === 'function' && apply(preloading, module, []) === true &&
    originalProcess.env.NODE_OPTIONS === undefined && args.length === offset + 2 &&
    args[offset] === '--require' &&
    (args[offset + 1] === '@actql/node/selected-infer-startup' ||
     args[offset + 1] === '@actql/local-node/selected-infer-startup')) {
  const parent = module.parent;
  const filename = join(__dirname, 'selected-infer-startup.cjs');
  // Module/cache shape alone is not an original. Keep the actual fixed entry,
  // native preload ancestor and same consumer resolution together.
  const entry = args[offset + 1] === '@actql/node/selected-infer-startup' ? parent?.parent : parent;
  if (parent?.filename === filename && require.cache[filename] === parent &&
      entry?.parent?.id === 'internal/preload' && require.cache[entry.filename] === entry &&
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
