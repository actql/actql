// Synthetic test custody only; never product secrets or a Source installation.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {sourcefreeSuiteRequiresReread} from '../release-sourcefree-query-cases.mjs';

export async function sourcefreeFixtureAuthorization(mode, suite, {reopen = false,
  directory = process.cwd()} = {}) {
  assert.ok(['local', 'https'].includes(mode));
  assert.ok(['in-unnest', 'sequence', 'time-series', 'temporal-join', 'aql-format', 'calendar'].includes(suite));
  const retained = sourcefreeSuiteRequiresReread(suite);
  const path = join(directory, `sourcefree-${suite}-authorization-${mode}.json`);
  if (reopen) {
    assert.equal(retained, true);
    return JSON.parse(await readFile(path, 'utf8'));
  }
  const reviewer = generateKeyPairSync('ed25519'), hostKey = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: `release-sourcefree-${mode}`, entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      ...(suite === 'in-unnest' ? [
        // Public Run inspection and the selected main Result are separate
        // protected reads, even when the Program needs no Source or Effect.
        {entry_id: 'run-read', outcome: 'allow', principal: {all: true},
          connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['run']},
          operation: {any_of: ['read']}, exclusions: []},
        {entry_id: 'result-main-read', outcome: 'allow', principal: {all: true},
          connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['result/main']},
          operation: {any_of: ['read']}, exclusions: []},
      ] : [])]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: hostKey.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
  if (retained) await writeFile(path, JSON.stringify(authorization) + '\n',
    {flag: 'wx', mode: 0o600});
  return authorization;
}
