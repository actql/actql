'use strict';

// Closed correspondence fields for the existing Journal facility. Names are
// shared by its early prefix and namespace consumer; no table supplies an
// operational original, native extent, capacity or permission.
module.exports = Object.freeze({
  fs:Object.freeze(['Dir','closeSync','existsSync','fstatSync','fsyncSync','lstatSync',
    'mkdirSync','mkdtempSync','openSync','opendirSync','readSync','realpathSync',
    'rmSync','writeFileSync','writeSync']),
  crypto:Object.freeze(['Hash','Hmac','createHash','createHmac','randomBytes','randomUUID','timingSafeEqual']),
  constants:Object.freeze(['O_RDONLY','O_NOFOLLOW','O_NONBLOCK']),
  directory:Object.freeze(['readSync','closeSync']),
  hash:Object.freeze(['update','digest']),
  hmac:Object.freeze(['update','digest']),
});
