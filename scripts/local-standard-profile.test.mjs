import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independent policy and concrete configuration preimages, not product output.
const sorted = value => Array.isArray(value) ? value.map(sorted) :
  value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const canonical = value => JSON.stringify(sorted(value));
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const profile = {
  control: {operations: ['cancel', 'publish', 'read', 'resolve', 'submit'], resource: 'run'},
  effect: {operations: ['effect'], outcome: 'delegate'},
  infer: {operations: ['infer', 'model_raw_capture'], scope: 'registered-model-tasks'},
  profile_id: 'actql-local-standard', profile_version: '0.1',
  read: {operations: ['read'], scope: 'configured-connections'},
  request: {operations: ['write'], resource: 'original-host-realization'},
  result: {operations: ['read'], scope: 'same-run-original-results'},
  scope: 'standard-local-installation',
  sign: {operations: ['sign'], resource: 'original-local-purpose-key'},
};
const entry = (entry_id, connection, resource, operation, outcome = 'allow') => ({
  entry_id, principal: {any_of: ['local-operator']},
  connection: connection === null ? {all: true} : {any_of: [connection]},
  resource: resource === null ? {all: true} : {any_of: [resource]},
  operation: {any_of: operation}, outcome, exclusions: [],
});
const configuration = {
  account_id: 'local-account',
  bootstrap: {profile_id: 'actql-local-standard', profile_version: '0.1', profile_cid: cid(profile)},
  entries: [
    entry('local-run', 'local-host', 'run', ['cancel', 'publish', 'read', 'resolve', 'submit']),
    entry('local-result-read', 'local-host', null, ['read']),
    entry('local-effect', null, null, ['effect'], 'delegate'),
    entry('local-read-0', 'files', null, ['read']),
    entry('local-read-1', 'crm', null, ['read']),
    entry('local-infer-0', 'provider', 'sha256:' + 'a'.repeat(64), ['infer', 'model_raw_capture']),
    entry('local-request', 'local-host', 'original-realization', ['write']),
  ].sort((left, right) => left.entry_id < right.entry_id ? -1 : 1),
  version: 'actql-execution-account-config/0.1',
};

test('standard Local profile has an independent complete policy preimage', () => {
  assert.equal(cid(profile), 'sha256:8c28b41c2fc824e43c77de4726337661b651287d2ac627770dc106e972afd60e');
  assert.equal(cid(configuration), 'sha256:8f48bc9c35f800722a1d50815c282d38d05ef80edeb17e023c8324cc2bdfaa0d');
  const source = readFileSync(new URL('../src/execution_authorization/local_standard_profile.mbt', import.meta.url), 'utf8');
  assert.equal(/#\|([^\n]+)/u.exec(source)[1], canonical(profile));
  const spec = readFileSync(new URL('../docs/spec/execution.md', import.meta.url), 'utf8');
  assert(spec.includes(cid(profile)));
  assert.equal(configuration.entries.find(rule => rule.entry_id === 'local-effect').outcome, 'delegate');
  assert.deepEqual(configuration.entries.find(rule => rule.entry_id === 'local-infer-0').resource,
    {any_of: ['sha256:' + 'a'.repeat(64)]});
});
