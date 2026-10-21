'use strict';

// Closed correspondence fields for the existing Journal facility. Names are
// shared by its early prefix and namespace consumer; no table supplies an
// operational original, native extent, capacity or permission.
module.exports = Object.freeze({
  fs:Object.freeze(['Dir','closeSync','existsSync','fstatSync','fsyncSync','lstatSync',
    'mkdirSync','mkdtempSync','openSync','opendirSync','readSync','realpathSync',
    'rmSync','writeFileSync','writeSync']),
  // Existing Store exclusion performs asynchronous metadata/FD work before
  // the Journal. These are distinct originals, not the sync fs functions.
  promises:Object.freeze(['lstat','mkdir','open','rename','rmdir','unlink']),
  // StatementSync::Iterate reads both before returning its native cursor.
  // These aliases are correspondence, never a service or resource issuer.
  iteratorGlobal:Object.freeze(['Iterator']),
  iteratorConstructor:Object.freeze(['prototype']),
  crypto:Object.freeze(['Hash','Hmac','createHash','createHmac','randomBytes','randomUUID','timingSafeEqual']),
  constants:Object.freeze(['O_RDONLY','O_NOFOLLOW','O_NONBLOCK']),
  directory:Object.freeze(['readSync','closeSync']),
  realpath:Object.freeze(['native']),
  hash:Object.freeze(['update','digest']),
  hmac:Object.freeze(['update','digest']),
});
