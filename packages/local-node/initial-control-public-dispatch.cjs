'use strict';

// Private Client-only delivery, never an application-time admission factory.
// The actual public wrapper loads this once before its child namespace. A
// normal facade import neither loads that wrapper nor discovers a later table.
const NodeModule = require('node:module');
const {join} = require('node:path');
const originalProcess = require('node:process');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const args = originalProcess.execArgv;
const offset = args.length === 3 && args[0] === '--no-lazy' ? 1 : 0;
let selectedInitialControlHostPreparation;
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
module.exports = {selectedInitialControlHostPreparation};
Object.setPrototypeOf(module.exports, null);
Object.freeze(module.exports);
