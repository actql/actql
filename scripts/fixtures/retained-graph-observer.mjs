import {generateKeyPairSync} from 'node:crypto';
import {userInfo} from 'node:os';

// Private acceptance credentials, never a real service credential.
// Initial execution and fresh-process reading use the same complete Host
// configuration; a fault hook alone is not an authorization installation.
export function createRetainedGraphAuthorization() {
  const keys = generateKeyPairSync('ed25519');
  return {
    // Installing checkpoint authorization also protects execution at this
    // synthetic Site. Use its ordinary scoped account, not a missing account
    // or an observer-specific bypass. Source authorization remains separate.
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'retained-graph-fixture', entries: [{entry_id: 'synthetic-site',
        outcome: 'allow', principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      // Run observation and the authored answer are distinct ordinary reads.
      // They retain this same synthetic principal/Site; neither grants another
      // Result, another principal or another operation.
      {entry_id: 'synthetic-site-read', outcome: 'allow',
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/answer', 'run']},
        operation: {any_of: ['read']}, exclusions: []}]}),
    reviewers: [{keyId: 'graph-fixture-reviewer', reviewerId: 'graph-fixture-reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'graph-fixture-host',
      privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
}

export function observeRetainedGraphDispatch(authorization, physicalDispatches) {
  if (!Array.isArray(authorization?.reviewers) || authorization.reviewers.length !== 1 ||
      typeof authorization?.hostKey?.privateKey !== 'string' ||
      typeof authorization?.accountConfiguration !== 'string') {
    throw new Error('MissingRetainedGraphAuthorization');
  }
  return {...authorization, faultInjection(name) {
    if (['physical_start_reserved', 'computed', 'local_compute_advanced'].includes(name)) {
      physicalDispatches.push(name);
    }
  }};
}
