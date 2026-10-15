'use strict';
// Independent negative startup: retain a larger historical slab, then restore
// the visible poolSize before the selected module would be loaded.
const {Buffer} = require('node:buffer');
Buffer.poolSize = 16384;
const retained = Array.from({length: 6}, () => Buffer.allocUnsafe(4095));
if (!retained.some(value => value.buffer.byteLength === 16384)) {
  throw new Error('Independent larger historical slab was not established');
}
Buffer.poolSize = 8192;
module.exports = retained;
