// Synthetic test custody only; never product secrets or a Source installation.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';

export async function sourcefreeFixtureAuthorization(mode, suite, {reopen = false,
  directory = process.cwd()} = {}) {
  assert.ok(['local', 'https'].includes(mode));
  assert.ok(['in-unnest', 'sequence', 'time-series'].includes(suite));
  const path = join(directory, `sourcefree-time-series-authorization-${mode}.json`);
  if (reopen) {
    assert.equal(suite, 'time-series');
    return JSON.parse(await readFile(path, 'utf8'));
  }
  const reviewer = generateKeyPairSync('ed25519'), hostKey = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: `release-sourcefree-${mode}`, entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: hostKey.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
  if (suite === 'time-series') await writeFile(path, JSON.stringify(authorization) + '\n',
    {flag: 'wx', mode: 0o600});
  return authorization;
}
