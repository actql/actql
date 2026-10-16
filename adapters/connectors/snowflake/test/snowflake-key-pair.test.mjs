import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, verify} from 'node:crypto';
import test from 'node:test';
import {checkSnowflakeKeyPairProfile, openSnowflakeKeyPairMaterial} from '../site/snowflake-key-pair.mjs';

const rsa = generateKeyPairSync('rsa', {modulusLength: 2048});
const rotated = generateKeyPairSync('rsa', {modulusLength: 2048});
const profile = Object.freeze({accountIdentifier: 'myorg.myaccount', user: 'alice',
  privateKeyEnvironment: 'SNOWFLAKE_KEY'});
const context = Object.freeze({grantCid: 'sha256:' + 'a'.repeat(64), principal: 'operator',
  operation: 'snowflake:sql:read', resourceOrigin: 'https://warehouse.invalid',
  namespaceId: 'original', environment: 'test', siteKey: 'original-site', siteGeneration: 1,
  connectorRegistration: 'snowflake'});
const pem = key => key.privateKey.export({type: 'pkcs8', format: 'pem'});
function claims(token, publicKey = rsa.publicKey) {
  const parts = token.split('.'); assert.equal(parts.length, 3);
  assert.deepEqual(JSON.parse(Buffer.from(parts[0], 'base64url')), {alg: 'RS256', typ: 'JWT'});
  assert(verify('RSA-SHA256', Buffer.from(parts.slice(0, 2).join('.')), publicKey,
    Buffer.from(parts[2], 'base64url')), 'independent public-key signature verification');
  assert(!verify('RSA-SHA256', Buffer.from(parts.slice(0, 2).join('.')), rotated.publicKey === publicKey ? rsa.publicKey : rotated.publicKey,
    Buffer.from(parts[2], 'base64url')), 'foreign public key does not verify');
  return JSON.parse(Buffer.from(parts[1], 'base64url'));
}
const options = (overrides = {}) => ({maxSecretBytes: 4096, resolveMaterial: async () => pem(rsa),
  now: () => 1800000000000, ...overrides});

test('key-pair selection is closed and owns only public issuer/environment strings', () => {
  const source = {...profile}, selected = checkSnowflakeKeyPairProfile(source);
  source.user = 'changed'; assert.equal(selected.user, 'alice'); assert(Object.isFrozen(selected));
  for (const value of [null, {}, {...profile, extra: true}, {...profile, accountIdentifier: 'https://evil.invalid'},
    {...profile, accountIdentifier: 'acct.snowflakecomputing.com'}, {...profile, accountIdentifier: 'bad/account'},
    {...profile, user: '\ud800'}, {...profile, privateKeyEnvironment: 'bad-name'},
    {...profile, passphraseEnvironment: undefined}]) assert.throws(() => checkSnowflakeKeyPairProfile(value),
      {code: 'InvalidSnowflakeKeyPairProfile'});
});

test('RSA JWT has independently verified issuer/fingerprint, exact subject and bounded expiry', async t => {
  const holder = openSnowflakeKeyPairMaterial(profile, options()); t.after(() => holder.close());
  const token = await holder.resolveSecret(context);
  const fingerprint = 'SHA256:' + createHash('sha256').update(rsa.publicKey.export({type: 'spki', format: 'der'})).digest('base64');
  assert.deepEqual(claims(token), {iss: `MYORG-MYACCOUNT.ALICE.${fingerprint}`,
    sub: 'MYORG-MYACCOUNT.ALICE', iat: 1800000000, exp: 1800003540});
});

test('each use resolves current material but an unchanged key retains the same in-flight token', async t => {
  const lookups = []; let now = 1800000000000;
  const holder = openSnowflakeKeyPairMaterial(profile, options({now: () => now,
    resolveMaterial: async value => {lookups.push(value); return pem(rsa);}})); t.after(() => holder.close());
  const first = await holder.resolveSecret(context); now += 31000;
  assert.equal(await holder.resolveSecret(context), first);
  assert.equal(lookups.length, 2);
  for (const value of lookups) {
    assert(Object.isFrozen(value)); assert.equal(value.materialEnvironment, 'SNOWFLAKE_KEY');
    for (const [key, expected] of Object.entries(context)) assert.equal(value[key], expected);
  }
});

test('rotation and expiry yield different material for the existing binding to refuse, never a use grant', async t => {
  let current = rsa, now = 1800000000000;
  const holder = openSnowflakeKeyPairMaterial(profile, options({now: () => now, resolveMaterial: async () => pem(current)}));
  t.after(() => holder.close());
  const original = await holder.resolveSecret(context); current = rotated;
  const changed = await holder.resolveSecret(context); assert.notEqual(changed, original); claims(changed, rotated.publicKey);
  now += 3540000;
  const renewed = await holder.resolveSecret(context); assert.notEqual(renewed, changed);
  assert.equal(claims(renewed, rotated.publicKey).iat, Math.floor(now / 1000));
});

test('encrypted PEM uses the separately selected bounded passphrase and never sends it', async t => {
  const encrypted = rsa.privateKey.export({type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase: 'private-fixture-passphrase'});
  const lookups = [];
  const holder = openSnowflakeKeyPairMaterial({...profile, passphraseEnvironment: 'SNOWFLAKE_PASSPHRASE'}, options({
    resolveMaterial: async value => {lookups.push(value.materialEnvironment);
      return value.materialEnvironment === 'SNOWFLAKE_KEY' ? encrypted : 'private-fixture-passphrase';}}));
  t.after(() => holder.close()); const token = await holder.resolveSecret(context); claims(token);
  assert.deepEqual(lookups, ['SNOWFLAKE_KEY', 'SNOWFLAKE_PASSPHRASE']);
  assert(!token.includes('private-fixture-passphrase'));
});

test('wrong, unavailable and over-limit key material do not fall back or echo secrets', async t => {
  const weak = generateKeyPairSync('rsa', {modulusLength: 1024});
  const elliptic = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const grantKey = generateKeyPairSync('ed25519');
  for (const key of [weak, elliptic, grantKey]) {
    const holder = openSnowflakeKeyPairMaterial(profile, options({resolveMaterial: async () => pem(key)}));
    t.after(() => holder.close()); await assert.rejects(holder.resolveSecret(context), {code: 'InvalidSnowflakeKeyPairMaterial'});
  }
  for (const value of [undefined, '', '\ud800', 'private-invalid-key']) {
    const holder = openSnowflakeKeyPairMaterial(profile, options({resolveMaterial: async () => value}));
    t.after(() => holder.close()); await assert.rejects(holder.resolveSecret(context), error => {
      assert.match(error.code, /^(SnowflakeKeyPairMaterialUnavailable|InvalidSnowflakeKeyPairMaterial)$/u);
      assert(!error.message.includes('private-invalid-key')); return true;
    });
  }
  const small = openSnowflakeKeyPairMaterial(profile, options({maxSecretBytes: 128}));
  t.after(() => small.close()); await assert.rejects(small.resolveSecret(context), {code: 'SnowflakeKeyPairMaterialLimit'});
});

test('invalid transport limits and clock refuse without inventing a time or numeric allowance', async t => {
  for (const value of [undefined, 0, -1, true, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => openSnowflakeKeyPairMaterial(profile, options({maxSecretBytes: value})), {code: 'InvalidSnowflakeKeyPairLimits'});
  }
  for (const value of [NaN, -1, true, 0.5, Number.MAX_SAFE_INTEGER + 1]) {
    const holder = openSnowflakeKeyPairMaterial(profile, options({now: () => value})); t.after(() => holder.close());
    await assert.rejects(holder.resolveSecret(context), {code: 'InvalidSnowflakeKeyPairClock'});
  }
});

test('abort and close fence both sides of a pending material lookup; close never restarts it', async () => {
  let release, entered, lookups = 0;
  const ready = new Promise(resolve => {entered = resolve;});
  const holder = openSnowflakeKeyPairMaterial(profile, options({resolveMaterial: () => {
    lookups++; entered(); return new Promise(resolve => {release = resolve;});}}));
  const pending = holder.resolveSecret(context); await ready; holder.close(); holder.close(); release(pem(rsa));
  await assert.rejects(pending, {code: 'SnowflakeKeyPairMaterialClosed'});
  await assert.rejects(holder.resolveSecret(context), {code: 'SnowflakeKeyPairMaterialClosed'}); assert.equal(lookups, 1);
  const aborted = new AbortController(); aborted.abort();
  const next = openSnowflakeKeyPairMaterial(profile, options({resolveMaterial: () => {throw new Error('unexpected lookup');}}));
  await assert.rejects(next.resolveSecret(context, aborted.signal), {name: 'AbortError'}); next.close();
});


test('cache hits cannot bypass a newly unavailable passphrase or key', async t => {
  const encrypted = rsa.privateKey.export({type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase: 'fixture-secret'});
  let available = true;
  const holder = openSnowflakeKeyPairMaterial({...profile, passphraseEnvironment: 'PASS'}, options({
    resolveMaterial: async value => value.materialEnvironment === 'SNOWFLAKE_KEY' ? encrypted : available ? 'fixture-secret' : 'wrong-secret'}));
  t.after(() => holder.close());
  const original = await holder.resolveSecret(context); available = false;
  await assert.rejects(holder.resolveSecret(context), {code: 'InvalidSnowflakeKeyPairMaterial'});
  available = true; assert.equal(await holder.resolveSecret(context), original);
});
