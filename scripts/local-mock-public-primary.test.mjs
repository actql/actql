import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Independently authored finite policy/configuration preimages. Neither oracle
// imports the materializer nor computes an expected value from its output.
const sorted = value => Array.isArray(value) ? value.map(sorted) :
  value !== null && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const canonical = value => JSON.stringify(sorted(value));
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const profile = {
  control: {operations: ['cancel', 'publish', 'read', 'resolve', 'submit'], resource: 'run'},
  effect: {operations: ['effect'], outcome: 'delegate'},
  infer: {connection: 'mock', operations: ['infer', 'model_raw_capture']},
  profile_id: 'actql-local-mock', profile_version: '0.1', read: {operations: ['read']},
  request: {operations: ['write'], resource: 'original-host-mock-realization'},
  result: {operations: ['read'], resources: ['result/answer', 'result/main']},
  scope: 'selected-mock-project-installation',
  sign: {operations: ['sign'], resource: 'original-local-purpose-key'},
};
const entry = (entry_id, connection, resource, operation, outcome = 'allow') => ({
  entry_id, principal: {any_of: ['local-operator']}, connection: {any_of: [connection]},
  resource: {any_of: [resource]}, operation: {any_of: operation}, outcome, exclusions: [],
});
const configuration = {
  account_id: 'mock-account',
  bootstrap: {profile_id: 'actql-local-mock', profile_version: '0.1', profile_cid: cid(profile)},
  entries: [
    entry('local-run', 'local-host', 'run', ['cancel', 'publish', 'read', 'resolve', 'submit']),
    entry('local-result-read', 'local-host', 'result/answer', ['read']),
    entry('local-primary-result-read', 'local-host', 'result/main', ['read']),
    entry('mock-read-0', 'salesforce', 'Account', ['read']),
    entry('mock-read-1', 'snowflake', 'usage_30d', ['read']),
    entry('mock-infer-0', 'mock', 'sha256:' + 'a'.repeat(64), ['infer', 'model_raw_capture']),
    entry('mock-update', 'salesforce', 'Account', ['effect'], 'delegate'),
    entry('local-sign', 'local-host', 'key:reviewer', ['sign']),
    entry('local-request', 'local-host', 'mock-realization', ['write']),
  ].sort((left, right) => left.entry_id < right.entry_id ? -1 : 1),
  version: 'actql-execution-account-config/0.1',
};
const source = readFileSync(new URL('../src/execution_authorization/local_mock_profile.mbt', import.meta.url), 'utf8');
const body = name => {
  const start = source.indexOf(`fn ${name}()`);
  assert.notEqual(start, -1);
  const match = /#\|([^\n]+)/u.exec(source.slice(start));
  assert(match);
  return match[1];
};

test('public primary finite Mock policy and configuration have independent complete canonical preimages', () => {
  assert.equal(cid(profile), 'sha256:8d3a8a44d338852bdef34d4547dc8a9c22d91e9831dac20ee42f144de8793e01');
  assert.equal(cid(configuration), 'sha256:82722eed1a6b4cfb1a33f06b3345246076cf6802483c97eab250f5febb8826e8');
  assert.equal(body('local_mock_profile_body'), canonical(profile));
  const normative = readFileSync(new URL('../docs/spec/execution.md', import.meta.url), 'utf8');
  assert(normative.includes(cid(profile)));
  assert.deepEqual(profile.result.resources, ['result/answer', 'result/main']);
  assert(configuration.entries.every(rule => rule.resource.any_of.every(resource => resource !== '*')));
});

test('complete answer-only predecessor policy/configuration identities remain exact', () => {
  const previous = {...profile, result: {operations: ['read'], resource: 'result/answer'}};
  const previousCid = 'sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f';
  assert.equal(cid(previous), previousCid);
  assert.equal(body('local_mock_answer_profile_body'), canonical(previous));
  const previousConfiguration = {...configuration,
    bootstrap: {...configuration.bootstrap, profile_cid: previousCid},
    entries: configuration.entries.filter(rule => rule.entry_id !== 'local-primary-result-read')};
  assert.equal(cid(previousConfiguration), 'sha256:31531ccc65ed73cdef89bc21ec83864d64f264de64894c11fad50c7170a94828');
  assert(!previousConfiguration.entries.some(rule => rule.resource.any_of.includes('result/main')));
  const oldest = {...previous,
    control: {operations: ['read', 'resolve'], resource: 'run'}};
  delete oldest.result;
  assert.equal(cid(oldest), 'sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a');
  assert.equal(body('local_mock_profile_predecessor_body'), canonical(oldest));
});
