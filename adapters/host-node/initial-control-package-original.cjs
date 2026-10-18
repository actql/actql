'use strict';

// The normal package builder replaces this source-only absence with its exact
// installed image inventory. The inventory is not an operational issuer; only
// the original selected preload can adopt it before entry imports.
module.exports = Object.freeze({imageInventory: undefined});
