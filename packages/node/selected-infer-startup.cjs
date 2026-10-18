'use strict';

// Preload-only public delivery. No runtime issuer, original, grant or handle
// escapes this entry; the existing Local startup authenticates its loader.
// Keep this original ancestor table through synchronous namespace reentry.
module.exports = {};
Object.setPrototypeOf(module.exports, null);
Object.freeze(module.exports);
require('@actql/local-node/selected-infer-startup');
