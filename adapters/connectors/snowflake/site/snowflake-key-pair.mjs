// Provider authentication material only. The existing Credential Owner alone
// claims/authorizes each use and binds the original acquisition's token.
import {constants, createHash, createPrivateKey, createPublicKey, sign} from 'node:crypto';

const lifetimeSeconds = 59 * 60;
const environmentName = value => typeof value === 'string' && /^[A-Z_][A-Z0-9_]{0,63}$/u.test(value);
const fail = code => {throw Object.assign(new Error(code), {code});};

export function checkSnowflakeKeyPairProfile(input) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) fail('InvalidSnowflakeKeyPairProfile');
  const {accountIdentifier, user, privateKeyEnvironment, passphraseEnvironment} = input;
  const keys = Object.keys(input);
  if (!['accountIdentifier', 'user', 'privateKeyEnvironment'].every(key => keys.includes(key)) ||
      keys.some(key => !['accountIdentifier', 'user', 'privateKeyEnvironment', 'passphraseEnvironment'].includes(key)) ||
      typeof accountIdentifier !== 'string' || accountIdentifier.length > 255 ||
      !/^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/u.test(accountIdentifier) ||
      /(?:^|\.)snowflakecomputing(?:\.|$)/iu.test(accountIdentifier) ||
      typeof user !== 'string' || !user.isWellFormed() || user.length === 0 ||
      Buffer.byteLength(user) > 255 || /[\u0000-\u001f\u007f]/u.test(user) ||
      !environmentName(privateKeyEnvironment) ||
      (keys.includes('passphraseEnvironment') && !environmentName(passphraseEnvironment))) {
    fail('InvalidSnowflakeKeyPairProfile');
  }
  return Object.freeze({accountIdentifier, user, privateKeyEnvironment,
    ...(passphraseEnvironment === undefined ? {} : {passphraseEnvironment})});
}

export function openSnowflakeKeyPairMaterial(profile, {maxSecretBytes,
  resolveMaterial, now = () => Date.now()}) {
  const selected = checkSnowflakeKeyPairProfile(profile);
  if (!Number.isSafeInteger(maxSecretBytes) || maxSecretBytes <= 0 ||
      (resolveMaterial !== undefined && typeof resolveMaterial !== 'function') || typeof now !== 'function') {
    fail('InvalidSnowflakeKeyPairLimits');
  }
  // Explicit issuer data, never inferred from a request URL. Account locators
  // must already exclude their region; an account name may use dots, which
  // Snowflake requires as hyphens in JWT claims. The raw selection remains in
  // the original installed identity separately from these provider spellings.
  const subject = `${selected.accountIdentifier.replaceAll('.', '-').toUpperCase()}.${selected.user.toUpperCase()}`;
  let closed = false, cached;
  const ensureOpen = signal => {
    signal?.throwIfAborted();
    if (closed) fail('SnowflakeKeyPairMaterialClosed');
  };
  async function material(context, name, signal, empty = false) {
    ensureOpen(signal);
    const value = resolveMaterial === undefined ? process.env[name]
      : await resolveMaterial(Object.freeze({...context, materialEnvironment: name}), signal);
    ensureOpen(signal);
    if (typeof value !== 'string' || !value.isWellFormed() || (!empty && value.length === 0)) {
      fail('SnowflakeKeyPairMaterialUnavailable');
    }
    if (value.length > maxSecretBytes || Buffer.byteLength(value) > maxSecretBytes) fail('SnowflakeKeyPairMaterialLimit');
    return value;
  }
  return Object.freeze({
    async resolveSecret(context, signal) {
      const pem = await material(context, selected.privateKeyEnvironment, signal);
      const passphrase = selected.passphraseEnvironment === undefined ? undefined
        : await material(context, selected.passphraseEnvironment, signal, true);
      ensureOpen(signal);
      const milliseconds = now();
      if (!Number.isSafeInteger(milliseconds) || milliseconds < 0) fail('InvalidSnowflakeKeyPairClock');
      const issued = Math.floor(milliseconds / 1000);
      let key, fingerprint;
      try {
        key = createPrivateKey({key: pem, format: 'pem', ...(passphrase === undefined ? {} : {passphrase})});
        if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength < 2048) {
          fail('InvalidSnowflakeKeyPairMaterial');
        }
        const publicKey = createPublicKey(key).export({type: 'spki', format: 'der'});
        fingerprint = 'SHA256:' + createHash('sha256').update(publicKey).digest('base64');
      } catch {
        // Crypto errors are not a source of provider grants or safe-to-echo
        // credential details. The original journal records this failed use.
        fail('InvalidSnowflakeKeyPairMaterial');
      }
      // One bounded material cache, not a per-Run inventory. Resolve and check
      // the actual current key even on a cache hit. A changed/renewed token is
      // refused by the original HTTPS binding rather than swapped mid-read.
      if (cached?.fingerprint === fingerprint && cached.issued <= issued && cached.expires > issued) return cached.token;
      const header = Buffer.from(JSON.stringify({alg: 'RS256', typ: 'JWT'})).toString('base64url');
      const expires = issued + lifetimeSeconds;
      const payload = Buffer.from(JSON.stringify({iss: `${subject}.${fingerprint}`,
        sub: subject, iat: issued, exp: expires})).toString('base64url');
      const unsigned = `${header}.${payload}`;
      let token;
      try {token = `${unsigned}.${sign('RSA-SHA256', Buffer.from(unsigned),
        {key, padding: constants.RSA_PKCS1_PADDING}).toString('base64url')}`;}
      catch {fail('InvalidSnowflakeKeyPairMaterial');}
      if (Buffer.byteLength(token) > maxSecretBytes) fail('SnowflakeKeyPairMaterialLimit');
      ensureOpen(signal);
      cached = Object.freeze({fingerprint, issued, expires, token});
      return token;
    },
    close() {closed = true; cached = undefined;},
  });
}
