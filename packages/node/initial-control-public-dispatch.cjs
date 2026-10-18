'use strict';

// Private Client-only delivery, never an application-time admission factory.
// The actual public wrapper loads this once before its child namespace. A
// normal facade import neither loads that wrapper nor discovers a later table.
const NodeModule = require('node:module');
const {join} = require('node:path');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
let selectedInitialControlHostPreparation;
if (typeof preloading === 'function' && apply(preloading, module, []) === true) {
  const parent = module.parent;
  const filename = join(__dirname, 'selected-infer-startup.cjs');
  if (parent?.filename === filename && require.cache[filename] === parent) {
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
