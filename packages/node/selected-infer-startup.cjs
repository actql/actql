'use strict';

// Preload-only public delivery. No runtime issuer, original, grant or handle
// escapes this entry; the existing Local startup authenticates its loader.
require('@actql/local-node/selected-infer-startup');
module.exports = Object.freeze({});
