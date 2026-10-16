// Disposable provider identity only. Host/Account/Credential/Run remain real.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, verify} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {publicSnowflakeInstallation} from './public-snowflake.fixture.mjs';

export async function keyPairPublicSnowflakeInstallation(t) {
  const f = await publicSnowflakeInstallation(t);
  const keys = generateKeyPairSync('rsa', {modulusLength: 2048});
  const privateKey = keys.privateKey.export({type: 'pkcs8', format: 'pem'});
  const materialEnvironment = 'ACTQL_SNOWFLAKE_PRIVATE_KEY';
  const {tokenEnvironment, ...site} = f.site;
  await writeFile(f.siteProfilePath, JSON.stringify({...site,
    authenticationType: 'KEYPAIR_JWT', keyPair: {accountIdentifier: 'testorg-testaccount',
      user: 'operator', privateKeyEnvironment: materialEnvironment}}));
  const originalProfile = JSON.parse(await readFile(f.path, 'utf8'));
  // Key transport has a distinct explicit bound; original token128 unchanged.
  await writeFile(f.path, JSON.stringify({...originalProfile,
    limits: {...originalProfile.limits, maxSecretBytes: 4096}}));
  let lookups = 0;
  f.installation.resolveSourceSecret = async context => {
    assert.equal(context.materialEnvironment, materialEnvironment);
    lookups++;
    return privateKey;
  };
  const sourceMaterialPath = join(f.root, 'original-key-pair-material.json');
  await writeFile(sourceMaterialPath, JSON.stringify({[materialEnvironment]: privateKey}), {mode: 0o600});
  const fingerprint = 'SHA256:' + createHash('sha256').update(
    keys.publicKey.export({type: 'spki', format: 'der'})).digest('base64');
  let originalToken;
  return {...f, sourceMaterialPath, materialLookups: () => lookups,
    assertOriginalCredential(entry) {
      assert.equal(entry.headers['x-snowflake-authorization-token-type'], 'KEYPAIR_JWT');
      assert.match(entry.headers.authorization, /^Bearer /u);
      const token = entry.headers.authorization.slice(7), parts = token.split('.');
      assert.equal(parts.length, 3);
      assert(verify('RSA-SHA256', Buffer.from(parts.slice(0, 2).join('.')), keys.publicKey,
        Buffer.from(parts[2], 'base64url')));
      const claims = JSON.parse(Buffer.from(parts[1], 'base64url'));
      assert.equal(claims.sub, 'TESTORG-TESTACCOUNT.OPERATOR');
      assert.equal(claims.iss, `${claims.sub}.${fingerprint}`);
      assert.equal(claims.exp - claims.iat, 3540);
      assert(claims.iat <= Math.floor(Date.now() / 1000) && claims.exp > Math.floor(Date.now() / 1000));
      if (originalToken === undefined) originalToken = token;
      assert.equal(token, originalToken, 'same acquisition keeps its original credential binding');
    }};
}
